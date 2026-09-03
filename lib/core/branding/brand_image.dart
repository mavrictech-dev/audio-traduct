import 'package:flutter/material.dart';

/// Imagen de marca tolerante a que el archivo todavía no exista.
///
/// Los recursos de marca se declaran por directorio en `pubspec.yaml`, así
/// que un PNG que aún no se copió no rompe la compilación — pero sí lanzaría
/// un error en tiempo de ejecución al pintarlo. Este widget intenta la lista
/// de [candidates] en orden y, si ninguna carga, muestra [fallback].
class BrandImage extends StatelessWidget {
  /// Rutas a probar, de la más deseada a la menos.
  final List<String> candidates;

  /// Qué mostrar si ninguna ruta carga.
  final Widget fallback;

  final double? height;
  final double? width;
  final BoxFit fit;
  final Color? color;

  const BrandImage({
    super.key,
    required this.candidates,
    this.fallback = const SizedBox.shrink(),
    this.height,
    this.width,
    this.fit = BoxFit.contain,
    this.color,
  });

  @override
  Widget build(BuildContext context) => _build(0);

  Widget _build(int index) {
    if (index >= candidates.length) return fallback;

    return Image.asset(
      candidates[index],
      height: height,
      width: width,
      fit: fit,
      color: color,
      filterQuality: FilterQuality.medium,
      // Si falta el archivo, probamos el siguiente candidato.
      errorBuilder: (_, _, _) => _build(index + 1),
    );
  }
}
