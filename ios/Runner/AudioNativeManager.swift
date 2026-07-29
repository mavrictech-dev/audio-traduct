import AVFoundation
import Flutter
import UIKit

/// Equivalente iOS de `MainActivity.kt` (Android).
///
/// Reproduce el mismo contrato de canales que el lado Android para que el código
/// Dart (`google_stt_datasource.dart`, `mic_passthrough_service.dart`,
/// `audio_device_manager.dart`) no necesite saber en qué plataforma corre:
///
///   MethodChannel "com.audiotraductor/audio"        → forceBuiltinMic, restoreOutput,
///                                                       selectOutput, startRecording,
///                                                       stopRecording, getBondedDevices
///   EventChannel  "com.audiotraductor/mic"           → stream de PCM16 mono 16kHz
///   MethodChannel "com.audiotraductor/passthrough"   → start, write, stop
///   MethodChannel "com.audiotraductor/system"        → openBluetoothSettings
///
/// Limitaciones reales de la plataforma (no son bugs, son restricciones de Apple):
/// - iOS no expone una lista de dispositivos Bluetooth "vinculados pero no conectados"
///   como `BluetoothAdapter.bondedDevices` en Android. Solo se puede leer la ruta
///   activa (`AVAudioSession.currentRoute`).
/// - No existe forma pública de forzar la salida a un dispositivo Bluetooth específico
///   cuando hay varios conectados; solo se puede alternar entre altavoz interno
///   (`overrideOutputAudioPort(.speaker)`) y "lo que el sistema tenga activo" (`.none`).
/// - No hay forma pública de abrir el panel de Ajustes → Bluetooth de iOS directamente
///   desde una app (Apple lo restringe). Se abre la página de Ajustes de la app.
final class AudioNativeManager: NSObject {

    static let shared = AudioNativeManager()

    // MARK: - Formatos
    //
    // Hay DOS formatos distintos y no hay que confundirlos:
    // - `pcm16Format`: PCM16 mono 16kHz — el formato que cruza la frontera con Dart
    //   (bytes que salen por el EventChannel del mic, bytes que entran por 'write'
    //   del passthrough). Coincide con lo que espera el lado Android.
    // - `engineFormat`: Float32 mono no entrelazado — el único formato con el que
    //   `AVAudioEngine.connect()` funciona de forma confiable. Conectar nodos en
    //   Int16 (como hacía una primera versión de este archivo) falla o se comporta
    //   mal en hardware real (error -10868 documentado en los foros de Apple).
    //   Por eso el passthrough convierte Int16 → Float32 ANTES de mandarlo al
    //   `AVAudioPlayerNode`; el AVAudioConverter de la captura, en cambio, se usa
    //   "standalone" (nunca se conecta a un nodo), así que ahí sí es seguro que su
    //   salida sea Int16 directamente.

    private let targetSampleRate: Double = 16000
    private lazy var pcm16Format = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: targetSampleRate,
        channels: 1,
        interleaved: true
    )!
    private lazy var engineFormat = AVAudioFormat(
        standardFormatWithSampleRate: targetSampleRate,
        channels: 1
    )!

    // MARK: - Motor de audio compartido (captura + passthrough)

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var passthroughConverter: AVAudioConverter?
    private var isCapturing = false
    private var isPassthroughActive = false

    private var micEventSink: FlutterEventSink?
    private var passthroughPlayer: AVAudioPlayerNode?

    private var selectedOutputIsBuiltin = true
    private var routeObserverAdded = false

    // MARK: - Setup

    /// Registra los cuatro canales sobre el `FlutterBinaryMessenger` de la app.
    /// Se llama una sola vez desde `AppDelegate`.
    func setup(messenger: FlutterBinaryMessenger) {
        let audioChannel = FlutterMethodChannel(name: "com.audiotraductor/audio", binaryMessenger: messenger)
        audioChannel.setMethodCallHandler { [weak self] call, result in
            self?.handleAudioCall(call, result: result)
        }

        let passthroughChannel = FlutterMethodChannel(name: "com.audiotraductor/passthrough", binaryMessenger: messenger)
        passthroughChannel.setMethodCallHandler { [weak self] call, result in
            self?.handlePassthroughCall(call, result: result)
        }

        let systemChannel = FlutterMethodChannel(name: "com.audiotraductor/system", binaryMessenger: messenger)
        systemChannel.setMethodCallHandler { [weak self] call, result in
            self?.handleSystemCall(call, result: result)
        }

        let micEventChannel = FlutterEventChannel(name: "com.audiotraductor/mic", binaryMessenger: messenger)
        micEventChannel.setStreamHandler(self)

        addAudioSessionObservers()
    }

    // MARK: - Canal "com.audiotraductor/audio"

    private func handleAudioCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "forceBuiltinMic":
            forceBuiltinMic()
            result(true)

        case "restoreOutput":
            restoreOutput()
            result(true)

        case "selectOutput":
            let args = call.arguments as? [String: Any]
            let name = args?["name"] as? String ?? ""
            let id = args?["id"] as? String ?? ""
            let type = args?["type"] as? String ?? ""
            selectOutputDevice(name: name, id: id, type: type)
            result(true)

        case "startRecording":
            requestMicPermissionIfNeeded { [weak self] granted in
                guard let self = self else { return }
                if granted {
                    self.startNativeRecording()
                    result(true)
                } else {
                    result(FlutterError(code: "PERMISSION_DENIED", message: "Microphone permission required", details: nil))
                }
            }

        case "stopRecording":
            stopNativeRecording()
            result(true)

        case "getBondedDevices":
            getBondedDevices(result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Canal "com.audiotraductor/passthrough"

    private func handlePassthroughCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            startPassthroughPlayer()
            result(true)

        case "write":
            if let args = call.arguments as? [String: Any], let typedData = args["bytes"] as? FlutterStandardTypedData {
                writeAudio(typedData.data)
            }
            result(true)

        case "stop":
            stopPassthroughPlayer()
            result(true)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Canal "com.audiotraductor/system"

    private func handleSystemCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "openBluetoothSettings":
            // Apple no permite abrir el panel de Bluetooth del sistema directamente
            // desde una app de terceros. Lo más cercano y compatible con las reglas
            // de la App Store es abrir la página de Ajustes de la propia app.
            if let url = URL(string: UIApplication.openSettingsURLString) {
                DispatchQueue.main.async {
                    UIApplication.shared.open(url, options: [:]) { success in
                        if success {
                            result(true)
                        } else {
                            result(FlutterError(code: "bt_settings_error", message: "No se pudo abrir Ajustes", details: nil))
                        }
                    }
                }
            } else {
                result(FlutterError(code: "bt_settings_error", message: "URL de Ajustes inválida", details: nil))
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Permisos

    private func requestMicPermissionIfNeeded(completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                completion(true)
            case .denied:
                completion(false)
            case .undetermined:
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async { completion(granted) }
                }
            @unknown default:
                completion(false)
            }
        } else {
            let session = AVAudioSession.sharedInstance()
            switch session.recordPermission {
            case .granted:
                completion(true)
            case .denied:
                completion(false)
            case .undetermined:
                session.requestRecordPermission { granted in
                    DispatchQueue.main.async { completion(granted) }
                }
            @unknown default:
                completion(false)
            }
        }
    }

    // MARK: - Sesión de audio

    /// Configura la sesión para grabar del mic integrado mientras se permite
    /// salida por Bluetooth A2DP, SIN activar el perfil HFP.
    ///
    /// Clave: `.allowBluetoothA2DP` sin `.allowBluetooth`. `.allowBluetooth` es lo que
    /// habilita el perfil manos-libres (HFP) y hace que iOS mueva el micrófono al
    /// headset — exactamente lo que en Android se evita desconectando el proxy HFP
    /// (`disconnectHeadsetHfp()`). Acá se evita directamente no pidiendo ese permiso.
    ///
    /// Modo `.measurement`: es el más parecido a `MediaRecorder.AudioSource.VOICE_RECOGNITION`
    /// de Android — minimiza el procesamiento automático (AGC, cancelación de eco) para
    /// no degradar la señal que llega a Whisper. A verificar en hardware real: en
    /// algunos dispositivos iOS el modo `.measurement` interactúa distinto con el ruteo
    /// Bluetooth que `.default`; si en pruebas de campo se nota un problema de ruteo,
    /// este es el primer parámetro a revisar.
    ///
    /// IMPORTANTE — compatibilidad verificada con `flutter_tts` (para que la voz hable
    /// apenas termina de traducir, sin cortar la captura del siguiente bloque):
    /// el plugin desactiva la sesión compartida al terminar cada frase SOLO si sus
    /// opciones de categoría se cruzan con `.duckOthers`/`.interruptSpokenAudioAndMixWithOthers`
    /// (ver `shouldDeactivateAndNotifyOthers` en `SwiftFlutterTtsPlugin.swift`). Como acá
    /// solo se usan `.allowBluetoothA2DP` y `.defaultToSpeaker`, esa condición nunca se
    /// cumple: la sesión se mantiene activa entre frase y frase y el tap del mic sigue
    /// vivo mientras el TTS habla. Si en el futuro se agregan esas opciones, esto se rompe.
    private func configureSessionForRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.allowBluetoothA2DP, .defaultToSpeaker]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            try forceBuiltinMicInputOrThrow()
        } catch {
            print("AudioNativeManager: error configurando sesión de grabación: \(error)")
        }
    }

    private func forceBuiltinMicInputOrThrow() throws {
        let session = AVAudioSession.sharedInstance()
        if let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try session.setPreferredInput(builtInMic)
        }
    }

    private func forceBuiltinMic() {
        do {
            try forceBuiltinMicInputOrThrow()
        } catch {
            print("AudioNativeManager: no se pudo forzar el mic integrado: \(error)")
        }
    }

    /// No hay "comm device" que restaurar como en Android (eso es un concepto de
    /// AudioManager de Android). En iOS alcanza con reafirmar el mic integrado y
    /// dejar de forzar el altavoz — el sistema vuelve a la ruta activa por defecto.
    private func restoreOutput() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.overrideOutputAudioPort(.none)
        } catch {
            print("AudioNativeManager: error restaurando salida: \(error)")
        }
        forceBuiltinMic()
    }

    /// Rutea la salida. iOS no permite elegir un dispositivo Bluetooth específico
    /// entre varios conectados (eso lo decide el sistema); solo se puede alternar
    /// entre "altavoz interno forzado" y "lo que esté activo" (que en la práctica,
    /// si hay un A2DP conectado, es ese).
    private func selectOutputDevice(name: String, id: String, type: String) {
        let session = AVAudioSession.sharedInstance()
        let normalizedType = type.trimmingCharacters(in: .whitespaces).lowercased()
        let normalizedId = id.trimmingCharacters(in: .whitespaces).lowercased()
        let isBuiltin = normalizedType == "integrado" || normalizedType == "builtin" || normalizedId == "builtin-speaker" || name.isEmpty

        selectedOutputIsBuiltin = isBuiltin

        do {
            if isBuiltin {
                try session.overrideOutputAudioPort(.speaker)
            } else {
                try session.overrideOutputAudioPort(.none)
            }
        } catch {
            print("AudioNativeManager: error seleccionando salida: \(error)")
        }
        forceBuiltinMic()
    }

    /// Best-effort: solo puede reportar la ruta ACTIVA (`currentRoute`), no dispositivos
    /// vinculados-pero-no-conectados como Android. Ver limitación documentada arriba.
    private func getBondedDevices(result: @escaping FlutterResult) {
        let session = AVAudioSession.sharedInstance()
        var devices: [[String: Any?]] = []

        for output in session.currentRoute.outputs where isBluetoothPort(output.portType) {
            devices.append([
                "name": output.portName,
                "address": output.uid,
                "type": output.portType.rawValue,
                "connected": true,
            ])
        }

        result(devices)
    }

    private func isBluetoothPort(_ portType: AVAudioSession.Port) -> Bool {
        return portType == .bluetoothA2DP || portType == .bluetoothHFP || portType == .bluetoothLE
    }

    // MARK: - Captura nativa (mic → EventChannel)

    private func startNativeRecording() {
        stopNativeRecording()
        configureSessionForRecording()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            print("AudioNativeManager: formato de entrada inválido, no se puede grabar")
            return
        }

        converter = AVAudioConverter(from: inputFormat, to: pcm16Format)

        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.processCapturedBuffer(buffer, inputFormat: inputFormat)
        }

        isCapturing = true
        ensureEngineRunning()
    }

    private func processCapturedBuffer(_ buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        guard let converter = converter else { return }

        let ratio = pcm16Format.sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: pcm16Format, frameCapacity: outputCapacity) else { return }

        var error: NSError?
        var consumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
        if error != nil { return }

        guard let channelData = outBuffer.int16ChannelData else { return }
        let frameLength = Int(outBuffer.frameLength)
        guard frameLength > 0 else { return }

        let data = Data(bytes: channelData[0], count: frameLength * MemoryLayout<Int16>.size)

        DispatchQueue.main.async { [weak self] in
            self?.micEventSink?(FlutterStandardTypedData(bytes: data))
        }
    }

    private func stopNativeRecording() {
        guard isCapturing else { return }
        isCapturing = false
        engine.inputNode.removeTap(onBus: 0)
        converter = nil
        stopEngineIfIdle()
    }

    // MARK: - Passthrough (mic → parlante en modo directo)

    private func startPassthroughPlayer() {
        stopPassthroughPlayer()

        let player = AVAudioPlayerNode()
        engine.attach(player)
        // engineFormat (Float32 no entrelazado), NO pcm16Format — ver nota en la
        // sección "Formatos" arriba sobre por qué conectar nodos en Int16 no es seguro.
        engine.connect(player, to: engine.mainMixerNode, format: engineFormat)
        passthroughPlayer = player
        passthroughConverter = AVAudioConverter(from: pcm16Format, to: engineFormat)

        isPassthroughActive = true
        ensureEngineRunning()
        player.play()
    }

    /// Recibe bytes PCM16 desde Dart (mismo formato que manda Android) y los convierte
    /// a Float32 antes de programarlos en el `AVAudioPlayerNode` — ese nodo está
    /// conectado en `engineFormat`, no en `pcm16Format`.
    private func writeAudio(_ data: Data) {
        guard let player = passthroughPlayer, let converter = passthroughConverter else { return }
        let frameCount = UInt32(data.count / MemoryLayout<Int16>.size)
        guard frameCount > 0, let inBuffer = AVAudioPCMBuffer(pcmFormat: pcm16Format, frameCapacity: frameCount) else { return }
        inBuffer.frameLength = frameCount

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            if let base = raw.bindMemory(to: Int16.self).baseAddress, let channel = inBuffer.int16ChannelData {
                channel[0].update(from: base, count: Int(frameCount))
            }
        }

        let ratio = engineFormat.sampleRate / pcm16Format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(frameCount) * ratio) + 32
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: engineFormat, frameCapacity: outCapacity) else { return }

        var error: NSError?
        var consumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inBuffer
        }

        converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
        guard error == nil, outBuffer.frameLength > 0 else { return }

        player.scheduleBuffer(outBuffer, completionHandler: nil)
    }

    private func stopPassthroughPlayer() {
        guard let player = passthroughPlayer else { return }
        player.stop()
        engine.disconnectNodeOutput(player)
        engine.detach(player)
        passthroughPlayer = nil
        passthroughConverter = nil
        isPassthroughActive = false
        stopEngineIfIdle()
    }

    // MARK: - Ciclo de vida del engine compartido

    private func ensureEngineRunning() {
        guard !engine.isRunning else { return }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            print("AudioNativeManager: error arrancando el engine: \(error)")
        }
    }

    private func stopEngineIfIdle() {
        guard !isCapturing, !isPassthroughActive, engine.isRunning else { return }
        engine.stop()
    }

    // MARK: - Cambios de ruta (equivalente a btStateReceiver de Android)

    private func addAudioSessionObservers() {
        guard !routeObserverAdded else { return }
        routeObserverAdded = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    /// Cuando cambia la ruta (se conecta/desconecta un Bluetooth), reafirmamos el mic
    /// integrado y, si había una grabación activa, reconstruimos el tap con el nuevo
    /// formato de entrada — el formato del inputNode puede cambiar con la ruta y un
    /// tap con el formato viejo se queda mudo o crashea.
    @objc private func handleRouteChange(_ notification: Notification) {
        forceBuiltinMic()
        guard isCapturing else { return }

        let inputNode = engine.inputNode
        inputNode.removeTap(onBus: 0)

        let newFormat = inputNode.outputFormat(forBus: 0)
        guard newFormat.sampleRate > 0 else { return }

        converter = AVAudioConverter(from: newFormat, to: pcm16Format)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: newFormat) { [weak self] buffer, _ in
            self?.processCapturedBuffer(buffer, inputFormat: newFormat)
        }
    }

    /// Pausa/retoma ante interrupciones del sistema (llamada entrante, Siri, etc.).
    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .ended {
            guard let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                ensureEngineRunning()
            }
        }
    }
}

// MARK: - FlutterStreamHandler (EventChannel "com.audiotraductor/mic")

extension AudioNativeManager: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        micEventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        micEventSink = nil
        stopNativeRecording()
        return nil
    }
}
