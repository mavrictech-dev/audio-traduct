import 'package:flutter/material.dart';
import 'brand_assets.dart';
import 'brand_image.dart';

/// Logo de la app (el mismo arte del icono) con esquinas redondeadas y un
/// halo suave detrás, para usarlo dentro de la app.
///
/// Elige automáticamente la variante clara u oscura según el tema activo.
class AppLogo extends StatelessWidget {
  final double size;

  /// Intensidad del halo. 0 lo desactiva.
  final double glow;

  const AppLogo({super.key, this.size = 120, this.glow = 1});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(size * 0.235);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: glow <= 0
            ? null
            : [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.32 * glow),
                  blurRadius: size * 0.42,
                  spreadRadius: size * 0.03,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18 * glow),
                  blurRadius: size * 0.18,
                  offset: Offset(0, size * 0.06),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BrandImage(
          candidates: [
            BrandAssets.appIconFor(theme.brightness),
            BrandAssets.appIconLight,
            BrandAssets.appIconTransparent,
          ],
          width: size,
          height: size,
          fit: BoxFit.cover,
          // Sin arte en disco, un marcador con el color de acento.
          fallback: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, scheme.primaryContainer],
              ),
            ),
            child: Icon(
              Icons.record_voice_over_rounded,
              size: size * 0.5,
              color: scheme.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
