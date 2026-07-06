# Audio Traductor

Este README está escrito para el **próximo programador** que tome el proyecto. La idea NO es vender la app: es que puedas entender rápido qué funciona, qué está roto a nivel conceptual, dónde tocar y dónde NO conviene tocar sin cuidado.

---

## 1. Qué hace hoy el proyecto

Aplicación Flutter para:

- capturar audio desde el celular,
- transcribirlo,
- traducirlo,
- reproducir la traducción por audio,
- guardar historial de sesiones.

## 2. Qué hace realmente hoy

El pipeline real actual es este:

1. el audio entra por el **micrófono interno del celular**,
2. Android nativo captura PCM mono 16 kHz,
3. la app espera una pausa (~600 ms) para cerrar el bloque,
4. manda ese bloque a **Google Cloud Speech-to-Text**,
5. traduce el texto con **Google ML Kit on-device**,
6. reproduce la traducción con **TTS nativo del dispositivo**,
7. guarda la sesión en **Hive**.

O sea: **NO es streaming instantáneo**. Es procesamiento por bloques.

---

## 3. Estado real del proyecto

### Funciona razonablemente bien en

- captura desde **micrófono interno**,
- selección de **salida de audio**,
- reproducción por altavoz/Bluetooth,
- traducción local con ML Kit,
- historial y exportación.

### El problema arquitectónico principal hoy

La transcripción sigue usando **Google Cloud STT**, así que la app **todavía depende de internet**.

### Riesgo crítico actual

Hay **API keys hardcodeadas** de Google Cloud en:

- `lib/core/constants/api_constants.dart`

Eso hay que asumirlo como **comprometido**. Si vas a continuar este proyecto, lo primero es **rotar/revocar** esas claves.

---

## 4. Si recién entrás al proyecto, leé esto primero

### Orden recomendado para entenderlo

1. `lib/main.dart`
2. `lib/app.dart`
3. `lib/features/translation/presentation/providers/translation_provider.dart`
4. `lib/core/di/injection_container.dart`
5. `lib/features/translation/data/repositories/translation_repository_impl.dart`
6. `lib/features/translation/data/datasources/google_stt_datasource.dart`
7. `lib/features/translation/data/datasources/ml_kit_translate_datasource.dart`
8. `lib/features/translation/data/datasources/google_tts_datasource.dart`
9. `lib/core/services/audio_device_manager.dart`
10. `android/app/src/main/kotlin/com/audiotraductor/audio_traductor/MainActivity.kt`

### Por qué ese orden

- primero ves cómo arranca la app,
- después quién orquesta el caso principal,
- después cómo se inyectan los servicios,
- después el pipeline de datos,
- y recién ahí el código nativo, que es la parte más delicada.

---

## 5. Mapa rápido de arquitectura

| Capa | Responsabilidad |
|---|---|
| `presentation/` | UI, pantallas, widgets, providers Riverpod. |
| `domain/` | Entidades y casos de uso. |
| `data/` | Datasources, repositorios y persistencia. |
| `core/` | DI, constantes, servicios de audio/Bluetooth, utilidades, errores y tema. |
| `android/` | Captura nativa, ruteo de salida, forzado del micrófono y passthrough. |

---

## 6. Componentes importantes y qué hace cada uno

### Entrada y arranque

| Archivo | Qué hace |
|---|---|
| `lib/main.dart` | Inicializa Hive, permisos, dependencias y warmup del TTS. |
| `lib/app.dart` | Construye `MaterialApp` y la navegación principal. |

### Orquestación principal

| Archivo | Qué hace |
|---|---|
| `lib/features/translation/presentation/providers/translation_provider.dart` | Maneja estado general: iniciar, detener, descargar modelos, modo micrófono directo y reproducción puntual. |
| `lib/core/di/injection_container.dart` | Define qué implementación real usa la app para STT, traducción y TTS. |

### Pantallas principales

| Archivo | Qué hace |
|---|---|
| `home_screen.dart` | Pantalla principal con grabación, idiomas, sesión activa, estado de entrada/salida y párrafos en vivo. |
| `settings_screen.dart` | Configuración de voz, velocidad, tema y dispositivos de audio. |
| `history_screen.dart` | Historial, detalle y borrado de sesiones. |

### Pipeline de traducción

| Archivo | Qué hace |
|---|---|
| `translation_repository_impl.dart` | Coordina STT → traducción → TTS → persistencia. También controla orden de colas para mostrar y reproducir párrafos. |
| `google_stt_datasource.dart` | Captura audio desde el canal nativo, detecta silencio y llama a Google Cloud STT. |
| `ml_kit_translate_datasource.dart` | Traducción on-device con descarga local de modelos. |
| `google_tts_datasource.dart` | Incluye el TTS real usado hoy (`RealTtsDatasource`) y una implementación cloud que hoy NO está inyectada. |
| `translation_local_datasource.dart` | Persistencia local de sesiones con Hive. |

### Audio / Bluetooth

| Archivo | Qué hace |
|---|---|
| `audio_device_manager.dart` | Descubre dispositivos, selecciona salida y reafirma el micrófono interno. |
| `mic_passthrough_service.dart` | Modo micrófono directo sin traducción. |
| `bluetooth_provider.dart` / `bluetooth_service.dart` | Estado Bluetooth y helpers de conexión. |

### Android nativo

| Archivo | Qué hace |
|---|---|
| `android/app/src/main/kotlin/com/audiotraductor/audio_traductor/MainActivity.kt` | La pieza más crítica del proyecto. Maneja captura nativa, canales Flutter, passthrough, salida Bluetooth/A2DP y forzado del micrófono integrado. |

---

## 7. APIs y servicios usados

### Activos en runtime hoy

| Servicio | Estado | Necesita internet | Archivo principal | Nota |
|---|---|---|---|---|
| Google Cloud Speech-to-Text | Activo | Sí | `google_stt_datasource.dart` | Principal dependencia externa actual. |
| Google ML Kit Translation | Activo | Solo para bajar modelos la primera vez | `ml_kit_translate_datasource.dart` | Después puede funcionar offline. |
| TTS nativo del dispositivo | Activo | No | `RealTtsDatasource` | Es el camino realmente inyectado hoy. |

### Presentes en código, pero no en el flujo principal actual

| Servicio | Estado | Archivo | Nota |
|---|---|---|---|
| Google Cloud Text-to-Speech | Implementado pero no usado por DI | `google_tts_datasource.dart` | Existe, pero hoy no es el TTS real del runtime. |
| Google Translate cloud | No integrado realmente | `google_translate_datasource.dart` | En práctica hoy es contrato + mock. |

---

## 8. Cómo está resuelto hoy el audio

### Entrada de audio

Este punto está bastante avanzado.

- La app usa `AudioRecord` nativo.
- Se intenta forzar siempre el **micrófono interno**.
- Se usa `VOICE_RECOGNITION`.
- Cuando hay Bluetooth, el código intenta evitar que Android cambie la entrada al headset.

### Selección de salida

También está implementada y es una parte importante del proyecto.

- Hay selección manual de salida en ajustes.
- Se listan dispositivos integrados, cableados y Bluetooth.
- Se intenta mantener la combinación: **mic del teléfono + salida por Bluetooth A2DP**.

### Dónde está la complejidad real

La complejidad GORDA no está en Flutter. Está en:

- `audio_device_manager.dart`
- `MainActivity.kt`

Si tocás esa zona sin entender perfiles Bluetooth, te podés llevar puesto el comportamiento de entrada/salida.

---

## 9. Limitaciones que NO vas a solucionar solo “optimizando código”

### 1. No hay traducción instantánea real

Siempre existe esta cadena:

1. capturar audio,
2. esperar pausa,
3. transcribir,
4. traducir,
5. sintetizar,
6. reproducir.

Eso mete latencia sí o sí.

### 2. La app trabaja por bloques

El corte por silencio (~600 ms) implica:

- más espera si alguien habla de corrido,
- peor comportamiento con ruido ambiente,
- sensación de retardo inevitable.

### 3. Android y Bluetooth ponen límites del sistema

- **HFP/SCO** puede secuestrar el micrófono.
- **A2DP** sirve mejor para salida, pero no resuelve todo.

El código actual ya pelea bastante con eso, pero no controla completamente el comportamiento del SO ni del hardware.

### 4. Offline total todavía NO existe

Aunque traducción y TTS pueden funcionar localmente, la transcripción actual sigue dependiendo de Google Cloud STT.

---

## 10. Qué cambiaría primero si continuás este proyecto

### Prioridad 1 — Seguridad

- Revocar/rotar keys expuestas.
- Sacarlas del repo.
- Eliminar dependencia de claves embebidas en cliente.

### Prioridad 2 — Reemplazar STT cloud

Si el objetivo del producto es operar sin internet, el siguiente cambio serio es reemplazar:

- `GoogleSttDatasource`

por una solución offline/local.

### Prioridad 3 — Limpiar herencia conceptual de Google

Hoy hay nombres y piezas que quedaron mezcladas:

- voces con naming tipo `Wavenet` / `Standard`,
- clases cloud coexistiendo con runtime local,
- intención offline mezclada con STT cloud.

Hay que ordenar eso para que el proyecto sea coherente.

---

## 11. Qué NO conviene tocar sin revisar impacto

- `MainActivity.kt`
- `audio_device_manager.dart`
- `translation_repository_impl.dart`
- `translation_provider.dart`

Estas cuatro piezas gobiernan casi todo el comportamiento sensible del sistema.

---

## 12. Problemas conocidos

### Críticos

- API keys de Google Cloud expuestas.
- Dependencia de internet para STT.
- Riesgo de confusión entre piezas cloud heredadas y piezas locales realmente activas.

### Técnicos / funcionales

- El producto puede parecer “tiempo real”, pero en verdad es un sistema por bloques.
- El naming de voces no representa del todo el motor TTS real en uso.
- El comportamiento Bluetooth puede variar según dispositivo y versión de Android.

---

## 13. Resumen para el próximo programador

Si tenés que quedarte con una sola idea, que sea esta:

> el proyecto YA resolvió bastante bien el problema de **capturar desde el micrófono interno** y **elegir la salida de audio**, pero TODAVÍA no resolvió el objetivo de ser realmente offline porque la transcripción sigue en Google Cloud.

Entonces el próximo paso serio NO es embellecer la UI.

El próximo paso serio es:

1. limpiar seguridad,
2. sacar GCP del STT,
3. ordenar la arquitectura para que lo que el producto promete coincida con lo que realmente hace.
