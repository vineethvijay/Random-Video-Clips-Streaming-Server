import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Reusable search bar with debounced input, filter chips, and sort dropdown.
class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    this.searchController,
    this.searchHint = 'Search…',
    this.onSearchChanged,
    this.sortWidget,
    this.filterWidgets = const [],
    this.trailing,
  });

  final TextEditingController? searchController;
  final String searchHint;
  final ValueChanged<String>? onSearchChanged;
  final Widget? sortWidget;
  final List<Widget> filterWidgets;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withValues(alpha: 0.1)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Search
          if (searchController != null)
            SizedBox(
              width: 220,
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                style: tt.bodySmall,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: searchHint,
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 18, color: cs.onSurfaceVariant),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  filled: true,
                  fillColor: AppTheme.surfaceHighest.withValues(alpha: 0.6),
                ),
              ),
            ),
          if (sortWidget != null) sortWidget!,
          ...filterWidgets,
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Sort dropdown builder matching the theme.
class SortDropdown<T extends Enum> extends StatelessWidget {
  const SortDropdown({
    super.key,
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> labels;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
      ),
      child: DropdownButton<T>(
        value: value,
        isDense: true,
        underline: const SizedBox.shrink(),
        dropdownColor: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        style: tt.bodySmall?.copyWith(color: cs.onSurface),
        icon: Icon(Icons.unfold_more_rounded,
            size: 16, color: cs.onSurfaceVariant),
        items: labels.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
