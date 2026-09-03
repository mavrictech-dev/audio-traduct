/// Texto de los Términos y Condiciones.
///
/// Si se modifica el contenido de forma sustancial, subir también
/// `OnboardingStore.currentTermsVersion` para que se vuelva a pedir la
/// aceptación una única vez.
class TermsContent {
  TermsContent._();

  static const String intro =
      'Al usar Audio Traductor aceptás las siguientes condiciones. '
      'Leelas antes de continuar.';

  static const List<TermsSection> sections = [
    TermsSection(
      title: '1. Uso del micrófono',
      body:
          'La app necesita acceso al micrófono para captar la voz y traducirla '
          'en tiempo real. El audio se procesa únicamente mientras la '
          'traducción está activa y no se guarda en el dispositivo como '
          'archivo de audio.',
    ),
    TermsSection(
      title: '2. Procesamiento de la voz',
      body:
          'Cuando hay conexión a internet, el reconocimiento de voz puede '
          'realizarse en servicios en la nube para mejorar la precisión. Sin '
          'conexión, el reconocimiento se hace en el propio dispositivo. La '
          'traducción entre idiomas se ejecuta siempre de forma local.',
    ),
    TermsSection(
      title: '3. Historial y datos',
      body:
          'Las transcripciones y traducciones se almacenan solo en tu '
          'dispositivo. Podés consultarlas, exportarlas o eliminarlas desde la '
          'pestaña Historial. Desinstalar la app borra esa información de '
          'forma permanente.',
    ),
    TermsSection(
      title: '4. Precisión del servicio',
      body:
          'La traducción automática puede contener errores. No debe usarse '
          'como única fuente en contextos médicos, legales, financieros o de '
          'seguridad, donde una interpretación equivocada pueda causar daño.',
    ),
    TermsSection(
      title: '5. Uso responsable',
      body:
          'Sos responsable de contar con el consentimiento de las personas '
          'cuya voz se capture, y de cumplir con la legislación aplicable '
          'sobre grabación y tratamiento de datos en tu jurisdicción.',
    ),
    TermsSection(
      title: '6. Propiedad y contacto',
      body:
          'Audio Traductor es desarrollado por Mavric Technologies. La marca, '
          'el diseño y el código son propiedad de Mavric Technologies. Ante '
          'cualquier consulta sobre estas condiciones podés contactarnos.',
    ),
  ];
}

/// Un apartado del texto legal.
class TermsSection {
  final String title;
  final String body;

  const TermsSection({required this.title, required this.body});
}
