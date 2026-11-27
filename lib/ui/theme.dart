import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Mutiny's palette: deep night purple with lavender light.
/// Mutiny's palette: Spotify's black-and-green idea, in black and purple.
abstract final class MColors {
  static const bg = Color(0xFF000000);
  static const bgRaised = Color(0xFF121014);
  static const deep = Color(0xFF2B1155); // dark purple
  static const violet = Color(0xFF8A3FFC);
  static const purple = Color(0xFFA259FF); // the accent, like Spotify green
  static const lavender = Color(0xFFB98AFF);
  static const lilac = Color(0xFFF2EAFF);

  /// Supporting purples (kept as names used across the app).
  static const fuchsia = Color(0xFFA259FF);
  static const pink = Color(0xFF7B2CBF);
  static const sky = Color(0xFF5A189A);

  static const text = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB3B3B3);
  static const textTertiary = Color(0xFF808080);

  static const glassFill = Color(0x14FFFFFF);
  static const glassBorder = Color(0x33FFFFFF);
  static const hairline = Color(0x1AFFFFFF);

  /// Primary buttons (Play, Save…): solid bright purple with black text.
  static const brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFB57BFF), Color(0xFFA259FF), Color(0xFF9145FF)],
  );

  /// Accent words in headings.
  static const brandVivid = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFC79CFF), Color(0xFFA259FF)],
  );

  /// Text/icons drawn on top of the purple accent.
  static const onAccent = Color(0xFF000000);
}

abstract final class MText {
  static const display = 'Unbounded';

  static const hero = TextStyle(
    fontFamily: display,
    fontSize: 44,
    height: 0.98,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.2,
    color: Colors.white,
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
      primary: MColors.purple,
      onPrimary: MColors.onAccent,
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
      cursorColor: MColors.purple,
      selectionColor: Color(0x55A259FF),
      selectionHandleColor: MColors.purple,
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 3,
      activeTrackColor: MColors.purple,
      inactiveTrackColor: Color(0x33FFFFFF),
      thumbColor: Colors.white,
      overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5.5),
      trackShape: RoundedRectSliderTrackShape(),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Color(0xF0282828),
      contentTextStyle: TextStyle(color: MColors.text, fontWeight: FontWeight.w500),
      shape: StadiumBorder(side: BorderSide(color: MColors.glassBorder)),
      elevation: 0,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: MColors.purple),
  );
}

const lightStatusBar = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
);
