import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Persistent bottom-navigation shell wrapping Dashboard / Admin / Stats pages.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static int _index(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    if (path.startsWith('/admin')) return 1;
    if (path.startsWith('/stats')) return 2;
    return 0;
  }

  static const _tabs = <_Tab>[
    _Tab('Dashboard', '/', Icons.dashboard_rounded),
    _Tab('Admin', '/admin', Icons.admin_panel_settings_rounded),
    _Tab('Stats', '/stats', Icons.bar_chart_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final idx = _index(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: cs.outline.withValues(alpha: 0.15),
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: idx,
          onTap: (i) {
            if (i != idx) context.go(_tabs[i].path);
          },
          items: _tabs.map((t) {
            return BottomNavigationBarItem(
              icon: Icon(t.icon),
              activeIcon: _GlowIcon(icon: t.icon, color: cs.primary),
              label: t.label,
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _Tab {
  const _Tab(this.label, this.path, this.icon);
  final String label;
  final String path;
  final IconData icon;
}

/// Wraps the active icon with a subtle glow background.
class _GlowIcon extends StatelessWidget {
  const _GlowIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: 0.15),
      ),
      child: Icon(icon, color: color),
    );
  }
}
