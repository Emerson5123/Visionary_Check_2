import 'package:flutter/material.dart';

/// Paleta de colores inspirada en BilletesMx (Banco de México)
/// Fondo blanco/gris claro, primario teal, acentos verdes
class AppTheme {
  // ── Colores principales ──────────────────────────────────────────────────
  static const Color primary       = Color(0xFF009B8D); // Teal principal BilletesMx
  static const Color primaryDark   = Color(0xFF007A6E); // Teal oscuro (AppBar, botones)
  static const Color primaryLight  = Color(0xFF4DCBBF); // Teal claro (fondos suaves)
  static const Color accent        = Color(0xFF00C9B1); // Teal brillante (highlights)

  // ── Fondos ───────────────────────────────────────────────────────────────
  static const Color background    = Color(0xFFF4F6F5); // Gris muy claro (fondo general)
  static const Color surface       = Color(0xFFFFFFFF); // Blanco (tarjetas)
  static const Color surfaceAlt    = Color(0xFFE8F5F3); // Teal muy suave (secciones alt)

  // ── Textos ───────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF1A2E2C); // Negro verdoso (texto principal)
  static const Color textSecondary = Color(0xFF5A7A76); // Gris verdoso (texto secundario)
  static const Color textOnPrimary = Color(0xFFFFFFFF); // Blanco sobre teal

  // ── Estados ──────────────────────────────────────────────────────────────
  static const Color success       = Color(0xFF2E9E72); // Verde éxito (auténtico)
  static const Color successLight  = Color(0xFFDFF5EC); // Fondo verde claro
  static const Color error         = Color(0xFFD64045); // Rojo error (sospechoso)
  static const Color errorLight    = Color(0xFFFDE8E8); // Fondo rojo claro
  static const Color warning       = Color(0xFFF59E0B); // Ámbar foco VoiceOver
  static const Color divider       = Color(0xFFD0E8E5); // Divisor teal suave

  // ── Gradientes ───────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF009B8D), Color(0xFF007A6E)],
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF4F6F5), Color(0xFFE8F5F3)],
  );

  static const LinearGradient successGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1E7A58), Color(0xFF2E9E72)],
  );

  static const LinearGradient errorGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFB02A2E), Color(0xFFD64045)],
  );

  // ── ThemeData completo ───────────────────────────────────────────────────
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.light(
      primary:       primary,
      secondary:     accent,
      surface:       surface,
      background:    background,
      error:         error,
      onPrimary:     textOnPrimary,
      onSecondary:   textOnPrimary,
      onSurface:     textPrimary,
      onBackground:  textPrimary,
      onError:       textOnPrimary,
    ),
    scaffoldBackgroundColor: background,
    appBarTheme: const AppBarTheme(
      backgroundColor: primary,
      foregroundColor: textOnPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: textOnPrimary,
        fontSize: 20,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.3,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: textOnPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 2,
      shadowColor: primary.withOpacity(0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    dividerTheme: const DividerThemeData(color: divider, thickness: 1),
  );
}