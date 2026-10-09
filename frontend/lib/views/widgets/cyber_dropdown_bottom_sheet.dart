import 'package:flutter/material.dart';

class CyberDropdownItem<T> {
  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final Color? color;

  const CyberDropdownItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
    this.color,
  });
}

/// Displays a sleek, sci-fi themed BottomSheet modal for selecting dropdown items.
Future<T?> showCyberDropdownBottomSheet<T>({
  required BuildContext context,
  required String title,
  required List<CyberDropdownItem<T>> items,
  T? selectedValue,
  String? searchHint,
  IconData? headerIcon,
  bool useRootNavigator = true,
}) async {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: useRootNavigator,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return _CyberDropdownBottomSheetContent<T>(
        title: title,
        items: items,
        selectedValue: selectedValue,
        searchHint: searchHint,
        headerIcon: headerIcon,
      );
    },
  );
}

class _CyberDropdownBottomSheetContent<T> extends StatefulWidget {
  final String title;
  final List<CyberDropdownItem<T>> items;
  final T? selectedValue;
  final String? searchHint;
  final IconData? headerIcon;

  const _CyberDropdownBottomSheetContent({
    required this.title,
    required this.items,
    required this.selectedValue,
    this.searchHint,
    this.headerIcon,
  });

  @override
  State<_CyberDropdownBottomSheetContent<T>> createState() =>
      _CyberDropdownBottomSheetContentState<T>();
}

class _CyberDropdownBottomSheetContentState<T>
    extends State<_CyberDropdownBottomSheetContent<T>> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    final filtered = widget.items.where((item) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return item.label.toLowerCase().contains(q) ||
          (item.subtitle?.toLowerCase().contains(q) ?? false);
    }).toList();

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // BottomSheet Handle
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    widget.headerIcon ?? Icons.unfold_more,
                    size: 18,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        '${widget.items.length} options available',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Search Bar (shown when list > 5 items)
            if (widget.items.length > 5) ...[
              TextField(
                controller: _searchCtrl,
                autofocus: widget.items.length > 10,
                onChanged: (val) => setState(() => _query = val.trim()),
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  hintText: widget.searchHint ?? 'Filter options...',
                  hintStyle: const TextStyle(fontSize: 11.5, color: Colors.grey),
                  prefixIcon: const Icon(Icons.search, size: 16, color: Colors.grey),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 14),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Item List
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No options match "$_query"',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: theme.dividerColor.withValues(alpha: 0.15),
                      ),
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final isSelected = widget.selectedValue == item.value;

                        return Material(
                          color: isSelected
                              ? accent.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          child: InkWell(
                            onTap: () => Navigator.of(context).pop(item.value),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(
                                children: [
                                  if (item.icon != null) ...[
                                    Icon(
                                      item.icon,
                                      size: 16,
                                      color: item.color ?? (isSelected ? accent : Colors.grey),
                                    ),
                                    const SizedBox(width: 10),
                                  ],
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.label,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                            color: isSelected ? accent : null,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                        if (item.subtitle != null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            item.subtitle!,
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(Icons.check_circle, size: 16, color: accent),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
