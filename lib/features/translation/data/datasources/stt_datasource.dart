/// Contrato abstracto para la transcripción de voz (Speech-to-Text).
///
/// Implementación de producción: [WhisperSttDatasource] (on-device, offline,
/// vía whisper.cpp). No hay implementación cloud — ver README §3 del proyecto
/// original para el motivo de la migración.
abstract class SttDatasource {
  Stream<SttResult> startStreaming({
    required Stream<List<int>> audioStream,
    required String languageCode,
  });

  Future<void> stop();
}

/// Resultado de una transcripción.
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
