import 'dart:async';
import 'dart:typed_data';
import 'package:audio_traductor/core/services/audio_level_service.dart';
import 'package:flutter/services.dart';

/// Servicio de passthrough: captura el micrófono y lo reproduce
/// por el altavoz en tiempo real usando AudioTrack nativo de Android.
///
/// Latencia ~100ms. Sin archivos, sin just_audio.
class MicPassthroughService {
  static const _channel = MethodChannel('com.audiotraductor/passthrough');
  static const _audioChannel = MethodChannel('com.audiotraductor/audio');
  static const _micChannel = EventChannel('com.audiotraductor/mic');

  StreamSubscription<List<int>>? _micSub;
  bool _running = false;

  bool get isRunning => _running;

  /// Inicia el passthrough (mic → parlante).
  Future<void> start() async {
    if (_running) return;
    _running = true;

    try {
      await _audioChannel.invokeMethod('startRecording');
      await _channel.invokeMethod('start');
    } catch (_) {
      _running = false;
      return;
    }

    try {
      final stream = _micChannel.receiveBroadcastStream().map<List<int>>((event) {
        if (event is Uint8List) return event;
        if (event is List<int>) return event;
        if (event is List) return List<int>.from(event);
        return const <int>[];
      });

      _micSub = stream.listen(
        (chunk) {
          if (!_running) return;
          var sum = 0;
          for (var i = 0; i < chunk.length - 1; i += 2) {
            final unsigned = ((chunk[i + 1] & 0xFF) << 8) | (chunk[i] & 0xFF);
            final sample = unsigned > 32767 ? unsigned - 65536 : unsigned;
            sum += sample.abs();
          }
          final mav = chunk.length > 0 ? sum / (chunk.length ~/ 2) : 0.0;
          AudioLevelService.instance.updateLevel(mav);

          _channel.invokeMethod('write', <String, dynamic>{
            'bytes': chunk,
          });
        },
        onError: (_) => stop(),
      );
    } catch (_) {
      _running = false;
    }
  }

  /// Detiene el passthrough.
  Future<void> stop() async {
    _running = false;
    AudioLevelService.instance.reset();
    await _micSub?.cancel();
    _micSub = null;
    try {
      await _audioChannel.invokeMethod('stopRecording');
    } catch (_) {}
    await _channel.invokeMethod('stop');
  }

  void dispose() {
    stop();
  }
}
