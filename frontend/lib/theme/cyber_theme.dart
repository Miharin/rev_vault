import 'package:flutter/material.dart';

enum AccentColorPreset {
  emerald(
    label: 'Emerald Core',
    color: Color(0xFF10B981),
    glowColor: Color(0x6610B981),
    icon: Icons.shield,
  ),
  cyan(
    label: 'Cyber Cyan',
    color: Color(0xFF06B6D4),
    glowColor: Color(0x6606B6D4),
    icon: Icons.bolt,
  ),
  amber(
    label: 'Neon Amber',
    color: Color(0xFFF59E0B),
    glowColor: Color(0x66F59E0B),
    icon: Icons.local_fire_department,
  ),
  purple(
    label: 'Plasma Purple',
    color: Color(0xFF8B5CF6),
    glowColor: Color(0x668B5CF6),
    icon: Icons.auto_awesome,
  );

  final String label;
  final Color color;
  final Color glowColor;
  final IconData icon;

  const AccentColorPreset({
    required this.label,
    required this.color,
    required this.glowColor,
    required this.icon,
  });
}

enum ThemePreference {
  circadian(label: 'Auto (Circadian)', icon: Icons.schedule),
  dark(label: 'Obsidian Dark', icon: Icons.dark_mode),
  light(label: 'Tech Daylight', icon: Icons.light_mode);

  final String label;
  final IconData icon;

  const ThemePreference({
    required this.label,
    required this.icon,
  });
}

class CyberTheme {
  // Obsidian Dark Palette
  static const Color darkBackground = Color(0xFF070B14);
  static const Color darkSurface = Color(0xFF0D1527);
  static const Color darkSurfaceElevated = Color(0xFF131F38);
  static const Color darkSurfaceBorder = Color(0xFF1E293B);
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextMuted = Color(0xFF94A3B8);

  // Tech Light Palette
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFF1F5F9);
  static const Color lightSurfaceBorder = Color(0xFFE2E8F0);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextMuted = Color(0xFF64748B);

  static ThemeData buildTheme({
    required bool isDark,
    required AccentColorPreset accent,
  }) {
    final primary = accent.color;
    final bg = isDark ? darkBackground : lightBackground;
    final surface = isDark ? darkSurface : lightSurface;
    final border = isDark ? darkSurfaceBorder : lightSurfaceBorder;
    final textPrimary = isDark ? darkTextPrimary : lightTextPrimary;
    final textMuted = isDark ? darkTextMuted : lightTextMuted;

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: isDark
          ? ColorScheme.dark(
              primary: primary,
              secondary: primary.withValues(alpha: 0.8),
              surface: surface,
              surfaceContainerHighest: darkSurfaceElevated,
              onSurface: textPrimary,
              outline: border,
            )
          : ColorScheme.light(
              primary: primary,
              secondary: primary.withValues(alpha: 0.8),
              surface: surface,
              surfaceContainerHighest: lightSurfaceElevated,
              onSurface: textPrimary,
              outline: border,
            ),
      dividerColor: border,
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: border),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      textTheme: TextTheme(
        bodyMedium: TextStyle(color: textPrimary, fontSize: 13),
        bodySmall: TextStyle(color: textMuted, fontSize: 11),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? darkSurfaceElevated : darkBackground,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: primary.withValues(alpha: 0.4)),
        ),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontFamily: 'monospace',
        ),
        waitDuration: const Duration(milliseconds: 300),
      ),
    );
  }
}
