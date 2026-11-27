import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Mutiny's palette: deep night purple with lavender light.
abstract final class MColors {
  static const bg = Color(0xFF0A0612);
  static const bgRaised = Color(0xFF140B24);
  static const deep = Color(0xFF2A1250);
  static const violet = Color(0xFF7C3AED);
  static const purple = Color(0xFFA78BFA);
  static const lavender = Color(0xFFC4B5FD);
  static const lilac = Color(0xFFE9DDFF);

  static const text = Color(0xFFF5F0FF);
  static const textSecondary = Color(0xB3E4D9FF); // ~70%
  static const textTertiary = Color(0x73D8CCF5); // ~45%

  static const glassFill = Color(0x14FFFFFF);
  static const glassBorder = Color(0x26FFFFFF);
  static const hairline = Color(0x14FFFFFF);
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
