import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Gradient-filled animated linear progress bar with an optional time label.
class AnimatedProgressBar extends StatelessWidget {
  const AnimatedProgressBar({
    super.key,
    required this.progress,
    this.elapsedLabel,
    this.totalLabel,
    this.height = 6,
    this.startColor,
    this.endColor,
  });

  /// 0.0 – 1.0
  final double progress;
  final String? elapsedLabel;
  final String? totalLabel;
  final double height;
  final Color? startColor;
  final Color? endColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final start = startColor ?? AppTheme.nowPlayingBlue;
    final end = endColor ?? cs.primary;
    final p = progress.clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Stack(
              children: [
                // Track
                Container(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                ),
                // Fill
                FractionallySizedBox(
                  widthFactor: p,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [start, end]),
                      borderRadius: BorderRadius.circular(height / 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (elapsedLabel != null || totalLabel != null) ...[
          const SizedBox(height: 4),
          Text(
            '${elapsedLabel ?? '0:00'} / ${totalLabel ?? '0:00'}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ],
    );
  }
}
