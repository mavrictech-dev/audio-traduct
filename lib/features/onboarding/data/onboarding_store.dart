import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Persistencia local del onboarding: deja registrado que este dispositivo
/// ya aceptó los Términos y Condiciones.
///
/// Se guarda en una caja de Hive propia (no en la del historial) para que
/// borrar el historial nunca vuelva a mostrar el modal. Solo se pierde si el
/// usuario borra los datos de la app o la desinstala.
class OnboardingStore {
  OnboardingStore._();

  static const String boxName = 'app_onboarding';
  static const String _termsVersionKey = 'terms_accepted_version';
  static const String _termsDateKey = 'terms_accepted_at';

  /// Versión vigente del texto legal. Si algún día cambian los términos,
  /// subir este número vuelve a pedir la aceptación una sola vez.
  static const int currentTermsVersion = 1;

  static Box? _box;

  /// Abre la caja. Debe llamarse después de `Hive.initFlutter()`.
  static Future<void> init() async {
    _box = await Hive.openBox(boxName);
  }

  /// `true` si este dispositivo ya aceptó la versión vigente de los términos.
  static bool get hasAcceptedTerms {
    final accepted = _box?.get(_termsVersionKey);
    return accepted is int && accepted >= currentTermsVersion;
  }

  /// Fecha en que se aceptaron los términos, si existe.
  static DateTime? get acceptedAt {
    final raw = _box?.get(_termsDateKey);
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  /// Registra la aceptación. A partir de acá el modal no vuelve a salir.
  static Future<void> acceptTerms() async {
    await _box?.put(_termsVersionKey, currentTermsVersion);
    await _box?.put(_termsDateKey, DateTime.now().toIso8601String());
  }
}
