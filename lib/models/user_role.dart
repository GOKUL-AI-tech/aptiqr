enum UserRole { student, faculty, admin }

extension UserRoleX on UserRole {
  String get value => name;

  String get label => switch (this) {
        UserRole.student => 'Student',
        UserRole.faculty => 'Faculty',
        UserRole.admin => 'Admin',
      };

  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => UserRole.student,
    );
  }
}
