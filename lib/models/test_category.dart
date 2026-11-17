import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';

/// The 3 parallel tracks a day's daily tests/QRs and the question bank
/// are partitioned into. Mirrors `public.test_category` (see
/// supabase/schema.sql). Distinct from `Question.subject`/`.topic`,
/// which stay free-text sub-topics *within* one of these categories
/// (e.g. category = technical, subject = "C Programming").
///
/// Each admin login is permanently scoped to exactly one of these (see
/// AdminProfile.category) — there is no in-app way to change it.
enum TestCategory { aptitude, technical, communication }

extension TestCategoryX on TestCategory {
  String get value => name;

  String get label => switch (this) {
        TestCategory.aptitude => 'Aptitude',
        TestCategory.technical => 'Technical',
        TestCategory.communication => 'Communication',
      };

  /// Short, all-caps form used on badges/headers (e.g. "TODAY'S APTITUDE QR").
  String get shortLabel => label.toUpperCase();

  IconData get icon => switch (this) {
        TestCategory.aptitude => Icons.calculate_rounded,
        TestCategory.technical => Icons.code_rounded,
        TestCategory.communication => Icons.forum_rounded,
      };

  /// A distinct accent per category so the 3 QR cards / question-bank
  /// headers are visually distinguishable at a glance, layered on top of
  /// the existing per-role accent (green admin / blue faculty / orange
  /// student) rather than replacing it.
  Color get accent => switch (this) {
        TestCategory.aptitude => AppColors.primaryOrange,
        TestCategory.technical => AppColors.faculty,
        TestCategory.communication => AppColors.admin,
      };

  static TestCategory fromString(String value) {
    return TestCategory.values.firstWhere(
      (c) => c.name == value,
      orElse: () => TestCategory.aptitude,
    );
  }
}
