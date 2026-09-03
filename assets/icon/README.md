# Icono de la app

| Archivo | Qué es |
|---|---|
| `app-icon-light.png` | Icono para modo claro: micrófono azul sobre fondo blanco. **1024×1024 px, sin transparencia.** |
| `app-icon-dark.png` | Icono para modo oscuro: micrófono celeste sobre fondo azul noche. **1024×1024 px.** |

Estos dos PNG cumplen doble función: son el icono del launcher y también el
logo que la app muestra adentro (pantalla de carga), vía `AppLogo`.

## Regenerar los iconos del launcher

Después de copiar o cambiar los PNG:

```
dart run flutter_launcher_icons
```

## Sobre el cambio automático claro/oscuro

- **iOS 18+**: funciona de verdad. El sistema alterna entre el icono claro y
  el oscuro (y la variante teñida) según el modo del dispositivo, sin que la
  app haga nada. Lo configura `image_path_ios_dark_transparent` en
  `pubspec.yaml`.
- **Android**: no existe esa función. El launcher usa un único icono. Lo más
  parecido es el "icono con tema" de Android 13+, que tiñe una capa
  monocromática con la paleta del sistema, y solo si el usuario activa esa
  opción. Requiere arte extra con zona segura (ver `pubspec.yaml`).
