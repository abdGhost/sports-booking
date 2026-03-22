import 'package:flutter/foundation.dart';

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

  factory BookingPlayer.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is int ? v : (v as num).toInt();

    return BookingPlayer(
      bookingId: asInt(json['booking_id']),
      userId: asInt(json['user_id']),
      name: json['name'] as String,
      email: json['email'] as String,
      paymentStatus: json['payment_status'] as String,
      teamId: json['team_id'] == null ? null : asInt(json['team_id']),
      teamName: json['team_name'] as String?,
      address: json['address'] as String?,
    );
  }
}
