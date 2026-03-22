import 'package:flutter/foundation.dart';

import 'sport_event.dart';

/// One row from `GET /me/bookings`.
@immutable
class MyBooking {
  const MyBooking({
    required this.bookingId,
    required this.paymentStatus,
    this.teamId,
    this.teamName,
    this.address,
    required this.event,
  });

  final int bookingId;
  final String paymentStatus;
  final int? teamId;
  final String? teamName;
  final String? address;
  final SportEvent event;

  factory MyBooking.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is int ? v : (v as num).toInt();

    return MyBooking(
      bookingId: asInt(json['booking_id']),
      paymentStatus: json['payment_status'] as String,
      teamId: json['team_id'] == null ? null : asInt(json['team_id']),
      teamName: json['team_name'] as String?,
      address: json['address'] as String?,
      event: SportEvent.fromJson(json['event'] as Map<String, dynamic>),
    );
  }
}
