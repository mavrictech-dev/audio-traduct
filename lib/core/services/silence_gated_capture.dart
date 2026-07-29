import 'dart:async';
import 'package:audio_traductor/core/services/audio_level_service.dart';
import 'package:flutter/services.dart';

/// Captura nativa del mic + segmentación por silencio (~600ms).
///
/// Extraído de lo que antes vivía adentro de `WhisperSttDatasource`: esta
/// parte es compartida por cualquier motor de reconocimiento (cloud, local,
/// o el híbrido que decide entre los dos) — no tiene nada que ver con QUIÉN
/// transcribe el bloque, solo con CUÁNDO un bloque de audio está listo para
/// mandarse a reconocer.
class SilenceGatedCapture {
  static const _silenceThresholdMs = 600;
  static const _rmsThreshold = 700;
  static const sampleRate = 16000;
  static const _audioChannel = MethodChannel('com.audiotraductor/audio');
  static const _micChannel = EventChannel('com.audiotraductor/mic');
  static const _passthroughChannel = MethodChannel('com.audiotraductor/passthrough');

  StreamSubscription<List<int>>? _micSub;
  StreamController<List<int>>? _batchController;
  bool _stopping = false;
  final List<int> _buffer = [];
  int _silenceSamples = 0;
  bool _hadSpeech = false;

  /// Arranca la captura nativa y devuelve un stream de bloques de PCM16 mono
  /// 16kHz, cada uno ya cortado por una pausa de silencio.
  Stream<List<int>> start() {
    _batchController = StreamController<List<int>>.broadcast();
    _stopping = false;
    _buffer.clear();
    _silenceSamples = 0;
    _hadSpeech = false;

    unawaited(_init());

    return _batchController!.stream;
  }

  Future<void> _init() async {
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
        onError: (e) => _batchController?.addError('Mic: $e'),
      );
    } catch (e) {
      _batchController?.addError('Error al iniciar mic: $e');
    }
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

    final silenceMs = _silenceSamples * 1000 ~/ sampleRate;
    if (_hadSpeech && silenceMs >= _silenceThresholdMs) {
      _flushBatch();
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

  void _flushBatch() {
    if (_buffer.isEmpty || _stopping) return;
    final pcmData = List<int>.from(_buffer);
    _buffer.clear();
    _hadSpeech = false;
    _silenceSamples = 0;
    _batchController?.add(pcmData);
  }

  Future<void> stop() async {
    _stopping = true;
    AudioLevelService.instance.reset();
    await _micSub?.cancel();
    _micSub = null;
    try {
      await _audioChannel.invokeMethod('stopRecording');
      await _passthroughChannel.invokeMethod('stop');
    } catch (_) {}
    await _batchController?.close();
    _batchController = null;
    _buffer.clear();
  }
}
