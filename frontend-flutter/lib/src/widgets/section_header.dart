import 'package:flutter/material.dart';

/// Page header with gradient icon, title, optional subtitle, and action buttons.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.actions = const [],
    this.onRefresh,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> actions;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(colors: [
              cs.primary.withValues(alpha: 0.3),
              cs.tertiary.withValues(alpha: 0.2),
            ]),
            border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
          ),
          child: Icon(icon, color: cs.primary, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: tt.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              if (subtitle != null)
                Text(subtitle!,
                    style: tt.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        ...actions,
        if (onRefresh != null)
          IconButton.filledTonal(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
      ],
    );
  }
}
