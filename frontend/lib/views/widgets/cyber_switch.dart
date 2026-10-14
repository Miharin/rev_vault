import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A sleek, modern tactical Cyberpunk toggle switch for RevVault.
/// Features dynamic squash-and-stretch thumb deformation, multi-tier photonic bloom,
/// ceramic top-lit capsule finish, micro-status LED indicator, and fluid spring physics.
class CyberSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? thumbColor;
  final Color? activeThumbColor;
  final Widget? activeThumbIcon;
  final Widget? inactiveThumbIcon;
  final double width;
  final double height;
  final bool showGlow;
  final String? tooltip;
  final String? semanticLabel;

  const CyberSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
    this.activeThumbColor,
    this.activeThumbIcon,
    this.inactiveThumbIcon,
    this.width = 42.0,
    this.height = 22.0,
    this.showGlow = true,
    this.tooltip,
    this.semanticLabel,
  });

  @override
  State<CyberSwitch> createState() => _CyberSwitchState();
}

class _CyberSwitchState extends State<CyberSwitch> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _slideAnimation;
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      value: widget.value ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
    );
    _slideAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInBack,
    );
  }

  @override
  void didUpdateWidget(CyberSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.onChanged != null) {
      widget.onChanged!(!widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = widget.onChanged != null;
    final primary = widget.activeColor ?? theme.colorScheme.primary;
    final inactiveBg = widget.inactiveColor ?? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55);

    final trackBorderRadius = BorderRadius.circular(widget.height / 2);
    final thumbBaseSize = widget.height - 4.0;
    final maxTravel = widget.width - widget.height;

    Widget switchContent = MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: isEnabled ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: isEnabled ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel: isEnabled ? () => setState(() => _isPressed = false) : null,
        onTap: isEnabled ? _handleTap : null,
        child: AnimatedScale(
          scale: _isPressed ? 0.95 : (_isHovered && isEnabled ? 1.02 : 1.0),
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          child: AnimatedBuilder(
            animation: _slideAnimation,
            builder: (context, child) {
              final rawT = _slideAnimation.value;
              final t = rawT.clamp(0.0, 1.0);

              // Kinematic squash-and-stretch: thumb elongates slightly during transit
              final stretch = math.sin(t * math.pi) * 3.5;
              final currentThumbWidth = thumbBaseSize + stretch;
              final currentThumbHeight = thumbBaseSize;
              final currentOffset = maxTravel * t;

              // Track gradient blending
              final trackDecoration = BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color.lerp(inactiveBg, primary, t)!,
                    Color.lerp(inactiveBg, primary.withValues(alpha: 0.82), t)!,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: trackBorderRadius,
                border: Border.all(
                  color: Color.lerp(
                    _isHovered && isEnabled
                        ? theme.dividerColor.withValues(alpha: 0.65)
                        : theme.dividerColor.withValues(alpha: 0.35),
                    Colors.white.withValues(alpha: 0.28),
                    t,
                  )!,
                  width: 1.2,
                ),
                boxShadow: widget.showGlow && t > 0.05 && isEnabled
                    ? [
                        // Stage 1: Tight inner optical glow
                        BoxShadow(
                          color: primary.withValues(alpha: 0.45 * t),
                          blurRadius: 7 * t,
                          spreadRadius: 0.5 * t,
                        ),
                        // Stage 2: Diffused atmospheric bloom
                        BoxShadow(
                          color: primary.withValues(alpha: 0.22 * t),
                          blurRadius: 16 * t,
                          spreadRadius: 1 * t,
                        ),
                      ]
                    : (_isHovered && isEnabled
                        ? [
                            BoxShadow(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                              blurRadius: 4,
                            ),
                          ]
                        : null),
              );

              return Container(
                width: widget.width,
                height: widget.height,
                padding: const EdgeInsets.all(2.0),
                decoration: trackDecoration,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Transform.translate(
                      offset: Offset(currentOffset, 0),
                      child: Container(
                        width: currentThumbWidth,
                        height: currentThumbHeight,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(thumbBaseSize / 2),
                          gradient: LinearGradient(
                            colors: t > 0.5
                                ? [
                                    widget.activeThumbColor ?? Colors.white,
                                    const Color(0xFFF1F5F9),
                                  ]
                                : [
                                    widget.thumbColor ?? (isEnabled ? Colors.white : Colors.white70),
                                    const Color(0xFFE2E8F0),
                                  ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.28),
                              blurRadius: 4,
                              offset: const Offset(0, 1.5),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 1,
                              offset: const Offset(0, 0.5),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: t > 0.5
                            ? (widget.activeThumbIcon ??
                                Container(
                                  width: 3.5,
                                  height: 3.5,
                                  decoration: BoxDecoration(
                                    color: primary,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: primary.withValues(alpha: 0.8),
                                        blurRadius: 3,
                                      ),
                                    ],
                                  ),
                                ))
                            : (widget.inactiveThumbIcon ??
                                Container(
                                  width: 3.5,
                                  height: 3.5,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    shape: BoxShape.circle,
                                  ),
                                )),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      switchContent = Tooltip(
        message: widget.tooltip!,
        child: switchContent,
      );
    }

    return Semantics(
      toggled: widget.value,
      enabled: isEnabled,
      label: widget.semanticLabel ?? widget.tooltip ?? 'Cyber Switch',
      child: switchContent,
    );
  }
}
