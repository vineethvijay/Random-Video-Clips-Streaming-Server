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
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFF111C36), Color(0xFF0F1A31)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFF2A3C65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (onRefresh != null)
                IconButton(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _tab(context, 'Dashboard', '/', _active(context, '/')),
              _tab(context, 'Admin', '/admin', _active(context, '/admin')),
              _tab(context, 'Stats', '/stats', _active(context, '/stats')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, String text, String path, bool active) {
    return FilledButton.tonal(
      onPressed: () => context.go(path),
      style: FilledButton.styleFrom(
        backgroundColor: active ? const Color(0xFF4F46E5) : const Color(0xFF1E2B49),
        foregroundColor: Colors.white,
      ),
      child: Text(text),
    );
  }
}
