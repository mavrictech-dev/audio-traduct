package com.audiotraductor.audio_traductor

import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.*
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var audioTrack: AudioTrack? = null
    private val minBufferSize = AudioTrack.getMinBufferSize(
        16000,
        AudioFormat.CHANNEL_OUT_MONO,
        AudioFormat.ENCODING_PCM_16BIT
    )

    // AudioRecord nativo para capturar del mic del teléfono
    private var audioRecord: AudioRecord? = null
    private var recordThread: Thread? = null
    private var recordSink: EventChannel.EventSink? = null
    private val recordHandler = Handler(Looper.getMainLooper())
    private val mainHandler = Handler(Looper.getMainLooper())
    private var btReceiverRegistered = false
    private var lastCommDevice: AudioDeviceInfo? = null
    private var selectedOutputAddress: String? = null
    private var selectedOutputName: String? = null
    // La entrada se selecciona de forma explícita. En Bluetooth clásico,
    // Android puede acoplarla a la salida HFP del mismo dispositivo.
    private var selectedInputId: String = "builtin-mic"
    private var selectedInputName: String? = null
    private val btStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            try {
                applySelectedInputRoute()
            } catch (_: Exception) {}
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerBluetoothStateReceiver()

        // ── Canal: forzar mic + captura nativa ──
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.audiotraductor/audio"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "forceBuiltinMic" -> {
                    try {
                        saveCurrentCommDevice()
                        clearCommDevice()
                        forceBuiltinMic()
                    } catch (_: Exception) {}
                    result.success(true)
                }
                "restoreOutput" -> {
                    try { restoreOutput() } catch (_: Exception) {}
                    result.success(true)
                }
                "selectOutput" -> {
                    try {
                        val name = call.argument<String>("name") ?: ""
                        val id = call.argument<String>("id") ?: ""
                        val type = call.argument<String>("type") ?: ""
                        selectOutputDevice(name, id, type)
                    } catch (_: Exception) {}
                    result.success(true)
                }
                "getInputDevices" -> {
                    result.success(getInputDevices())
                }
                "selectInput" -> {
                    val id = call.argument<String>("id") ?: "builtin-mic"
                    selectInputDevice(id)
                    result.success(true)
                }
                "startRecording" -> {
                    if (androidx.core.content.ContextCompat.checkSelfPermission(this@MainActivity, android.Manifest.permission.RECORD_AUDIO) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        androidx.core.app.ActivityCompat.requestPermissions(this@MainActivity, arrayOf(android.Manifest.permission.RECORD_AUDIO), 1)
                        result.error("PERMISSION_DENIED", "Microphone permission required", null)
                    } else {
                        startNativeRecording(flutterEngine.dartExecutor.binaryMessenger)
                        result.success(true)
                    }
                }
                "stopRecording" -> {
                    stopNativeRecording()
                    result.success(true)
                }
                "getBondedDevices" -> {
                    getBluetoothAudioDevices(result)
                }
                else -> result.notImplemented()
            }
        }

        // ── Canal de passthrough ──
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.audiotraductor/passthrough"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    startAudioTrack()
                    result.success(true)
                }
                "write" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes != null) writeAudio(bytes)
                    result.success(true)
                }
                "stop" -> {
                    stopAudioTrack()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.audiotraductor/system"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openBluetoothSettings" -> {
                    try {
                        openBluetoothSettings()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("bt_settings_error", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun openBluetoothSettings() {
        val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    /// Entradas reales disponibles para el selector de Flutter. El id del
    /// integrado se estabiliza para que el valor sobreviva a un refresh.
    private fun getInputDevices(): List<Map<String, String>> {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val result = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
            // En Bluetooth clásico la fuente SCO puede no existir hasta que
            // activamos la ruta de comunicación. Se publica abajo usando su
            // dispositivo sink de availableCommunicationDevices.
            .filter { device -> device.type != AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
            .map { device ->
                mapOf(
                    "id" to inputId(device),
                    "name" to (device.productName?.toString()?.trim()
                        ?.takeIf { it.isNotEmpty() } ?: inputName(device)),
                    "type" to inputTypeLabel(device.type),
                )
            }
            .toMutableList()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.availableCommunicationDevices
                .filter { device -> isBluetoothCommunicationDevice(device) }
                .forEach { device ->
                    val name = device.productName?.toString()?.trim()
                        ?.takeIf { it.isNotEmpty() } ?: "Micrófono Bluetooth"
                    result.add(
                        mapOf(
                            "id" to "comm-${device.id}",
                            "name" to name,
                            "type" to bluetoothTypeLabel(device.type),
                        )
                    )
                }
        } else {
            // En Android 11 o anterior SCO se activa con startBluetoothSco.
            audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
                .filter { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
                .forEach { device ->
                    result.add(
                        mapOf(
                            "id" to inputId(device),
                            "name" to (device.productName?.toString()?.trim()
                                ?.takeIf { it.isNotEmpty() } ?: "Micrófono Bluetooth"),
                            "type" to "Bluetooth clásico",
                        )
                    )
                }
        }

        return result.distinctBy { "${it["name"]}|${it["type"]}" }
    }

    private fun inputId(device: AudioDeviceInfo): String =
        if (device.type == AudioDeviceInfo.TYPE_BUILTIN_MIC) "builtin-mic"
        else "input-${device.id}"

    private fun inputName(device: AudioDeviceInfo): String = when (device.type) {
        AudioDeviceInfo.TYPE_BUILTIN_MIC -> "Micrófono integrado"
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Micrófono con cable"
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_HEADSET -> "Micrófono USB"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Micrófono Bluetooth"
        AudioDeviceInfo.TYPE_BLE_HEADSET -> "Micrófono Bluetooth LE"
        else -> "Micrófono externo"
    }

    private fun inputTypeLabel(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_MIC -> "Integrado"
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Cable"
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_HEADSET -> "USB"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth clásico"
        AudioDeviceInfo.TYPE_BLE_HEADSET -> "Bluetooth LE"
        else -> "Externo"
    }

    private fun bluetoothTypeLabel(type: Int): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            type == AudioDeviceInfo.TYPE_BLE_HEADSET
        ) "Bluetooth LE" else "Bluetooth clásico"

    private fun isBluetoothCommunicationDevice(device: AudioDeviceInfo): Boolean {
        if (device.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO) return true
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            device.type == AudioDeviceInfo.TYPE_BLE_HEADSET
    }

    private fun selectedCommunicationDevice(): AudioDeviceInfo? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            !selectedInputId.startsWith("comm-")
        ) return null
        val requestedId = selectedInputId.removePrefix("comm-").toIntOrNull()
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return audioManager.availableCommunicationDevices.firstOrNull { device ->
            device.id == requestedId && isBluetoothCommunicationDevice(device)
        }
    }

    private fun isBluetoothInputSelected(): Boolean {
        if (selectedInputId.startsWith("comm-")) return true
        return selectedInputDevice()?.let { device ->
            device.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    device.type == AudioDeviceInfo.TYPE_BLE_HEADSET)
        } ?: false
    }

    private fun selectedInputDevice(): AudioDeviceInfo? {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val inputs = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
        if (selectedInputId == "builtin-mic") {
            return inputs.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }
        }

        return inputs.firstOrNull { inputId(it) == selectedInputId }
            ?: selectedInputName?.let { wantedName ->
                inputs.firstOrNull { device ->
                    device.productName?.toString()?.trim()
                        ?.equals(wantedName, ignoreCase = true) == true
                }
            }
    }

    private fun selectInputDevice(id: String) {
        val requested = id.trim().ifEmpty { "builtin-mic" }
        val previousInputId = selectedInputId
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val physical = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
            .firstOrNull { inputId(it) == requested }
        val communication = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            requested.startsWith("comm-")) {
            val commId = requested.removePrefix("comm-").toIntOrNull()
            audioManager.availableCommunicationDevices.firstOrNull { device ->
                device.id == commId && isBluetoothCommunicationDevice(device)
            }
        } else null
        val exists = physical != null || communication != null
        selectedInputId = if (exists) requested else "builtin-mic"
        selectedInputName = (communication ?: physical)
            ?.productName?.toString()?.trim()
        // AudioRecord aplica preferredDevice de forma más fiable al crearse.
        // Si el usuario cambia de micrófono durante una traducción, recreamos
        // la captura sin cortar el EventChannel que consume Flutter.
        if (audioRecord != null && selectedInputId != previousInputId) {
            rebuildActiveRecordingForSelectedInput()
        } else {
            applySelectedInputRoute()
        }
    }

    @Suppress("DEPRECATION")
    private fun applySelectedInputRoute() {
        if (selectedInputId == "builtin-mic") {
            forceBuiltinMic()
        } else {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val communicationDevice = selectedCommunicationDevice()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                communicationDevice != null
            ) {
                // Android selecciona automáticamente la fuente que acompaña
                // al sink HFP/LE indicado por setCommunicationDevice.
                audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                audioManager.setCommunicationDevice(communicationDevice)
            } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S &&
                isBluetoothInputSelected()
            ) {
                audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                audioManager.startBluetoothSco()
                audioManager.isBluetoothScoOn = true
            }

            applyPreferredInputToActiveRecording()
        }
    }

    /// Captura audio nativo con AudioRecord usando VOICE_RECOGNITION
    private fun selectOutputDevice(name: String, id: String, type: String) {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val normalizedName = name.trim().lowercase()
        val normalizedId = id.trim().lowercase()
        val normalizedType = type.trim().lowercase()
        val addressFromId = extractAddressFromId(normalizedId)
        val isBuiltinOutput = normalizedType == "integrado" ||
            normalizedType == "builtin" ||
            normalizedId == "builtin-speaker" ||
            normalizedName == "builtin-speaker" ||
            addressFromId.isEmpty() && !normalizedType.contains("bluetooth") && !normalizedId.contains(":")

        if (normalizedName.isEmpty() || isBuiltinOutput) {
            selectedOutputAddress = null
            selectedOutputName = null
            // Una entrada Bluetooth de comunicación controla también su
            // salida asociada. Limpiarla aquí apagaría el micrófono elegido.
            if (!isBluetoothInputSelected()) {
                audioManager.mode = AudioManager.MODE_NORMAL
                audioManager.isSpeakerphoneOn = true
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    audioManager.clearCommunicationDevice()
                }
            }
            applyPreferredOutputToAudioTrack()
            scheduleSelectedInputReassertion()
            return
        }

        // Rutear salida al BT seleccionado SIN tocar el dispositivo de entrada.
        // setCommunicationDevice() roba también el micrófono y lo mueve al BT.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (!isBluetoothInputSelected()) {
                audioManager.mode = AudioManager.MODE_NORMAL
                audioManager.clearCommunicationDevice()
            }

            val allDevices = buildList {
                addAll(audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).toList())
                addAll(audioManager.availableCommunicationDevices)
            }.distinctBy { it.id }

            val matched = allDevices.firstOrNull { device ->
                val productName = device.productName?.toString()?.trim()?.lowercase().orEmpty()
                val address = device.address?.trim()?.lowercase().orEmpty()

                addressFromId.isNotEmpty() && address == addressFromId ||
                normalizedId.isNotEmpty() && address == normalizedId ||
                normalizedName.isNotEmpty() && productName == normalizedName ||
                normalizedName.isNotEmpty() && productName.contains(normalizedName)
            }

            if (matched != null) {
                selectedOutputAddress = matched.address?.trim()?.lowercase()
                selectedOutputName = matched.productName?.toString()?.trim()?.lowercase()
                audioManager.isSpeakerphoneOn = false
                applyPreferredOutputToAudioTrack()
                scheduleSelectedInputReassertion()
                rebuildActiveRecordingForSelectedInput()
            }
        }
    }

    private fun applyPreferredOutputToAudioTrack() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val track = audioTrack ?: return
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)

        val address = selectedOutputAddress
        val name = selectedOutputName

        val preferred = devices.firstOrNull { device ->
            val deviceAddress = device.address?.trim()?.lowercase().orEmpty()
            val productName = device.productName?.toString()?.trim()?.lowercase().orEmpty()
            (address != null && address.isNotEmpty() && deviceAddress == address) ||
            (name != null && name.isNotEmpty() && productName == name)
        }

        try {
            track.preferredDevice = preferred
        } catch (_: Exception) {}
    }

    private fun extractAddressFromId(id: String): String {
        if (id.startsWith("bt-bonded-") && id.endsWith("-out")) {
            return id.removePrefix("bt-bonded-").removeSuffix("-out")
        }
        if (id.endsWith("-out")) {
            return id.removeSuffix("-out")
        }
        return ""
    }

    private fun getBluetoothAudioDevices(result: MethodChannel.Result) {
        val devices = linkedMapOf<String, MutableMap<String, Any?>>()
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val btAdapter = BluetoothAdapter.getDefaultAdapter()
        val mainHandler = Handler(Looper.getMainLooper())
        val delivered = AtomicBoolean(false)

        fun isBluetoothAudioType(type: Int): Boolean {
            return type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && type == AudioDeviceInfo.TYPE_BLE_HEADSET)
        }

        fun upsertDevice(name: String?, address: String?, type: Int?, connected: Boolean) {
            val safeName = name?.trim().orEmpty()
            val safeAddress = address?.trim().orEmpty()
            if (safeName.isEmpty() && safeAddress.isEmpty()) return

            val key = if (safeAddress.isNotEmpty()) safeAddress.lowercase() else safeName.lowercase()
            val existing = devices[key]
            if (existing == null) {
                devices[key] = mutableMapOf(
                    "name" to if (safeName.isNotEmpty()) safeName else safeAddress,
                    "address" to safeAddress,
                    "type" to type,
                    "connected" to connected,
                )
                return
            }

            if ((existing["name"] as? String).isNullOrBlank() && safeName.isNotEmpty()) {
                existing["name"] = safeName
            }
            if ((existing["address"] as? String).isNullOrBlank() && safeAddress.isNotEmpty()) {
                existing["address"] = safeAddress
            }
            if (type != null) {
                existing["type"] = type
            }
            val wasConnected = existing["connected"] as? Boolean ?: false
            existing["connected"] = wasConnected || connected
        }

        fun markBondedDevicesFromProfile(proxy: BluetoothProfile, profileId: Int) {
            try {
                btAdapter?.bondedDevices?.forEach { device ->
                    val isConnected = proxy.getConnectionState(device) == BluetoothProfile.STATE_CONNECTED
                    if (isConnected) {
                        upsertDevice(device.name, device.address, profileId, true)
                    }
                }
            } catch (_: Exception) {}
        }

        fun deliverOnce() {
            if (delivered.compareAndSet(false, true)) {
                result.success(devices.values.map { it.toMap() })
            }
        }

        try {
            val audioDevices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            for (device in audioDevices) {
                if (!isBluetoothAudioType(device.type)) continue
                upsertDevice(
                    device.productName?.toString(),
                    device.address,
                    device.type,
                    true,
                )
            }

            btAdapter?.bondedDevices?.forEach { bt ->
                upsertDevice(bt.name, bt.address, bt.type, false)
            }
        } catch (_: Exception) {}

        if (btAdapter == null) {
            deliverOnce()
            return
        }

        val profiles = listOf(BluetoothProfile.A2DP, BluetoothProfile.HEADSET)
        val pending = AtomicInteger(profiles.size)

        fun finishProfile() {
            if (pending.decrementAndGet() <= 0) {
                deliverOnce()
            }
        }

        mainHandler.postDelayed({ deliverOnce() }, 1200)

        profiles.forEach { profile ->
            try {
                val started = btAdapter.getProfileProxy(
                    this,
                    object : BluetoothProfile.ServiceListener {
                        override fun onServiceConnected(profileId: Int, proxy: BluetoothProfile) {
                            try {
                                markBondedDevicesFromProfile(proxy, profileId)
                                proxy.connectedDevices.forEach { device ->
                                    upsertDevice(device.name, device.address, profileId, true)
                                }
                            } catch (_: Exception) {
                            } finally {
                                try {
                                    btAdapter.closeProfileProxy(profileId, proxy)
                                } catch (_: Exception) {}
                                finishProfile()
                            }
                        }

                        override fun onServiceDisconnected(profileId: Int) = Unit
                    },
                    profile,
                )

                if (!started) {
                    finishProfile()
                }
            } catch (_: Exception) {
                finishProfile()
            }
        }
    }

    private fun startNativeRecording(messenger: BinaryMessenger) {
        stopNativeRecording()
        applySelectedInputRoute()

        EventChannel(messenger, "com.audiotraductor/mic").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    recordSink = events
                    recordThread = Thread {
                        val bufferSize = AudioRecord.getMinBufferSize(
                            16000,
                            AudioFormat.CHANNEL_IN_MONO,
                            AudioFormat.ENCODING_PCM_16BIT
                        )

                        audioRecord = buildAudioRecord(bufferSize)

                        // La preferencia se aplica sobre un dispositivo de entrada
                        // real; nunca sobre availableCommunicationDevices.
                        applyPreferredInputToActiveRecording()

                        audioRecord?.startRecording()
                        scheduleSelectedInputReassertion()

                        val buffer = ByteArray(bufferSize)
                        while (!Thread.currentThread().isInterrupted && audioRecord?.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                            val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                            if (read > 0) {
                                val chunk = buffer.copyOf(read)
                                recordHandler.post { recordSink?.success(chunk) }
                            }
                        }
                    }
                    recordThread?.start()
                }

                override fun onCancel(arguments: Any?) {
                    stopNativeRecording()
                }
            }
        )
    }

    private fun stopNativeRecording() {
        recordThread?.interrupt()
        recordThread = null
        try {
            audioRecord?.stop()
        } catch (_: Exception) {}
        audioRecord?.release()
        audioRecord = null
        recordSink = null
    }

    /// Guarda el comm device actual antes de limpiarlo (para restaurar salida luego).
    private fun saveCurrentCommDevice() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            lastCommDevice = am.communicationDevice
        }
    }

    /// Restaura el dispositivo de salida guardado.
    ///
    /// IMPORTANTE: NO usa setCommunicationDevice porque eso reactiva el HFP
    /// del BT y vuelve a tomar el micrófono del headset. En su lugar solo
    /// controlamos el altavoz y reaffirmamos el mic del celu.
    private fun restoreOutput() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val comm = lastCommDevice
            if (comm != null &&
                comm.type != AudioDeviceInfo.TYPE_BLUETOOTH_A2DP &&
                comm.type != AudioDeviceInfo.TYPE_BLUETOOTH_SCO
            ) {
                // Solo restaurar dispositivos NO Bluetooth
                am.setCommunicationDevice(comm)
            }
            am.isSpeakerphoneOn = false
        }
        // Re-afirmar mic del celular
        applyPreferredInputToActiveRecording()
        scheduleSelectedInputReassertion()
    }

    /// Limpia el comm device (solo API ≥ 31).
    private fun clearCommDevice() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.clearCommunicationDevice()
        }
    }

    /// Fuerza el micrófono del teléfono (no toca comm device).
    @Suppress("DEPRECATION")
    private fun forceBuiltinMic() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.clearCommunicationDevice()
        }
        audioManager.isBluetoothScoOn = false
        audioManager.stopBluetoothSco()
        audioManager.mode = AudioManager.MODE_NORMAL

        try {
            audioManager.setParameters("BT_SCO=off")
        } catch (_: Exception) {}

        // No desconectamos el perfil HFP: hacerlo sacaba el audífono de la
        // lista e impedía cambiar después a su micrófono. Detener SCO y
        // limpiar communicationDevice basta para volver al integrado.
        applyPreferredInputToActiveRecording()
    }

    /// El HAL de audio del Emulador de Android no enruta VOICE_RECOGNITION
    /// hacia el input del host (queda mudo); solo MIC/DEFAULT sí lo hacen.
    /// En hardware real preferimos VOICE_RECOGNITION por su mejor tuning para STT.
    private fun isRunningOnEmulator(): Boolean {
        return Build.FINGERPRINT.startsWith("generic") ||
            Build.FINGERPRINT.startsWith("unknown") ||
            Build.MODEL.contains("google_sdk") ||
            Build.MODEL.contains("Emulator") ||
            Build.MODEL.contains("Android SDK built for x86") ||
            Build.MANUFACTURER.contains("Genymotion") ||
            (Build.BRAND.startsWith("generic") && Build.DEVICE.startsWith("generic")) ||
            Build.PRODUCT.contains("sdk_gphone") ||
            Build.HARDWARE.contains("goldfish") ||
            Build.HARDWARE.contains("ranchu")
    }

    private fun buildAudioRecord(bufferSize: Int): AudioRecord {
        val source = when {
            isBluetoothInputSelected() -> MediaRecorder.AudioSource.VOICE_COMMUNICATION
            isRunningOnEmulator() -> MediaRecorder.AudioSource.MIC
            else -> MediaRecorder.AudioSource.VOICE_RECOGNITION
        }
        return AudioRecord.Builder()
            .setAudioSource(source)
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(16000)
                    .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .build()
            )
            .setBufferSizeInBytes(bufferSize)
            .build()
    }

    private fun rebuildActiveRecordingForSelectedInput() {
        val current = audioRecord ?: return
        try {
            val bufferSize = AudioRecord.getMinBufferSize(
                16000,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            current.stop()
            current.release()
            audioRecord = buildAudioRecord(bufferSize)
            applyPreferredInputToActiveRecording()
            audioRecord?.startRecording()
            scheduleSelectedInputReassertion()
        } catch (_: Exception) {}
    }

    private fun scheduleSelectedInputReassertion() {
        val delays = listOf<Long>(0, 250, 800)
        delays.forEach { delayMs ->
            mainHandler.postDelayed({
                try {
                    applySelectedInputRoute()
                } catch (_: Exception) {}
            }, delayMs)
        }
    }

    private fun applyPreferredInputToActiveRecording() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val preferredInput = selectedInputDevice()
            if (preferredInput != null) {
                audioRecord?.preferredDevice = preferredInput
            }
        } catch (_: Exception) {}
    }

    private fun registerBluetoothStateReceiver() {
        if (btReceiverRegistered) return
        try {
            val filter = IntentFilter().apply {
                addAction(BluetoothAdapter.ACTION_CONNECTION_STATE_CHANGED)
                addAction(BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED)
                addAction(BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED)
                addAction(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
            }
            registerReceiver(btStateReceiver, filter)
            btReceiverRegistered = true
        } catch (_: Exception) {}
    }

    private fun startAudioTrack() {
        stopAudioTrack()
        try {
            val bufferSize = maxOf(minBufferSize, 6400)
            audioTrack = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(16000)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .build()
                )
                .setBufferSizeInBytes(bufferSize)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
            applyPreferredOutputToAudioTrack()
            audioTrack?.play()
        } catch (_: Exception) {
            stopAudioTrack()
        }
    }

    private fun writeAudio(bytes: ByteArray) {
        audioTrack?.write(bytes, 0, bytes.size)
    }

    private fun stopAudioTrack() {
        audioTrack?.stop()
        audioTrack?.release()
        audioTrack = null
    }

    override fun onDestroy() {
        if (btReceiverRegistered) {
            try {
                unregisterReceiver(btStateReceiver)
            } catch (_: Exception) {}
            btReceiverRegistered = false
        }
        stopAudioTrack()
        stopNativeRecording()
        super.onDestroy()
    }
}
