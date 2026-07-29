import 'dart:convert';
import 'package:audio_traductor/core/constants/api_constants.dart';
import 'package:audio_traductor/core/errors/exceptions.dart';
import 'package:http/http.dart' as http;

/// Reconocimiento de voz vía Google Cloud Speech-to-Text.
///
/// Solo transcribe — no captura audio ni sabe de segmentación por silencio.
/// Es el camino "rápido" dentro de `HybridSttDatasource`: se usa cuando hay
/// internet, y si falla por cualquier motivo (sin key, sin red, timeout,
/// error de la API) el llamador cae a `WhisperRecognizer` offline.
class CloudSttRecognizer {
  final http.Client _http = http.Client();

  Future<String> recognize(
    List<int> pcmData,
    String languageCode, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!ApiConstants.hasSttKey) {
      throw const ServerException(
        message: 'Google Cloud STT no configurado (falta API key)',
      );
    }

    final base64Audio = base64Encode(pcmData);
    final uri = Uri.parse(ApiConstants.sttEndpoint).replace(
      queryParameters: {'key': ApiConstants.sttApiKey},
    );

    final response = await _http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'config': {
              'encoding': 'LINEAR16',
              'sampleRateHertz': 16000,
              'languageCode': _mapLanguage(languageCode),
              'model': 'latest_long',
              'enableAutomaticPunctuation': true,
              'maxAlternatives': 1,
            },
            'audio': {'content': base64Audio},
          }),
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw ServerException(
        message: 'Google STT error ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = data['results'] as List?;
    if (results == null || results.isEmpty) return '';

    final transcripts = <String>[];
    for (final item in results) {
      final result = item as Map<String, dynamic>;
      final alternatives = result['alternatives'] as List?;
      if (alternatives == null || alternatives.isEmpty) continue;
      final first = alternatives.first as Map;
      final transcript = (first['transcript'] as String?)?.trim();
      if (transcript != null && transcript.isNotEmpty) {
        transcripts.add(transcript);
      }
    }
    return transcripts.join(' ').trim();
  }

  String _mapLanguage(String code) {
    const map = {
      'es': 'es-ES', 'en': 'en-US', 'pt': 'pt-BR', 'fr': 'fr-FR',
      'de': 'de-DE', 'it': 'it-IT', 'ja': 'ja-JP', 'zh': 'zh-CN',
      'ko': 'ko-KR', 'ru': 'ru-RU', 'ar': 'ar-SA', 'nl': 'nl-NL',
    };
    return map[code] ?? 'en-US';
  }
}
