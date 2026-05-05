import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Paginator with clickable page numbers and prev/next arrows.
class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.page,
    required this.totalPages,
    this.onPrev,
    this.onNext,
    this.onPageSelected,
  });

  final int page;
  final int totalPages;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  /// Direct page jump — receives 1-based page number.
  final ValueChanged<int>? onPageSelected;

  /// Build the list of page indicators: ints for page buttons, null for ellipsis.
  List<int?> _pageNumbers() {
    if (totalPages <= 7) {
      return List.generate(totalPages, (i) => i + 1);
    }
    // Always show first, last, current, and 1 neighbour each side.
    final pages = <int?>[1];
    final start = math.max(2, page - 1);
    final end = math.min(totalPages - 1, page + 1);
    if (start > 2) pages.add(null); // ellipsis
    for (int i = start; i <= end; i++) {
      pages.add(i);
    }
    if (end < totalPages - 1) pages.add(null); // ellipsis
    pages.add(totalPages);
    return pages;
  }

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    final numbers = _pageNumbers();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Prev arrow
          _ArrowButton(
            icon: Icons.chevron_left_rounded,
            onTap: page > 1 ? (onPrev ?? () => onPageSelected?.call(page - 1)) : null,
          ),
          const SizedBox(width: 4),
          // Page numbers
          for (final p in numbers) ...[
            if (p == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text('…',
                    style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: 13)),
              )
            else
              _PageButton(
                page: p,
                isActive: p == page,
                onTap: () {
                  if (p != page) onPageSelected?.call(p);
                },
              ),
          ],
          const SizedBox(width: 4),
          // Next arrow
          _ArrowButton(
            icon: Icons.chevron_right_rounded,
            onTap: page < totalPages ? (onNext ?? () => onPageSelected?.call(page + 1)) : null,
          ),
        ],
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.page,
    required this.isActive,
    required this.onTap,
  });
  final int page;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: isActive ? cs.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: isActive ? null : onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            constraints: const BoxConstraints(minWidth: 30, minHeight: 28),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '$page',
              style: TextStyle(
                color: isActive ? cs.onPrimary : cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        color: cs.onSurfaceVariant,
        disabledColor: cs.onSurfaceVariant.withValues(alpha: 0.25),
      ),
    );
  }
}
