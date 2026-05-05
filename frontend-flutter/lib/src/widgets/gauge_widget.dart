import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Circular gauge for system metrics (CPU, Memory, GPU).
class GaugeWidget extends StatelessWidget {
  const GaugeWidget({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.size = 80,
    this.subtitle,
  });

  /// 0.0 – 100.0
  final String label;
  final double value;
  final Color? color;
  final double size;
  final String? subtitle;

  Color get _effectiveColor {
    if (color != null) return color!;
    if (value > 80) return AppTheme.accentRose;
    if (value > 50) return AppTheme.accentAmber;
    return AppTheme.accentEmerald;
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _GaugePainter(
              value: value.clamp(0, 100) / 100,
              color: _effectiveColor,
              trackColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            ),
            child: Center(
              child: Text(
                '${value.toStringAsFixed(0)}%',
                style: tt.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _effectiveColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: tt.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 10,
            ),
          ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.color,
    required this.trackColor,
  });

  final double value;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;
    const startAngle = -math.pi * 0.75;
    const sweepFull = math.pi * 1.5;

    // Track
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepFull,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );

    // Fill
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepFull * value,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.color != color;
}
