import 'dart:ui';

import 'package:flutter/material.dart';

/// Frosted-glass container with optional gradient border glow.
/// Enhanced with tap animation and inner shadow.
class GlassCard extends StatefulWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.blur = 18,
    this.opacity = 0.12,
    this.borderRadius = 16,
    this.glowColor,
    this.padding,
    this.margin,
    this.onTap,
    this.tapAnimate = true,
  });

  final Widget child;
  final double blur;
  final double opacity;
  final double borderRadius;
  final Color? glowColor;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final bool tapAnimate;

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final glow = widget.glowColor ?? cs.primary;
    final radius = BorderRadius.circular(widget.borderRadius);

    Widget card = Container(
      margin: widget.margin,
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
          filter: ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
          child: Container(
            padding: widget.padding ?? const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: radius,
              color: cs.surfaceContainerHigh
                  .withValues(alpha: 0.65 + widget.opacity),
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
            child: widget.child,
          ),
        ),
      ),
    );

    if (widget.onTap != null && widget.tapAnimate) {
      card = GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: card,
        ),
      );
    } else if (widget.onTap != null) {
      card = GestureDetector(onTap: widget.onTap, child: card);
    }

    return card;
  }
}
