import 'package:flutter/material.dart';
import 'liquid_glass.dart';

/// Reemplazo directo de [Card] con material de vidrio. Mismo patrón de
/// margen que ya se usaba en toda la app con `Card` — para no reescribir
/// el contenido de cada sección, solo cambia la superficie que lo envuelve.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    this.padding,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: LiquidGlass(
        borderRadius: borderRadius,
        padding: padding,
        tintOpacity: 0.13,
        blurSigma: 16,
        child: child,
      ),
    );
  }
}
