import 'package:flutter/material.dart';
import 'brand_assets.dart';
import 'brand_image.dart';

/// Crédito de autoría que se muestra al pie de todas las vistas.
///
/// Vive en el shell principal (encima de la barra de navegación) para que
/// aparezca igual en Traductor, Historial y Ajustes sin tocar el layout de
/// cada pantalla.
class MavricFooter extends StatelessWidget {
  /// Alto del isotipo. En el pie va chico; la pantalla de carga lo agranda.
  final double markSize;

  /// Tamaño de la tipografía del crédito.
  final double fontSize;

  /// Opacidad del conjunto. El pie va discreto para no competir con la UI.
  final double opacity;

  final EdgeInsetsGeometry padding;

  const MavricFooter({
    super.key,
    this.markSize = 16,
    this.fontSize = 11,
    this.opacity = 0.55,
    this.padding = const EdgeInsets.only(bottom: 6, top: 2),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final color = theme.colorScheme.onSurfaceVariant.withValues(alpha: opacity);

    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandImage(
            candidates: [
              BrandAssets.mavricMarkFor(brightness),
              BrandAssets.mavricLogoFor(brightness),
            ],
            height: markSize,
            width: markSize,
            // Sin logo en disco no dibujamos nada: el texto solo ya alcanza.
            fallback: const SizedBox.shrink(),
          ),
          const SizedBox(width: 6),
          Text(
            BrandStrings.developedBy,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
