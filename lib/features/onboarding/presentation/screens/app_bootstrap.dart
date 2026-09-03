import 'package:audio_traductor/app.dart';
import 'package:audio_traductor/core/di/injection_container.dart';
import 'package:audio_traductor/features/onboarding/data/onboarding_store.dart';
import 'package:audio_traductor/features/onboarding/presentation/screens/splash_screen.dart';
import 'package:audio_traductor/features/onboarding/presentation/widgets/terms_dialog.dart';
import 'package:audio_traductor/features/translation/data/datasources/tts_datasource.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Etapas del arranque.
enum _Stage { loading, terms, ready }

/// Puerta de entrada de la app: pantalla de carga, luego -solo en el primer
/// inicio del dispositivo- los Términos y Condiciones, y recién ahí el shell
/// principal.
///
/// La inicialización pesada (dependencias, TTS) corre *durante* la pantalla
/// de carga en vez de antes de `runApp()`, así el usuario ve la animación en
/// lugar de un arranque en blanco. Los permisos se piden después de aceptar
/// los términos, no antes.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  _Stage _stage = _Stage.loading;

  /// Trabajo de arranque que antes vivía en `main()`.
  Future<void> _initialize(void Function(String) report) async {
    report('Preparando la app...');
    await OnboardingStore.init();

    report('Cargando motores de traducción...');
    await InjectionContainer.init();

    report('Preparando la voz...');
    // Sin await: precalienta en segundo plano, no hace falta esperarlo.
    RealTtsDatasource.instance.warmup('en', 'en-US-Wavenet-D');

    report('Todo listo');
  }

  /// Al terminar la carga: términos si nunca se aceptaron, si no derecho al
  /// shell principal.
  void _onSplashFinished() {
    if (OnboardingStore.hasAcceptedTerms) {
      _enterApp();
    } else {
      setState(() => _stage = _Stage.terms);
    }
  }

  Future<void> _onTermsAccepted() async {
    await OnboardingStore.acceptTerms();
    if (!mounted) return;
    _enterApp();
  }

  void _enterApp() {
    setState(() => _stage = _Stage.ready);
    _requestPermissions();
  }

  /// Micrófono y Bluetooth. Se piden una vez adentro de la app para que el
  /// usuario ya tenga contexto de para qué son.
  Future<void> _requestPermissions() async {
    final recorder = AudioRecorder();
    try {
      if (!await recorder.hasPermission()) {
        final stream = await recorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            numChannels: 1,
            sampleRate: 16000,
          ),
        );
        stream.listen(null).cancel();
        await recorder.stop();
      }
    } catch (_) {
      // El usuario puede haber rechazado el permiso: la pantalla principal
      // ya avisa cuando no hay micrófono disponible.
    }

    // BLUETOOTH_CONNECT: necesario para desconectar HFP y usar el mic del celular.
    await Permission.bluetoothConnect.request();
  }

  @override
  Widget build(BuildContext context) {
    // El shell se monta apenas se aceptan los términos y ya no se desmonta,
    // para no reconstruir la app entera detrás del modal.
    return Stack(
      children: [
        if (_stage == _Stage.ready) const MainShell(),
        if (_stage == _Stage.loading)
          SplashScreen(
            onInitialize: _initialize,
            onFinished: _onSplashFinished,
          ),
        if (_stage == _Stage.terms) _TermsLayer(onAccepted: _onTermsAccepted),
      ],
    );
  }
}

/// Capa a pantalla completa que muestra el modal legal sobre un velo oscuro.
class _TermsLayer extends StatelessWidget {
  final VoidCallback onAccepted;

  const _TermsLayer({required this.onAccepted});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        color: isDark
            ? const Color(0xFF0A1628).withValues(alpha: 0.92)
            : const Color(0xFFE8F0FE).withValues(alpha: 0.94),
        child: TermsDialog(onAccepted: onAccepted),
      ),
    );
  }
}
