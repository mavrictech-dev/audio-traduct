import 'package:flutter/material.dart';
import 'package:audio_traductor/core/services/audio_level_service.dart';

/// Botón circular animado para iniciar/detener la traducción.
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
          return AnimatedScale(
            scale: 1.0 + (effectiveLevel * 0.4),
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOutQuad,
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isStreaming ? colorScheme.error : colorScheme.primary,
                boxShadow: [
                  BoxShadow(
                    color: (widget.isStreaming ? colorScheme.error : colorScheme.primary)
                        .withValues(alpha: 0.3 + (effectiveLevel * 0.3)),
                    blurRadius: 20.0 + (effectiveLevel * 10.0),
                    spreadRadius: 2.0 + (effectiveLevel * 5.0),
                  ),
                ],
              ),
              child: Icon(
                widget.isStreaming ? Icons.stop_rounded : Icons.mic_rounded,
                size: 40,
                color: colorScheme.onPrimary,
              ),
            ),
          );
        },
      ),
    );
  }
}
