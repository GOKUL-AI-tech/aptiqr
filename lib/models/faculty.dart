class FacultyProfile {
  final String id;
  final String facultyId;
  final String? departmentId;
  final List<int> assignedYears;
  final String fullName;
  final String? email;
  final bool isActive;

  const FacultyProfile({
    required this.id,
    required this.facultyId,
    required this.fullName,
    this.departmentId,
    this.assignedYears = const [1, 2, 3, 4],
    this.email,
    this.isActive = true,
  });

  factory FacultyProfile.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return FacultyProfile(
      id: json['id'] as String,
      facultyId: json['faculty_id'] as String,
      departmentId: json['department_id'] as String?,
      assignedYears: (json['assigned_years'] as List<dynamic>? ?? [1, 2, 3, 4])
          .map((e) => e as int)
          .toList(),
      fullName: profile?['full_name'] as String? ?? json['full_name'] as String? ?? '',
      email: profile?['email'] as String? ?? json['email'] as String?,
      isActive: profile?['is_active'] as bool? ?? true,
    );
  }
}
