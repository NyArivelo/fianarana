import 'package:flutter/material.dart';

/// Thème inspiré de la maquette design.html (EduDesk Pro)
/// Palette: brand blue (#2563eb), slate backgrounds/borders, Inter-like UI.
class AppTheme {
  static const _brand = Color(0xFF2563EB); // blue-600
  static const _brandDark = Color(0xFF1D4ED8); // blue-700
  static const _slate50 = Color(0xFFF8FAFC);
  static const _slate100 = Color(0xFFF1F5F9);
  static const _slate200 = Color(0xFFE2E8F0);
  static const _slate700 = Color(0xFF334155);
  static const _slate800 = Color(0xFF1E293B);
  static const _slate900 = Color(0xFF0F172A);
  static const _slate950 = Color(0xFF020617);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _brand,
      primary: _brand,
      secondary: _brandDark,
      surface: Colors.white,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _slate100,
      visualDensity: VisualDensity.compact,
      fontFamily: null, // Inter si disponible dans assets, sinon défaut système
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: _slate900,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _slate900),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _slate200),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.white,
        selectedIconTheme: const IconThemeData(color: _brand),
        selectedLabelTextStyle: const TextStyle(color: _brand, fontWeight: FontWeight.w600, fontSize: 12),
        unselectedIconTheme: const IconThemeData(color: _slate700),
        unselectedLabelTextStyle: const TextStyle(color: _slate700, fontSize: 12),
        indicatorColor: const Color(0xFFDBEAFE), // blue-100
      ),
      dividerTheme: const DividerThemeData(color: _slate200, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: _slate50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _slate200)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _slate200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _brand, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _brand,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _slate700,
          side: const BorderSide(color: _slate200),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(_slate50),
        headingTextStyle: const TextStyle(fontWeight: FontWeight.w600, color: _slate700, fontSize: 12),
        dataTextStyle: const TextStyle(color: _slate900, fontSize: 13),
        dividerThickness: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _slate100,
        side: const BorderSide(color: _slate200),
        labelStyle: const TextStyle(fontSize: 12, color: _slate700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _brand,
      primary: const Color(0xFF60A5FA), // blue-400 for contrast
      secondary: _brand,
      surface: _slate900,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _slate950,
      visualDensity: VisualDensity.compact,
      appBarTheme: const AppBarTheme(
        backgroundColor: _slate900,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: _slate900,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _slate800),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: _slate900,
        selectedIconTheme: IconThemeData(color: Color(0xFF93C5FD)),
        selectedLabelTextStyle: TextStyle(color: Color(0xFF93C5FD), fontWeight: FontWeight.w600, fontSize: 12),
        unselectedIconTheme: IconThemeData(color: Color(0xFF94A3B8)),
        unselectedLabelTextStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
        indicatorColor: Color(0xFF172554),
      ),
      dividerTheme: const DividerThemeData(color: _slate800, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: const Color(0xFF0B1220),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _slate800)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _slate800)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF60A5FA), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _brand,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFCBD5E1),
          side: const BorderSide(color: _slate800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(const Color(0xFF0B1220)),
        headingTextStyle: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1), fontSize: 12),
        dataTextStyle: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13),
        dividerThickness: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _slate800,
        side: const BorderSide(color: _slate700),
        labelStyle: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}
