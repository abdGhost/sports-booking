import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/api_config.dart';
import '../models/organizer_matchup.dart';
import '../models/scheduled_match.dart';
import '../providers/auth_provider.dart';
import '../theme/sports_app_theme.dart';

class MatchupDetailScreen extends StatefulWidget {
  const MatchupDetailScreen({
    super.key,
    required this.eventId,
    required this.matchup,
  });

  final int eventId;
  final OrganizerMatchup matchup;

  @override
  State<MatchupDetailScreen> createState() => _MatchupDetailScreenState();
}

class _MatchupDetailScreenState extends State<MatchupDetailScreen> {
  late final TextEditingController _aCtrl;
  late final TextEditingController _bCtrl;
  late OrganizerMatchupStatus _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.matchup;
    _aCtrl = TextEditingController(text: m.scoreA.toString());
    _bCtrl = TextEditingController(text: m.scoreB.toString());
    _status = m.status;
  }

  @override
  void dispose() {
    _aCtrl.dispose();
    _bCtrl.dispose();
    super.dispose();
  }

  String _apiStatus(OrganizerMatchupStatus s) {
    switch (s) {
      case OrganizerMatchupStatus.scheduled:
        return 'scheduled';
      case OrganizerMatchupStatus.live:
        return 'live';
      case OrganizerMatchupStatus.finished:
        return 'finished';
    }
  }

  OrganizerMatchup _mergeFromServer(ScheduledMatchItem sm) {
    final kick = sm.scheduledAt ?? widget.matchup.kickoff;
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
      id: widget.matchup.id,
      teamAId: sm.homeTeamId,
      teamAName: sm.homeTeamName,
      teamBId: sm.awayTeamId,
      teamBName: sm.awayTeamName,
      kickoff: kick,
      reportingAt: report.isBefore(kick) ? report : kick,
      scoreA: sm.homeScore ?? 0,
      scoreB: sm.awayScore ?? 0,
      status: status,
      notes: sm.notes ?? widget.matchup.notes,
    );
  }

  Future<void> _save() async {
    final a = int.tryParse(_aCtrl.text.trim()) ?? 0;
    final b = int.tryParse(_bCtrl.text.trim()) ?? 0;
    final matchId = int.tryParse(widget.matchup.id);

    if (matchId == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Saved on this device only — this matchup is not on the server yet.',
          ),
        ),
      );
      Navigator.of(context).pop(
        widget.matchup.copyWith(scoreA: a, scoreB: b, status: _status),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    if (auth.token == null || auth.token!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to save scores to the server.')),
      );
      return;
    }

    setState(() => _saving = true);
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/events/${widget.eventId}/schedule/matches/$matchId',
    );
    try {
      final res = await http.patch(
        uri,
        headers: {
          ...auth.authHeaders(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'home_score': a,
          'away_score': b,
          'status': _apiStatus(_status),
        }),
      );
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);

      if (res.statusCode != 200) {
        var msg = 'Could not save (${res.statusCode})';
        try {
          final err = jsonDecode(res.body);
          if (err is Map && err['detail'] != null) {
            msg = '${err['detail']}';
          }
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
        return;
      }

      OrganizerMatchup out =
          widget.matchup.copyWith(scoreA: a, scoreB: b, status: _status);
      try {
        final map = jsonDecode(res.body) as Map<String, dynamic>;
        final list = map['matches'] as List<dynamic>? ?? [];
        for (final raw in list) {
          final sm = ScheduledMatchItem.fromJson(raw as Map<String, dynamic>);
          if (sm.id == matchId) {
            out = _mergeFromServer(sm);
            break;
          }
        }
      } catch (_) {}

      Navigator.of(context).pop(out);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = widget.matchup;
    final kick = DateFormat('EEE d MMM · h:mm a').format(m.kickoff.toLocal());

    return Scaffold(
      backgroundColor: SportsAppColors.pageBackground,
      appBar: AppBar(
        title: Text(
          'Matchup details',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: SportsAppColors.accentBlue900,
          ),
        ),
        backgroundColor: SportsAppColors.pageBackground,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: SportsAppColors.border.withValues(alpha: 0.85),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: sportsCardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${m.teamAName} vs ${m.teamBName}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: SportsAppColors.accentBlue900,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.event_available_rounded,
                          size: 18,
                          color: SportsAppColors.cyan.withValues(alpha: 0.9),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          kick,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: SportsAppColors.navy,
                          ),
                        ),
                      ],
                    ),
                    if (m.notes != null && m.notes!.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        m.notes!.trim(),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: SportsAppColors.textMuted,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Score & status',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: SportsAppColors.accentBlue900,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _aCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Score · ${m.teamAName}',
                        filled: true,
                        fillColor: SportsAppColors.surfaceElevated,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _bCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Score · ${m.teamBName}',
                        filled: true,
                        fillColor: SportsAppColors.surfaceElevated,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Status',
                  filled: true,
                  fillColor: SportsAppColors.surfaceElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<OrganizerMatchupStatus>(
                    value: _status,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(12),
                    items: OrganizerMatchupStatus.values
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(_statusLabel(s)),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (v) {
                            if (v != null) {
                              setState(() => _status = v);
                            }
                          },
                  ),
                ),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: SportsAppColors.navy,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(OrganizerMatchupStatus s) {
    switch (s) {
      case OrganizerMatchupStatus.scheduled:
        return 'Scheduled';
      case OrganizerMatchupStatus.live:
        return 'Live';
      case OrganizerMatchupStatus.finished:
        return 'Finished';
    }
  }
}
