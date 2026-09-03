import 'package:flutter/material.dart';

/// Rutas de los recursos de marca y resolución según el brillo del tema.
///
/// Todas las imágenes se declaran por directorio en `pubspec.yaml`
/// (`assets/brand/`, `assets/icon/`), así que si alguna todavía no está
/// puesta en disco la app compila igual: los widgets de marca usan
/// `errorBuilder` y caen a una versión tipográfica.
class BrandAssets {
  BrandAssets._();

  // ── Marca Mavric ──
  /// Logotipo horizontal completo sobre fondos claros (texto azul oscuro).
  static const String mavricLogoLight = 'assets/brand/mavric-logo-light.png';

  /// Logotipo horizontal completo sobre fondos oscuros (texto claro).
  static const String mavricLogoDark = 'assets/brand/mavric-logo-dark.png';

  /// Isotipo (solo el hexágono) para fondos claros. Se usa en el pie de
  /// página, donde el logotipo completo quedaría ilegible de tan chico.
  static const String mavricMarkLight = 'assets/brand/mavric-mark-light.png';

  /// Isotipo (solo el hexágono) para fondos oscuros.
  static const String mavricMarkDark = 'assets/brand/mavric-mark-dark.png';

  // ── Icono / logo de la app ──
  /// Icono de la app en versión clara (fondo blanco).
  static const String appIconLight = 'assets/icon/app-icon-light.png';

  /// Icono de la app en versión oscura (fondo azul noche).
  static const String appIconDark = 'assets/icon/app-icon-dark.png';

  /// Mismo arte sin fondo. Sirve sobre cualquier color y lo usan las
  /// variantes oscura y teñida del icono de iOS 18.
  static const String appIconTransparent =
      'assets/icon/app-icon-transparent.png';

  // ── Fondo ──
  /// Fondo decorativo que se pinta detrás de la pantalla de carga.
  static const String splashBackground = 'assets/splash-bg.png';

  /// Logotipo completo de Mavric legible sobre el fondo del tema actual.
  static String mavricLogoFor(Brightness brightness) =>
      brightness == Brightness.dark ? mavricLogoDark : mavricLogoLight;

  /// Isotipo de Mavric legible sobre el fondo del tema actual.
  static String mavricMarkFor(Brightness brightness) =>
      brightness == Brightness.dark ? mavricMarkDark : mavricMarkLight;

  /// Icono de la app en la variante que corresponde al tema actual.
  static String appIconFor(Brightness brightness) =>
      brightness == Brightness.dark ? appIconDark : appIconLight;
}

/// Textos de marca. Centralizados para que el crédito diga siempre lo mismo
/// en todas las vistas.
class BrandStrings {
  BrandStrings._();

  static const String company = 'Mavric Technologies';
  static const String developedBy = 'Desarrollado por $company';
}
