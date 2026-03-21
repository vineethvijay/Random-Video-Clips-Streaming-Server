import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Production-grade dark theme — violet/indigo seed, Plus Jakarta Sans, M3.
/// Glassmorphism-ready surfaces with rich accent palette.
class AppTheme {
  AppTheme._();

  // ── Brand palette ──
  static const Color _seed = Color(0xFF8B5CF6);
  static const Color accentCyan = Color(0xFF22D3EE);
  static const Color accentEmerald = Color(0xFF34D399);
  static const Color accentAmber = Color(0xFFFBBF24);
  static const Color accentRose = Color(0xFFFB7185);
  static const Color nowPlayingBlue = Color(0xFF60A5FA);

  // ── Surface tones ──
  static const Color _bg = Color(0xFF060912);
  static const Color _surfaceLowest = Color(0xFF070A12);
  static const Color _surfaceLow = Color(0xFF0D111C);
  static const Color _surface = Color(0xFF131A28);
  static const Color _surfaceHigh = Color(0xFF1A2234);
  static const Color _surfaceHighest = Color(0xFF222C42);

  static ThemeData dark() {
    final base = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    );

    final colorScheme = base.copyWith(
      surfaceContainerLowest: _surfaceLowest,
      surfaceContainerLow: _surfaceLow,
      surfaceContainer: _surface,
      surfaceContainerHigh: _surfaceHigh,
      surfaceContainerHighest: _surfaceHighest,
    );

    final textTheme = GoogleFonts.plusJakartaSansTextTheme(
      ThemeData(brightness: Brightness.dark).textTheme,
    ).apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _bg,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,

      // ── Cards ──
      cardTheme: CardThemeData(
        color: _surfaceHigh,
        elevation: 0,
        shadowColor: colorScheme.primary.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.25),
          ),
        ),
      ),

      // ── Buttons ──
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 1,
          shadowColor: colorScheme.primary.withValues(alpha: 0.35),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side:
              BorderSide(color: colorScheme.outline.withValues(alpha: 0.6)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),

      // ── Inputs ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceHighest.withValues(alpha: 0.85),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.35),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        floatingLabelStyle: TextStyle(color: colorScheme.primary),
      ),

      // ── Chips ──
      chipTheme: ChipThemeData(
        backgroundColor: _surfaceHighest,
        selectedColor: colorScheme.primaryContainer,
        disabledColor: _surface,
        labelStyle: textTheme.labelLarge,
        secondaryLabelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side:
            BorderSide(color: colorScheme.outline.withValues(alpha: 0.35)),
      ),

      // ── Dividers ──
      dividerTheme: DividerThemeData(
        color: colorScheme.outline.withValues(alpha: 0.2),
        thickness: 1,
      ),

      // ── Bottom Navigation ──
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: _surfaceLow,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle:
            textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: textTheme.labelSmall,
      ),

      // ── ListTile ──
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.onSurfaceVariant,
        titleTextStyle: textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.15,
          color: colorScheme.onSurface,
          height: 1.2,
        ),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w400,
          height: 1.35,
        ),
      ),

      // ── Progress indicators ──
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        circularTrackColor: _surfaceHighest,
      ),

      // ── Snackbar ──
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
      ),

      // ── Dropdown menu ──
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _surfaceHighest,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: colorScheme.outline.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
    );
  }
}
