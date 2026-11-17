import 'test_category.dart';

/// Extends `profiles` for a role='admin' user. Mirrors FacultyProfile/
/// StudentProfile's shape (a role-specific extension row joined with the
/// shared `profiles` row for name/email).
///
/// [category] is fixed at account-creation time (see README "Creating
/// the Technical / Communication admin logins") and scopes every
/// question-bank row and daily test/QR this admin can see or create —
/// see current_admin_category() in supabase/policies.sql.
class AdminProfile {
  final String id;
  final TestCategory category;
  final String fullName;
  final String? email;
  final bool isActive;

  const AdminProfile({
    required this.id,
    required this.category,
    required this.fullName,
    this.email,
    this.isActive = true,
  });

  factory AdminProfile.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return AdminProfile(
      id: json['id'] as String,
      category: TestCategoryX.fromString(json['category'] as String? ?? 'aptitude'),
      fullName: profile?['full_name'] as String? ?? json['full_name'] as String? ?? '',
      email: profile?['email'] as String? ?? json['email'] as String?,
      isActive: profile?['is_active'] as bool? ?? true,
    );
  }
}
