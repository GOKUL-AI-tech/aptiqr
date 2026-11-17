import 'user_role.dart';

/// Mirrors `public.profiles`, the shared identity row for every signed-in
/// user regardless of role.
class AppProfile {
  final String id;
  final UserRole role;
  final String fullName;
  final String? email;
  final String? phone;
  final String? photoUrl;
  final bool isActive;

  const AppProfile({
    required this.id,
    required this.role,
    required this.fullName,
    this.email,
    this.phone,
    this.photoUrl,
    this.isActive = true,
  });

  factory AppProfile.fromJson(Map<String, dynamic> json) {
    return AppProfile(
      id: json['id'] as String,
      role: UserRoleX.fromString(json['role'] as String),
      fullName: json['full_name'] as String? ?? '',
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      photoUrl: json['photo_url'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}
