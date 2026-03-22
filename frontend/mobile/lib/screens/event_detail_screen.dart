import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/api_config.dart';
import '../models/sport_event.dart';
import '../providers/auth_provider.dart';
import '../theme/sports_app_theme.dart';
import '../utils/reverse_geocode.dart';
import '../widgets/sports_components.dart';

String _skillLevelDisplay(String key) {
  switch (key.toLowerCase()) {
    case 'all':
      return 'All levels';
    case 'beginner':
      return 'Beginner';
    case 'intermediate':
      return 'Intermediate';
    case 'advanced':
      return 'Advanced';
    case 'competitive':
      return 'Competitive';
    default:
      return key;
  }
}

String _competitionFormatLabel(String key) {
  switch (key.toLowerCase()) {
    case 'knockout':
      return 'Knockout';
    case 'league':
      return 'League';
    case 'group_knockout':
      return 'Group + knockout';
    default:
      return key;
  }
}

/// Organizer `extra_config` keys shown in a fixed order (matches create-event screen).
Iterable<Widget> _extraLocalRuleRows(SportEvent event) sync* {
  final x = event.extraConfig;
  if (x == null || x.isEmpty) {
    return;
  }
  const order = <(String, String)>[
    ('overs', 'Overs'),
    ('balls_per_over', 'Balls per over'),
    ('max_total_players', 'Total player cap'),
    ('half_minutes', 'Minutes per half'),
    ('quarters', 'Quarters'),
    ('quarter_minutes', 'Minutes per quarter'),
    ('sets_to_win', 'Sets to win'),
    ('games_to_win', 'Games to win'),
  ];
  for (final e in order) {
    final v = x[e.$1];
    if (v == null) {
      continue;
    }
    yield _FactRow(
      icon: Icons.tune_rounded,
      iconBg: SportsAppColors.cyan.withValues(alpha: 0.12),
      label: e.$2,
      value: v.toString(),
    );
    yield Divider(
      height: 1,
      indent: 58,
      color: SportsAppColors.border.withValues(alpha: 0.9),
    );
  }
}

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({super.key, required this.event});

  final SportEvent event;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  late SportEvent _event = widget.event;
  bool _booking = false;

  String _statusLabel(int s) {
    switch (s) {
      case 0:
        return 'Draft';
      case 1:
        return 'Open';
      case 2:
        return 'Full';
      case 3:
        return 'Live';
      case 4:
        return 'Completed';
      default:
        return 'Unknown';
    }
  }

  Color _statusColor(int s) {
    switch (s) {
      case 3:
        return SportsAppColors.liveRed;
      case 1:
        return SportsAppColors.cyan;
      case 2:
        return SportsAppColors.accentWarm;
      default:
        return SportsAppColors.textMuted;
    }
  }

  IconData _iconForSport(String sport) {
    switch (sport.toLowerCase()) {
      case 'cricket':
        return Icons.sports_cricket;
      case 'football':
      case 'soccer':
        return Icons.sports_soccer_rounded;
      case 'basketball':
        return Icons.sports_basketball_rounded;
      case 'volleyball':
        return Icons.sports_volleyball_rounded;
      case 'badminton':
      case 'tennis':
        return Icons.sports_tennis_rounded;
      case 'baseball':
        return Icons.sports_baseball_rounded;
      case 'hockey':
        return Icons.sports_hockey_rounded;
      default:
        return Icons.sports_rounded;
    }
  }

  String _slotsLine(SportEvent e) {
    if (e.isFull) return 'Fully booked';
    final r = e.remainingSlots;
    final unit = e.registrationMode == 'team' ? 'team slot' : 'spot';
    return '$r $unit${r == 1 ? '' : 's'} available';
  }

  Future<void> _reloadEvent() async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/events/${_event.id}');
    try {
      final res = await http.get(uri);
      if (!mounted || res.statusCode != 200) {
        return;
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() => _event = SportEvent.fromJson(map));
    } catch (_) {}
  }

  Future<void> _onBookPressed() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in as a player to book.')),
      );
      return;
    }
    if (auth.user?.role != 'player') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only players can book matches.')),
      );
      return;
    }

    String? teamName;
    int? joinTeamId;

    if (_event.registrationMode == 'team') {
      final squadCtrl = TextEditingController();
      final joinCtrl = TextEditingController();
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: SportsAppColors.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Register your squad',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: SportsAppColors.accentBlue900,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create a new squad name, or enter your captain’s squad ID to join.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: SportsAppColors.textMuted,
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: squadCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'New squad name',
                    hintText: 'e.g. Silchar Youth FC',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: joinCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Or join squad ID',
                    hintText: 'Number from your captain',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: SportsAppColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Continue'),
                ),
              ],
            ),
          );
        },
      );
      teamName = squadCtrl.text.trim().isEmpty ? null : squadCtrl.text.trim();
      final joinRaw = joinCtrl.text.trim();
      if (joinRaw.isNotEmpty) {
        joinTeamId = int.tryParse(joinRaw);
      }
      squadCtrl.dispose();
      joinCtrl.dispose();
      if (ok != true || !mounted) {
        return;
      }
      if (joinTeamId == null &&
          (teamName == null || teamName.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter a squad name or a squad ID to join.'),
          ),
        );
        return;
      }
      if (joinTeamId != null && joinTeamId < 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Squad ID must be a positive number.')),
        );
        return;
      }
    }

    setState(() => _booking = true);
    final uri = Uri.parse('${ApiConfig.baseUrl}/events/${_event.id}/bookings/me');
    final body = <String, dynamic>{};
    if (_event.registrationMode == 'team') {
      if (joinTeamId != null) {
        body['join_team_id'] = joinTeamId;
        if (teamName != null && teamName.isNotEmpty) {
          body['team_name'] = teamName;
        }
      } else {
        body['team_name'] = teamName;
      }
    }

    try {
      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          ...auth.authHeaders(),
        },
        body: jsonEncode(body),
      );
      if (!mounted) {
        return;
      }
      if (res.statusCode != 200) {
        String msg = 'Could not book (${res.statusCode}).';
        try {
          final m = jsonDecode(res.body) as Map<String, dynamic>;
          final d = m['detail'];
          if (d is String) {
            msg = d;
          }
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }
      await _reloadEvent();
      if (!mounted) {
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tid = data['team_id'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tid != null
                ? 'You’re in! Your squad ID is $tid (share it with teammates).'
                : 'You’re booked.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _booking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final local = _event.startTime.toLocal();
    final dateLine = DateFormat('EEEE, MMMM d, y').format(local);
    final timeLine = DateFormat('h:mm a').format(local);
    final statusColor = _statusColor(_event.status);

    return Scaffold(
      backgroundColor: SportsAppColors.pageBackground,
      appBar: AppBar(
        title: Text(
          'Match',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            fontSize: 17,
            letterSpacing: -0.2,
            color: SportsAppColors.accentBlue900,
          ),
        ),
        centerTitle: true,
        backgroundColor: SportsAppColors.pageBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: SportsAppColors.border.withValues(alpha: 0.85),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SportsBackground(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _EventHeroCard(
                      event: _event,
                      statusLabel: _statusLabel(_event.status),
                      statusColor: statusColor,
                      sportIcon: _iconForSport(_event.sportType),
                    ),
                    const SizedBox(height: 14),
                    _TournamentChipsRow(
                      ageGroup: _event.ageGroup,
                      formatLabel: _competitionFormatLabel(_event.competitionFormat),
                      teamEntries: _event.registrationMode == 'team',
                    ),
                    const SizedBox(height: 20),
                    const SportsSectionTitle(
                      'Details',
                      bottomSpacing: 12,
                      color: SportsAppColors.accentBlue900,
                    ),
                    _EventFactsCard(
                      event: _event,
                      dateLine: dateLine,
                      timeLine: timeLine,
                      slotsSummary: _slotsLine(_event),
                    ),
                    if (_event.description != null &&
                        _event.description!.trim().isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const SportsSectionTitle(
                        'About this game',
                        bottomSpacing: 12,
                        color: SportsAppColors.accentBlue900,
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: sportsCardDecoration(),
                        child: Text(
                          _event.description!.trim(),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: SportsAppColors.textPrimary,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 88),
                  ],
                ),
              ),
            ),
          ),
          _EventDetailCtaBar(
            event: _event,
            booking: _booking,
            onBook: _onBookPressed,
            onWaitlist: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Waitlist flow not wired in this demo.'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TournamentChipsRow extends StatelessWidget {
  const _TournamentChipsRow({
    required this.ageGroup,
    required this.formatLabel,
    required this.teamEntries,
  });

  final String ageGroup;
  final String formatLabel;
  final bool teamEntries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget chip(IconData icon, String label) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: SportsAppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: SportsAppColors.border.withValues(alpha: 0.85),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: SportsAppColors.cyan),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: SportsAppColors.accentBlue900,
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip(Icons.cake_outlined, 'Age $ageGroup'),
        chip(Icons.emoji_events_outlined, formatLabel),
        chip(
          Icons.how_to_reg_outlined,
          teamEntries ? 'Team entries' : 'Individual spots',
        ),
      ],
    );
  }
}

class _EventHeroCard extends StatelessWidget {
  const _EventHeroCard({
    required this.event,
    required this.statusLabel,
    required this.statusColor,
    required this.sportIcon,
  });

  final SportEvent event;
  final String statusLabel;
  final Color statusColor;
  final IconData sportIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const radius = 24.0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: SportsAppColors.navy.withValues(alpha: 0.09),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color: SportsAppColors.border.withValues(alpha: 0.9),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                right: -20,
                bottom: -32,
                child: Icon(
                  sportIcon,
                  size: 148,
                  color: SportsAppColors.cyan.withValues(alpha: 0.1),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          statusLabel.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.9,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      event.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: SportsAppColors.textPrimary,
                        height: 1.15,
                        letterSpacing: -0.4,
                      ),
                    ),
                    if (event.venueName.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 18,
                            color: SportsAppColors.cyan,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              event.venueName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: SportsAppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.sports_rounded,
                          size: 18,
                          color: SportsAppColors.cyan,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          event.sportType,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: SportsAppColors.accentBlue800,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reverse-geocodes event coordinates — never shows raw lat/lng.
class _MapAddressRow extends StatefulWidget {
  const _MapAddressRow({required this.lat, required this.lng});

  final double lat;
  final double lng;

  @override
  State<_MapAddressRow> createState() => _MapAddressRowState();
}

class _MapAddressRowState extends State<_MapAddressRow> {
  late final Future<String?> _future =
      reverseGeocode(widget.lat, widget.lng);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<String?>(
      future: _future,
          builder: (context, snapshot) {
        final loading =
            snapshot.connectionState == ConnectionState.waiting;
        if (snapshot.hasError) {
          debugPrint(
            '[Geocode] event detail map row error: ${snapshot.error}',
          );
        }
        final addr = snapshot.data;
        final value = loading
            ? 'Loading address…'
            : (addr != null && addr.isNotEmpty
                ? addr
                : 'Address unavailable');

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: SportsAppColors.cyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.map_outlined,
                  color: SportsAppColors.accentBlue800,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LOCATION',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: SportsAppColors.textMuted,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: SportsAppColors.textPrimary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EventFactsCard extends StatelessWidget {
  const _EventFactsCard({
    required this.event,
    required this.dateLine,
    required this.timeLine,
    required this.slotsSummary,
  });

  final SportEvent event;
  final String dateLine;
  final String timeLine;
  final String slotsSummary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fillRatio = event.maxSlots > 0
        ? event.bookedSlots / event.maxSlots
        : 0.0;

    return Container(
      decoration: sportsCardDecoration(),
      child: Column(
        children: [
          _FactRow(
            icon: Icons.event_rounded,
            iconBg: SportsAppColors.cyan.withValues(alpha: 0.12),
            label: 'Date',
            value: dateLine,
          ),
          Divider(
            height: 1,
            indent: 58,
            color: SportsAppColors.border.withValues(alpha: 0.9),
          ),
          _FactRow(
            icon: Icons.schedule_rounded,
            iconBg: SportsAppColors.cyan.withValues(alpha: 0.12),
            label: 'Time',
            value: timeLine,
          ),
          Divider(
            height: 1,
            indent: 58,
            color: SportsAppColors.border.withValues(alpha: 0.9),
          ),
          _MapAddressRow(lat: event.lat, lng: event.long),
          Divider(
            height: 1,
            indent: 58,
            color: SportsAppColors.border.withValues(alpha: 0.9),
          ),
          _FactRow(
            icon: Icons.timer_outlined,
            iconBg: SportsAppColors.cyan.withValues(alpha: 0.12),
            label: 'Duration',
            value: '${event.durationMinutes} min',
          ),
          Divider(
            height: 1,
            indent: 58,
            color: SportsAppColors.border.withValues(alpha: 0.9),
          ),
          ..._extraLocalRuleRows(event),
          if (event.skillLevel != null && event.skillLevel!.isNotEmpty)
            _FactRow(
              icon: Icons.signal_cellular_alt_rounded,
              iconBg: SportsAppColors.cyan.withValues(alpha: 0.12),
              label: 'Level',
              value: _skillLevelDisplay(event.skillLevel!),
            ),
          if (event.skillLevel != null && event.skillLevel!.isNotEmpty)
            Divider(
              height: 1,
              indent: 58,
              color: SportsAppColors.border.withValues(alpha: 0.9),
            ),
          if (event.contactPhone != null && event.contactPhone!.trim().isNotEmpty)
            _FactRow(
              icon: Icons.phone_outlined,
              iconBg: SportsAppColors.cyan.withValues(alpha: 0.12),
              label: 'Contact',
              value: event.contactPhone!.trim(),
            ),
          if (event.contactPhone != null && event.contactPhone!.trim().isNotEmpty)
            Divider(
              height: 1,
              indent: 58,
              color: SportsAppColors.border.withValues(alpha: 0.9),
            ),
          _FactRow(
            icon: Icons.payments_rounded,
            iconBg: SportsAppColors.cyan.withValues(alpha: 0.12),
            label: 'Price',
            value: '\$${event.price.toStringAsFixed(2)}',
            valueStyle: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: SportsAppColors.accentBlue900,
            ),
          ),
          Divider(
            height: 1,
            indent: 58,
            color: SportsAppColors.border.withValues(alpha: 0.9),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: SportsAppColors.cyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.groups_rounded,
                    color: SportsAppColors.accentBlue800,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AVAILABILITY',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: SportsAppColors.textMuted,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.9,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: fillRatio.clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: SportsAppColors.border.withValues(
                            alpha: 0.65,
                          ),
                          color: event.isFull
                              ? SportsAppColors.accentWarm
                              : SportsAppColors.cyan,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        slotsSummary,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: SportsAppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${event.bookedSlots} booked · ${event.maxSlots} total',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: SportsAppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.icon,
    required this.iconBg,
    required this.label,
    required this.value,
    this.valueStyle,
  });

  final IconData icon;
  final Color iconBg;
  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: SportsAppColors.accentBlue800, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: SportsAppColors.textMuted,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: valueStyle ??
                      theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: SportsAppColors.textPrimary,
                        height: 1.25,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventDetailCtaBar extends StatelessWidget {
  const _EventDetailCtaBar({
    required this.event,
    required this.booking,
    required this.onBook,
    required this.onWaitlist,
  });

  final SportEvent event;
  final bool booking;
  final VoidCallback onBook;
  final VoidCallback onWaitlist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 12,
      shadowColor: SportsAppColors.navy.withValues(alpha: 0.12),
      color: SportsAppColors.card,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (event.status == 1)
                FilledButton(
                  onPressed: (event.isFull || booking) ? null : onBook,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    minimumSize: const Size(double.infinity, 56),
                    backgroundColor: SportsAppColors.navy,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: SportsAppColors.textMuted.withValues(
                      alpha: 0.35,
                    ),
                    disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: booking
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          event.isFull ? 'Sold out' : 'Book now',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                            color: Colors.white,
                          ),
                        ),
                ),
              if (event.status == 2)
                FilledButton.tonal(
                  onPressed: onWaitlist,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    minimumSize: const Size(double.infinity, 56),
                    backgroundColor: SportsAppColors.accentWarm.withValues(
                      alpha: 0.14,
                    ),
                    foregroundColor: SportsAppColors.accentWarm,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Join waitlist',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              if (event.status != 1 && event.status != 2)
                Text(
                  _inactiveCtaMessage(event.status),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: SportsAppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _inactiveCtaMessage(int status) {
    switch (status) {
      case 0:
        return 'This match is not open for booking yet.';
      case 3:
        return 'This match is live — check with the organizer.';
      case 4:
        return 'This match has ended.';
      default:
        return 'Booking is unavailable.';
    }
  }
}
