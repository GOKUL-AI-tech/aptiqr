class StudentProfile {
  final String id; // == profiles.id == auth uid
  final String registerNumber;
  final String departmentId;
  final int year;
  final String? section;
  final String fullName;
  final String? email;
  final bool isActive;

  const StudentProfile({
    required this.id,
    required this.registerNumber,
    required this.departmentId,
    required this.year,
    required this.fullName,
    this.section,
    this.email,
    this.isActive = true,
  });

  factory StudentProfile.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return StudentProfile(
      id: json['id'] as String,
      registerNumber: json['register_number'] as String,
      departmentId: json['department_id'] as String,
      year: json['year'] as int,
      section: json['section'] as String?,
      fullName: profile?['full_name'] as String? ?? json['full_name'] as String? ?? '',
      email: profile?['email'] as String? ?? json['email'] as String?,
      isActive: profile?['is_active'] as bool? ?? true,
    );
  }
}
