import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/api_config.dart';
import '../models/booking_player.dart';
import '../models/organizer_matchup.dart';
import '../models/sport_event.dart';
import '../providers/auth_provider.dart';
import '../theme/sports_app_theme.dart';
import '../widgets/sports_components.dart';
import 'matchup_detail_screen.dart';

/// Shown when the API returns no bookings so you can preview the check-in UI.
/// Negative [bookingId] marks demo rows (saves stay on-device only).
const List<BookingPlayer> _kDummyDemoRoster = [
  BookingPlayer(
    bookingId: -1,
    userId: 901,
    name: 'Sam Okonkwo',
    email: 'sam.ok@example.com',
    paymentStatus: 'paid',
    teamId: 1,
    teamName: 'North District FC',
    address: 'Gate A — north lot, Field 2',
  ),
  BookingPlayer(
    bookingId: -2,
    userId: 902,
    name: 'Jordan Lee',
    email: 'jordan@example.com',
    paymentStatus: 'paid',
    teamId: 1,
    teamName: 'North District FC',
  ),
  BookingPlayer(
    bookingId: -3,
    userId: 903,
    name: 'Robin Singh',
    email: 'robin@example.com',
    paymentStatus: 'paid',
    teamId: 2,
    teamName: 'Riverside United',
  ),
  BookingPlayer(
    bookingId: -10,
    userId: 910,
    name: 'Alex Kim',
    email: 'alex@example.com',
    paymentStatus: 'paid',
    teamId: 2,
    teamName: 'Riverside United',
  ),
  BookingPlayer(
    bookingId: -4,
    userId: 904,
    name: 'Priya Nair',
    email: 'priya@example.com',
    paymentStatus: 'paid',
    teamId: 3,
    teamName: 'City Youth',
  ),
  BookingPlayer(
    bookingId: -5,
    userId: 905,
    name: 'Diego Flores',
    email: 'diego@example.com',
    paymentStatus: 'paid',
    teamId: 3,
    teamName: 'City Youth',
  ),
  BookingPlayer(
    bookingId: -6,
    userId: 906,
    name: 'Emma Wilson',
    email: 'emma@example.com',
    paymentStatus: 'pending',
    teamId: 4,
    teamName: 'Silchar Juniors',
  ),
  BookingPlayer(
    bookingId: -7,
    userId: 907,
    name: 'Chris Park',
    email: 'chris@example.com',
    paymentStatus: 'paid',
    teamId: 4,
    teamName: 'Silchar Juniors',
  ),
  BookingPlayer(
    bookingId: -8,
    userId: 908,
    name: 'Morgan Chen',
    email: 'morgan@example.com',
    paymentStatus: 'pending',
    teamId: null,
  ),
];

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

  /// Organizer-scheduled pairings (UI-only; wire to API later).
  final List<OrganizerMatchup> _matchups = [];

  List<BookingPlayer> get _rosterRows =>
      _players.isNotEmpty ? _players : _kDummyDemoRoster;

  bool get _usingDummyRoster => _players.isEmpty;

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
    final byTeam = _groupByTeamId(_rosterRows);
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SportsAppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
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
              setModal(() => reportingTime = t);
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
                      'Pick two squads, then set when the match starts and when teams should report.',
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
                            setModal(() => teamBId = v);
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
                            onPressed: reportingOk && teamAId != teamBId
                                ? () {
                                    final m = OrganizerMatchup(
                                      id: '${DateTime.now().microsecondsSinceEpoch}',
                                      teamAId: teamAId,
                                      teamAName: nameFor(teamAId),
                                      teamBId: teamBId,
                                      teamBName: nameFor(teamBId),
                                      kickoff: kickoff,
                                      reportingAt: reportingAt,
                                    );
                                    Navigator.pop(context);
                                    setState(() => _matchups.insert(0, m));
                                    ScaffoldMessenger.of(this.context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Matchup scheduled (saved on this device for now).'),
                                      ),
                                    );
                                  }
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: SportsAppColors.navy,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Save matchup'),
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

  Future<void> _openMatchupDetail(OrganizerMatchup m) async {
    final updated = await Navigator.of(context).push<OrganizerMatchup>(
      MaterialPageRoute(
        builder: (_) => MatchupDetailScreen(matchup: m),
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
                        onPressed: () => setState(() => _matchups.removeWhere((x) => x.id == m.id)),
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
    await Future.wait([_loadEvent(), _loadBookings()]);
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
        setState(() {
          _players = list
              .map((e) => BookingPlayer.fromJson(e as Map<String, dynamic>))
              .toList();
        });
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

  Widget _buildPreviewBanner(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: SportsAppColors.cyan.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: SportsAppColors.cyan.withValues(alpha: 0.28),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 20,
              color: SportsAppColors.cyan.withValues(alpha: 0.95),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sample roster: players are grouped by squad (football-style). '
                'Live data from the server replaces this preview.',
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
    );
  }

  List<Widget> _buildCheckInMatchupSections(ThemeData theme) {
    final rows = _rosterRows;
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
                        'Squad ID $tid — share this so teammates join the same group.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: SportsAppColors.textMuted,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
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
          if (_usingDummyRoster) _buildPreviewBanner(theme),
          ..._buildCheckInMatchupSections(theme),
        ],
      ),
    );
  }
}
