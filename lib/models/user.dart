/// User model representing application users.
class User {
  final int id;
  final String email;
  final String? username;
  final String? fullName;
  final UserRole role;
  final bool isActive;
  final DateTime createdAt;

  User({
    required this.id,
    required this.email,
     this.username,
    this.fullName,
    required this.role,
    required this.isActive,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      email: json['email'] as String,
      username: json['email'] as String?,
      fullName: json['name'] as String?,
      role: UserRole.fromString(json['role'] as String),
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'full_name': fullName,
      'role': role.value,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isInstructor => role == UserRole.instructor || role == UserRole.admin;
  bool get isStudent => role == UserRole.student;
}

enum UserRole {
  student('student'),
  instructor('teacher'),
  admin('admin');

  final String value;
  const UserRole(this.value);

  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (role) => role.value == value,
      orElse: () => UserRole.student,
    );
  }
}
