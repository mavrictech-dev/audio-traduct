import 'package:audio_traductor/core/branding/mavric_footer.dart';
import 'package:audio_traductor/core/theme/liquid_glass/liquid_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'terms_content.dart';

/// Modal de Términos y Condiciones del primer inicio.
///
/// No se puede descartar tocando fuera ni con el botón atrás: la única salida
/// es aceptar (continúa) o rechazar (cierra la app). Habilita el botón de
/// aceptar recién cuando el texto se leyó hasta el final.
class TermsDialog extends StatefulWidget {
  /// Se dispara cuando el usuario acepta.
  final VoidCallback onAccepted;

  const TermsDialog({super.key, required this.onAccepted});

  @override
  State<TermsDialog> createState() => _TermsDialogState();
}

class _TermsDialogState extends State<TermsDialog> {
  final _scrollController = ScrollController();
  bool _reachedEnd = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Si el texto entra entero en pantalla no hay scroll que hacer:
    // habilitamos el botón apenas se mide el viewport.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  void _onScroll() {
    if (_reachedEnd || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 24) {
      setState(() => _reachedEnd = true);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final media = MediaQuery.of(context);

    return PopScope(
      canPop: false,
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 20,
            vertical: media.padding.vertical + 32,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 460,
              maxHeight: media.size.height * 0.82,
            ),
            child: LiquidGlass(
              borderRadius: BorderRadius.circular(28),
              blurSigma: 30,
              tintOpacity: 0.22,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _header(theme, scheme),
                  Flexible(child: _body(theme, scheme)),
                  _actions(scheme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withValues(alpha: 0.16),
            ),
            child: Icon(
              Icons.gavel_rounded,
              color: scheme.primary,
              size: 26,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Términos y Condiciones',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            TermsContent.intro,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(ThemeData theme, ColorScheme scheme) {
    return Stack(
      children: [
        Scrollbar(
          controller: _scrollController,
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            itemCount: TermsContent.sections.length,
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (_, i) {
              final section = TermsContent.sections[i];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    section.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    section.body,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                  ),
                ],
              );
            },
          ),
        ),
        // Degradado inferior: sugiere que todavía queda texto por leer.
        if (!_reachedEnd)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 36,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      scheme.surface.withValues(alpha: 0),
                      scheme.surface.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _actions(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _reachedEnd ? widget.onAccepted : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                _reachedEnd ? 'Aceptar y continuar' : 'Deslizá para leer todo',
              ),
            ),
          ),
          TextButton(
            // Cerrar la app es la única alternativa a aceptar.
            onPressed: () => SystemNavigator.pop(),
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
            ),
            child: const Text('No acepto'),
          ),
          const MavricFooter(opacity: 0.5),
        ],
      ),
    );
  }
}
