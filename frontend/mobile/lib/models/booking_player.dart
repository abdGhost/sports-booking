import 'package:flutter/foundation.dart';

import 'team_roster_member.dart';

@immutable
class BookingPlayer {
  const BookingPlayer({
    required this.bookingId,
    required this.userId,
    required this.name,
    required this.email,
    required this.paymentStatus,
    this.teamId,
    this.teamName,
    this.address,
    this.teamRoster,
  });

  final int bookingId;
  final int userId;
  final String name;
  final String email;
  final String paymentStatus;
  final int? teamId;
  final String? teamName;

  /// Meet / check-in line saved by organizer while the match is live.
  final String? address;

  /// Captain-declared roster for this squad (same list on each member booking).
  final List<TeamRosterMember>? teamRoster;

  factory BookingPlayer.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is int ? v : (v as num).toInt();

    List<TeamRosterMember>? roster;
    final raw = json['team_roster'];
    if (raw is List<dynamic>) {
      roster = raw
          .map((e) => TeamRosterMember.fromJson(e as Map<String, dynamic>))
          .where((m) => m.name.isNotEmpty)
          .toList();
      if (roster.isEmpty) {
        roster = null;
      }
    }

    return BookingPlayer(
      bookingId: asInt(json['booking_id']),
      userId: asInt(json['user_id']),
      name: json['name'] as String,
      email: json['email'] as String,
      paymentStatus: json['payment_status'] as String,
      teamId: json['team_id'] == null ? null : asInt(json['team_id']),
      teamName: json['team_name'] as String?,
      address: json['address'] as String?,
      teamRoster: roster,
    );
  }
}
