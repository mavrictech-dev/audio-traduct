import 'dart:async';
import 'package:audio_traductor/core/services/audio_level_service.dart';
import 'package:flutter/services.dart';

/// Captura nativa del mic + segmentación de baja latencia.
///
/// Extraído de lo que antes vivía adentro de `WhisperSttDatasource`: esta
/// parte es compartida por cualquier motor de reconocimiento (cloud, local,
/// o el híbrido que decide entre los dos) — no tiene nada que ver con QUIÉN
/// transcribe el bloque, solo con CUÁNDO un bloque de audio está listo para
/// mandarse a reconocer.
class SilenceGatedCapture {
  // Para no amputar palabras suaves al final, esperamos una pausa completa y
  // enviamos TODO el audio capturado, incluido el silencio final. A partir de
  // 5 s aprovechamos una pausa breve para mantener baja la latencia; solo
  // forzamos un corte tras 30 s de voz totalmente continua.
  static const _silenceThresholdMs = 650;
  static const _preferredUtteranceMs = 5000;
  static const _boundarySilenceMs = 250;
  static const _hardUtteranceMs = 30000;
  static const _preRollMs = 300;
  static const _minSpeechMs = 100;
  static const _rmsThreshold = 300;
  static const sampleRate = 16000;
  static const _audioChannel = MethodChannel('com.audiotraductor/audio');
  static const _micChannel = EventChannel('com.audiotraductor/mic');

  StreamSubscription<List<int>>? _micSub;
  StreamController<List<int>>? _batchController;
  bool _stopping = false;
  final List<int> _buffer = [];
  final List<int> _preRollBuffer = [];
  int _silenceSamples = 0;
  int _utteranceSamples = 0;
  int _speechSamples = 0;
  bool _hadSpeech = false;

  /// Arranca la captura nativa y devuelve un stream de bloques de PCM16 mono
  /// 16kHz, cada uno ya cortado por una pausa de silencio.
  Stream<List<int>> start() {
    _batchController = StreamController<List<int>>.broadcast();
    _stopping = false;
    _buffer.clear();
    _preRollBuffer.clear();
    _silenceSamples = 0;
    _utteranceSamples = 0;
    _speechSamples = 0;
    _hadSpeech = false;

    unawaited(_init());

    return _batchController!.stream;
  }

  Future<void> _init() async {
    try {
      await _audioChannel.invokeMethod('startRecording');

      final stream = _micChannel.receiveBroadcastStream().map<List<int>>((
        event,
      ) {
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

    final mav = _calcMav(chunk);
    AudioLevelService.instance.updateLevel(mav);
    final isSpeech = mav > _rmsThreshold;
    final samplesInChunk = chunk.length ~/ 2;

    if (!_hadSpeech) {
      _appendPreRoll(chunk);
      if (!isSpeech) return;

      // Conserva unas décimas previas para no cortar la primera sílaba.
      _buffer.addAll(_preRollBuffer);
      _preRollBuffer.clear();
      _hadSpeech = true;
      _utteranceSamples = samplesInChunk;
      _speechSamples = samplesInChunk;
      _silenceSamples = 0;
      return;
    }

    _buffer.addAll(chunk);
    _utteranceSamples += samplesInChunk;
    if (isSpeech) {
      _silenceSamples = 0;
      _speechSamples += samplesInChunk;
    } else {
      _silenceSamples += samplesInChunk;
    }

    final silenceMs = _silenceSamples * 1000 ~/ sampleRate;
    final utteranceMs = _utteranceSamples * 1000 ~/ sampleRate;
    final reachedSafeBoundary =
        utteranceMs >= _preferredUtteranceMs && silenceMs >= _boundarySilenceMs;
    if (silenceMs >= _silenceThresholdMs ||
        reachedSafeBoundary ||
        utteranceMs >= _hardUtteranceMs) {
      _flushBatch();
    }
  }

  void _appendPreRoll(List<int> chunk) {
    _preRollBuffer.addAll(chunk);
    final maxBytes = sampleRate * _preRollMs ~/ 1000 * 2;
    if (_preRollBuffer.length > maxBytes) {
      _preRollBuffer.removeRange(0, _preRollBuffer.length - maxBytes);
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

  void _flushBatch({bool allowWhileStopping = false}) {
    if (_buffer.isEmpty || (_stopping && !allowWhileStopping)) return;

    final minimumSpeechSamples = sampleRate * _minSpeechMs ~/ 1000;
    final pcmData = _speechSamples >= minimumSpeechSamples
        // No recortar la cola: una sílaba final suave puede caer por debajo
        // del umbral y parecer silencio aunque todavía sea parte de la palabra.
        ? List<int>.from(_buffer)
        : const <int>[];
    _buffer.clear();
    _preRollBuffer.clear();
    _hadSpeech = false;
    _silenceSamples = 0;
    _utteranceSamples = 0;
    _speechSamples = 0;
    if (pcmData.isNotEmpty) _batchController?.add(pcmData);
  }

  Future<void> stop() async {
    if (_stopping) return;
    AudioLevelService.instance.reset();
    await _micSub?.cancel();
    _micSub = null;
    try {
      await _audioChannel.invokeMethod('stopRecording');
    } catch (_) {}

    // Entregar la frase que quedó abierta antes de cerrar el stream. El
    // consumidor mantiene su listener hasta que este último bloque termine.
    _flushBatch(allowWhileStopping: true);
    _stopping = true;
    await _batchController?.close();
    _batchController = null;
    _buffer.clear();
    _preRollBuffer.clear();
  }
}
