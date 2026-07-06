import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:audio_traductor/core/constants/api_constants.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

abstract class SttDatasource {
  Stream<SttResult> startStreaming({
    required Stream<List<int>> audioStream,
    required String languageCode,
  });

  Future<void> stop();
}

class SttResult {
  final String transcript;
  final bool isFinal;
  final double confidence;

  const SttResult({
    required this.transcript,
    this.isFinal = false,
    this.confidence = 0.0,
  });
}

/// Google Cloud Speech-to-Text con segmentación manual por silencio.
///
/// Flujo:
/// - el mic del celular sigue capturando audio nativo
/// - 600ms de pausa cierran el párrafo
/// - ese bloque se manda a Google STT
/// - la app sigue escuchando mientras traduce/reproduce el anterior
class GoogleSttDatasource implements SttDatasource {
  static const _silenceThresholdMs = 600;
  static const _rmsThreshold = 700;
  static const _audioChannel = MethodChannel('com.audiotraductor/audio');
  static const _micChannel = EventChannel('com.audiotraductor/mic');

  final String _apiKey;
  final http.Client _http = http.Client();
  StreamSubscription<List<int>>? _micSub;
  StreamController<SttResult>? _controller;
  bool _stopping = false;
  String _languageCode = 'es';
  final List<int> _buffer = [];
  int _silenceSamples = 0;
  bool _hadSpeech = false;
  Future<void>? _recognitionQueue;

  GoogleSttDatasource(this._apiKey);

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
      await _audioChannel.invokeMethod('forceBuiltinMic');
      await Future.delayed(const Duration(milliseconds: 150));
      await _audioChannel.invokeMethod('startRecording');

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
    final isSpeech = mav > _rmsThreshold;
    final samplesInChunk = chunk.length ~/ 2;

    if (isSpeech) {
      _silenceSamples = 0;
      _hadSpeech = true;
    } else if (_hadSpeech) {
      _silenceSamples += samplesInChunk;
    }

    final silenceMs = _silenceSamples * 1000 ~/ 16000;
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

    try {
      final base64Audio = base64Encode(pcmData);
      final uri = Uri.parse(ApiConstants.sttEndpoint).replace(
        queryParameters: {'key': _apiKey},
      );

      final response = await _http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'config': {
            'encoding': 'LINEAR16',
            'sampleRateHertz': 16000,
            'languageCode': _mapLanguage(_languageCode),
            'model': 'latest_long',
            'enableAutomaticPunctuation': true,
            'maxAlternatives': 1,
          },
          'audio': {'content': base64Audio},
        }),
      );

      if (response.statusCode != 200 || _stopping) {
        if (response.statusCode != 200) {
          _controller?.addError('STT API error ${response.statusCode}: ${response.body}');
        }
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List?;
      if (results == null || results.isEmpty) return;

      final transcripts = <String>[];
      double confidence = 1.0;

      for (final item in results) {
        final result = item as Map<String, dynamic>;
        final alternatives = result['alternatives'] as List?;
        if (alternatives == null || alternatives.isEmpty) continue;
        final first = alternatives.first as Map;
        final transcript = (first['transcript'] as String?)?.trim();
        if (transcript != null && transcript.isNotEmpty) {
          transcripts.add(transcript);
        }
        confidence = ((first['confidence'] as num?)?.toDouble() ?? confidence);
      }

      final finalTranscript = transcripts.join(' ').trim();
      if (finalTranscript.isEmpty || _stopping) return;

      _controller?.add(SttResult(
        transcript: finalTranscript,
        isFinal: true,
        confidence: confidence,
      ));
    } catch (e) {
      _controller?.addError('STT error: $e');
    }
  }

  @override
  Future<void> stop() async {
    _stopping = true;
    await _micSub?.cancel();
    _micSub = null;
    _recognitionQueue = null;
    try {
      await _audioChannel.invokeMethod('stopRecording');
    } catch (_) {}
    await _controller?.close();
    _controller = null;
    _buffer.clear();
  }

  String _mapLanguage(String code) {
    const map = {
      'es': 'es-ES',
      'en': 'en-US',
      'pt': 'pt-BR',
      'fr': 'fr-FR',
      'de': 'de-DE',
      'it': 'it-IT',
      'ja': 'ja-JP',
      'zh': 'zh-CN',
      'ko': 'ko-KR',
      'ru': 'ru-RU',
      'ar': 'ar-SA',
      'nl': 'nl-NL',
    };
    return map[code] ?? 'en-US';
  }
}
