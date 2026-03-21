import 'dart:ui';

import 'package:flutter/material.dart';

/// Frosted-glass container with optional gradient border glow.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.blur = 18,
    this.opacity = 0.12,
    this.borderRadius = 16,
    this.glowColor,
    this.padding,
    this.margin,
  });

  final Widget child;
  final double blur;
  final double opacity;
  final double borderRadius;
  final Color? glowColor;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final glow = glowColor ?? cs.primary;
    final radius = BorderRadius.circular(borderRadius);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: glow.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding ?? const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: radius,
              color: cs.surfaceContainerHigh.withValues(alpha: 0.65 + opacity),
              border: Border.all(
                color: cs.outline.withValues(alpha: 0.2),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cs.surfaceContainerHigh.withValues(alpha: 0.7),
                  cs.surfaceContainer.withValues(alpha: 0.5),
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
