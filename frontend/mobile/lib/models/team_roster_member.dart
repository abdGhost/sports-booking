import 'package:flutter/foundation.dart';

@immutable
class TeamRosterMember {
  const TeamRosterMember({
    required this.name,
    this.email,
    this.isCaptain = false,
  });

  final String name;
  final String? email;
  final bool isCaptain;

  factory TeamRosterMember.fromJson(Map<String, dynamic> json) {
    return TeamRosterMember(
      name: json['name'] as String? ?? '',
      email: json['email'] as String?,
      isCaptain: json['is_captain'] as bool? ?? false,
    );
  }
}
