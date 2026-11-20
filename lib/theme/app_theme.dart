import 'package:material_ui/material_ui.dart';

/// Single source of truth for fonts. Widgets must never hard-code a font name.
///
/// To switch font: change [display] (and register the .ttf in pubspec.yaml if
/// it isn't a system font), then do a full restart.
class AppFonts {
  AppFonts._();

  /// Buttons, counters, timer, headings. System font on macOS/Windows.
  static const String display = 'Impact';

  /// Used when [display] is missing on the device (e.g. iPad has no Impact).
  static const List<String> fallback = ['DynaPuff'];
}

/// Colours ported from py-photobooth `ui/styles.py` and `components/*.py`.
class AppColors {
  AppColors._();

  /// Deep Christmas red — primary background for buttons/badges.
  static const Color red = Color(0xFF81151B);
  static const Color redHover = Color(0xFFB82424);
  static const Color redPressed = Color(0xFFA01E1E);

  /// DecorativeButton uses slightly different hover/pressed shades.
  static const Color decorativeHover = Color(0xFFA01E1E); // rgb(160,30,30)
  static const Color decorativePressed = Color(0xFF640F14); // rgb(100,15,20)

  /// Gold accent — text, borders, selection outlines.
  static const Color gold = Color(0xFFC9A961);

  static const Color background = Color(0xFFFFFFFF);
  static const Color disabledFill = Color(0xFFF5F5F5);
  static const Color flash = Color(0xFFFFFFFF);
}

/// Text styles. Sizes are in design-canvas pixels (1920×1080, see step 2).
class AppText {
  AppText._();

  static const TextStyle _display = TextStyle(
    fontFamily: AppFonts.display,
    fontFamilyFallback: AppFonts.fallback,
    fontWeight: FontWeight.bold,
    color: AppColors.gold,
    // Explicit, so text never gets Flutter's yellow "no Material" underline.
    decoration: TextDecoration.none,
  );

  /// START button (DecorativeButton) — Impact 60 bold.
  static final TextStyle decorativeButton = _display.copyWith(fontSize: 60);

  /// Regular themed buttons (Back / Next / Print / Start over).
  static final TextStyle button = _display.copyWith(fontSize: 32);

  /// "Photos: N / 4" counter and countdown timer — Impact 64 bold.
  static final TextStyle counter = _display.copyWith(fontSize: 64);

  /// "Preview" heading on the selection screen.
  static final TextStyle heading = _display.copyWith(fontSize: 24);

  /// Stepper caption, e.g. "Number of prints" (Qt 18pt ≈ 24px).
  static final TextStyle label = _display.copyWith(fontSize: 24);

  /// Stepper value box.
  static final TextStyle stepperValue = _display.copyWith(fontSize: 36);

  /// Stepper −/+ glyphs.
  static final TextStyle stepperButton = _display.copyWith(
    fontSize: 32,
    color: Colors.white,
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: AppFonts.display,
    fontFamilyFallback: AppFonts.fallback,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.red,
      primary: AppColors.red,
      secondary: AppColors.gold,
      surface: AppColors.background,
    ),
  );
}
