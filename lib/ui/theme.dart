import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Mutiny's palette: deep night purple with lavender light.
abstract final class MColors {
  static const bg = Color(0xFF110824);
  static const bgRaised = Color(0xFF1D1036);
  static const deep = Color(0xFF3B1A78);
  static const violet = Color(0xFF8B5CF6);
  static const purple = Color(0xFFB794FF);
  static const lavender = Color(0xFFD2C2FF);
  static const lilac = Color(0xFFF4ECFF);

  /// Bright accents that make the purple pop.
  static const fuchsia = Color(0xFFF07CFF);
  static const pink = Color(0xFFFF7EB6);
  static const sky = Color(0xFF7DD8FF);

  static const text = Color(0xFFFFFBFF);
  static const textSecondary = Color(0xD1F0E8FF); // ~82%
  static const textTertiary = Color(0x99E6DCFF); // ~60%

  static const glassFill = Color(0x14FFFFFF);
  static const glassBorder = Color(0x40FFFFFF);
  static const hairline = Color(0x1FFFFFFF);

  /// Signature gradient for primary buttons and highlights.
  static const brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFBE7FF), Color(0xFFE3B8FF), Color(0xFFB794FF)],
  );

  static const brandVivid = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFB794FF), Color(0xFFF07CFF), Color(0xFFFF9CC8)],
  );
}

abstract final class MText {
  static const display = 'Unbounded';

  static const hero = TextStyle(
    fontFamily: display,
    fontSize: 44,
    height: 0.98,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.2,
    color: MColors.lilac,
  );

  static const h1 = TextStyle(
    fontFamily: display,
    fontSize: 26,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.6,
    color: MColors.text,
  );

  static const h2 = TextStyle(
    fontFamily: display,
    fontSize: 19,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: MColors.text,
  );

  static const title = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: MColors.text,
  );

  static const body = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    color: MColors.textSecondary,
  );

  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: MColors.textTertiary,
  );

  static const label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.4,
    color: MColors.textTertiary,
  );
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: MColors.lavender,
      onPrimary: MColors.bg,
      secondary: MColors.purple,
      surface: MColors.bgRaised,
      onSurface: MColors.text,
    ),
    scaffoldBackgroundColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: const Color(0x0FFFFFFF),
  );
  return base.copyWith(
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: MColors.lavender,
      selectionColor: Color(0x55A78BFA),
      selectionHandleColor: MColors.lavender,
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 3,
      activeTrackColor: MColors.lilac,
      inactiveTrackColor: Color(0x33FFFFFF),
      thumbColor: MColors.lilac,
      overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5.5),
      trackShape: RoundedRectSliderTrackShape(),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Color(0xF0241640),
      contentTextStyle: TextStyle(color: MColors.text, fontWeight: FontWeight.w500),
      shape: StadiumBorder(side: BorderSide(color: MColors.glassBorder)),
      elevation: 0,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: MColors.lavender),
  );
}

const lightStatusBar = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
);
