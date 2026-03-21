import 'package:flutter/material.dart';

/// Primary line (filename, label) + muted metadata line with clear spacing.
/// Use for chunks, audio lists, stats rows, etc.
class PrimaryMetaRow extends StatelessWidget {
  const PrimaryMetaRow({
    super.key,
    required this.primary,
    required this.meta,
    this.trailing,
    this.verticalPadding = 6,
  });

  final String primary;
  final String meta;
  final Widget? trailing;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primary,
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.15,
                    color: cs.onSurface,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  meta,
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w400,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
