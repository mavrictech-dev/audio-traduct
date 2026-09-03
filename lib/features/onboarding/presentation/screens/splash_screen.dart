import 'dart:math' as math;

import 'package:audio_traductor/core/branding/app_logo.dart';
import 'package:audio_traductor/core/branding/brand_assets.dart';
import 'package:audio_traductor/core/branding/brand_image.dart';
import 'package:audio_traductor/core/constants/app_constants.dart';
import 'package:audio_traductor/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Pantalla de carga de la app.
///
/// Hace dos cosas a la vez:
///   1. Corre la inicialización pesada ([onInitialize]) — dependencias, TTS,
///      lectura de preferencias — mientras el usuario ve la animación.
///   2. Garantiza un tiempo mínimo en pantalla ([minimumDuration]) para que
///      la animación no aparezca y desaparezca de un parpadeo en dispositivos
///      rápidos.
///
/// Cuando terminan ambas cosas, se desvanece y llama a [onFinished].
class SplashScreen extends StatefulWidget {
  /// Trabajo de arranque. Recibe un reporter para ir contando en qué anda.
  final Future<void> Function(void Function(String status) report)? onInitialize;

  /// Se llama una vez completada la carga y la animación de salida.
  final VoidCallback onFinished;

  /// Tiempo mínimo que la pantalla permanece visible.
  final Duration minimumDuration;

  const SplashScreen({
    super.key,
    required this.onFinished,
    this.onInitialize,
    this.minimumDuration = const Duration(milliseconds: 2400),
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  /// Entrada escalonada de cada elemento (logo, título, barra, marca).
  late final AnimationController _entrance;

  /// Latido continuo del halo y de las ondas alrededor del logo.
  late final AnimationController _pulse;

  /// Desvanecido de salida.
  late final AnimationController _exit;

  String _status = 'Iniciando...';
  bool _leaving = false;

  @override
  void initState() {
    super.initState();

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    _exit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );

    _run();
  }

  /// Corre la inicialización y el tiempo mínimo en paralelo.
  Future<void> _run() async {
    final startedAt = DateTime.now();

    try {
      await widget.onInitialize?.call(_report);
    } catch (_) {
      // Un fallo de arranque no debe dejar al usuario mirando la carga para
      // siempre: seguimos igual y que la pantalla correspondiente lo muestre.
    }

    final elapsed = DateTime.now().difference(startedAt);
    final remaining = widget.minimumDuration - elapsed;
    if (remaining > Duration.zero) await Future.delayed(remaining);

    if (!mounted) return;
    setState(() => _leaving = true);
    await _exit.forward();
    if (!mounted) return;
    widget.onFinished();
  }

  void _report(String status) {
    if (!mounted || _leaving) return;
    setState(() => _status = status);
  }

  @override
  void dispose() {
    _entrance.dispose();
    _pulse.dispose();
    _exit.dispose();
    super.dispose();
  }

  /// Curva de entrada de un tramo del escalonado.
  Animation<double> _stagger(double begin, double end) {
    return CurvedAnimation(
      parent: _entrance,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final gradient = isDark ? AppTheme.darkGradient : AppTheme.lightGradient;

    // El logo se adapta al alto disponible para que en pantallas chicas
    // el bloque de marca de abajo no quede fuera de la vista.
    final logoSize =
        (MediaQuery.of(context).size.height * 0.17).clamp(88.0, 132.0);

    return AnimatedBuilder(
      animation: _exit,
      builder: (context, child) => Opacity(
        opacity: 1 - _exit.value,
        child: Transform.scale(scale: 1 + _exit.value * 0.04, child: child),
      ),
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: gradient,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _background(isDark),
              _auroras(scheme),
              SafeArea(
                child: Column(
                  children: [
                    const Spacer(flex: 3),
                    _logoBlock(scheme, logoSize),
                    const SizedBox(height: 24),
                    _titleBlock(theme, scheme),
                    const Spacer(flex: 2),
                    _progressBlock(theme, scheme),
                    const SizedBox(height: 36),
                    _brandBlock(theme, scheme),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Arte de fondo, muy tenue para no competir con el logo.
  Widget _background(bool isDark) {
    return Opacity(
      opacity: isDark ? 0.16 : 0.30,
      child: const BrandImage(
        candidates: [BrandAssets.splashBackground],
        fit: BoxFit.cover,
      ),
    );
  }

  /// Dos manchas de color que respiran de fondo. Le dan profundidad al
  /// degradado plano sin necesidad de otra imagen.
  Widget _auroras(ColorScheme scheme) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = _pulse.value * 2 * math.pi;
        return IgnorePointer(
          child: Stack(
            children: [
              _aurora(
                color: scheme.primary,
                alignment: Alignment(-0.7 + 0.1 * math.sin(t), -0.6),
                size: 320,
                opacity: 0.20 + 0.06 * math.sin(t),
              ),
              _aurora(
                color: scheme.tertiary,
                alignment: Alignment(0.75, 0.5 + 0.1 * math.cos(t)),
                size: 280,
                opacity: 0.16 + 0.05 * math.cos(t),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _aurora({
    required Color color,
    required Alignment alignment,
    required double size,
    required double opacity,
  }) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity.clamp(0.0, 1.0)),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }

  /// Logo con ondas concéntricas que salen del centro — un guiño a que la
  /// app es de audio.
  Widget _logoBlock(ColorScheme scheme, double logoSize) {
    final animation = _stagger(0.0, 0.55);
    // Espacio que necesitan las ondas al expandirse del todo.
    final field = logoSize * 1.85;

    return AnimatedBuilder(
      animation: Listenable.merge([animation, _pulse]),
      builder: (context, _) {
        return Opacity(
          opacity: animation.value,
          child: Transform.scale(
            scale: 0.82 + 0.18 * animation.value,
            child: SizedBox(
              width: field,
              height: field,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Tres ondas desfasadas, expandiéndose y apagándose.
                  for (var i = 0; i < 3; i++)
                    _ripple(scheme, (_pulse.value + i / 3) % 1.0, logoSize),
                  AppLogo(size: logoSize, glow: animation.value),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _ripple(ColorScheme scheme, double progress, double logoSize) {
    final diameter = logoSize * (1.06 + progress * 0.76);
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.30 * (1 - progress)),
          width: 1.4,
        ),
      ),
    );
  }

  Widget _titleBlock(ThemeData theme, ColorScheme scheme) {
    final animation = _stagger(0.30, 0.80);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Opacity(
        opacity: animation.value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - animation.value)),
          child: child,
        ),
      ),
      child: Column(
        children: [
          Text(
            AppConstants.appName,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              AppConstants.appDescription,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Barra de progreso indeterminada y el paso que se está ejecutando.
  Widget _progressBlock(ThemeData theme, ColorScheme scheme) {
    final animation = _stagger(0.55, 1.0);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) =>
          Opacity(opacity: animation.value, child: child),
      child: Column(
        children: [
          SizedBox(
            width: 160,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: scheme.onSurface.withValues(alpha: 0.10),
                valueColor: AlwaysStoppedAnimation(scheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: Text(
              _status,
              key: ValueKey(_status),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Crédito de Mavric: logotipo completo y la línea de autoría.
  Widget _brandBlock(ThemeData theme, ColorScheme scheme) {
    final animation = _stagger(0.70, 1.0);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Opacity(
        opacity: animation.value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - animation.value)),
          child: child,
        ),
      ),
      child: Column(
        children: [
          BrandImage(
            candidates: [
              BrandAssets.mavricLogoFor(theme.brightness),
              BrandAssets.mavricMarkFor(theme.brightness),
            ],
            height: 46,
            fallback: Text(
              BrandStrings.company,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            BrandStrings.developedBy,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
