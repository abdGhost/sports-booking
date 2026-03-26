import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/sport_event.dart';
import '../providers/auth_provider.dart';
import '../providers/event_provider.dart';
import '../providers/location_provider.dart';
import '../theme/sports_app_theme.dart';
import 'create_event_screen.dart';
import 'event_detail_screen.dart';

/// Lists events created by the signed-in organizer (`GET /events/me`).
class OrganizerEventsScreen extends StatefulWidget {
  const OrganizerEventsScreen({super.key});

  @override
  State<OrganizerEventsScreen> createState() => _OrganizerEventsScreenState();
}

class _OrganizerEventsScreenState extends State<OrganizerEventsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    await context.read<EventProvider>().fetchMyEvents(auth.authHeaders());
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const CreateEventScreen(),
      ),
    );
    if (created == true && mounted) {
      await _load();
      // Keep Home feed fresh too: new event should appear in nearby cards.
      if (!mounted) {
        return;
      }
      final loc = context.read<LocationProvider>();
      await context.read<EventProvider>().fetchNearbyEvents(
        loc.effectiveLat,
        loc.effectiveLng,
      );
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

  /// Matches primary actions on [CreateEventScreen] (publish / save draft).
  static ButtonStyle _createPrimaryButtonStyle() {
    return FilledButton.styleFrom(
      backgroundColor: SportsAppColors.navy,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(60),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: SportsAppColors.pageBackground,
      appBar: AppBar(
        title: Text(
          'My events',
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
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton.icon(
            onPressed: _openCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              'Create event',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            style: _createPrimaryButtonStyle(),
          ),
        ),
      ),
      body: SportsBackground(
        child: Consumer<EventProvider>(
          builder: (context, ev, _) {
            if (ev.myEventsLoading && ev.myEvents.isEmpty) {
              return const Center(
                child: CircularProgressIndicator(color: SportsAppColors.cyan),
              );
            }

            if (ev.myEventsError != null && ev.myEvents.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.cloud_off_outlined,
                        size: 48,
                        color: SportsAppColors.textMuted.withValues(alpha: 0.8),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        ev.myEventsError!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: SportsAppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try again'),
                        style: _createPrimaryButtonStyle(),
                      ),
                    ],
                  ),
                ),
              );
            }

            if (ev.myEvents.isEmpty) {
              return const _EmptyMyEventsState();
            }

            return RefreshIndicator(
              color: SportsAppColors.cyan,
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (ev.myEventsError != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: Material(
                          color: SportsAppColors.accentWarm.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 20,
                                  color: SportsAppColors.accentWarm,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    ev.myEventsError!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: SportsAppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final e = ev.myEvents[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _MyEventRow(
                              event: e,
                              sportIcon: _iconForSport(e.sportType),
                              badge: _statusBadge(e.status),
                              onTap: () async {
                                await Navigator.of(context).push<void>(
                                  MaterialPageRoute<void>(
                                    builder: (_) => EventDetailScreen(event: e),
                                  ),
                                );
                                if (context.mounted) {
                                  await _load();
                                }
                              },
                            ),
                          );
                        },
                        childCount: ev.myEvents.length,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EmptyMyEventsState extends StatelessWidget {
  const _EmptyMyEventsState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: SportsAppColors.cyan.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.emoji_events_outlined,
                size: 40,
                color: SportsAppColors.cyan,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'No events on this account',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: SportsAppColors.accentBlue900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Only events you create while signed in here show up in My events. '
              'If you used another email, sign in with that account—or create a new listing.\n\n'
              'The Home tab lists nearby games from every organizer.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: SportsAppColors.textMuted,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _MyEventRow extends StatelessWidget {
  const _MyEventRow({
    required this.event,
    required this.sportIcon,
    required this.badge,
    required this.onTap,
  });

  final SportEvent event;
  final IconData sportIcon;
  final (String, Color) badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final local = event.startTime.toLocal();
    final timeStr = DateFormat('h:mm').format(local);
    final ampm = DateFormat('a').format(local);
    final statusLabel = badge.$1;
    final statusColor = badge.$2;
    final venue = event.venueName.trim().isEmpty ? 'Venue TBD' : event.venueName.trim();

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: sportsCardDecoration(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 48,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      timeStr,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: SportsAppColors.accentBlue900,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      ampm,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: SportsAppColors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 3,
                height: 44,
                decoration: BoxDecoration(
                  color: SportsAppColors.cyan.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: SportsAppColors.cyan.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  sportIcon,
                  size: 22,
                  color: SportsAppColors.accentBlue800,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: SportsAppColors.textPrimary,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${event.sportType} · $venue · ${event.bookedSlots}/${event.maxSlots} booked',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: SportsAppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.45),
                  ),
                ),
                child: Text(
                  statusLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
