# Icono de la app

| Archivo | Qué es | Dónde se usa |
|---|---|---|
| `app-icon-light.png` | Micrófono azul sobre fondo blanco, 1254×1254 RGB | Icono del launcher (Android e iOS) y logo dentro de la app en tema claro |
| `app-icon-dark.png` | Micrófono celeste sobre fondo azul noche, 1254×1254 RGB | Logo dentro de la app en tema oscuro |
| `app-icon-transparent.png` | El mismo arte sin fondo, 1254×1254 RGBA | Splash nativo, variantes oscura y teñida del icono de iOS 18 |

Ojo: de las tres versiones "transparent" que vinieron del generador, solo la
`v3` tenía canal alfa real. Las otras eran RGB y se habrían visto con un
recuadro blanco encima del degradado.

## Regenerar los iconos del launcher

Después de copiar o cambiar los PNG:

```
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

## Sobre el cambio automático claro/oscuro

- **iOS 18+**: funciona de verdad. El sistema alterna entre el icono claro, el
  oscuro y la variante teñida según el modo del dispositivo, sin que la app
  haga nada. Lo configuran `image_path_ios_dark_transparent` y
  `image_path_ios_tinted_grayscale` en `pubspec.yaml`. La variante oscura usa
  el arte transparente a propósito: iOS pinta su propio fondo detrás, y una
  imagen opaca con las esquinas ya redondeadas se vería recortada dos veces.
- **Android**: no existe esa función. El launcher usa un único icono
  (`app-icon-light.png`). Lo más parecido es el "icono con tema" de Android
  13+, que tiñe una capa monocromática con la paleta del sistema, y solo si el
  usuario activa esa opción. Requiere arte extra con zona segura — está
  documentado y comentado en `pubspec.yaml`.
