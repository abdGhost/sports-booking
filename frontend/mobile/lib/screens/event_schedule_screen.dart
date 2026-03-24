import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_route_observer.dart';
import '../config/api_config.dart';
import '../models/scheduled_match.dart';
import '../models/sport_event.dart';
import '../providers/auth_provider.dart';
import '../theme/sports_app_theme.dart';
import 'organizer_schedule_editor_screen.dart';

/// Squad fixtures published by the organizer (`GET /events/{id}/schedule`).
class EventScheduleScreen extends StatefulWidget {
  const EventScheduleScreen({super.key, required this.event});

  final SportEvent event;

  @override
  State<EventScheduleScreen> createState() => _EventScheduleScreenState();
}

class _EventScheduleScreenState extends State<EventScheduleScreen>
    with RouteAware {
  List<ScheduledMatchItem>? _matches;
  String? _error;
  bool _loading = true;
  bool _routeListening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeListening) {
      return;
    }
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
      _routeListening = true;
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/events/${widget.event.id}/schedule',
    );
    try {
      final res = await http.get(uri);
      if (!mounted) {
        return;
      }
      if (res.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = 'Could not load schedule (${res.statusCode}).';
        });
        return;
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final list = map['matches'] as List<dynamic>? ?? [];
      setState(() {
        _loading = false;
        _matches = list
            .map((e) => ScheduledMatchItem.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  bool get _canEdit {
    final auth = context.read<AuthProvider>();
    final u = auth.user;
    return u != null &&
        u.isOrganizer &&
        u.id == widget.event.organizerId;
  }

  Future<void> _openSingleMatchEditor(ScheduledMatchItem m) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => OrganizerScheduleEditorScreen(
          event: widget.event,
          singleMatchEditId: m.id,
        ),
      ),
    );
    if (ok == true && mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: SportsAppColors.pageBackground,
      appBar: AppBar(
        title: Text(
          'Scheduled matches',
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
      body: RefreshIndicator(
        color: SportsAppColors.navy,
        onRefresh: _load,
        child: _buildBody(theme),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: CircularProgressIndicator(color: SportsAppColors.navy),
          ),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            _error!,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: SportsAppColors.accentWarm,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    final matches = _matches ?? [];
    if (matches.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
        children: [
          Icon(
            Icons.event_note_rounded,
            size: 56,
            color: SportsAppColors.textMuted.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 16),
          Text(
            'No fixtures yet',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: SportsAppColors.accentBlue900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _canEdit
                ? 'Add head-to-head matches between registered squads. Players will see them here.'
                : 'The organizer will publish knockout or league fixtures here after teams are in.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: SportsAppColors.textMuted,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_canEdit) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () async {
                final ok = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) =>
                        OrganizerScheduleEditorScreen(event: widget.event),
                  ),
                );
                if (ok == true && mounted) {
                  await _load();
                }
              },
              icon: const Icon(Icons.edit_calendar_rounded),
              label: const Text('Build schedule'),
              style: FilledButton.styleFrom(
                backgroundColor: SportsAppColors.navy,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      itemCount: matches.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final m = matches[i];
        final when = m.scheduledAt != null
            ? DateFormat('EEE d MMM · h:mm a').format(m.scheduledAt!.toLocal())
            : 'Time TBD';
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _canEdit ? () => _openSingleMatchEditor(m) : null,
            borderRadius: BorderRadius.circular(24),
            child: Ink(
              decoration: sportsCardDecoration(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: m.round != null && m.round!.trim().isNotEmpty
                              ? Padding(
                                  padding:
                                      const EdgeInsets.only(top: 4, bottom: 10),
                                  child: Text(
                                    m.round!.trim().toUpperCase(),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: SportsAppColors.cyan,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                )
                              : const SizedBox(height: 8),
                        ),
                        if (_canEdit)
                          IconButton(
                            tooltip: 'Edit this match',
                            onPressed: () => _openSingleMatchEditor(m),
                            icon: Icon(
                              Icons.edit_rounded,
                              color: SportsAppColors.cyan.withValues(alpha: 0.95),
                            ),
                          ),
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            m.homeTeamName,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: SportsAppColors.accentBlue900,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            'VS',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: SportsAppColors.textMuted,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            m.awayTeamName,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: SportsAppColors.accentBlue900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 18,
                          color: SportsAppColors.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            when,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: SportsAppColors.navy,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (m.venue != null && m.venue!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 18,
                            color: SportsAppColors.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              m.venue!.trim(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: SportsAppColors.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (m.notes != null && m.notes!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        m.notes!.trim(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: SportsAppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
