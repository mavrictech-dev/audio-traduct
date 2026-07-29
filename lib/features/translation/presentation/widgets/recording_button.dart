import 'package:flutter/material.dart';
import 'package:audio_traductor/core/services/audio_level_service.dart';
import 'package:audio_traductor/core/theme/liquid_glass/liquid_glass.dart';

/// Botón de grabación: un orbe de vidrio que reacciona al nivel de voz real
/// (mismo [AudioLevelService] que ya alimentaba el pulso del botón original).
/// El blur, el tinte y el brillo del vidrio crecen con el volumen — la idea
/// es que el vidrio "escuche": cuanto más fuerte se habla, más viva se ve
/// la superficie, en vez de solo escalar un círculo plano.
class RecordingButton extends StatefulWidget {
  final bool isStreaming;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const RecordingButton({
    super.key,
    required this.isStreaming,
    required this.onStart,
    required this.onStop,
  });

  @override
  State<RecordingButton> createState() => _RecordingButtonState();
}

class _RecordingButtonState extends State<RecordingButton> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: widget.isStreaming ? widget.onStop : widget.onStart,
      child: ValueListenableBuilder<double>(
        valueListenable: AudioLevelService.instance.levelNotifier,
        builder: (context, level, child) {
          final effectiveLevel = widget.isStreaming ? level : 0.0;
          final accent = widget.isStreaming ? colorScheme.error : colorScheme.primary;
          // `onPrimary` asume un fondo SÓLIDO de `primary` — ya no aplica:
          // el orbe ahora es vidrio translúcido, así que el contraste real
          // depende del brillo general del tema, no del par primary/onPrimary.
          final iconColor = theme.brightness == Brightness.dark
              ? Colors.white
              : colorScheme.onSurface;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOutQuad,
            width: 92 + (effectiveLevel * 22),
            height: 92 + (effectiveLevel * 22),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.32 + (effectiveLevel * 0.32)),
                  blurRadius: 24.0 + (effectiveLevel * 20.0),
                  spreadRadius: 2.0 + (effectiveLevel * 8.0),
                ),
              ],
            ),
            child: LiquidGlass(
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              tintColor: accent,
              tintOpacity: 0.30 + (effectiveLevel * 0.24),
              blurSigma: 16 + (effectiveLevel * 14),
              child: Center(
                child: Icon(
                  widget.isStreaming ? Icons.stop_rounded : Icons.mic_rounded,
                  size: 40,
                  color: iconColor,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
