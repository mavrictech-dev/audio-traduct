import 'package:audio_traductor/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Inicializar Hive ──
  // Es lo único que corre antes de `runApp`: es rápido y todo lo demás
  // (dependencias, TTS, permisos) necesita que ya haya UI en pantalla.
  await Hive.initFlutter();

  // ── Arrancar la app ──
  // El resto de la inicialización sucede dentro de la pantalla de carga
  // (ver `AppBootstrap`), para que el usuario vea la animación de marca
  // en vez de un arranque en blanco.
  runApp(
    const ProviderScope(
      child: AudioTraductorApp(),
    ),
  );
}
