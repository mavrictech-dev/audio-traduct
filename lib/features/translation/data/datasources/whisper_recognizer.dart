import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audio_traductor/core/errors/exceptions.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';

/// Reconocimiento de voz offline con whisper.cpp (on-device, sin red, sin key).
///
/// Solo transcribe — no captura audio ni sabe de segmentación por silencio,
/// eso vive en `SilenceGatedCapture` y es compartido con el reconocedor cloud.
/// Se usa como fallback dentro de `HybridSttDatasource` cuando no hay
/// internet o falla Google Cloud STT.
class WhisperRecognizer {
  static const _sampleRate = 16000;

  // 'tiny' por defecto: prioriza latencia sobre precisión. whisper.cpp
  // recarga el modelo completo desde disco EN CADA transcripción (no hay
  // forma de mantener el contexto cargado con este plugin) — por eso el
  // tamaño del modelo importa menos de lo que parece; aun así 'tiny' es la
  // opción más liviana disponible.
  final WhisperModel model;
  final Whisper _whisper;

  WhisperRecognizer({this.model = WhisperModel.tiny}) : _whisper = Whisper(model: model);

  /// Núcleos a usar en la inferencia, con techo para no competir con la UI.
  int get _inferenceThreads {
    final cores = Platform.numberOfProcessors;
    return cores < 4 ? cores : (cores > 6 ? 6 : cores);
  }

  /// Transcribe un bloque de PCM16 mono 16kHz. Tira excepción si falla —
  /// el llamador decide qué hacer (típicamente: nada más, ya es el fallback).
  Future<String> recognize(List<int> pcmData, String languageCode) async {
    File? wavFile;
    try {
      final tempDir = await getTemporaryDirectory();
      wavFile = File(
        '${tempDir.path}/whisper_batch_${DateTime.now().microsecondsSinceEpoch}.wav',
      );
      await wavFile.writeAsBytes(_pcm16ToWav(pcmData), flush: true);

      final response = await _whisper.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: wavFile.path,
          // Los códigos de idioma de la app ('es','en','pt','fr',...) ya son
          // los mismos que usa whisper.cpp — no hace falta mapeo.
          language: languageCode,
          isTranslate: false,
          isNoTimestamps: true,
          splitOnWord: false,
          threads: _inferenceThreads,
        ),
      );

      return response.text.trim();
    } finally {
      if (wavFile != null) {
        try {
          await wavFile.delete();
        } catch (_) {}
      }
    }
  }

  /// Arma un WAV canónico de 44 bytes de header a partir de PCM16 mono crudo.
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

  // ── Descarga del modelo ──

  /// Tamaño mínimo esperado por modelo (bytes), a modo de chequeo de
  /// integridad barato. Ver nota completa en el historial: un .bin de ggml
  /// truncado crashea el proceso del lado nativo (FFI), no tira una
  /// excepción de Dart atrapable.
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

  /// Verifica si el modelo ya está descargado Y es un archivo completo.
  Future<bool> isModelDownloaded() async {
    final dir = await _resolveModelDir();
    final file = File(model.getPath(dir.path));
    if (!file.existsSync()) return false;

    final minBytes = _minExpectedBytes[model] ?? 0;
    if (file.lengthSync() < minBytes) {
      try {
        file.deleteSync();
      } catch (_) {}
      return false;
    }
    return true;
  }

  /// Descarga el modelo con progreso; si ya está descargado (y es válido),
  /// no vuelve a bajarlo.
  Future<void> downloadModel({required void Function(double progress) onProgress}) async {
    if (await isModelDownloaded()) {
      onProgress(1.0);
      return;
    }

    final dir = await _resolveModelDir();
    final destination = File(model.getPath(dir.path));
    final uri = Uri.parse(
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${model.modelName}.bin',
    );
    final client = http.Client();

    try {
      final response = await client.send(http.Request('GET', uri));
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

      final minBytes = _minExpectedBytes[model] ?? 0;
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
    } finally {
      client.close();
    }
  }
}
