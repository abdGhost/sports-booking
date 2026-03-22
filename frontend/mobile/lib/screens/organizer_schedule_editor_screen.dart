import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/api_config.dart';
import '../models/scheduled_match.dart';
import '../models/sport_event.dart';
import '../providers/auth_provider.dart';
import '../theme/sports_app_theme.dart';

class _DraftRow {
  _DraftRow({
    required this.id,
    String round = '',
    required this.homeTeamId,
    required this.awayTeamId,
    this.scheduledAt,
    String venue = '',
    String notes = '',
  })  : roundCtrl = TextEditingController(text: round),
        venueCtrl = TextEditingController(text: venue),
        notesCtrl = TextEditingController(text: notes);

  int id;
  int homeTeamId;
  int awayTeamId;
  DateTime? scheduledAt;
  final TextEditingController roundCtrl;
  final TextEditingController venueCtrl;
  final TextEditingController notesCtrl;

  void dispose() {
    roundCtrl.dispose();
    venueCtrl.dispose();
    notesCtrl.dispose();
  }
}

/// Owner-only: `PUT /events/{id}/schedule` — pair registered squads into fixtures.
class OrganizerScheduleEditorScreen extends StatefulWidget {
  const OrganizerScheduleEditorScreen({super.key, required this.event});

  final SportEvent event;

  @override
  State<OrganizerScheduleEditorScreen> createState() =>
      _OrganizerScheduleEditorScreenState();
}

class _OrganizerScheduleEditorScreenState
    extends State<OrganizerScheduleEditorScreen> {
  Map<int, String> _teams = {};
  final List<_DraftRow> _rows = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final id = widget.event.id;
    final base = ApiConfig.baseUrl;
    try {
      final bookRes = await http.get(Uri.parse('$base/events/$id/bookings'));
      final schedRes = await http.get(Uri.parse('$base/events/$id/schedule'));
      if (!mounted) {
        return;
      }
      if (bookRes.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = 'Could not load teams (${bookRes.statusCode}).';
        });
        return;
      }
      final teams = _parseTeams(jsonDecode(bookRes.body) as List<dynamic>);
      _teams = teams;
      final ids = teams.keys.toList()..sort();
      if (schedRes.statusCode == 200) {
        final body = jsonDecode(schedRes.body) as Map<String, dynamic>;
        final list = body['matches'] as List<dynamic>? ?? [];
        for (final raw in list) {
          final m = ScheduledMatchItem.fromJson(raw as Map<String, dynamic>);
          _rows.add(
            _DraftRow(
              id: m.id,
              round: m.round ?? '',
              homeTeamId: m.homeTeamId,
              awayTeamId: m.awayTeamId,
              scheduledAt: m.scheduledAt,
              venue: m.venue ?? '',
              notes: m.notes ?? '',
            ),
          );
        }
      }
      if (_rows.isEmpty && ids.length >= 2) {
        _rows.add(
          _DraftRow(
            id: 1,
            homeTeamId: ids[0],
            awayTeamId: ids[1],
          ),
        );
      }
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  static Map<int, String> _parseTeams(List<dynamic> list) {
    final out = <int, String>{};
    int asInt(dynamic v) => v is int ? v : (v as num).toInt();
    for (final raw in list) {
      final row = raw as Map<String, dynamic>;
      final tid = row['team_id'] ?? row['teamId'];
      if (tid == null) {
        continue;
      }
      final id = asInt(tid);
      if (out.containsKey(id)) {
        continue;
      }
      final name = (row['team_name'] ?? row['teamName']) as String?;
      out[id] = (name != null && name.trim().isNotEmpty) ? name.trim() : 'Team $id';
    }
    return out;
  }

  int _nextId() {
    if (_rows.isEmpty) {
      return 1;
    }
    return _rows.map((r) => r.id).reduce((a, b) => a > b ? a : b) + 1;
  }

  void _removeAt(int index) {
    final r = _rows.removeAt(index);
    r.dispose();
    setState(() {});
  }

  void _addFixture() {
    final teamIds = _teams.keys.toList()..sort();
    if (teamIds.length < 2) {
      return;
    }
    setState(() {
      _rows.add(
        _DraftRow(
          id: _nextId(),
          homeTeamId: teamIds[0],
          awayTeamId: teamIds[1],
        ),
      );
    });
  }

  Future<void> _pickTime(_DraftRow row) async {
    final initial = row.scheduledAt ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (d == null || !mounted) {
      return;
    }
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (t == null || !mounted) {
      return;
    }
    setState(() {
      row.scheduledAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  Future<void> _save() async {
    final auth = context.read<AuthProvider>();
    if (_rows.isNotEmpty && _teams.length < 2) {
      setState(() => _error = 'Need at least two registered squads to add fixtures.');
      return;
    }
    for (final r in _rows) {
      if (r.homeTeamId == r.awayTeamId) {
        setState(() => _error = 'Home and away must be different squads.');
        return;
      }
      if (!_teams.containsKey(r.homeTeamId) ||
          !_teams.containsKey(r.awayTeamId)) {
        setState(
          () => _error = 'Pick teams from the registered squad list only.',
        );
        return;
      }
    }
    final seen = <int>{};
    for (final r in _rows) {
      if (seen.contains(r.id)) {
        setState(() => _error = 'Duplicate match id ${r.id}.');
        return;
      }
      seen.add(r.id);
    }

    final payload = <String, dynamic>{
      'matches': [
        for (final r in _rows)
          ScheduledMatchItem(
            id: r.id,
            round: r.roundCtrl.text.trim().isEmpty
                ? null
                : r.roundCtrl.text.trim(),
            homeTeamId: r.homeTeamId,
            awayTeamId: r.awayTeamId,
            homeTeamName: _teams[r.homeTeamId]!,
            awayTeamName: _teams[r.awayTeamId]!,
            scheduledAt: r.scheduledAt,
            venue: r.venueCtrl.text.trim().isEmpty
                ? null
                : r.venueCtrl.text.trim(),
            notes: r.notesCtrl.text.trim().isEmpty
                ? null
                : r.notesCtrl.text.trim(),
          ).toJson(),
      ],
    };

    setState(() {
      _saving = true;
      _error = null;
    });
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/events/${widget.event.id}/schedule',
    );
    try {
      final res = await http.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          ...auth.authHeaders(),
        },
        body: jsonEncode(payload),
      );
      if (!mounted) {
        return;
      }
      if (res.statusCode != 200) {
        setState(() {
          _saving = false;
          _error = _parseErr(res.body) ?? 'Save failed (${res.statusCode}).';
        });
        return;
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  static String? _parseErr(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      final d = m['detail'];
      if (d is String) {
        return d;
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final teamIds = _teams.keys.toList()..sort();

    return Scaffold(
      backgroundColor: SportsAppColors.pageBackground,
      appBar: AppBar(
        title: const Text('Edit schedule'),
        backgroundColor: SportsAppColors.pageBackground,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: SportsAppColors.navy),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: SportsAppColors.accentWarm,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    children: [
                      Text(
                        widget.event.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: SportsAppColors.accentBlue900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        teamIds.length < 2
                            ? 'At least two squads must register before you can publish fixtures.'
                            : '${teamIds.length} squads registered — pair them below.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: SportsAppColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (var i = 0; i < _rows.length; i++) ...[
                        _buildRowCard(theme, _rows[i], i, teamIds),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: teamIds.length < 2 ? null : _addFixture,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add fixture'),
                        ),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: SportsAppColors.navy,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(52),
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
                              : const Text('Save schedule'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildRowCard(
    ThemeData theme,
    _DraftRow row,
    int index,
    List<int> teamIds,
  ) {
    return Material(
      color: SportsAppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Match ${index + 1}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: SportsAppColors.accentBlue900,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _removeAt(index),
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: SportsAppColors.accentWarm,
                ),
              ],
            ),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Round / stage (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              controller: row.roundCtrl,
            ),
            const SizedBox(height: 10),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Home',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: teamIds.contains(row.homeTeamId)
                      ? row.homeTeamId
                      : (teamIds.isNotEmpty ? teamIds.first : null),
                  items: [
                    for (final id in teamIds)
                      DropdownMenuItem(
                        value: id,
                        child: Text(_teams[id] ?? 'Team $id'),
                      ),
                  ],
                  onChanged: teamIds.isEmpty
                      ? null
                      : (v) {
                          if (v != null) {
                            setState(() => row.homeTeamId = v);
                          }
                        },
                ),
              ),
            ),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Away',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: teamIds.contains(row.awayTeamId)
                      ? row.awayTeamId
                      : (teamIds.length > 1
                          ? teamIds[1]
                          : (teamIds.isNotEmpty ? teamIds.first : null)),
                  items: [
                    for (final id in teamIds)
                      DropdownMenuItem(
                        value: id,
                        child: Text(_teams[id] ?? 'Team $id'),
                      ),
                  ],
                  onChanged: teamIds.isEmpty
                      ? null
                      : (v) {
                          if (v != null) {
                            setState(() => row.awayTeamId = v);
                          }
                        },
                ),
              ),
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Kick-off'),
              subtitle: Text(
                row.scheduledAt != null
                    ? DateFormat('EEE d MMM y · h:mm a')
                        .format(row.scheduledAt!.toLocal())
                    : 'Tap to set',
              ),
              trailing: const Icon(Icons.schedule_rounded),
              onTap: () => _pickTime(row),
            ),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Venue / pitch (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              controller: row.venueCtrl,
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
              controller: row.notesCtrl,
            ),
          ],
        ),
      ),
    );
  }
}

