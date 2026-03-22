import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/api_config.dart';
import '../providers/auth_provider.dart';
import '../providers/location_provider.dart';
import '../theme/sports_app_theme.dart';
import '../widgets/sports_components.dart';

/// Organizer-only: create an event via `POST /events/me` (organizer from JWT).
class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _venueController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _contactController = TextEditingController();
  final _priceController = TextEditingController(text: '15');
  final _slotsController = TextEditingController(text: '10');
  final _oversController = TextEditingController(text: '20');
  final _ballsPerOverController = TextEditingController(text: '6');
  final _halfMinutesController = TextEditingController();
  final _quarterCountController = TextEditingController();
  final _quarterMinutesController = TextEditingController();
  final _setsToWinController = TextEditingController();
  final _gamesToWinController = TextEditingController();
  final _maxTotalPlayersController = TextEditingController();
  final _tournamentTeamsController = TextEditingController();

  /// Stored as `sport_type` on the API (matches home filter chips).
  static const _sports = <String>[
    'Cricket',
    'Football',
    'Basketball',
    'Volleyball',
    'Badminton',
  ];

  String _sport = 'Football';
  DateTime _start = DateTime.now().add(const Duration(hours: 2));
  int _durationMinutes = 90;
  String _ageGroup = 'Open';
  String _competitionFormat = 'knockout';
  bool _isTournament = true;
  DateTime _tournamentStartDate = DateTime.now();
  DateTime _tournamentEndDate = DateTime.now().add(const Duration(days: 1));
  /// `team` = players register in squads (football-style); `individual` = solo slots.
  String _registrationMode = 'team';
  /// `0` = draft, `1` = open (listed for players).
  int _status = 1;

  static const _durationOptions = <int>[
    30,
    45,
    60,
    75,
    90,
    120,
    150,
    180,
    240,
  ];

  /// Suggested match length by sport (ICC / FIFA / FIBA / FIVB / BWF–style norms for rec play).
  static int _defaultDurationMinutesForSport(String sport) {
    switch (sport) {
      case 'Cricket':
        return 180; // ~T20 block; use 240 for longer
      case 'Football':
        return 90; // two halves + buffer
      case 'Basketball':
        return 60; // typical gym slot
      case 'Volleyball':
        return 90; // best-of sets
      case 'Badminton':
        return 90; // best-of-3 games
      default:
        return 90;
    }
  }

  static const _ageGroups = <String>[
    'U8',
    'U10',
    'U12',
    'U14',
    'U15',
    'U17',
    'U19',
    'Open',
    '35+',
  ];

  static const _competitionFormatLabels = <String, String>{
    'knockout': 'Knockout',
    'league': 'League',
    'group_knockout': 'Group + knockout',
  };

  bool _submitting = false;
  String? _error;

  bool _isIndiaContext(BuildContext context, LocationProvider loc) {
    final countryCode = Localizations.localeOf(context).countryCode;
    if (countryCode != null && countryCode.toUpperCase() == 'IN') {
      return true;
    }
    final addr = loc.addressDisplay.toLowerCase();
    return addr.contains('india');
  }

  static IconData _iconForSport(String sport) {
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
        return Icons.sports_tennis_rounded;
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

  static String? _parseApiError(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      final d = m['detail'];
      if (d is String) {
        return d;
      }
      if (d is List && d.isNotEmpty) {
        final first = d.first;
        if (first is Map && first['msg'] != null) {
          return first['msg'] as String;
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _venueController.dispose();
    _descriptionController.dispose();
    _contactController.dispose();
    _priceController.dispose();
    _slotsController.dispose();
    _oversController.dispose();
    _ballsPerOverController.dispose();
    _halfMinutesController.dispose();
    _quarterCountController.dispose();
    _quarterMinutesController.dispose();
    _setsToWinController.dispose();
    _gamesToWinController.dispose();
    _maxTotalPlayersController.dispose();
    _tournamentTeamsController.dispose();
    super.dispose();
  }

  void _putPositiveInt(Map<String, dynamic> m, String key, String raw) {
    final t = raw.trim();
    if (t.isEmpty) {
      return;
    }
    final n = int.tryParse(t);
    if (n != null && n > 0) {
      m[key] = n;
    }
  }

  /// Sport-specific keys aligned with API `extra_config` (informational; not enforced server-side).
  Map<String, dynamic>? _extraConfigForSubmit() {
    final m = <String, dynamic>{};
    switch (_sport) {
      case 'Cricket':
        _putPositiveInt(m, 'overs', _oversController.text);
        _putPositiveInt(m, 'balls_per_over', _ballsPerOverController.text);
        break;
      case 'Football':
        _putPositiveInt(m, 'half_minutes', _halfMinutesController.text);
        break;
      case 'Basketball':
        _putPositiveInt(m, 'quarters', _quarterCountController.text);
        _putPositiveInt(m, 'quarter_minutes', _quarterMinutesController.text);
        break;
      case 'Volleyball':
        _putPositiveInt(m, 'sets_to_win', _setsToWinController.text);
        break;
      case 'Badminton':
        _putPositiveInt(m, 'games_to_win', _gamesToWinController.text);
        break;
      default:
        break;
    }
    _putPositiveInt(m, 'max_total_players', _maxTotalPlayersController.text);
    if (_isTournament && _registrationMode == 'team') {
      _putPositiveInt(m, 'total_teams', _tournamentTeamsController.text);
      m['tournament_start_date'] =
          DateFormat('yyyy-MM-dd').format(_tournamentStartDate);
      m['tournament_end_date'] = DateFormat('yyyy-MM-dd').format(_tournamentEndDate);
    }
    if (m.isEmpty) {
      return null;
    }
    return m;
  }

  Future<void> _pickTournamentDate({required bool isStart}) async {
    final now = DateTime.now();
    final current = isStart ? _tournamentStartDate : _tournamentEndDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: current.isBefore(now) ? now : current,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      if (isStart) {
        _tournamentStartDate = DateTime(selected.year, selected.month, selected.day);
        if (_tournamentEndDate.isBefore(_tournamentStartDate)) {
          _tournamentEndDate = _tournamentStartDate;
        }
      } else {
        _tournamentEndDate = DateTime(selected.year, selected.month, selected.day);
      }
    });
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _start.isBefore(now) ? now : _start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (time == null || !mounted) {
      return;
    }
    setState(() {
      _start = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  bool _validateStartInFuture() {
    final now = DateTime.now();
    if (_start.isBefore(now.subtract(const Duration(minutes: 1)))) {
      setState(() {
        _error = 'Start time must be in the future.';
      });
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (!_validateStartInFuture()) {
      return;
    }
    final auth = context.read<AuthProvider>();
    final loc = context.read<LocationProvider>();
    final title = _titleController.text.trim();
    final venue = _venueController.text.trim();
    final desc = _descriptionController.text.trim();
    final contact = _contactController.text.trim();
    final price = double.tryParse(_priceController.text.trim());
    final slots = int.tryParse(_slotsController.text.trim());
    if (price == null || slots == null || slots < 1) {
      setState(() => _error = 'Check price and capacity.');
      return;
    }
    if (_isTournament && _registrationMode == 'team') {
      final totalTeams = int.tryParse(_tournamentTeamsController.text.trim());
      if (totalTeams == null || totalTeams < 2) {
        setState(() => _error = 'Tournament requires at least 2 teams.');
        return;
      }
      if (_tournamentEndDate.isBefore(_tournamentStartDate)) {
        setState(() => _error = 'Tournament end date must be on/after start date.');
        return;
      }
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final uri = Uri.parse('${ApiConfig.baseUrl}/events/me');
    final body = <String, dynamic>{
      'title': title,
      'sport_type': _sport,
      'venue_name': venue,
      if (desc.isNotEmpty) 'description': desc,
      'duration_minutes': _durationMinutes,
      if (contact.isNotEmpty) 'contact_phone': contact,
      'lat': loc.effectiveLat,
      'long': loc.effectiveLng,
      'price': price,
      'max_slots': slots,
      'start_time': _start.toUtc().toIso8601String(),
      'status': _status,
      'age_group': _ageGroup,
      'competition_format': _competitionFormat,
      'registration_mode': _registrationMode,
    };
    final extra = _extraConfigForSubmit();
    if (extra != null) {
      body['extra_config'] = extra;
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
        setState(() {
          _error = _parseApiError(res.body) ??
              'Could not create event (HTTP ${res.statusCode}).';
          _submitting = false;
        });
        return;
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _submitting = false;
        });
      }
    }
  }

  InputDecoration _fieldDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: SportsAppColors.surfaceElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: SportsAppColors.border.withValues(alpha: 0.9)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: SportsAppColors.border.withValues(alpha: 0.9)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: SportsAppColors.cyan, width: 1),
      ),
    );
  }

  Widget _buildLocalRulesSection(ThemeData theme) {
    final sportRows = <Widget>[];
    switch (_sport) {
      case 'Cricket':
        sportRows.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _oversController,
                  keyboardType: TextInputType.number,
                  decoration: _fieldDecoration('Overs', hint: '20'),
                  validator: (v) {
                    final n = int.tryParse(v?.trim() ?? '');
                    if (n == null || n < 1) {
                      return 'Enter overs';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _ballsPerOverController,
                  keyboardType: TextInputType.number,
                  decoration: _fieldDecoration('Balls per over (play)', hint: '6'),
                  validator: (v) {
                    final n = int.tryParse(v?.trim() ?? '');
                    if (n == null || n < 1) {
                      return 'Enter balls';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
        );
        break;
      case 'Football':
        sportRows.add(
          TextFormField(
            controller: _halfMinutesController,
            keyboardType: TextInputType.number,
            decoration: _fieldDecoration(
              'Minutes per half (optional)',
              hint: '45',
            ),
          ),
        );
        break;
      case 'Basketball':
        sportRows.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _quarterCountController,
                  keyboardType: TextInputType.number,
                  decoration: _fieldDecoration('Quarters (optional)', hint: '4'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _quarterMinutesController,
                  keyboardType: TextInputType.number,
                  decoration: _fieldDecoration('Min / quarter (optional)', hint: '12'),
                ),
              ),
            ],
          ),
        );
        break;
      case 'Volleyball':
        sportRows.add(
          TextFormField(
            controller: _setsToWinController,
            keyboardType: TextInputType.number,
            decoration: _fieldDecoration(
              'Sets to win match (optional)',
              hint: '3',
            ),
          ),
        );
        break;
      case 'Badminton':
        sportRows.add(
          TextFormField(
            controller: _gamesToWinController,
            keyboardType: TextInputType.number,
            decoration: _fieldDecoration(
              'Games to win (optional)',
              hint: '2',
            ),
          ),
        );
        break;
      default:
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SportsSectionTitle(
          'Local match rules',
          bottomSpacing: 10,
          color: SportsAppColors.accentBlue900,
        ),
        Text(
          'Overs, squad caps, segment timing — optional; shown on the event page.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: SportsAppColors.textMuted,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        ...sportRows,
        if (sportRows.isNotEmpty) const SizedBox(height: 12),
        TextFormField(
          controller: _maxTotalPlayersController,
          keyboardType: TextInputType.number,
          decoration: _fieldDecoration(
            _sport == 'Cricket'
                ? 'Total number of players'
                : 'Total players cap (optional)',
            hint: _sport == 'Cricket' ? 'e.g. 22' : 'Across all squads / players',
          ),
          validator: _sport == 'Cricket'
              ? (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null || n < 1) {
                    return 'Enter total players';
                  }
                  return null;
                }
              : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = context.watch<LocationProvider>();
    final isIndia = _isIndiaContext(context, loc);
    final startLabel = DateFormat('EEE, MMM d, y · HH:mm').format(_start);
    final locLoading = loc.loading;

    return Scaffold(
      backgroundColor: SportsAppColors.pageBackground,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Create event'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SportsBackground(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                const SportsSectionTitle(
                  'Location',
                  bottomSpacing: 10,
                  color: SportsAppColors.accentBlue900,
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  decoration: sportsCardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: SportsAppColors.cyan.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.location_on_rounded,
                              color: SportsAppColors.cyan,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SelectionArea(
                                  child: Text(
                                    loc.addressDisplay,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: SportsAppColors.textMuted,
                                      fontWeight: FontWeight.w600,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: locLoading
                            ? null
                            : () async {
                                await loc.refreshFromDevice();
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      loc.errorMessage != null &&
                                              loc.errorMessage!.isNotEmpty
                                          ? loc.errorMessage!
                                          : 'Location updated',
                                    ),
                                  ),
                                );
                              },
                        icon: locLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location_rounded, size: 20),
                        label: Text(
                          locLoading ? 'Getting fix…' : 'Refresh from device',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: SportsAppColors.cyan,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const SportsSectionTitle(
                  'Sport',
                  bottomSpacing: 10,
                  color: SportsAppColors.accentBlue900,
                ),
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _sports.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final s = _sports[i];
                      final sel = _sport == s;
                      return SportsCategoryBubble(
                        icon: _iconForSport(s),
                        label: s,
                        selected: sel,
                        width: 86,
                        iconSize: 24,
                        verticalPadding: 8,
                        onTap: () => setState(() {
                          _sport = s;
                          _durationMinutes = _defaultDurationMinutesForSport(s);
                          _registrationMode = 'team';
                        }),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                const SportsSectionTitle(
                  'Details',
                  bottomSpacing: 10,
                  color: SportsAppColors.accentBlue900,
                ),
                TextFormField(
                  controller: _titleController,
                  textCapitalization: TextCapitalization.words,
                  decoration: _fieldDecoration('Event title'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a title' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _venueController,
                  textCapitalization: TextCapitalization.words,
                  decoration: _fieldDecoration('Venue / meeting point'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty)
                          ? 'Enter where players meet'
                          : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 5,
                  minLines: 3,
                  decoration: _fieldDecoration(
                    'Description (optional)',
                    hint:
                        'Pitch/court number, equipment, fees, parking — expand on rules above.',
                  ),
                ),
                const SizedBox(height: 14),
                Material(
                  color: SportsAppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: _pickStart,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: SportsAppColors.cyan.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.event_rounded,
                              color: SportsAppColors.cyan,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Start time',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: SportsAppColors.textMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  startLabel,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: SportsAppColors.textPrimary,
                                  ),
                                ),
                              ],
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
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _fieldDecoration(
                          isIndia ? 'Price (₹)' : 'Price (\$)',
                          hint: isIndia ? '0 (INR)' : '0 (USD)',
                        ),
                        validator: (v) {
                          final p = double.tryParse(v?.trim() ?? '');
                          if (p == null || p < 0) {
                            return 'Valid amount';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _slotsController,
                        keyboardType: TextInputType.number,
                        decoration: _fieldDecoration(
                          _registrationMode == 'team'
                              ? 'Max teams (squads)'
                              : 'Max players',
                          hint: '10',
                        ),
                        validator: (v) {
                          final n = int.tryParse(v?.trim() ?? '');
                          if (n == null || n < 1) {
                            return 'Min 1';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildLocalRulesSection(theme),
                const SizedBox(height: 14),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Team / squad registration'),
                  subtitle: const Text(
                    'On by default — players join as squads. Turn off for solo spots.',
                  ),
                  value: _registrationMode == 'team',
                  onChanged: (on) => setState(() {
                    if (on) {
                      _registrationMode = 'team';
                    } else {
                      _registrationMode = 'individual';
                      _isTournament = false;
                    }
                  }),
                ),
                const SizedBox(height: 8),
                if (_registrationMode == 'team')
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tournament event'),
                    subtitle: const Text(
                      'On by default for squad events — start/end dates and total teams',
                    ),
                    value: _isTournament,
                    onChanged: (v) => setState(() => _isTournament = v),
                  ),
                if (_registrationMode == 'team' && _isTournament) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _tournamentTeamsController,
                    keyboardType: TextInputType.number,
                    decoration: _fieldDecoration('Total teams', hint: 'e.g. 10'),
                    validator: (v) {
                      final n = int.tryParse(v?.trim() ?? '');
                      if (_registrationMode == 'team' &&
                          _isTournament &&
                          (n == null || n < 2)) {
                        return 'Min 2 teams';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: SportsAppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            onTap: () => _pickTournamentDate(isStart: true),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Text(
                                'Tournament start: ${DateFormat('dd MMM y').format(_tournamentStartDate)}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Material(
                          color: SportsAppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            onTap: () => _pickTournamentDate(isStart: false),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Text(
                                'Tournament end: ${DateFormat('dd MMM y').format(_tournamentEndDate)}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Builder(
                    builder: (_) {
                      final teams = int.tryParse(_tournamentTeamsController.text.trim());
                      if (teams != 10) {
                        return const SizedBox.shrink();
                      }
                      final note = _competitionFormat == 'league'
                          ? '10-team league typically schedules 45 matches (single round-robin).'
                          : '10-team knockout typically needs 9 matches, with 6 first-round byes.';
                      return Text(
                        note,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: SportsAppColors.textMuted,
                          height: 1.3,
                        ),
                      );
                    },
                  ),
                ],
                if (_sport != 'Cricket') ...[
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: InputDecorator(
                          decoration: _fieldDecoration('Duration'),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: _durationMinutes,
                              isExpanded: true,
                              items: _durationOptions
                                  .map(
                                    (m) => DropdownMenuItem<int>(
                                      value: m,
                                      child: Text('$m min'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(
                                () => _durationMinutes = v ?? 90,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                const SportsSectionTitle(
                  'Age & format',
                  bottomSpacing: 10,
                  color: SportsAppColors.accentBlue900,
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: InputDecorator(
                        decoration: _fieldDecoration('Age group'),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _ageGroup,
                            isExpanded: true,
                            items: _ageGroups
                                .map(
                                  (a) => DropdownMenuItem<String>(
                                    value: a,
                                    child: Text(a),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _ageGroup = v ?? 'Open'),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InputDecorator(
                        decoration: _fieldDecoration('Competition'),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _competitionFormat,
                            isExpanded: true,
                            items: _competitionFormatLabels.entries
                                .map(
                                  (e) => DropdownMenuItem<String>(
                                    value: e.key,
                                    child: Text(e.value),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(
                              () => _competitionFormat = v ?? 'knockout',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _contactController,
                  keyboardType: TextInputType.phone,
                  decoration: _fieldDecoration(
                    'Contact phone (optional)',
                    hint: 'For day-of coordination',
                  ),
                ),
                const SizedBox(height: 18),
                const SportsSectionTitle(
                  'Visibility',
                  bottomSpacing: 10,
                  color: SportsAppColors.accentBlue900,
                ),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment<int>(
                      value: 1,
                      label: Text('Open'),
                      icon: Icon(Icons.public_rounded, size: 18),
                    ),
                    ButtonSegment<int>(
                      value: 0,
                      label: Text('Draft'),
                      icon: Icon(Icons.edit_note_rounded, size: 18),
                    ),
                  ],
                  selected: {_status},
                  onSelectionChanged: (set) =>
                      setState(() => _status = set.first),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.comfortable,
                    side: const WidgetStatePropertyAll(
                      BorderSide(color: SportsAppColors.border),
                    ),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return SportsAppColors.cyan;
                      }
                      return SportsAppColors.card;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return Colors.white;
                      }
                      return SportsAppColors.textMuted;
                    }),
                    iconColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return Colors.white;
                      }
                      return SportsAppColors.textMuted;
                    }),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: SportsAppColors.liveRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: SportsAppColors.liveRed.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: SportsAppColors.liveRed,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _error!,
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
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: SportsAppColors.navy,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(60),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 18,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _status == 0 ? 'Save as draft' : 'Publish event',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
