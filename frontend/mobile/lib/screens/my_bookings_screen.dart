import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/api_config.dart';
import '../models/my_booking.dart';
import '../providers/auth_provider.dart';
import '../theme/sports_app_theme.dart';
import 'event_detail_screen.dart';

/// Lists matches the signed-in **player** has booked (`GET /me/bookings`).
class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  List<MyBooking>? _items;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn || auth.user == null) {
      setState(() {
        _loading = false;
        _error = 'Sign in to see your bookings.';
      });
      return;
    }
    if (auth.user!.isOrganizer) {
      setState(() {
        _loading = false;
        _items = [];
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final uri = Uri.parse('${ApiConfig.baseUrl}/me/bookings');
    try {
      final res = await http.get(uri, headers: auth.authHeaders());
      if (!mounted) {
        return;
      }
      if (res.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = 'Could not load bookings (${res.statusCode}).';
          _items = null;
        });
        return;
      }
      final list = jsonDecode(res.body) as List<dynamic>;
      setState(() {
        _loading = false;
        _items = list
            .map((e) => MyBooking.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
          _items = null;
        });
      }
    }
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
      case 'tennis':
        return Icons.sports_tennis_rounded;
      default:
        return Icons.sports_rounded;
    }
  }

  static (String, Color) _statusBadge(int status) {
    switch (status) {
      case 0:
        return ('Draft', SportsAppColors.textMuted);
      case 1:
        return ('Open', SportsAppColors.cyan);
      case 2:
        return ('Full', SportsAppColors.accentWarm);
      case 3:
        return ('Live', SportsAppColors.liveRed);
      case 4:
        return ('Done', SportsAppColors.textMuted);
      default:
        return ('—', SportsAppColors.textMuted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final isOrganizer = auth.user?.isOrganizer ?? false;

    return Scaffold(
      backgroundColor: SportsAppColors.pageBackground,
      appBar: AppBar(
        title: Text(
          'My bookings',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
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
      body: RefreshIndicator(
        color: SportsAppColors.navy,
        onRefresh: _load,
        child: _buildBody(theme, isOrganizer),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, bool isOrganizer) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: SportsAppColors.navy),
      );
    }

    if (isOrganizer) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Text(
            'Organizer accounts manage events instead of player bookings.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: SportsAppColors.textMuted,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Use My events in the bottom bar to see matches you host.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: SportsAppColors.accentBlue900,
              fontWeight: FontWeight.w600,
            ),
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

    final items = _items ?? [];
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 48, 20, 32),
        children: [
          Icon(
            Icons.event_available_outlined,
            size: 56,
            color: SportsAppColors.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No bookings yet',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: SportsAppColors.accentBlue900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Browse nearby matches on the home screen and join one you like.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: SportsAppColors.textMuted,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final b = items[i];
        final e = b.event;
        final start = DateFormat('EEE d MMM · HH:mm').format(e.startTime.toLocal());
        final (statusLabel, statusColor) = _statusBadge(e.status);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => EventDetailScreen(event: e),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              decoration: sportsCardDecoration(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: SportsAppColors.cyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _iconForSport(e.sportType),
                      color: SportsAppColors.cyan,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: SportsAppColors.accentBlue900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${e.sportType} · ${e.venueName}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: SportsAppColors.textMuted,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          start,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: SportsAppColors.navy,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (b.teamName != null && b.teamName!.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Squad: ${b.teamName}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: SportsAppColors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                statusLabel,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: statusColor,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Payment: ${b.paymentStatus}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: SportsAppColors.textMuted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: SportsAppColors.textMuted.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
