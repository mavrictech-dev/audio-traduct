import 'dart:async';
import 'package:audio_traductor/core/services/silence_gated_capture.dart';
import 'package:audio_traductor/features/translation/data/datasources/cloud_stt_recognizer.dart';
import 'package:audio_traductor/features/translation/data/datasources/stt_datasource.dart';
import 'package:audio_traductor/features/translation/data/datasources/whisper_recognizer.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// STT híbrido: nube cuando hay internet (rápido), Whisper local como
/// respaldo (offline, o si la nube falla por cualquier motivo).
///
/// Por qué: whisper.cpp recarga el modelo entero desde disco en CADA
/// transcripción (no hay forma de mantenerlo cargado con el plugin actual),
/// lo que lo hace notablemente más lento que Google Cloud STT para uso en
/// vivo. Este datasource prioriza velocidad cuando hay conexión, y solo cae a
/// Whisper cuando de verdad no hay más remedio — así se mantiene la promesa
/// de que la app funciona sin internet, sin resignar velocidad cuando sí lo
/// hay.
///
/// La captura nativa y la segmentación por silencio son compartidas
/// (`SilenceGatedCapture`) — lo único que cambia por bloque es QUIÉN lo
/// transcribe.
class HybridSttDatasource implements SttDatasource {
  final SilenceGatedCapture _capture = SilenceGatedCapture();
  final CloudSttRecognizer _cloud = CloudSttRecognizer();
  final WhisperRecognizer _whisper;

  StreamSubscription<List<int>>? _batchSub;
  StreamController<SttResult>? _controller;
  String _languageCode = 'es';
  bool _stopping = false;
  Future<void>? _recognitionQueue;

  HybridSttDatasource({WhisperRecognizer? whisper})
    : _whisper = whisper ?? WhisperRecognizer();

  @override
  Stream<SttResult> startStreaming({
    required Stream<List<int>> audioStream,
    required String languageCode,
  }) async* {
    _controller = StreamController<SttResult>.broadcast();
    _stopping = false;
    _languageCode = languageCode;
    _recognitionQueue = null;

    final batches = _capture.start();
    _batchSub = batches.listen(
      _onBatchReady,
      onError: (e) => _controller?.addError(e),
    );

    yield* _controller!.stream;
  }

  void _onBatchReady(List<int> pcmData) {
    if (_stopping || pcmData.isEmpty) return;
    // Cola estricta: el bloque N+1 no se transcribe antes que termine el N,
    // así los párrafos salen en el orden en que se hablaron (misma idea que
    // ya usaba GoogleSttDatasource).
    _recognitionQueue = (_recognitionQueue ?? Future.value())
        .then((_) => _recognizeBatch(pcmData))
        .catchError((_) {});
  }

  Future<void> _recognizeBatch(List<int> pcmData) async {
    if (pcmData.isEmpty || _stopping) return;

    final transcript = await _recognizeWithFallback(pcmData);
    if (_stopping || transcript == null || transcript.isEmpty) return;

    _controller?.add(
      SttResult(transcript: transcript, isFinal: true, confidence: 1.0),
    );
  }

  /// Intenta nube primero (si hay conexión); ante CUALQUIER falla —sin key,
  /// sin red, timeout, error de la API— cae a Whisper local sin propagar el
  /// error de la nube (para el usuario, la traducción simplemente sigue).
  Future<String?> _recognizeWithFallback(List<int> pcmData) async {
    if (await _isOnline()) {
      try {
        return await _cloud.recognize(pcmData, _languageCode);
      } catch (_) {
        // sigue al fallback local
      }
    }

    try {
      return await _whisper.recognize(pcmData, _languageCode);
    } catch (e) {
      _controller?.addError('STT error: $e');
      return null;
    }
  }

  /// Se chequea antes de CADA bloque (no solo al arrancar la sesión): la
  /// conexión puede caerse a mitad de una charla larga y queremos adaptarnos,
  /// no quedarnos pegados al camino que era válido al principio.
  Future<bool> _isOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.isNotEmpty &&
          results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    if (_stopping) return;

    // La captura emite primero la frase que todavía estaba abierta. Mantener
    // el listener y la cola activos evita perder las últimas palabras.
    await _capture.stop();
    await _recognitionQueue;

    _stopping = true;
    await _batchSub?.cancel();
    _batchSub = null;
    _recognitionQueue = null;
    await _controller?.close();
    _controller = null;
  }

  // ── Descarga del modelo de Whisper (fallback offline) ──

  Future<bool> isSttModelDownloaded() => _whisper.isModelDownloaded();

  Future<void> downloadSttModel({
    required void Function(double progress) onProgress,
  }) {
    return _whisper.downloadModel(onProgress: onProgress);
  }
}
