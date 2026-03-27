import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/api_config.dart';
import '../utils/organizer_booking_seen_store.dart';
import '../models/booking_player.dart';
import '../models/team_roster_member.dart';
import '../models/organizer_matchup.dart';
import '../models/scheduled_match.dart';
import '../models/sport_event.dart';
import '../providers/auth_provider.dart';
import '../theme/sports_app_theme.dart';
import '../widgets/sports_components.dart';
import 'matchup_detail_screen.dart';
import 'organizer_schedule_editor_screen.dart';

(int, int) _unorderedTeamPair(int a, int b) => a < b ? (a, b) : (b, a);

int _maxFixturesPerSquadPair(String competitionFormat) {
  final f = competitionFormat.toLowerCase().trim();
  if (f == 'league' || f == 'group_knockout') {
    return 2;
  }
  return 1;
}

int? _knockoutLoserTeamId(ScheduledMatchItem m) {
  if (m.status != 'finished' || m.homeScore == null || m.awayScore == null) {
    return null;
  }
  if (m.homeScore! > m.awayScore!) {
    return m.awayTeamId;
  }
  if (m.awayScore! > m.homeScore!) {
    return m.homeTeamId;
  }
  return null;
}

int _fixtureOrderCompare(ScheduledMatchItem a, ScheduledMatchItem b) {
  final ta = a.scheduledAt;
  final tb = b.scheduledAt;
  if (ta == null && tb == null) {
    return a.id.compareTo(b.id);
  }
  if (ta == null) {
    return 1;
  }
  if (tb == null) {
    return -1;
  }
  final c = ta.compareTo(tb);
  if (c != 0) {
    return c;
  }
  return a.id.compareTo(b.id);
}

/// Mirrors backend schedule rules: pair limits + knockout elimination ordering.
String? _validateNewMatchupForSchedule({
  required String competitionFormat,
  required List<ScheduledMatchItem> existing,
  required int teamAId,
  required int teamBId,
  required DateTime kickoff,
  required int nextMatchId,
}) {
  final maxPer = _maxFixturesPerSquadPair(competitionFormat);
  final pair = _unorderedTeamPair(teamAId, teamBId);
  var count = 0;
  for (final m in existing) {
    if (_unorderedTeamPair(m.homeTeamId, m.awayTeamId) == pair) {
      count++;
    }
  }
  if (count >= maxPer) {
    return maxPer == 1
        ? 'These squads already have a matchup. In knockout, each pair can only meet once.'
        : 'These squads already have two fixtures (home and away). Remove one before adding another.';
  }

  final fmt = competitionFormat.toLowerCase().trim();
  if (fmt != 'knockout') {
    return null;
  }

  ScheduledMatchItem? latestLossFor(int tid) {
    ScheduledMatchItem? best;
    for (final m in existing) {
      final lid = _knockoutLoserTeamId(m);
      if (lid != tid) {
        continue;
      }
      if (best == null || _fixtureOrderCompare(m, best) > 0) {
        best = m;
      }
    }
    return best;
  }

  final synthetic = ScheduledMatchItem(
    id: nextMatchId,
    homeTeamId: teamAId,
    awayTeamId: teamBId,
    homeTeamName: '',
    awayTeamName: '',
    scheduledAt: kickoff,
  );

  for (final tid in [teamAId, teamBId]) {
    final lostIn = latestLossFor(tid);
    if (lostIn == null) {
      continue;
    }
    if (_fixtureOrderCompare(synthetic, lostIn) > 0) {
      return 'Knockout: a squad eliminated in a finished match cannot be scheduled in a later fixture.';
    }
  }
  return null;
}

/// Turns raw API / validation text into short, actionable copy for organizers.
String _clarifyScheduleSaveError(String raw) {
  final t = raw.trim();
  if (t.isEmpty) {
    return 'Could not save the matchup. Please try again.';
  }
  final lower = t.toLowerCase();
  if (lower.contains('squad pairing already') ||
      lower.contains('each pair can only meet once')) {
    return 'These two squads already have a game on the schedule. In knockout, '
        'you can only schedule one match between the same pair. Remove the existing '
        'fixture first, or choose two different squads.';
  }
  if (lower.contains('two fixtures') && lower.contains('home and away')) {
    return 'You already have two games between this pair (home and away). '
        'Delete one of those fixtures before adding another.';
  }
  if (lower.contains('eliminated') || lower.contains('later fixture')) {
    return 'For knockout events, a squad that already lost a finished match cannot '
        'be added to a new game with a later kickoff. Change the kickoff time, '
        'pick different squads, or remove/adjust the finished game first.';
  }
  if (lower.contains('home and away must be different')) {
    return 'Home and away must be two different squads.';
  }
  if (lower.contains('registered squad')) {
    return 'Both teams must be squads registered for this event. Refresh and check '
        'the Registered squads list.';
  }
  if (lower.contains('only the event owner') ||
      lower.contains('only organizers can')) {
    return 'Only the organizer who owns this event can publish the schedule. '
        'Sign in with the correct organizer account.';
  }
  if (lower.contains('team events only') || lower.contains('team/squad')) {
    return 'The schedule only applies to team (squad) events.';
  }
  if (lower.contains('at least two') && lower.contains('squad')) {
    return 'You need at least two registered squads before adding fixtures.';
  }
  return t;
}

String _parseScheduleHttpError(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map && decoded['detail'] != null) {
      final d = decoded['detail'];
      if (d is String) {
        return _clarifyScheduleSaveError(d);
      }
      if (d is List) {
        final parts = <String>[];
        for (final item in d) {
          if (item is Map) {
            final msg = item['msg'];
            if (msg is String && msg.trim().isNotEmpty) {
              parts.add(msg.trim());
            }
          }
        }
        if (parts.isNotEmpty) {
          return _clarifyScheduleSaveError(parts.join(' '));
        }
      }
    }
  } catch (_) {}
  return _clarifyScheduleSaveError(
    'The server could not save this matchup. Check your connection and try again.',
  );
}

/// Organizer tools: scheduled matchups and registered squads.
class OrganizerDashboard extends StatefulWidget {
  const OrganizerDashboard({
    super.key,
    required this.eventId,
    this.event,
  });

  final int eventId;

  /// When provided (e.g. from home), used for the header before the network load finishes.
  final SportEvent? event;

  @override
  State<OrganizerDashboard> createState() => _OrganizerDashboardState();
}

class _OrganizerDashboardState extends State<OrganizerDashboard> {
  SportEvent? _event;
  List<BookingPlayer> _players = [];
  bool _loading = false;
  String? _loadError;

  /// Pairings from `GET /events/{id}/schedule` (updated after create/delete).
  final List<OrganizerMatchup> _matchups = [];

  Map<int, List<BookingPlayer>> _groupByTeamId(List<BookingPlayer> rows) {
    final m = <int, List<BookingPlayer>>{};
    for (final p in rows) {
      final tid = p.teamId;
      if (tid != null) {
        m.putIfAbsent(tid, () => []).add(p);
      }
    }
    return m;
  }

  String _squadDisplayName(int teamId, List<BookingPlayer> members) {
    for (final p in members) {
      final n = p.teamName?.trim();
      if (n != null && n.isNotEmpty) {
        return n;
      }
    }
    return 'Squad $teamId';
  }

  List<({int teamId, String name})> _squadsForMatchupPicker() {
    final byTeam = _groupByTeamId(_players);
    final ids = byTeam.keys.toList()..sort();
    return ids
        .map(
          (id) => (teamId: id, name: _squadDisplayName(id, byTeam[id]!)),
        )
        .toList();
  }

  Future<void> _openCreateMatchupSheet() async {
    final squads = _squadsForMatchupPicker();
    if (squads.length < 2) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You need at least two registered squads to create a matchup.'),
        ),
      );
      return;
    }

    final tomorrow = DateTime.now().add(const Duration(days: 1));
    var kickoff = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 15, 0);
    var reportingTime = const TimeOfDay(hour: 14, minute: 30);
    var teamAId = squads.first.teamId;
    var teamBId = squads[1].teamId;

    if (!mounted) {
      return;
    }
    final scaffoldMessengerContext = context;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SportsAppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        var saving = false;
        var sheetError = '';
        return StatefulBuilder(
          builder: (context, setModal) {
            final theme = Theme.of(context);
            final padBottom = MediaQuery.viewInsetsOf(context).bottom;

            String nameFor(int id) {
              for (final s in squads) {
                if (s.teamId == id) {
                  return s.name;
                }
              }
              return 'Squad $id';
            }

            Future<void> pickKickoff() async {
              final d = await showDatePicker(
                context: context,
                initialDate: kickoff,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
              );
              if (d == null) {
                return;
              }
              if (!context.mounted) {
                return;
              }
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(kickoff),
              );
              if (t == null) {
                return;
              }
              setModal(() {
                kickoff = DateTime(d.year, d.month, d.day, t.hour, t.minute);
                sheetError = '';
              });
            }

            Future<void> pickReportingTime() async {
              final t = await showTimePicker(
                context: context,
                initialTime: reportingTime,
              );
              if (t == null) {
                return;
              }
              if (!context.mounted) {
                return;
              }
              setModal(() {
                reportingTime = t;
                sheetError = '';
              });
            }

            final reportingAt = DateTime(
              kickoff.year,
              kickoff.month,
              kickoff.day,
              reportingTime.hour,
              reportingTime.minute,
            );
            final reportingOk = !reportingAt.isAfter(kickoff);

            return Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + padBottom),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: SportsAppColors.border,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Create matchup',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: SportsAppColors.accentBlue900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pick two squads, then set kickoff and reporting time. '
                      'If save fails, read the highlighted note — it usually means a duplicate pair '
                      '(knockout) or a squad is already out of the tournament.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: SportsAppColors.textMuted,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Home / Squad A',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: SportsAppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    InputDecorator(
                      decoration: _sheetFieldDecoration('Select squad'),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: teamAId,
                          isExpanded: true,
                          items: squads
                              .map(
                                (s) => DropdownMenuItem<int>(
                                  value: s.teamId,
                                  child: Text('${s.name} (ID ${s.teamId})'),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v == null) {
                              return;
                            }
                            setModal(() {
                              teamAId = v;
                              sheetError = '';
                              if (teamBId == teamAId) {
                                final other = squads.firstWhere((s) => s.teamId != teamAId);
                                teamBId = other.teamId;
                              }
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Away / Squad B',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: SportsAppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    InputDecorator(
                      decoration: _sheetFieldDecoration('Select squad'),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: teamBId,
                          isExpanded: true,
                          items: squads
                              .where((s) => s.teamId != teamAId)
                              .map(
                                (s) => DropdownMenuItem<int>(
                                  value: s.teamId,
                                  child: Text('${s.name} (ID ${s.teamId})'),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v == null) {
                              return;
                            }
                            setModal(() {
                              teamBId = v;
                              sheetError = '';
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Match date & time',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: SportsAppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: SportsAppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: pickKickoff,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.event_rounded,
                                color: SportsAppColors.cyan.withValues(alpha: 0.95),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  DateFormat('EEE, MMM d, y · h:mm a').format(kickoff),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: SportsAppColors.accentBlue900,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: SportsAppColors.textMuted.withValues(alpha: 0.7),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Reporting time',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: SportsAppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Same day as the match — when players should arrive (e.g. warm-up).',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: SportsAppColors.textMuted,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: SportsAppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: pickReportingTime,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.how_to_reg_outlined,
                                color: SportsAppColors.accentWarm.withValues(alpha: 0.95),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  reportingTime.format(context),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: SportsAppColors.accentBlue900,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: SportsAppColors.textMuted.withValues(alpha: 0.7),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (!reportingOk) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Reporting time should be before kickoff.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: SportsAppColors.accentWarm,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (sheetError.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: SportsAppColors.accentWarm.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: SportsAppColors.accentWarm.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 20,
                              color: SportsAppColors.accentWarm,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                sheetError,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: SportsAppColors.accentBlue900,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: saving || !reportingOk || teamAId == teamBId
                                ? null
                                : () async {
                                    setModal(() {
                                      saving = true;
                                      sheetError = '';
                                    });
                                    final err = await _saveMatchupToApi(
                                      teamAId: teamAId,
                                      teamBId: teamBId,
                                      teamAName: nameFor(teamAId),
                                      teamBName: nameFor(teamBId),
                                      kickoff: kickoff,
                                      reportingAt: reportingAt,
                                    );
                                    if (!mounted) {
                                      return;
                                    }
                                    if (err != null) {
                                      setModal(() {
                                        saving = false;
                                        sheetError = err;
                                      });
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(err),
                                            behavior: SnackBarBehavior.floating,
                                            duration: const Duration(seconds: 6),
                                          ),
                                        );
                                      }
                                      return;
                                    }
                                    setModal(() => saving = false);
                                    if (!context.mounted) {
                                      return;
                                    }
                                    Navigator.pop(context);
                                    if (!mounted) {
                                      return;
                                    }
                                    ScaffoldMessenger.of(scaffoldMessengerContext).showSnackBar(
                                      const SnackBar(
                                        content: Text('Matchup saved — visible on Scheduled matches.'),
                                      ),
                                    );
                                  },
                            style: FilledButton.styleFrom(
                              backgroundColor: SportsAppColors.navy,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: saving
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Save matchup'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  InputDecoration _sheetFieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: SportsAppColors.surfaceElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: SportsAppColors.border.withValues(alpha: 0.9)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: SportsAppColors.border.withValues(alpha: 0.9)),
      ),
    );
  }

  String _matchupStatusShort(OrganizerMatchupStatus s) {
    switch (s) {
      case OrganizerMatchupStatus.scheduled:
        return 'Scheduled';
      case OrganizerMatchupStatus.live:
        return 'Live';
      case OrganizerMatchupStatus.finished:
        return 'Done';
    }
  }

  Future<void> _openFixtureEditor(OrganizerMatchup m) async {
    final mid = int.tryParse(m.id);
    if (mid == null) {
      return;
    }
    var ev = _event ?? widget.event;
    if (ev == null) {
      await _loadEvent();
      ev = _event ?? widget.event;
    }
    if (ev == null || !mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load event. Pull to refresh and try again.'),
        ),
      );
      return;
    }
    final eventForEdit = ev;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => OrganizerScheduleEditorScreen(
          event: eventForEdit,
          singleMatchEditId: mid,
        ),
      ),
    );
    if (ok == true && mounted) {
      await _loadScheduleMatchups();
    }
  }

  Future<void> _openMatchupDetail(OrganizerMatchup m) async {
    final updated = await Navigator.of(context).push<OrganizerMatchup>(
      MaterialPageRoute(
        builder: (_) => MatchupDetailScreen(
          eventId: widget.eventId,
          matchup: m,
        ),
      ),
    );
    if (!mounted || updated == null) {
      return;
    }
    setState(() {
      final i = _matchups.indexWhere((x) => x.id == updated.id);
      if (i >= 0) {
        _matchups[i] = updated;
      }
    });
  }

  Widget _buildMatchupCard(OrganizerMatchup m, ThemeData theme) {
    final kickoffLabel = DateFormat('EEE, MMM d · h:mm a').format(m.kickoff);
    final reportLabel = DateFormat('h:mm a').format(m.reportingAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openMatchupDetail(m),
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            decoration: sportsCardDecoration(),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          m.teamAName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: SportsAppColors.cyan,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'VS',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: SportsAppColors.accentWarm,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          m.teamBName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: SportsAppColors.accentWarm,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _openFixtureEditor(m),
                        icon: Icon(
                          Icons.edit_calendar_outlined,
                          color: SportsAppColors.cyan.withValues(alpha: 0.95),
                        ),
                        tooltip: 'Edit fixture',
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () async {
                          final mid = int.tryParse(m.id);
                          if (mid != null) {
                            await _deleteMatchupFromApi(m.id);
                          } else {
                            setState(() => _matchups.removeWhere((x) => x.id == m.id));
                          }
                        },
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: SportsAppColors.textMuted.withValues(alpha: 0.85),
                        ),
                        tooltip: 'Remove',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: m.status == OrganizerMatchupStatus.live
                              ? SportsAppColors.liveRed.withValues(alpha: 0.12)
                              : SportsAppColors.cyan.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: m.status == OrganizerMatchupStatus.live
                                ? SportsAppColors.liveRed.withValues(alpha: 0.35)
                                : SportsAppColors.border.withValues(alpha: 0.8),
                          ),
                        ),
                        child: Text(
                          _matchupStatusShort(m.status),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: m.status == OrganizerMatchupStatus.live
                                ? SportsAppColors.liveRed
                                : SportsAppColors.accentBlue900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Score · ${m.scoreA} – ${m.scoreB}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: SportsAppColors.accentBlue900,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: SportsAppColors.textMuted.withValues(alpha: 0.7),
                        size: 22,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.event_available_rounded,
                        size: 18,
                        color: SportsAppColors.accentBlue900.withValues(alpha: 0.75),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Kickoff · $kickoffLabel',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: SportsAppColors.accentBlue900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 18,
                        color: SportsAppColors.textMuted.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Report by · $reportLabel (match day)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: SportsAppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap for score, notes & status',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: SportsAppColors.textMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScheduledMatchupsSection(ThemeData theme) {
    if (_matchups.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SportsSectionTitle(
          'Scheduled matchups',
          bottomSpacing: 10,
          color: SportsAppColors.accentBlue900,
        ),
        ..._matchups.map((m) => _buildMatchupCard(m, theme)),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh(showSpinner: true);
      }
    });
  }

  Future<void> _refresh({bool showSpinner = false}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    } else {
      setState(() => _loadError = null);
    }
    await Future.wait([
      _loadEvent(),
      _loadBookings(),
      _loadScheduleMatchups(),
    ]);
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadEvent() async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/events/${widget.eventId}');
    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) {
        if (mounted && _event == null) {
          setState(() {
            _loadError = 'Could not load event (HTTP ${res.statusCode})';
          });
        }
        return;
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _event = SportEvent.fromJson(map);
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted && _event == null) {
        setState(() {
          _loadError ??= e.toString();
        });
      }
    }
  }

  String _bookingTitle(BookingPlayer p) {
    if (p.teamId != null) {
      final tn = p.teamName?.trim();
      if (tn != null && tn.isNotEmpty) {
        return '${p.name} · $tn';
      }
      return '${p.name} · Squad ${p.teamId}';
    }
    return p.name;
  }

  Future<void> _loadBookings() async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/events/${widget.eventId}/bookings',
    );
    final authHeaders = context.read<AuthProvider>().authHeaders();
    try {
      final res = await http.get(uri, headers: authHeaders);
      if (res.statusCode != 200) {
        if (mounted) {
          setState(() => _players = []);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Could not load roster (HTTP ${res.statusCode})'),
              ),
            );
          }
        }
        return;
      }
      final list = jsonDecode(res.body) as List<dynamic>;
      if (mounted) {
        final players = list
            .map((e) => BookingPlayer.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() {
          _players = players;
        });
        await OrganizerBookingSeenStore.instance.acknowledgeBookings(
          widget.eventId,
          players.map((p) => p.bookingId).toSet(),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _players = []);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Roster error: $e')),
          );
        }
      }
    }
  }

  int _nextScheduleMatchId(List<dynamic> existing) {
    var maxId = 0;
    for (final raw in existing) {
      if (raw is! Map) {
        continue;
      }
      final id = raw['id'];
      final n = id is int
          ? id
          : (id is num ? id.toInt() : int.tryParse('$id') ?? 0);
      if (n > maxId) {
        maxId = n;
      }
    }
    return maxId + 1;
  }

  OrganizerMatchup _organizerMatchupFromScheduled(ScheduledMatchItem sm) {
    final kick = sm.scheduledAt ?? DateTime.now();
    final report = kick.subtract(const Duration(minutes: 30));
    final st = sm.status?.toLowerCase();
    OrganizerMatchupStatus status;
    switch (st) {
      case 'live':
        status = OrganizerMatchupStatus.live;
        break;
      case 'finished':
        status = OrganizerMatchupStatus.finished;
        break;
      default:
        status = OrganizerMatchupStatus.scheduled;
    }
    return OrganizerMatchup(
      id: sm.id.toString(),
      teamAId: sm.homeTeamId,
      teamAName: sm.homeTeamName,
      teamBId: sm.awayTeamId,
      teamBName: sm.awayTeamName,
      kickoff: kick,
      reportingAt: report.isBefore(kick) ? report : kick,
      scoreA: sm.homeScore ?? 0,
      scoreB: sm.awayScore ?? 0,
      status: status,
      notes: sm.notes,
    );
  }

  Future<void> _loadScheduleMatchups() async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/events/${widget.eventId}/schedule',
    );
    try {
      final res = await http.get(uri);
      if (!mounted) {
        return;
      }
      if (res.statusCode != 200) {
        setState(() => _matchups.clear());
        return;
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final list = map['matches'] as List<dynamic>? ?? [];
      final next = <OrganizerMatchup>[];
      for (final raw in list) {
        if (raw is! Map<String, dynamic>) {
          continue;
        }
        try {
          next.add(
            _organizerMatchupFromScheduled(
              ScheduledMatchItem.fromJson(raw),
            ),
          );
        } catch (_) {
          continue;
        }
      }
      setState(() {
        _matchups
          ..clear()
          ..addAll(next);
      });
    } catch (_) {
      if (mounted) {
        setState(() => _matchups.clear());
      }
    }
  }

  Future<String?> _saveMatchupToApi({
    required int teamAId,
    required int teamBId,
    required String teamAName,
    required String teamBName,
    required DateTime kickoff,
    required DateTime reportingAt,
  }) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || token.isEmpty) {
      return 'Sign in to save matchups to the server.';
    }
    final orgId = _event?.organizerId ?? widget.event?.organizerId;
    final uid = auth.user?.id;
    if (orgId != null && uid != null && uid != orgId) {
      return 'Only the event organizer can publish the schedule.';
    }
    final headers = auth.authHeaders();
    final base = ApiConfig.baseUrl;
    final eid = widget.eventId;
    try {
      final getRes = await http.get(Uri.parse('$base/events/$eid/schedule'));
      if (getRes.statusCode != 200) {
        return _clarifyScheduleSaveError(
          'Could not load the current schedule (server ${getRes.statusCode}). '
          'Check your connection and try again.',
        );
      }
      final map = jsonDecode(getRes.body) as Map<String, dynamic>;
      final existing = map['matches'] as List<dynamic>? ?? [];
      final nextId = _nextScheduleMatchId(existing);
      final existingMaps = <Map<String, dynamic>>[];
      final parsedExisting = <ScheduledMatchItem>[];
      for (final raw in existing) {
        if (raw is Map<String, dynamic>) {
          existingMaps.add(Map<String, dynamic>.from(raw));
          try {
            parsedExisting.add(ScheduledMatchItem.fromJson(raw));
          } catch (_) {}
        }
      }
      final cf =
          _event?.competitionFormat ?? widget.event?.competitionFormat ?? 'knockout';
      final preflight = _validateNewMatchupForSchedule(
        competitionFormat: cf,
        existing: parsedExisting,
        teamAId: teamAId,
        teamBId: teamBId,
        kickoff: kickoff,
        nextMatchId: nextId,
      );
      if (preflight != null) {
        return _clarifyScheduleSaveError(preflight);
      }
      final newItem = ScheduledMatchItem(
        id: nextId,
        round: 'Matchup',
        homeTeamId: teamAId,
        awayTeamId: teamBId,
        homeTeamName: teamAName,
        awayTeamName: teamBName,
        scheduledAt: kickoff,
        notes:
            'Report by ${DateFormat('h:mm a').format(reportingAt)} on match day',
      );
      existingMaps.add(newItem.toJson());
      final putRes = await http.put(
        Uri.parse('$base/events/$eid/schedule'),
        headers: {
          ...headers,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'matches': existingMaps}),
      );
      if (putRes.statusCode != 200) {
        return _parseScheduleHttpError(putRes.body);
      }
      await _loadScheduleMatchups();
      return null;
    } catch (_) {
      return _clarifyScheduleSaveError(
        'Could not reach the server while saving. Check your connection and try again.',
      );
    }
  }

  Future<void> _deleteMatchupFromApi(String idStr) async {
    final mid = int.tryParse(idStr);
    if (mid == null) {
      return;
    }
    final auth = context.read<AuthProvider>();
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/events/${widget.eventId}/schedule/matches/$mid',
    );
    try {
      final res = await http.delete(uri, headers: auth.authHeaders());
      if (!mounted) {
        return;
      }
      if (res.statusCode == 200) {
        await _loadScheduleMatchups();
        return;
      }
      var msg = 'Could not remove (${res.statusCode})';
      try {
        final err = jsonDecode(res.body);
        if (err is Map && err['detail'] != null) {
          msg = '${err['detail']}';
        }
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SportsAppColors.pageBackground,
      appBar: AppBar(
        title: Text(
          _event?.title ?? 'Organizer',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: SportsAppColors.card,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateMatchupSheet,
        icon: const Icon(Icons.add_circle_outline_rounded),
        label: const Text('Create matchup'),
        backgroundColor: SportsAppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: SportsBackground(
        child: _buildMainContent(context),
      ),
    );
  }

  List<Widget> _buildCheckInMatchupSections(ThemeData theme) {
    final rows = _players;
    if (rows.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: sportsCardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.groups_outlined,
                      size: 24,
                      color: SportsAppColors.cyan.withValues(alpha: 0.95),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No registered squads yet',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: SportsAppColors.accentBlue900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'When players book this team event, their squads appear here for check-in. '
                  'If you expect data, confirm the app is using the same API as your backend and pull to refresh.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: SportsAppColors.textMuted,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    final byTeam = _groupByTeamId(rows);
    final solos = rows.where((p) => p.teamId == null).toList();
    final teamIds = byTeam.keys.toList()..sort();
    final out = <Widget>[];

    if (teamIds.isNotEmpty) {
      out.add(
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: SportsSectionTitle(
            'Registered squads',
            bottomSpacing: 4,
            color: SportsAppColors.accentBlue900,
          ),
        ),
      );
      for (final tid in teamIds) {
        final members = byTeam[tid]!;
        final squadName = _squadDisplayName(tid, members);
        List<TeamRosterMember>? declaredRoster;
        for (final p in members) {
          final r = p.teamRoster;
          if (r != null && r.isNotEmpty) {
            declaredRoster = r;
            break;
          }
        }
        out.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 20,
                  color: SportsAppColors.cyan.withValues(alpha: 0.95),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        squadName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: SportsAppColors.accentBlue900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Team code $tid — share so teammates with accounts can join.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: SportsAppColors.textMuted,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      if (declaredRoster != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Roster from captain',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: SportsAppColors.accentBlue900,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...declaredRoster.map((m) {
                          final badge = m.isCaptain ? 'Captain · ' : '';
                          final em = m.email != null && m.email!.isNotEmpty
                              ? ' · ${m.email}'
                              : '';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '$badge${m.name}$em',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: SportsAppColors.textMuted,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
        for (final p in members) {
          out.add(_buildPlayerCheckInCard(p, theme, squadRoster: true));
          out.add(const SizedBox(height: 12));
        }
      }
    }

    if (solos.isNotEmpty) {
      out.add(
        Padding(
          padding: EdgeInsets.only(bottom: 10, top: teamIds.isNotEmpty ? 8 : 0),
          child: const SportsSectionTitle(
            'Individual bookings',
            bottomSpacing: 4,
            color: SportsAppColors.accentBlue900,
          ),
        ),
      );
      for (final p in solos) {
        out.add(_buildPlayerCheckInCard(p, theme));
        out.add(const SizedBox(height: 12));
      }
    }

    return out;
  }

  Widget _buildPlayerCheckInCard(
    BookingPlayer p,
    ThemeData theme, {
    bool squadRoster = false,
  }) {
    final addr = p.address;
    final primary = squadRoster ? p.name : _bookingTitle(p);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SportsAppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: SportsAppColors.border.withValues(alpha: 0.85),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: SportsAppColors.cyan.withValues(alpha: 0.2),
                child: (!squadRoster && p.teamId != null)
                    ? Text(
                        '${p.teamId}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: SportsAppColors.cyan,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    : Text(
                        p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: SportsAppColors.cyan,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      primary,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: SportsAppColors.accentBlue900,
                      ),
                    ),
                    if (!squadRoster && p.teamId != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        p.name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: SportsAppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      '${p.email} · ${p.paymentStatus}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: SportsAppColors.textMuted,
                      ),
                    ),
                    if (addr != null && addr.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 16,
                            color: SportsAppColors.cyan.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              addr,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: SportsAppColors.accentBlue900,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildMainContent(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && _event == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: SportsAppColors.textMuted,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _refresh(showSpinner: true),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(
                  backgroundColor: SportsAppColors.cyan,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: SportsAppColors.cyan,
      onRefresh: () => _refresh(showSpinner: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _buildScheduledMatchupsSection(theme),
          ..._buildCheckInMatchupSections(theme),
        ],
      ),
    );
  }
}
