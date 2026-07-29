import 'dart:ui';
import 'package:flutter/material.dart';

/// Material "Liquid Glass": recreación visual en Flutter del lenguaje de
/// diseño de iOS 26 (blur real + degradé + brillo especular en el borde
/// superior). NO es la API nativa `UIGlassEffect`/`CAMaterialLayer` de UIKit
/// -esa es privada de Apple y no está expuesta a Flutter- pero apunta al
/// mismo lenguaje visual, y funciona igual en Android y en iOS.
///
/// El tinte sale siempre del [ColorScheme] activo (o de [tintColor] si se
/// especifica uno puntual, como en el botón de grabación), nunca de un color
/// fijo: así conserva el selector de color semilla que ya existe en Ajustes.
class LiquidGlass extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final double blurSigma;
  final double tintOpacity;
  final EdgeInsetsGeometry? padding;
  final Color? tintColor;

  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.blurSigma = 22,
    this.tintOpacity = 0.16,
    this.padding,
    this.tintColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = tintColor ?? scheme.surface;

    final borderColor = Colors.white.withValues(alpha: isDark ? 0.14 : 0.55);
    final highlightColor = Colors.white.withValues(alpha: isDark ? 0.16 : 0.75);
    final shadowColor = Colors.black.withValues(alpha: isDark ? 0.35 : 0.12);

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                base.withValues(alpha: (tintOpacity + 0.07).clamp(0.0, 1.0)),
                base.withValues(alpha: tintOpacity),
              ],
            ),
            border: Border.all(width: 1, color: borderColor),
            boxShadow: [
              BoxShadow(color: shadowColor, blurRadius: 20, offset: const Offset(0, 8)),
            ],
          ),
          child: Stack(
            children: [
              // Brillo especular: simula el reflejo de luz sobre la curva del vidrio.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 1.2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, highlightColor, Colors.transparent],
                      stops: const [0.05, 0.5, 0.95],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: padding ?? EdgeInsets.zero,
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
