import 'package:flutter/foundation.dart';

/// Mirrors [SportEvent] from the FastAPI backend (`models.py` / `schemas.py`).
@immutable
class SportEvent {
  const SportEvent({
    required this.id,
    required this.organizerId,
    required this.title,
    required this.sportType,
    required this.venueName,
    this.description,
    required this.durationMinutes,
    this.skillLevel,
    this.contactPhone,
    required this.lat,
    required this.long,
    required this.price,
    required this.maxSlots,
    required this.bookedSlots,
    required this.startTime,
    required this.status,
    this.distanceKm,
    this.ageGroup = 'Open',
    this.competitionFormat = 'knockout',
    this.registrationMode = 'team',
    this.extraConfig,
  });

  final int id;
  final int organizerId;
  final String title;
  final String sportType;

  /// Field / court / meeting point name (critical for players finding the game).
  final String venueName;

  /// What to bring, rules, format, etc.
  final String? description;

  /// Session length in minutes.
  final int durationMinutes;

  /// e.g. `all`, `beginner`, `intermediate`, `advanced`, `competitive`.
  final String? skillLevel;

  /// Day-of contact (optional).
  final String? contactPhone;

  final double lat;
  final double long;
  final double price;
  final int maxSlots;
  final int bookedSlots;
  final DateTime startTime;

  /// Backend: 0 Draft, 1 Open, 2 Full, 3 Live, 4 Completed
  final int status;

  /// Present when loaded from `/events/nearby`.
  final double? distanceKm;

  /// e.g. U12, U15, Open.
  final String ageGroup;

  /// league | knockout | group_knockout
  final String competitionFormat;

  /// team | individual
  final String registrationMode;
  final Map<String, dynamic>? extraConfig;

  int get remainingSlots => maxSlots - bookedSlots;

  bool get isFull => remainingSlots <= 0;

  factory SportEvent.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is int ? v : (v as num).toInt();

    return SportEvent(
      id: asInt(json['id']),
      organizerId: asInt(json['organizer_id']),
      title: json['title'] as String,
      sportType: json['sport_type'] as String,
      venueName: json['venue_name'] as String? ?? '',
      description: json['description'] as String?,
      durationMinutes: json['duration_minutes'] != null
          ? asInt(json['duration_minutes'])
          : 90,
      skillLevel: json['skill_level'] as String?,
      contactPhone: json['contact_phone'] as String?,
      lat: (json['lat'] as num).toDouble(),
      long: (json['long'] as num).toDouble(),
      price: (json['price'] as num).toDouble(),
      maxSlots: asInt(json['max_slots']),
      bookedSlots: asInt(json['booked_slots']),
      startTime: DateTime.parse(json['start_time'] as String),
      status: asInt(json['status']),
      distanceKm: json['distance_km'] != null
          ? (json['distance_km'] as num).toDouble()
          : null,
      ageGroup: json['age_group'] as String? ?? 'Open',
      competitionFormat: json['competition_format'] as String? ?? 'knockout',
      registrationMode: json['registration_mode'] as String? ?? 'team',
      extraConfig: json['extra_config'] is Map
          ? Map<String, dynamic>.from(json['extra_config'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'organizer_id': organizerId,
        'title': title,
        'sport_type': sportType,
        'venue_name': venueName,
        if (description != null) 'description': description,
        'duration_minutes': durationMinutes,
        if (skillLevel != null) 'skill_level': skillLevel,
        if (contactPhone != null) 'contact_phone': contactPhone,
        'lat': lat,
        'long': long,
        'price': price,
        'max_slots': maxSlots,
        'booked_slots': bookedSlots,
        'start_time': startTime.toIso8601String(),
        'status': status,
        if (distanceKm != null) 'distance_km': distanceKm,
        'age_group': ageGroup,
        'competition_format': competitionFormat,
        'registration_mode': registrationMode,
        if (extraConfig != null) 'extra_config': extraConfig,
      };
}
