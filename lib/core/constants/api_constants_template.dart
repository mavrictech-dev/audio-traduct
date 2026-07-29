// Copiá este archivo como api_constants.dart y completá tu propia key.
// api_constants.dart está en .gitignore — NO se sube al repo.
//
// Esta key es OPCIONAL: si no la configurás (o si es inválida), la app sigue
// funcionando 100% offline con Whisper local — Google Cloud STT es solo el
// camino rápido cuando hay internet, ver HybridSttDatasource.

class ApiConstants {
  ApiConstants._();

  static const String sttApiKey = 'INGRESA_TU_STT_API_KEY';

  static const String sttEndpoint =
      'https://speech.googleapis.com/v1/speech:recognize';

  /// true solo si de verdad completaste una key (no el placeholder).
  static bool get hasSttKey =>
      sttApiKey.isNotEmpty && !sttApiKey.startsWith('INGRESA_');
}
