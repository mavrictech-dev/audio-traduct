import 'package:flutter/foundation.dart';

class AudioLevelService {
  AudioLevelService._();
  static final AudioLevelService instance = AudioLevelService._();

  final ValueNotifier<double> levelNotifier = ValueNotifier<double>(0.0);

  void updateLevel(double mav) {
    // Normalizamos el MAV (Media de Amplitud Absoluta). 
    // Usualmente la voz normal oscila entre 500 y 3000.
    double normalized = mav / 3000.0;
    if (normalized > 1.0) normalized = 1.0;
    if (normalized < 0.0) normalized = 0.0;
    levelNotifier.value = normalized;
  }

  void reset() {
    levelNotifier.value = 0.0;
  }
}
