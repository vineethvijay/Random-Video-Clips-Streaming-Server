import 'package:flutter/material.dart';

/// Simple paginator with page counter and prev/next arrows.
class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.page,
    required this.totalPages,
    this.onPrev,
    this.onNext,
  });

  final int page;
  final int totalPages;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Page $page of $totalPages',
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: page > 1 ? onPrev : null,
                icon: const Icon(Icons.chevron_left_rounded),
                iconSize: 20,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: page < totalPages ? onNext : null,
                icon: const Icon(Icons.chevron_right_rounded),
                iconSize: 20,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
