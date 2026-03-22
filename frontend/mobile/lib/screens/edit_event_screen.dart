import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/api_config.dart';
import '../models/sport_event.dart';
import '../providers/auth_provider.dart';
import '../theme/sports_app_theme.dart';
import '../widgets/sports_components.dart';

/// Owner-only: PATCH `/events/{id}/organizer` — join fee, registration, match time, prizes.
class EditEventScreen extends StatefulWidget {
  const EditEventScreen({super.key, required this.event});

  final SportEvent event;

  @override
  State<EditEventScreen> createState() => _EditEventScreenState();
}

class _EditEventScreenState extends State<EditEventScreen> {
  late DateTime _registrationStart;
  late DateTime _registrationEnd;
  late DateTime _matchStart;
  late final TextEditingController _feeController;
  late final TextEditingController _prizeFirstController;
  late final TextEditingController _prizeRunnerUpController;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    final now = DateTime.now();
    _registrationStart = e.registrationStart ?? now;
    _registrationEnd = e.registrationEnd ?? now.add(const Duration(days: 1));
    _matchStart = e.startTime;
    _feeController = TextEditingController(text: e.price.toString());
    final x = e.extraConfig;
    _prizeFirstController = TextEditingController(
      text: x != null && x['prize_first_inr'] != null
          ? _numStr(x['prize_first_inr'])
          : '',
    );
    _prizeRunnerUpController = TextEditingController(
      text: x != null && x['prize_runner_up_inr'] != null
          ? _numStr(x['prize_runner_up_inr'])
          : '',
    );
  }

  static String _numStr(dynamic v) {
    if (v is num) {
      return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    }
    return v.toString();
  }

  @override
  void dispose() {
    _feeController.dispose();
    _prizeFirstController.dispose();
    _prizeRunnerUpController.dispose();
    super.dispose();
  }

  Future<void> _pickRegistration({required bool isStart}) async {
    final current = isStart ? _registrationStart : _registrationEnd;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) {
      return;
    }
    setState(() {
      final next = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (isStart) {
        _registrationStart = next;
        if (!_registrationEnd.isAfter(_registrationStart)) {
          _registrationEnd = _registrationStart.add(const Duration(hours: 1));
        }
      } else {
        _registrationEnd = next;
        if (!_registrationEnd.isAfter(_registrationStart)) {
          _registrationStart = _registrationEnd.subtract(const Duration(hours: 1));
        }
      }
      if (!_matchStart.isAfter(_registrationEnd)) {
        _matchStart = _registrationEnd.add(const Duration(hours: 1));
      }
    });
  }

  Future<void> _pickMatchStart() async {
    final current =
        _matchStart.isAfter(_registrationEnd) ? _matchStart : _registrationEnd.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) {
      return;
    }
    setState(() {
      _matchStart = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (!_matchStart.isAfter(_registrationEnd)) {
        _matchStart = _registrationEnd.add(const Duration(minutes: 1));
      }
    });
  }

  InputDecoration _decoration(String label, {String? hint}) {
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

  Widget _dateTile({
    required ThemeData theme,
    required String label,
    required DateTime at,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final valueLabel = DateFormat('EEE, MMM d, y · HH:mm').format(at);
    return Material(
      color: SportsAppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: SportsAppColors.cyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: SportsAppColors.cyan, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: SportsAppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      valueLabel,
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
    );
  }

  Future<void> _save() async {
    final fee = double.tryParse(_feeController.text.trim());
    if (fee == null || fee < 0) {
      setState(() => _error = 'Enter a valid join fee.');
      return;
    }
    if (!_registrationEnd.isAfter(_registrationStart)) {
      setState(() => _error = 'Registration must close after it opens.');
      return;
    }
    if (!_matchStart.isAfter(_registrationEnd)) {
      setState(() => _error = 'Match start must be after registration closes.');
      return;
    }

    final auth = context.read<AuthProvider>();
    final pf = double.tryParse(_prizeFirstController.text.trim());
    final pr = double.tryParse(_prizeRunnerUpController.text.trim());
    final mergedExtra = Map<String, dynamic>.from(widget.event.extraConfig ?? {});
    if (pf != null && pf > 0) {
      mergedExtra['prize_first_inr'] = pf;
    } else {
      mergedExtra.remove('prize_first_inr');
    }
    if (pr != null && pr > 0) {
      mergedExtra['prize_runner_up_inr'] = pr;
    } else {
      mergedExtra.remove('prize_runner_up_inr');
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/events/${widget.event.id}/organizer',
    );
    final body = <String, dynamic>{
      'price': fee,
      'registration_start': _registrationStart.toUtc().toIso8601String(),
      'registration_end': _registrationEnd.toUtc().toIso8601String(),
      'start_time': _matchStart.toUtc().toIso8601String(),
      'extra_config': mergedExtra,
    };

    try {
      final res = await http.patch(
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
          _saving = false;
          _error = 'Could not save (${res.statusCode}).';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: SportsAppColors.pageBackground,
      appBar: AppBar(
        title: const Text('Edit event'),
        backgroundColor: SportsAppColors.pageBackground,
        surfaceTintColor: Colors.transparent,
      ),
      body: SportsBackground(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            Text(
              widget.event.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: SportsAppColors.accentBlue900,
              ),
            ),
            const SizedBox(height: 20),
            const SportsSectionTitle(
              'Registration & match',
              bottomSpacing: 10,
              color: SportsAppColors.accentBlue900,
            ),
            _dateTile(
              theme: theme,
              label: 'Registration opens',
              at: _registrationStart,
              icon: Icons.how_to_reg_rounded,
              onTap: () => _pickRegistration(isStart: true),
            ),
            const SizedBox(height: 12),
            _dateTile(
              theme: theme,
              label: 'Registration closes',
              at: _registrationEnd,
              icon: Icons.event_busy_rounded,
              onTap: () => _pickRegistration(isStart: false),
            ),
            const SizedBox(height: 12),
            _dateTile(
              theme: theme,
              label: 'Match starts',
              at: _matchStart,
              icon: Icons.play_circle_outline_rounded,
              onTap: _pickMatchStart,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _feeController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _decoration('Join fee (₹)'),
            ),
            const SizedBox(height: 20),
            const SportsSectionTitle(
              'Prize money (₹)',
              bottomSpacing: 10,
              color: SportsAppColors.accentBlue900,
            ),
            Text(
              'Set to 0 or clear to remove a prize from the listing.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: SportsAppColors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _prizeFirstController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: _decoration('Champion (1st)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _prizeRunnerUpController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: _decoration('Runner-up (2nd)'),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: SportsAppColors.accentWarm,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: SportsAppColors.navy,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(54),
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
                  : const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}
