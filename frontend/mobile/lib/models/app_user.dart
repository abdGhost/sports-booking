import 'package:flutter/foundation.dart';

@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  final int id;
  final String name;
  final String email;

  /// `"organizer"` or `"player"` (matches FastAPI).
  final String role;

  bool get isOrganizer => role == 'organizer';

  factory AppUser.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is int ? v : (v as num).toInt();

    return AppUser(
      id: asInt(json['id']),
      name: json['name'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
    );
  }
}
