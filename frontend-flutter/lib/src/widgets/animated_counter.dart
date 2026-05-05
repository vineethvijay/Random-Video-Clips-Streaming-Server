import 'package:flutter/material.dart';

/// Animated number counter with roll transition.
class AnimatedCounter extends StatelessWidget {
  const AnimatedCounter({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 600),
    this.prefix = '',
    this.suffix = '',
  });

  final num value;
  final TextStyle? style;
  final Duration duration;
  final String prefix;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, val, _) {
        final display = value is int
            ? '$prefix${val.toInt()}$suffix'
            : '$prefix${val.toStringAsFixed(1)}$suffix';
        return Text(display, style: style);
      },
    );
  }
}
