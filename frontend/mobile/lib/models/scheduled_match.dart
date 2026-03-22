import 'package:flutter/foundation.dart';

@immutable
class ScheduledMatchItem {
  const ScheduledMatchItem({
    required this.id,
    this.round,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.homeTeamName,
    required this.awayTeamName,
    this.scheduledAt,
    this.venue,
    this.notes,
    this.status,
    this.homeScore,
    this.awayScore,
  });

  final int id;
  final String? round;
  final int homeTeamId;
  final int awayTeamId;
  final String homeTeamName;
  final String awayTeamName;
  final DateTime? scheduledAt;
  final String? venue;
  final String? notes;
  /// API: `scheduled` | `live` | `finished` | `postponed` | `cancelled`
  final String? status;
  final int? homeScore;
  final int? awayScore;

  factory ScheduledMatchItem.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is int ? v : (v as num).toInt();

    return ScheduledMatchItem(
      id: asInt(json['id']),
      round: json['round'] as String?,
      homeTeamId: asInt(json['home_team_id']),
      awayTeamId: asInt(json['away_team_id']),
      homeTeamName: json['home_team_name'] as String? ?? '',
      awayTeamName: json['away_team_name'] as String? ?? '',
      scheduledAt: json['scheduled_at'] != null
          ? DateTime.parse(json['scheduled_at'] as String)
          : null,
      venue: json['venue'] as String?,
      notes: json['notes'] as String?,
      status: json['status'] as String?,
      homeScore: json['home_score'] == null ? null : asInt(json['home_score']),
      awayScore: json['away_score'] == null ? null : asInt(json['away_score']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (round != null) 'round': round,
      'home_team_id': homeTeamId,
      'away_team_id': awayTeamId,
      'home_team_name': homeTeamName,
      'away_team_name': awayTeamName,
      if (scheduledAt != null)
        'scheduled_at': scheduledAt!.toUtc().toIso8601String(),
      if (venue != null) 'venue': venue,
      if (notes != null) 'notes': notes,
      if (status != null) 'status': status,
      if (homeScore != null) 'home_score': homeScore,
      if (awayScore != null) 'away_score': awayScore,
    };
  }
}
