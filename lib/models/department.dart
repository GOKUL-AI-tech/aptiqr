class Department {
  final String id;
  final String code;
  final String name;
  final List<int> yearsOffered;
  final bool isActive;

  const Department({
    required this.id,
    required this.code,
    required this.name,
    required this.yearsOffered,
    required this.isActive,
  });

  factory Department.fromJson(Map<String, dynamic> json) {
    return Department(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      yearsOffered: (json['years_offered'] as List<dynamic>? ?? [1, 2, 3, 4])
          .map((e) => e as int)
          .toList(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}
