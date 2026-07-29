import 'package:flutter/material.dart';
import 'liquid_glass.dart';

class GlassNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const GlassNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// Barra de navegación inferior flotante, en vidrio, con esquinas continuas.
/// Reemplaza a la `NavigationBar` de Material — misma navegación de 3
/// pestañas, terminación visual distinta.
class GlassNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<GlassNavItem> items;

  const GlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset > 0 ? bottomInset : 16),
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(30),
        blurSigma: 28,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        child: SizedBox(
          height: 58,
          child: Row(
            children: List.generate(items.length, (i) {
              final selected = i == currentIndex;
              final item = items[i];
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onDestinationSelected(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: selected
                          ? scheme.primary.withValues(alpha: 0.22)
                          : Colors.transparent,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          selected ? item.selectedIcon : item.icon,
                          color: selected ? scheme.primary : scheme.onSurfaceVariant,
                          size: 24,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                            color: selected ? scheme.primary : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
