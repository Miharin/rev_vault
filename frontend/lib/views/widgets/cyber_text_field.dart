import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A sleek, reusable, modern text field built for RevVault.
/// Standardizes styling, typography, height constraints, clear button handling,
/// prefix/suffix icons, monospace formatting, validation, and theme responsiveness.
class CyberTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? initialValue;
  final String? hintText;
  final String? labelText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final Widget? prefix;
  final Widget? suffix;
  final bool showClearButton;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onEditingComplete;
  final VoidCallback? onTap;
  final FormFieldValidator<String>? validator;
  final AutovalidateMode? autovalidateMode;
  final bool isMonospace;
  final double? height;
  final double fontSize;
  final Color? fillColor;
  final BorderRadius? borderRadius;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final int? maxLines;
  final int? minLines;
  final bool expands;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final EdgeInsetsGeometry? contentPadding;
  final MouseCursor? mouseCursor;

  const CyberTextField({
    super.key,
    this.controller,
    this.initialValue,
    this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffixIcon,
    this.prefix,
    this.suffix,
    this.showClearButton = false,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.onTap,
    this.validator,
    this.autovalidateMode,
    this.isMonospace = false,
    this.height,
    this.fontSize = 12.5,
    this.fillColor,
    this.borderRadius,
    this.autofocus = false,
    this.focusNode,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines,
    this.expands = false,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.contentPadding,
    this.mouseCursor,
  });

  @override
  State<CyberTextField> createState() => _CyberTextFieldState();
}

class _CyberTextFieldState extends State<CyberTextField> {
  TextEditingController? _internalController;
  TextEditingController get _effectiveController =>
      widget.controller ?? (_internalController ??= TextEditingController(text: widget.initialValue));

  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = _effectiveController.text.isNotEmpty;
    _effectiveController.addListener(_handleControllerChange);
  }

  @override
  void didUpdateWidget(covariant CyberTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.removeListener(_handleControllerChange);
      _effectiveController.addListener(_handleControllerChange);
      _hasText = _effectiveController.text.isNotEmpty;
    } else if (widget.controller == null && widget.initialValue != oldWidget.initialValue) {
      if (_internalController != null && _internalController!.text != widget.initialValue) {
        _internalController!.text = widget.initialValue ?? '';
        _hasText = _internalController!.text.isNotEmpty;
      }
    }
  }

  @override
  void dispose() {
    _effectiveController.removeListener(_handleControllerChange);
    _internalController?.dispose();
    super.dispose();
  }

  void _handleControllerChange() {
    final hasNow = _effectiveController.text.isNotEmpty;
    if (_hasText != hasNow && mounted) {
      setState(() {
        _hasText = hasNow;
      });
    }
  }

  void _clearText() {
    _effectiveController.clear();
    widget.onChanged?.call('');
    if (mounted) {
      setState(() {
        _hasText = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = widget.borderRadius ?? BorderRadius.circular(8);
    final effectiveFillColor = widget.fillColor ??
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35);

    // If height is not specified, use 42 for inputs without labelText, and natural height for labeled/multiline/expanding inputs
    final double? effectiveHeight = widget.expands
        ? null
        : (widget.height ?? (widget.labelText == null && widget.maxLines == 1 ? 42.0 : null));

    final textAlignVertical = widget.expands ? TextAlignVertical.top : TextAlignVertical.center;

    Widget? resolvedSuffix;
    if (widget.showClearButton && _hasText && widget.enabled && !widget.readOnly) {
      resolvedSuffix = IconButton(
        icon: const Icon(Icons.clear, size: 14),
        splashRadius: 16,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        tooltip: 'Clear',
        onPressed: _clearText,
      );
    } else if (widget.suffixIcon != null) {
      resolvedSuffix = widget.suffixIcon;
    }

    final inputDecoration = InputDecoration(
      labelText: widget.labelText,
      labelStyle: TextStyle(
        fontSize: widget.fontSize,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
      ),
      hintText: widget.hintText,
      hintStyle: TextStyle(
        fontSize: widget.fontSize,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
      ),
      prefix: widget.prefix,
      suffix: widget.suffix,
      prefixIcon: widget.prefixIcon != null
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: widget.prefixIcon,
            )
          : null,
      prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      suffixIcon: resolvedSuffix != null
          ? Padding(
              padding: const EdgeInsets.only(right: 6),
              child: resolvedSuffix,
            )
          : null,
      suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      isDense: true,
      filled: true,
      fillColor: effectiveFillColor,
      contentPadding: widget.contentPadding ??
          EdgeInsets.symmetric(
            horizontal: widget.prefixIcon != null ? 6 : 12,
            vertical: effectiveHeight != null ? 0 : 10,
          ),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.25)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.25)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: theme.colorScheme.error, width: 1.0),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: theme.colorScheme.error, width: 1.5),
      ),
    );

    final inputStyle = TextStyle(
      fontFamily: widget.isMonospace ? 'monospace' : null,
      fontSize: widget.fontSize,
      color: widget.enabled ? theme.colorScheme.onSurface : theme.disabledColor,
    );

    final Widget childField;
    if (widget.validator != null) {
      childField = TextFormField(
        controller: _effectiveController,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        enabled: widget.enabled,
        readOnly: widget.readOnly,
        obscureText: widget.obscureText,
        maxLines: widget.maxLines,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        inputFormatters: widget.inputFormatters,
        onChanged: widget.onChanged,
        onFieldSubmitted: widget.onSubmitted,
        onEditingComplete: widget.onEditingComplete,
        onTap: widget.onTap,
        mouseCursor: widget.mouseCursor,
        validator: widget.validator,
        autovalidateMode: widget.autovalidateMode,
        textAlignVertical: textAlignVertical,
        expands: widget.expands,
        minLines: widget.minLines,
        style: inputStyle,
        decoration: inputDecoration,
      );
    } else {
      childField = TextField(
        controller: _effectiveController,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        enabled: widget.enabled,
        readOnly: widget.readOnly,
        obscureText: widget.obscureText,
        maxLines: widget.maxLines,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        inputFormatters: widget.inputFormatters,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        onEditingComplete: widget.onEditingComplete,
        onTap: widget.onTap,
        mouseCursor: widget.mouseCursor,
        textAlignVertical: textAlignVertical,
        expands: widget.expands,
        minLines: widget.minLines,
        style: inputStyle,
        decoration: inputDecoration,
      );
    }

    if (effectiveHeight != null) {
      return SizedBox(
        height: effectiveHeight,
        child: childField,
      );
    }

    return childField;
  }
}
