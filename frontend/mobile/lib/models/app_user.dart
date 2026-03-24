import 'package:flutter/foundation.dart';

@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.lastLat,
    this.lastLong,
  });

  final int id;
  final String name;
  final String email;

  /// `"organizer"` or `"player"` (matches FastAPI).
  final String role;

  /// Last location synced to the server (`PATCH /auth/me/location`), if any.
  final double? lastLat;
  final double? lastLong;

  bool get isOrganizer => role == 'organizer';

  factory AppUser.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is int ? v : (v as num).toInt();
    double? asDouble(dynamic v) {
      if (v == null) {
        return null;
      }
      return v is double ? v : (v as num).toDouble();
    }

    return AppUser(
      id: asInt(json['id']),
      name: json['name'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
      lastLat: asDouble(json['last_lat']),
      lastLong: asDouble(json['last_long']),
    );
  }
}
