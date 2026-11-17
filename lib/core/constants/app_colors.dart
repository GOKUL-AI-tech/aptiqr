import 'package:flutter/material.dart';

/// Brand palette lifted from the college's signature orange
/// (see the product design deck — splash + title slides), refined into a
/// fuller neutral/shadow scale for a cleaner, "modern SaaS" look: soft
/// off-white surfaces, one strong accent per role, and a dedicated
/// shadow tone (derived from the text color rather than flat black, which
/// reads as softer/more premium than a default black drop shadow).
class AppColors {
  AppColors._();

  static const Color primaryOrange = Color(0xFFE8622C);
  static const Color primaryOrangeDark = Color(0xFFC44D1E);
  static const Color primaryOrangeLight = Color(0xFFFBEAE2);

  static const Color faculty = Color(0xFF2F6FED); // blue accent (faculty slides)
  static const Color facultyDark = Color(0xFF1F4FC4);
  static const Color facultyLight = Color(0xFFE9F0FE);

  static const Color admin = Color(0xFF3C8C4A); // green accent (admin slides)
  static const Color adminDark = Color(0xFF276B39);
  static const Color adminLight = Color(0xFFEAF6EC);

  static const Color student = primaryOrange;
  static const Color studentDark = primaryOrangeDark;
  static const Color studentLight = primaryOrangeLight;

  // Soft cool-neutral scale — a hint of blue/grey rather than flat white/
  // grey, which is what makes stacked white cards read as "premium" rather
  // than just "no color".
  static const Color background = Color(0xFFF5F6FA);
  static const Color surface = Colors.white;
  static const Color surfaceAlt = Color(0xFFEEF0F6); // input fills, secondary chips/tiles
  static const Color textPrimary = Color(0xFF161821);
  static const Color textSecondary = Color(0xFF666D80);
  static const Color border = Color(0xFFE7E9F1);

  /// Soft, tinted shadow used everywhere instead of flat black — reads as
  /// a gentle lift rather than a harsh drop shadow.
  static const Color shadow = Color(0x1F161821);

  static const Color success = Color(0xFF2E9E5B);
  static const Color successLight = Color(0xFFE3F6EA);
  static const Color warning = Color(0xFFE0A526);
  static const Color warningLight = Color(0xFFFBF1DD);
  static const Color error = Color(0xFFD64545);
  static const Color errorLight = Color(0xFFFCE9E9);
  static const Color absent = Color(0xFF9E9E9E);

  /// Role-scoped accent — used across faculty/admin screens so each
  /// role keeps a distinct identity, matching the deck's color-coding.
  static Color forRole(String role) {
    switch (role) {
      case 'faculty':
        return faculty;
      case 'admin':
        return admin;
      default:
        return student;
    }
  }

  static Color lightForRole(String role) {
    switch (role) {
      case 'faculty':
        return facultyLight;
      case 'admin':
        return adminLight;
      default:
        return studentLight;
    }
  }

  /// Deeper shade of the role accent — the second stop for gradients
  /// (AppLogo, LoadingButton) and pressed/emphasis states.
  static Color darkForRole(String role) {
    switch (role) {
      case 'faculty':
        return facultyDark;
      case 'admin':
        return adminDark;
      default:
        return studentDark;
    }
  }

  /// Diagonal two-stop gradient for a role — used sparingly on hero-ish
  /// elements (logo mark, primary CTA) to add depth without touching
  /// every screen's layout.
  static List<Color> gradientForRole(String role) => [forRole(role), darkForRole(role)];
}
