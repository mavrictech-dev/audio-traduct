import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audio_traductor/core/errors/exceptions.dart';
import 'package:audio_traductor/core/services/audio_level_service.dart';
import 'package:audio_traductor/features/translation/data/datasources/stt_datasource.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';

/// Whisper.cpp on-device con segmentación manual por silencio.
///
/// Reemplaza a `GoogleSttDatasource` (eliminado). El flujo de captura y de
/// segmentación por silencio (~600ms) es EXACTAMENTE el mismo que tenía la
/// versión cloud — eso ya funcionaba bien y no había motivo para tocarlo.
/// Lo único que cambia es qué se hace con cada bloque de audio ya cortado:
/// en vez de mandarlo por HTTP a Google, se escribe a un WAV temporal y se
/// transcribe localmente con whisper.cpp (sin red, sin key).
class WhisperSttDatasource implements SttDatasource {
  static const _silenceThresholdMs = 600;
  static const _rmsThreshold = 700;
  static const _sampleRate = 16000;
  static const _audioChannel = MethodChannel('com.audiotraductor/audio');
  static const _micChannel = EventChannel('com.audiotraductor/mic');
  static const _passthroughChannel = MethodChannel('com.audiotraductor/passthrough');

  final WhisperModel _model;
  final Whisper _whisper;
  final http.Client _http = http.Client();

  StreamSubscription<List<int>>? _micSub;
  StreamController<SttResult>? _controller;
  bool _stopping = false;
  String _languageCode = 'es';
  final List<int> _buffer = [];
  int _silenceSamples = 0;
  bool _hadSpeech = false;
  Future<void>? _recognitionQueue;

  WhisperSttDatasource({WhisperModel model = WhisperModel.base})
      : _model = model,
        _whisper = Whisper(model: model);

  @override
  Stream<SttResult> startStreaming({
    required Stream<List<int>> audioStream,
    required String languageCode,
  }) async* {
    _controller = StreamController<SttResult>.broadcast();
    _stopping = false;
    _languageCode = languageCode;
    _buffer.clear();
    _silenceSamples = 0;
    _hadSpeech = false;
    _recognitionQueue = null;

    try {
      await _audioChannel.invokeMethod('startRecording');
      await _passthroughChannel.invokeMethod('start');

      final stream = _micChannel.receiveBroadcastStream().map<List<int>>((event) {
        if (event is Uint8List) return event;
        if (event is List<int>) return event;
        if (event is List) return List<int>.from(event);
        return const <int>[];
      });

      _micSub = stream.listen(
        _onAudioData,
        onError: (e) => _controller?.addError('Mic: $e'),
      );
    } catch (e) {
      _controller?.addError('Error al iniciar mic: $e');
    }

    yield* _controller!.stream;
  }

  void _onAudioData(List<int> chunk) {
    if (_stopping) return;
    _buffer.addAll(chunk);

    final mav = _calcMav(chunk);
    AudioLevelService.instance.updateLevel(mav);
    final isSpeech = mav > _rmsThreshold;
    final samplesInChunk = chunk.length ~/ 2;

    if (isSpeech) {
      _silenceSamples = 0;
      _hadSpeech = true;
    } else if (_hadSpeech) {
      _silenceSamples += samplesInChunk;
    }

    final silenceMs = _silenceSamples * 1000 ~/ _sampleRate;
    if (_hadSpeech && silenceMs >= _silenceThresholdMs) {
      _enqueueRecognizeBatch();
    }
  }

  double _calcMav(List<int> bytes) {
    var sum = 0;
    for (var i = 0; i < bytes.length - 1; i += 2) {
      final unsigned = ((bytes[i + 1] & 0xFF) << 8) | (bytes[i] & 0xFF);
      final sample = unsigned > 32767 ? unsigned - 65536 : unsigned;
      sum += sample.abs();
    }
    final count = bytes.length ~/ 2;
    return count > 0 ? sum / count : 0.0;
  }

  void _enqueueRecognizeBatch() {
    if (_buffer.isEmpty || _stopping) return;
    final pcmData = List<int>.from(_buffer);
    _buffer.clear();
    _hadSpeech = false;
    _silenceSamples = 0;

    _recognitionQueue = (_recognitionQueue ?? Future.value())
        .then((_) => _recognizeBatch(pcmData))
        .catchError((_) {});
  }

  Future<void> _recognizeBatch(List<int> pcmData) async {
    if (pcmData.isEmpty || _stopping) return;

    File? wavFile;
    try {
      final tempDir = await getTemporaryDirectory();
      wavFile = File(
        '${tempDir.path}/whisper_batch_${DateTime.now().microsecondsSinceEpoch}.wav',
      );
      await wavFile.writeAsBytes(_pcm16ToWav(pcmData), flush: true);

      if (_stopping) return;

      final response = await _whisper.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: wavFile.path,
          // Los códigos de idioma de la app ('es','en','pt','fr',...) ya son
          // los mismos que usa whisper.cpp — a diferencia de Google STT/TTS,
          // acá no hace falta ningún mapeo a variantes tipo 'es-ES'.
          language: _languageCode,
          isTranslate: false,
          isNoTimestamps: true,
          splitOnWord: false,
          threads: 4,
        ),
      );

      if (_stopping) return;

      final transcript = response.text.trim();
      if (transcript.isEmpty) return;

      _controller?.add(SttResult(
        transcript: transcript,
        isFinal: true,
        // whisper.cpp no expone un score de confianza como Google STT.
        // No pasa nada: nada en el pipeline (translation_repository_impl.dart)
        // lee este campo hoy.
        confidence: 1.0,
      ));
    } catch (e) {
      _controller?.addError('Whisper STT error: $e');
    } finally {
      if (wavFile != null) {
        try {
          await wavFile.delete();
        } catch (_) {}
      }
    }
  }

  /// Arma un WAV canónico de 44 bytes de header a partir de PCM16 mono crudo.
  /// El audio ya llega en este formato exacto desde el canal nativo — no hace
  /// falta ninguna conversión de formato, solo envolverlo en un header WAV
  /// para que whisper.cpp pueda leerlo desde archivo.
  Uint8List _pcm16ToWav(List<int> pcmBytes) {
    final dataLength = pcmBytes.length;
    const bitsPerSample = 16;
    const numChannels = 1;
    final byteRate = _sampleRate * numChannels * bitsPerSample ~/ 8;
    const blockAlign = numChannels * bitsPerSample ~/ 8;

    final header = BytesBuilder();
    header.add(ascii.encode('RIFF'));
    header.add(_uint32le(36 + dataLength));
    header.add(ascii.encode('WAVE'));
    header.add(ascii.encode('fmt '));
    header.add(_uint32le(16));
    header.add(_uint16le(1)); // PCM
    header.add(_uint16le(numChannels));
    header.add(_uint32le(_sampleRate));
    header.add(_uint32le(byteRate));
    header.add(_uint16le(blockAlign));
    header.add(_uint16le(bitsPerSample));
    header.add(ascii.encode('data'));
    header.add(_uint32le(dataLength));
    header.add(pcmBytes);
    return header.toBytes();
  }

  Uint8List _uint32le(int value) {
    final b = ByteData(4)..setUint32(0, value, Endian.little);
    return b.buffer.asUint8List();
  }

  Uint8List _uint16le(int value) {
    final b = ByteData(2)..setUint16(0, value, Endian.little);
    return b.buffer.asUint8List();
  }

  @override
  Future<void> stop() async {
    _stopping = true;
    AudioLevelService.instance.reset();
    await _micSub?.cancel();
    _micSub = null;
    _recognitionQueue = null;
    try {
      await _audioChannel.invokeMethod('stopRecording');
      await _passthroughChannel.invokeMethod('stop');
    } catch (_) {}
    await _controller?.close();
    _controller = null;
    _buffer.clear();
  }

  // ── Descarga del modelo (mismo patrón que MlKitTranslateDatasource) ──

  /// Tamaño mínimo esperado por modelo (bytes), a modo de chequeo de
  /// integridad barato. Si el archivo existe pero pesa menos que esto, es
  /// que una descarga anterior quedó a medias (red cortada, app cerrada a
  /// mitad de la descarga, etc.) — un .bin de ggml truncado NO tira una
  /// excepción de Dart al cargarlo: whisper.cpp lo lee del lado nativo (FFI)
  /// y un archivo corrupto ahí crashea el proceso entero sin dar chance de
  /// capturar el error. Por eso esta validación es la única defensa real.
  static const Map<WhisperModel, int> _minExpectedBytes = {
    WhisperModel.tiny: 70 * 1000 * 1000,
    WhisperModel.base: 130 * 1000 * 1000,
    WhisperModel.small: 450 * 1000 * 1000,
    WhisperModel.medium: 1400 * 1000 * 1000,
    WhisperModel.largeV1: 2800 * 1000 * 1000,
    WhisperModel.largeV2: 2800 * 1000 * 1000,
  };

  Future<Directory> _resolveModelDir() {
    return Platform.isAndroid ? getApplicationSupportDirectory() : getLibraryDirectory();
  }

  /// Verifica si el modelo de Whisper ya está descargado Y es un archivo
  /// completo (no un .bin truncado de una descarga anterior interrumpida).
  Future<bool> isModelDownloaded() async {
    final dir = await _resolveModelDir();
    final file = File(_model.getPath(dir.path));
    if (!file.existsSync()) return false;

    final minBytes = _minExpectedBytes[_model] ?? 0;
    if (file.lengthSync() < minBytes) {
      // Archivo corrupto/incompleto: lo borramos para forzar una descarga
      // limpia la próxima vez, en vez de dejar una bomba de tiempo nativa.
      try {
        file.deleteSync();
      } catch (_) {}
      return false;
    }
    return true;
  }

  /// Descarga el modelo de Whisper con progreso, guardándolo en el mismo path
  /// que después va a buscar la librería nativa — si ya está descargado (y
  /// es válido), no vuelve a bajarlo.
  Future<void> downloadModel({required void Function(double progress) onProgress}) async {
    if (await isModelDownloaded()) {
      onProgress(1.0);
      return;
    }

    final dir = await _resolveModelDir();
    final destination = File(_model.getPath(dir.path));

    final uri = Uri.parse(
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${_model.modelName}.bin',
    );

    try {
      final response = await _http.send(http.Request('GET', uri));
      if (response.statusCode != 200) {
        throw ServerException(
          message: 'No se pudo descargar el modelo de voz (HTTP ${response.statusCode})',
        );
      }

      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = destination.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress(received / total);
        }
      } finally {
        await sink.close();
      }

      // La conexión puede cortarse a mitad de la descarga sin que el stream
      // tire una excepción (queda un archivo más chico de lo esperado).
      // Verificamos el tamaño final antes de darla por buena.
      final minBytes = _minExpectedBytes[_model] ?? 0;
      if (destination.lengthSync() < minBytes) {
        throw ServerException(
          message: 'La descarga del modelo de voz quedó incompleta (conexión cortada)',
        );
      }

      onProgress(1.0);
    } catch (e) {
      if (destination.existsSync()) {
        try {
          destination.deleteSync();
        } catch (_) {}
      }
      rethrow;
    }
  }
}
