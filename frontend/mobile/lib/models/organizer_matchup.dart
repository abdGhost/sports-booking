import 'package:flutter/foundation.dart';

enum OrganizerMatchupStatus { scheduled, live, finished }

/// A scheduled pairing between two squads (UI-only until backend persists matchups).
@immutable
class OrganizerMatchup {
  const OrganizerMatchup({
    required this.id,
    required this.teamAId,
    required this.teamAName,
    required this.teamBId,
    required this.teamBName,
    required this.kickoff,
    required this.reportingAt,
    this.scoreA = 0,
    this.scoreB = 0,
    this.status = OrganizerMatchupStatus.scheduled,
    this.notes,
  });

  final String id;
  final int teamAId;
  final String teamAName;
  final int teamBId;
  final String teamBName;

  /// Match kickoff (local date + time).
  final DateTime kickoff;

  /// Teams should report by this time (same calendar day as [kickoff]).
  final DateTime reportingAt;
  final int scoreA;
  final int scoreB;
  final OrganizerMatchupStatus status;
  final String? notes;

  OrganizerMatchup copyWith({
    int? scoreA,
    int? scoreB,
    OrganizerMatchupStatus? status,
    String? notes,
  }) {
    return OrganizerMatchup(
      id: id,
      teamAId: teamAId,
      teamAName: teamAName,
      teamBId: teamBId,
      teamBName: teamBName,
      kickoff: kickoff,
      reportingAt: reportingAt,
      scoreA: scoreA ?? this.scoreA,
      scoreB: scoreB ?? this.scoreB,
      status: status ?? this.status,
      notes: notes ?? this.notes,
    );
  }
}
