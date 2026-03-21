import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    super.key,
    required this.title,
    this.onRefresh,
  });

  final String title;
  final VoidCallback? onRefresh;

  bool _active(BuildContext context, String path) {
    final current = GoRouterState.of(context).uri.path;
    return current == path;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            cs.surfaceContainerHigh,
            cs.surfaceContainer.withValues(alpha: 0.92),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: cs.outline.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.14),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: [
                      cs.primary.withValues(alpha: 0.35),
                      cs.tertiary.withValues(alpha: 0.25),
                    ],
                  ),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.45)),
                ),
                child: Icon(Icons.play_circle_fill_rounded, color: cs.primary, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: tt.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Control panel · HLS streaming',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onRefresh != null)
                IconButton.filledTonal(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Refresh',
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _tab(
                context,
                label: 'Dashboard',
                path: '/',
                icon: Icons.dashboard_rounded,
                active: _active(context, '/'),
              ),
              _tab(
                context,
                label: 'Admin',
                path: '/admin',
                icon: Icons.admin_panel_settings_rounded,
                active: _active(context, '/admin'),
              ),
              _tab(
                context,
                label: 'Stats',
                path: '/stats',
                icon: Icons.bar_chart_rounded,
                active: _active(context, '/stats'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tab(
    BuildContext context, {
    required String label,
    required String path,
    required IconData icon,
    required bool active,
  }) {
    final cs = Theme.of(context).colorScheme;

    return FilledButton.tonalIcon(
      onPressed: () => context.go(path),
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        foregroundColor: active ? cs.onPrimary : cs.onSurface,
        backgroundColor: active ? cs.primary : cs.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        elevation: active ? 2 : 0,
        shadowColor: cs.primary.withValues(alpha: 0.45),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: active ? cs.primary.withValues(alpha: 0.6) : cs.outline.withValues(alpha: 0.25),
          ),
        ),
      ),
    );
  }
}
