import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_theme.dart';

/// Shimmer skeleton loader that mimics card shapes.
class ShimmerLoader extends StatelessWidget {
  const ShimmerLoader({
    super.key,
    this.height = 80,
    this.width,
    this.borderRadius = 14,
    this.count = 1,
    this.spacing = 12,
  });

  final double height;
  final double? width;
  final double borderRadius;
  final int count;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppTheme.surfaceHigh,
      highlightColor: AppTheme.surfaceHighest,
      child: Column(
        children: List.generate(count, (i) {
          return Padding(
            padding: EdgeInsets.only(bottom: i < count - 1 ? spacing : 0),
            child: Container(
              height: height,
              width: width ?? double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.surfaceHigh,
                borderRadius: BorderRadius.circular(borderRadius),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Shimmer stat card row skeleton.
class ShimmerStatRow extends StatelessWidget {
  const ShimmerStatRow({super.key, this.count = 4});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppTheme.surfaceHigh,
      highlightColor: AppTheme.surfaceHighest,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: List.generate(count, (_) {
          return Container(
            width: 150,
            height: 60,
            decoration: BoxDecoration(
              color: AppTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
            ),
          );
        }),
      ),
    );
  }
}
