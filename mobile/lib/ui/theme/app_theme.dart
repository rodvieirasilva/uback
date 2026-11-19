import 'package:material_ui/material_ui.dart';

/// Material 3 Light and Dark themes for UBack, automatically following system appearance.
abstract final class AppTheme {
  static const Color _seed = Color(0xFF2563EB);

  static ThemeData light() {
    final cs = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: cs,
      scaffoldBackgroundColor: const Color(0xFFF6F8FA),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF6F8FA),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  static ThemeData dark() {
    final cs = ColorScheme.fromSeed(
      seedColor: const Color(0xFF4F8CFF),
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: cs,
      scaffoldBackgroundColor: const Color(0xFF0E1117),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0E1117),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF161B22),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF161B22),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  static Color successColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.greenAccent
          : const Color(0xFF15803D);

  static Color warningColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.orangeAccent
          : const Color(0xFFC2410C);

  static Color infoColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.lightBlueAccent
          : const Color(0xFF0369A1);

  static Color dangerColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.redAccent
          : const Color(0xFFB91C1C);
}
