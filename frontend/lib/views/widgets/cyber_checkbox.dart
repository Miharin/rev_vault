import 'package:flutter/material.dart';

/// A sleek, tactical Cyberpunk-themed checkbox designed for RevVault.
/// Supports binary and tristate (indeterminate) selection, responsive hover glow,
/// custom sizes (micro 16px/18px for data grids up to 22px for forms),
/// and full accessibility semantics.
class CyberCheckbox extends StatefulWidget {
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final bool tristate;
  final double size;
  final Color? activeColor;
  final Color? checkColor;
  final Color? inactiveBorderColor;
  final String? tooltip;
  final String? semanticLabel;

  const CyberCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.tristate = false,
    this.size = 18.0,
    this.activeColor,
    this.checkColor,
    this.inactiveBorderColor,
    this.tooltip,
    this.semanticLabel,
  });

  @override
  State<CyberCheckbox> createState() => _CyberCheckboxState();
}

class _CyberCheckboxState extends State<CyberCheckbox> {
  bool _isHovered = false;

  void _handleTap() {
    if (widget.onChanged == null) return;

    if (widget.tristate) {
      if (widget.value == null) {
        widget.onChanged!(true);
      } else if (widget.value == true) {
        widget.onChanged!(false);
      } else {
        widget.onChanged!(true);
      }
    } else {
      widget.onChanged!(!(widget.value ?? false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = widget.onChanged != null;
    final primary = widget.activeColor ?? theme.colorScheme.primary;
    final isChecked = widget.value == true;
    final isIndeterminate = widget.value == null;
    final hasActiveState = isChecked || isIndeterminate;

    final glyphColor = widget.checkColor ?? Colors.white;

    Widget checkboxBox = MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: isEnabled ? _handleTap : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: hasActiveState
                ? (isEnabled ? primary : primary.withValues(alpha: 0.35))
                : (_isHovered && isEnabled
                    ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: hasActiveState
                  ? primary
                  : (_isHovered && isEnabled
                      ? primary.withValues(alpha: 0.8)
                      : (widget.inactiveBorderColor ?? theme.dividerColor.withValues(alpha: 0.45))),
              width: 1.4,
            ),
            boxShadow: hasActiveState && isEnabled
                ? [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.35),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : (_isHovered && isEnabled
                    ? [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.15),
                          blurRadius: 3,
                        ),
                      ]
                    : null),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 120),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: child,
            ),
            child: isChecked
                ? Icon(
                    Icons.check,
                    key: const ValueKey('check'),
                    size: widget.size * 0.72,
                    color: glyphColor,
                  )
                : isIndeterminate
                    ? Center(
                        key: const ValueKey('dash'),
                        child: Container(
                          width: widget.size * 0.52,
                          height: 2.0,
                          decoration: BoxDecoration(
                            color: glyphColor,
                            borderRadius: BorderRadius.circular(1.0),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('empty')),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      checkboxBox = Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(milliseconds: 400),
        child: checkboxBox,
      );
    }

    return Semantics(
      checked: isChecked,
      enabled: isEnabled,
      label: widget.semanticLabel ?? widget.tooltip ?? 'Cyber Checkbox',
      child: checkboxBox,
    );
  }
}
