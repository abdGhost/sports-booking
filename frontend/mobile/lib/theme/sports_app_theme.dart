import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette aligned with the reference UI: deep navy, bright cyan, white cards,
/// light gray page background, red for live states.
abstract final class SportsAppColors {
  static const Color navy = Color(0xFF0F2744);
  static const Color navyDark = Color(0xFF0A1628);
  static const Color cyan = Color(0xFF0EA5E9);
  static const Color cyanLight = Color(0xFF38BDF8);
  static const Color pageBackground = Color(0xFFF1F5F9);
  static const Color card = Color(0xFFFFFFFF);
  /// Slightly off-white tiles (lists, panels).
  static const Color surfaceElevated = Color(0xFFF8FAFC);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);
  static const Color border = Color(0xFFE2E8F0);
  static const Color liveRed = Color(0xFFEF4444);
  /// Secondary highlight (full slots, warm CTAs).
  static const Color accentWarm = Color(0xFFFF7A45);
  /// Shared dark blues (blue-800 / blue-900) for text, search, hero — not slate/black.
  static const Color accentBlue800 = Color(0xFF1E40AF);
  static const Color accentBlue900 = Color(0xFF1E3A8A);
  // Backward-compatible aliases used by some older screens.
  static const Color background = pageBackground;
  static const Color accent = cyan;
}

class SportsAppTheme {
  SportsAppTheme._();

  static ThemeData build() {
    final baseLight = ThemeData(brightness: Brightness.light, useMaterial3: true);
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(
      baseLight.textTheme,
    ).apply(
      bodyColor: SportsAppColors.textPrimary,
      displayColor: SportsAppColors.textPrimary,
    );

    final colorScheme = ColorScheme.light(
      primary: SportsAppColors.cyan,
      onPrimary: Colors.white,
      secondary: SportsAppColors.navy,
      onSecondary: Colors.white,
      surface: SportsAppColors.card,
      onSurface: SportsAppColors.textPrimary,
      onSurfaceVariant: SportsAppColors.textMuted,
      outline: SportsAppColors.border,
      error: SportsAppColors.liveRed,
      surfaceContainerHighest: const Color(0xFFF8FAFC),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: SportsAppColors.pageBackground,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: SportsAppColors.card,
        foregroundColor: SportsAppColors.navy,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          fontSize: 17,
          color: SportsAppColors.navy,
          letterSpacing: 0.8,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 3,
        shadowColor: SportsAppColors.navy.withValues(alpha: 0.12),
        color: SportsAppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: SportsAppColors.border.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: SportsAppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: SportsAppColors.navy,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SportsAppColors.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: SportsAppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: SportsAppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: SportsAppColors.cyan, width: 2),
        ),
        labelStyle: const TextStyle(color: SportsAppColors.textMuted),
        hintStyle: TextStyle(color: SportsAppColors.textMuted.withValues(alpha: 0.85)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: SportsAppColors.cyan,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 0,
          textStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.comfortable,
          side: const WidgetStatePropertyAll(
            BorderSide(color: SportsAppColors.border),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: SportsAppColors.cyan,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: SportsAppColors.cyan,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: SportsAppColors.card,
        selectedItemColor: SportsAppColors.cyan,
        unselectedItemColor: SportsAppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 12,
      ),
    );
  }
}

/// Soft page background (reference: light gray behind white cards).
class SportsBackground extends StatelessWidget {
  const SportsBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFE8F4FC),
            SportsAppColors.pageBackground,
            Color(0xFFF8FAFC),
          ],
        ),
      ),
      child: child,
    );
  }
}

/// Full-bleed raster photo from [imageAsset] with a dark transparent wash over the
/// image so content stays readable on white cards. Default: `feature_tennis.jpg`.
class SportsAuthBackground extends StatelessWidget {
  const SportsAuthBackground({
    super.key,
    required this.child,
    this.imageAsset = 'assets/images/feature_tennis.jpg',
  });

  final Widget child;

  /// Bundle under `assets/images/` (see `pubspec.yaml`).
  final String imageAsset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Image.asset(
            imageAsset,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => ColoredBox(
              color: SportsAppColors.navyDark.withValues(alpha: 0.92),
              child: const Center(
                child: Icon(Icons.sports_soccer_rounded, size: 64, color: SportsAppColors.cyan),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.45),
                  SportsAppColors.navyDark.withValues(alpha: 0.55),
                  SportsAppColors.navyDark.withValues(alpha: 0.68),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// White card shadow used for elevated surfaces (matches reference depth).
BoxDecoration sportsCardDecoration({Color? color}) {
  return BoxDecoration(
    color: color ?? SportsAppColors.card,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: SportsAppColors.border.withValues(alpha: 0.8)),
    boxShadow: [
      BoxShadow(
        color: SportsAppColors.navy.withValues(alpha: 0.08),
        blurRadius: 24,
        offset: const Offset(0, 10),
      ),
    ],
  );
}

WidgetStateProperty<Color?> sportsAppInkNoHoverOverlay() =>
    WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered)) {
        return Colors.transparent;
      }
      return null;
    });
