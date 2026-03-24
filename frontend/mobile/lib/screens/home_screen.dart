import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/sport_event.dart';
import '../providers/auth_provider.dart';
import '../providers/event_provider.dart';
import '../providers/location_provider.dart';
import '../theme/sports_app_theme.dart';
import '../utils/geo_utils.dart';
import '../utils/inr_money.dart';
import '../widgets/sports_components.dart';
import 'create_event_screen.dart';
import 'event_detail_screen.dart';
import 'help_support_screen.dart';
import 'my_bookings_screen.dart';
import 'organizer_events_screen.dart';

/// Frost chip used on Nearby + Featured photo cards (live-score style).
Widget _sportCardFrostChip(BuildContext context, String text, {IconData? withIcon}) {
  final theme = Theme.of(context);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (withIcon != null) ...[
          Icon(withIcon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ],
    ),
  );
}

/// Player home: layered hero + floating search, pull-to-refresh, refined cards.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _sportFilter;
  int _navIndex = 0;
  LocationProvider? _locProvider;
  late void Function() _onLocationChanged;

  static const _sportChips = <String>[
    'Soccer',
    'Basketball',
    'Tennis',
    'Volleyball',
    'Baseball',
    'Hockey',
  ];

  static const _featuredCards = <(String, String, String, String)>[
    (
      'assets/images/feature_soccer.jpg',
      'Weekend Football League',
      'Open slots · Prime turf',
      'Soccer',
    ),
    (
      'assets/images/feature_basketball.jpg',
      'City Court Showdown',
      'Night event · 5v5 teams',
      'Basketball',
    ),
    (
      'assets/images/feature_tennis.jpg',
      'Sunset Tennis Rally',
      'Coaching session available',
      'Tennis',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _onLocationChanged = () {
      if (!mounted) {
        return;
      }
      final loc = context.read<LocationProvider>();
      context.read<EventProvider>().fetchNearbyEvents(
        loc.effectiveLat,
        loc.effectiveLng,
      );
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final loc = context.read<LocationProvider>();
      _locProvider = loc;
      loc.addListener(_onLocationChanged);
      _onLocationChanged();
    });
  }

  @override
  void dispose() {
    _locProvider?.removeListener(_onLocationChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() {
    final loc = context.read<LocationProvider>();
    return context.read<EventProvider>().fetchNearbyEvents(
      loc.effectiveLat,
      loc.effectiveLng,
    );
  }

  String _firstName(AuthProvider auth) {
    final u = auth.user;
    if (u == null) return 'Player';
    final n = u.name.trim();
    if (n.isEmpty) return 'Player';
    return n.split(RegExp(r'\s+')).first;
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// Home hero subtitle — organizers browse the same feed; copy highlights nearby events.
  String _homeHeroTagline(AuthProvider auth) {
    if (auth.user?.isOrganizer ?? false) {
      return 'Browse nearby events';
    }
    return 'Find nearby events';
  }

  double _distanceKm(SportEvent e, double userLat, double userLong) {
    if (e.distanceKm != null) {
      return e.distanceKm!;
    }
    return haversineDistanceKm(userLat, userLong, e.lat, e.long);
  }

  List<SportEvent> _filtered(List<SportEvent> all) {
    var list = all;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where(
            (e) =>
                e.title.toLowerCase().contains(q) ||
                e.sportType.toLowerCase().contains(q),
          )
          .toList();
    }
    if (_sportFilter != null) {
      list = list
          .where(
            (e) => e.sportType.toLowerCase() == _sportFilter!.toLowerCase(),
          )
          .toList();
    }
    return list;
  }

  SportEvent? _firstLive(List<SportEvent> items) {
    for (final e in items) {
      if (e.status == 3) {
        return e;
      }
    }
    return null;
  }

  IconData _iconForSport(String sport) {
    switch (sport.toLowerCase()) {
      case 'basketball':
        return Icons.sports_basketball_rounded;
      case 'tennis':
        return Icons.sports_tennis_rounded;
      case 'volleyball':
        return Icons.sports_volleyball_rounded;
      case 'baseball':
        return Icons.sports_baseball_rounded;
      case 'hockey':
        return Icons.sports_hockey_rounded;
      case 'soccer':
      default:
        return Icons.sports_soccer_rounded;
    }
  }

  String _imageForSport(String sport) {
    switch (sport.toLowerCase()) {
      case 'basketball':
        return 'assets/images/feature_basketball.jpg';
      case 'tennis':
        return 'assets/images/feature_tennis.jpg';
      case 'volleyball':
      case 'baseball':
      case 'hockey':
      case 'soccer':
      default:
        return 'assets/images/feature_soccer.jpg';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLine = DateFormat('EEE, MMM d').format(DateTime.now());

    return Scaffold(
      backgroundColor: SportsAppColors.pageBackground,
      body: Consumer3<AuthProvider, EventProvider, LocationProvider>(
        builder: (context, auth, provider, loc, _) {
          final items = _filtered(provider.events);
          final live = _firstLive(items);
          final userLat = loc.effectiveLat;
          final userLong = loc.effectiveLng;

          if (_navIndex == 2) {
            return _ProfileTab(auth: auth);
          }

          if (_navIndex == 1) {
            return _MatchesTab(
              events: _filtered(provider.events),
              userLat: userLat,
              userLong: userLong,
              onRefresh: _onRefresh,
              searchController: _searchController,
              onSearchChanged: (v) => setState(() => _query = v),
              sportFilter: _sportFilter,
              onClearSportFilter: () => setState(() => _sportFilter = null),
              iconForSport: _iconForSport,
              statusLabel: _statusLabel,
            );
          }

          return SportsBackground(
            child: RefreshIndicator(
              color: SportsAppColors.cyan,
              onRefresh: _onRefresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 236,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _HomeHeroHeader(
                            greeting: _greeting(),
                            firstName: _firstName(auth),
                            dateLine: dateLine,
                            tagline: _homeHeroTagline(auth),
                          ),
                          Positioned(
                            left: 20,
                            right: 20,
                            top: 164,
                            child: _FloatingSearchField(
                              controller: _searchController,
                              onChanged: (v) => setState(() => _query = v),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (live != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _LiveFeaturedCard(
                          event: live,
                          distanceKm: _distanceKm(live, userLat, userLong),
                          sportIcon: _iconForSport(live.sportType),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => EventDetailScreen(event: live),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (live != null)
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 168,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        scrollDirection: Axis.horizontal,
                        itemCount: _featuredCards.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
                        itemBuilder: (context, i) {
                          final item = _featuredCards[i];
                          return _FeaturedImageCard(
                            imagePath: item.$1,
                            title: item.$2,
                            subtitle: item.$3,
                            sportLabel: item.$4,
                            sportIcon: _iconForSport(item.$4),
                            onTap: () {
                              if (items.isNotEmpty) {
                                final event = items[i % items.length];
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => EventDetailScreen(event: event),
                                  ),
                                );
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 26)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SportsSectionTitle(
                            'Pick a sport',
                            bottomSpacing: 4,
                            action: _sportFilter != null
                                ? TextButton(
                                    onPressed: () =>
                                        setState(() => _sportFilter = null),
                                    child: Text(
                                      'Clear',
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            color: SportsAppColors.cyan,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  )
                                : null,
                          ),
                          SizedBox(
                            height: 58,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _sportChips.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, i) {
                                final sport = _sportChips[i];
                                final selected =
                                    _sportFilter?.toLowerCase() ==
                                    sport.toLowerCase();
                                return _SportIconButton(
                                  icon: _iconForSport(sport),
                                  selected: selected,
                                  onTap: () {
                                    setState(() {
                                      if (selected) {
                                        _sportFilter = null;
                                      } else {
                                        _sportFilter = sport;
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (provider.isLoading)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                  else if (provider.errorMessage != null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.cloud_off_rounded,
                                size: 56,
                                color: SportsAppColors.textMuted.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                provider.errorMessage!,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: SportsAppColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                onPressed: _onRefresh,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Try again'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: SportsAppColors.navy,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else if (items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(22),
                                decoration: BoxDecoration(
                                  color: SportsAppColors.cyan.withValues(
                                    alpha: 0.1,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.sports_rounded,
                                  size: 48,
                                  color: SportsAppColors.cyan.withValues(
                                    alpha: 0.85,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'No events nearby',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: SportsAppColors.accentBlue900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _query.trim().isNotEmpty || _sportFilter != null
                                    ? 'Try a different search or sport filter.'
                                    : 'Check back soon or widen your area.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: SportsAppColors.textMuted,
                                ),
                              ),
                              if (_query.trim().isNotEmpty ||
                                  _sportFilter != null) ...[
                                const SizedBox(height: 20),
                                OutlinedButton(
                                  onPressed: () {
                                    setState(() {
                                      _query = '';
                                      _sportFilter = null;
                                      _searchController.clear();
                                    });
                                  },
                                  child: const Text('Reset filters'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    )
                  else ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                        child: SportsSectionTitle(
                          'Nearby events',
                          action: TextButton(
                            onPressed: () {},
                            child: Text(
                              'See all',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: SportsAppColors.cyan,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 168,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          scrollDirection: Axis.horizontal,
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 14),
                          itemBuilder: (context, i) {
                            final e = items[i];
                            return _HorizontalMatchCard(
                              event: e,
                              distanceKm: _distanceKm(e, userLat, userLong),
                              sportIcon: _iconForSport(e.sportType),
                              imagePath: _imageForSport(e.sportType),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => EventDetailScreen(event: e),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                        child: SportsSectionTitle(
                          'All events',
                          color: SportsAppColors.textPrimary,
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final e = items[index];
                          final dist = _distanceKm(e, userLat, userLong);
                          final badge = _statusLabel(e.status);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _EventListTileCard(
                              event: e,
                              distanceKm: dist,
                              statusLabel: badge.$1,
                              statusColor: badge.$2,
                              sportIcon: _iconForSport(e.sportType),
                              imagePath: _imageForSport(e.sportType),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => EventDetailScreen(event: e),
                                  ),
                                );
                              },
                            ),
                          );
                        }, childCount: items.length),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Material(
            elevation: 14,
            shadowColor: SportsAppColors.navy.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(28),
            color: SportsAppColors.card,
            clipBehavior: Clip.antiAlias,
            child: NavigationBarTheme(
              data: NavigationBarThemeData(
                height: 52,
                backgroundColor: Colors.transparent,
                indicatorColor: SportsAppColors.cyan.withValues(alpha: 0.22),
                iconTheme: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return IconThemeData(
                    size: 24,
                    color: selected
                        ? SportsAppColors.accentBlue800
                        : SportsAppColors.textMuted,
                  );
                }),
              ),
              child: NavigationBar(
                selectedIndex: _navIndex,
                onDestinationSelected: (i) => setState(() => _navIndex = i),
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                shadowColor: Colors.transparent,
                indicatorColor: SportsAppColors.cyan.withValues(alpha: 0.22),
                labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
                destinations: [
                  NavigationDestination(
                    icon: _NavBarSvg(asset: 'assets/vectors/nav_home_outline.svg'),
                    selectedIcon: _NavBarSvg(asset: 'assets/vectors/nav_home_filled.svg'),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: _NavBarSvg(asset: 'assets/vectors/nav_calendar_outline.svg'),
                    selectedIcon: _NavBarSvg(asset: 'assets/vectors/nav_calendar_filled.svg'),
                    label: 'Events',
                  ),
                  NavigationDestination(
                    icon: _NavBarSvg(asset: 'assets/vectors/nav_profile_outline.svg'),
                    selectedIcon: _NavBarSvg(asset: 'assets/vectors/nav_profile_filled.svg'),
                    label: 'Profile',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  (String, Color) _statusLabel(int status) {
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
}

/// Bottom-nav SVG tinted by [NavigationBarThemeData.iconTheme] / [IconTheme].
class _NavBarSvg extends StatelessWidget {
  const _NavBarSvg({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? SportsAppColors.textMuted;
    return SvgPicture.asset(
      asset,
      width: 24,
      height: 24,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

class _HomeHeroHeader extends StatelessWidget {
  const _HomeHeroHeader({
    required this.greeting,
    required this.firstName,
    required this.dateLine,
    required this.tagline,
  });

  final String greeting;
  final String firstName;
  final String dateLine;
  final String tagline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 196,
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(32),
            bottomRight: Radius.circular(32),
          ),
          boxShadow: [
            BoxShadow(
              color: SportsAppColors.accentBlue900.withValues(alpha: 0.32),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/sports_hero.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [SportsAppColors.accentBlue900, SportsAppColors.accentBlue800],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    SportsAppColors.accentBlue800.withValues(alpha: 0.38),
                    SportsAppColors.accentBlue900.withValues(alpha: 0.55),
                    SportsAppColors.accentBlue900.withValues(alpha: 0.72),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
            Positioned.fill(
              child: SvgPicture.asset(
                'assets/vectors/stadium_pattern.svg',
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.white.withValues(alpha: 0.1),
                  BlendMode.srcATop,
                ),
              ),
            ),
            Positioned(
              right: -20,
              top: 20,
              child: Icon(
                Icons.sports_soccer_rounded,
                size: 160,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 14, 56),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$greeting,',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          firstName,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today_rounded,
                              size: 15,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              dateLine,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(
                                  alpha: 0.88,
                                ),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tagline,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingSearchField extends StatefulWidget {
  const _FloatingSearchField({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_FloatingSearchField> createState() => _FloatingSearchFieldState();
}

class _FloatingSearchFieldState extends State<_FloatingSearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
  }

  @override
  void didUpdateWidget(covariant _FloatingSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  void _sync() => setState(() {});

  @override
  Widget build(BuildContext context) {
    const fill = Colors.white;
    const radius = BorderRadius.all(Radius.circular(28));
    final borderIdle = BorderSide(
      color: SportsAppColors.border,
      width: 1,
    );
    final borderFocused = BorderSide(
      color: SportsAppColors.textMuted.withValues(alpha: 0.55),
      width: 1,
    );

    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          hoverColor: Colors.transparent,
          fillColor: fill,
        ),
      ),
      child: TextField(
        controller: widget.controller,
        onChanged: widget.onChanged,
        cursorColor: SportsAppColors.accentBlue800,
        style: const TextStyle(
          color: SportsAppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hoverColor: Colors.transparent,
          hintText: 'Search sports, venues, events…',
          hintStyle: TextStyle(
            color: SportsAppColors.textMuted.withValues(alpha: 0.75),
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: SportsAppColors.textMuted.withValues(alpha: 0.85),
          ),
          suffixIcon: widget.controller.text.isNotEmpty
              ? IconButton(
                  style: ButtonStyle(
                    overlayColor: sportsAppInkNoHoverOverlay(),
                  ),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: SportsAppColors.textMuted.withValues(alpha: 0.75),
                  ),
                  onPressed: () {
                    widget.controller.clear();
                    widget.onChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: fill,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 16,
          ),
          border: OutlineInputBorder(borderRadius: radius, borderSide: borderIdle),
          enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: borderIdle),
          focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: borderFocused),
        ),
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.auth});

  final AuthProvider auth;

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      final s = parts[0];
      return s.isNotEmpty ? s[0].toUpperCase() : '?';
    }
    final a = parts.first.isNotEmpty ? parts.first[0] : '';
    final b = parts.last.isNotEmpty ? parts.last[0] : '';
    return ('$a$b').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = auth.user;
    if (user == null) {
      return SportsBackground(
        child: SafeArea(
          child: Center(
            child: Text(
              'Not signed in',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: SportsAppColors.textMuted,
              ),
            ),
          ),
        ),
      );
    }

    final initials = _initials(user.name);

    return SportsBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 44,
                            backgroundColor: SportsAppColors.cyan.withValues(alpha: 0.18),
                            child: Text(
                              initials,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: SportsAppColors.accentBlue800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            user.name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: SportsAppColors.accentBlue900,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.mail_outline_rounded,
                                size: 18,
                                color: SportsAppColors.textMuted,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  user.email,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: SportsAppColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (user.isOrganizer) ...[
                            const SportsSectionTitle(
                              'Organizer',
                              bottomSpacing: 10,
                              color: SportsAppColors.accentBlue900,
                            ),
                            Container(
                              decoration: sportsCardDecoration(),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  _ProfileMenuRow(
                                    icon: Icons.add_circle_outline,
                                    label: 'Create event',
                                    showTopDivider: false,
                                    onTap: () async {
                                      final created =
                                          await Navigator.of(context).push<bool>(
                                        MaterialPageRoute<bool>(
                                          builder: (_) =>
                                              const CreateEventScreen(),
                                        ),
                                      );
                                      if (created == true && context.mounted) {
                                        final loc =
                                            context.read<LocationProvider>();
                                        await context
                                            .read<EventProvider>()
                                            .fetchNearbyEvents(
                                              loc.effectiveLat,
                                              loc.effectiveLng,
                                            );
                                      }
                                    },
                                  ),
                                  _ProfileMenuRow(
                                    icon: Icons.dashboard_outlined,
                                    label: 'My events',
                                    showTopDivider: true,
                                    onTap: () {
                                      final auth =
                                          context.read<AuthProvider>();
                                      if (auth.user == null ||
                                          !auth.user!.isOrganizer) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Sign in as an organizer to manage events.',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      Navigator.of(context).push<void>(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const OrganizerEventsScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                          const SportsSectionTitle(
                            'Location',
                            bottomSpacing: 10,
                            color: SportsAppColors.accentBlue900,
                          ),
                          Consumer2<LocationProvider, AuthProvider>(
                            builder: (context, loc, auth, _) {
                              return Container(
                                decoration: sportsCardDecoration(),
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _ProfileMenuRow(
                                      icon: Icons.my_location_rounded,
                                      label: 'Update my location',
                                      showTopDivider: false,
                                      onTap: () async {
                                        await loc.refreshFromDevice();
                                        if (!context.mounted) {
                                          return;
                                        }
                                        final err = loc.errorMessage;
                                        final String feedback;
                                        if (err != null && err.isNotEmpty) {
                                          feedback = err;
                                        } else if (!auth.isLoggedIn) {
                                          feedback =
                                              'Location saved on this device. Sign in to sync it to your account.';
                                        } else if (loc.lastServerSyncSucceeded) {
                                          feedback =
                                              'Location updated on your account.';
                                        } else {
                                          feedback =
                                              'Location saved on this device. Could not reach the server — check your connection and try again.';
                                        }
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(feedback),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      },
                                    ),
                                    Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: SportsAppColors.border.withValues(
                                        alpha: 0.85,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        8,
                                        16,
                                        12,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Address',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: SportsAppColors.textMuted,
                                              letterSpacing: 0.15,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          SelectionArea(
                                            child: Text(
                                              loc.addressDisplay,
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: SportsAppColors.textMuted,
                                                fontWeight: FontWeight.w600,
                                                height: 1.25,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SportsSectionTitle(
                            'Account',
                            bottomSpacing: 10,
                            color: SportsAppColors.accentBlue900,
                          ),
                          Container(
                            decoration: sportsCardDecoration(),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                if (!user.isOrganizer)
                                  _ProfileMenuRow(
                                    icon: Icons.event_note_outlined,
                                    label: 'My bookings',
                                    showTopDivider: false,
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const MyBookingsScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                _ProfileMenuRow(
                                  icon: Icons.notifications_outlined,
                                  label: 'Notifications',
                                  showTopDivider: user.isOrganizer ? false : true,
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Notification settings coming soon.'),
                                      ),
                                    );
                                  },
                                ),
                                _ProfileMenuRow(
                                  icon: Icons.help_outline_rounded,
                                  label: 'Help & support',
                                  showTopDivider: true,
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => const HelpSupportScreen(),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await context.read<AuthProvider>().logout();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: SportsAppColors.navyDark,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(56),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 18,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text('Logout'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileMenuRow extends StatelessWidget {
  const _ProfileMenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.showTopDivider = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool showTopDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTopDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: SportsAppColors.border.withValues(alpha: 0.85),
          ),
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: SportsAppColors.cyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: SportsAppColors.accentBlue800,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: SportsAppColors.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: SportsAppColors.textMuted.withValues(alpha: 0.5),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Schedule-style events view (date strip + grouped list), aligned with common
/// fixture / calendar apps (day chips, time-first rows, status badges).
class _MatchesTab extends StatefulWidget {
  const _MatchesTab({
    required this.events,
    required this.userLat,
    required this.userLong,
    required this.onRefresh,
    required this.searchController,
    required this.onSearchChanged,
    required this.sportFilter,
    required this.onClearSportFilter,
    required this.iconForSport,
    required this.statusLabel,
  });

  final List<SportEvent> events;
  final double userLat;
  final double userLong;
  final Future<void> Function() onRefresh;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String? sportFilter;
  final VoidCallback onClearSportFilter;
  final IconData Function(String sport) iconForSport;
  final (String, Color) Function(int status) statusLabel;

  @override
  State<_MatchesTab> createState() => _MatchesTabState();
}

class _MatchesTabState extends State<_MatchesTab> {
  /// `null` = show all upcoming, grouped by calendar day.
  DateTime? _dayFilter;

  static DateTime _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  double _distanceKm(SportEvent e) {
    if (e.distanceKm != null) return e.distanceKm!;
    return haversineDistanceKm(widget.userLat, widget.userLong, e.lat, e.long);
  }

  List<SportEvent> get _eventsSorted {
    final list = List<SportEvent>.from(widget.events)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return list;
  }

  List<SportEvent> get _eventsForList {
    if (_dayFilter == null) return _eventsSorted;
    return _eventsSorted
        .where(
          (e) => _sameDay(_dateOnly(e.startTime.toLocal()), _dayFilter!),
        )
        .toList();
  }

  List<(DateTime day, List<SportEvent> items)> _groupedByDay() {
    final map = <DateTime, List<SportEvent>>{};
    for (final e in _eventsSorted) {
      final d = _dateOnly(e.startTime.toLocal());
      map.putIfAbsent(d, () => []).add(e);
    }
    final keys = map.keys.toList()..sort();
    return [for (final k in keys) (k, map[k]!)];
  }

  String _chipTopLabel(DateTime day, DateTime today) {
    if (_sameDay(day, today)) return 'Today';
    if (_sameDay(day, today.add(const Duration(days: 1)))) {
      return 'Tomorrow';
    }
    return DateFormat('EEE').format(day);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = _dateOnly(DateTime.now());
    final chipDays = List.generate(14, (i) => today.add(Duration(days: i)));

    return SportsBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Events',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: SportsAppColors.accentBlue900,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Browse events by day — tap a date to filter',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: SportsAppColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: _FloatingSearchField(
                controller: widget.searchController,
                onChanged: widget.onSearchChanged,
              ),
            ),
            if (widget.sportFilter != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Sport: ${widget.sportFilter}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: SportsAppColors.accentBlue900,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onClearSportFilter,
                      child: Text(
                        'Clear',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: SportsAppColors.cyan,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _MatchDayChip(
                      top: 'All',
                      bottom: '',
                      selected: _dayFilter == null,
                      compactBottom: true,
                      onTap: () => setState(() => _dayFilter = null),
                    ),
                  ),
                  ...chipDays.map((day) {
                    final sel =
                        _dayFilter != null && _sameDay(_dayFilter!, day);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _MatchDayChip(
                        top: _chipTopLabel(day, today),
                        bottom: DateFormat('MMM d').format(day),
                        selected: sel,
                        onTap: () => setState(() => _dayFilter = day),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                color: SportsAppColors.cyan,
                onRefresh: widget.onRefresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    if (_eventsSorted.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _MatchesEmptyState(
                          hasFilters: widget.searchController.text
                                  .trim()
                                  .isNotEmpty ||
                              widget.sportFilter != null,
                        ),
                      )
                    else if (_dayFilter != null && _eventsForList.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _MatchesEmptyDay(
                          day: _dayFilter!,
                        ),
                      )
                    else if (_dayFilter != null)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final e = _eventsForList[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _MatchScheduleRow(
                                  event: e,
                                  distanceKm: _distanceKm(e),
                                  sportIcon: widget.iconForSport(e.sportType),
                                  badge: widget.statusLabel(e.status),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            EventDetailScreen(event: e),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                            childCount: _eventsForList.length,
                          ),
                        ),
                      )
                    else
                      ..._buildGroupedSlivers(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroupedSlivers(BuildContext context) {
    final theme = Theme.of(context);
    final groups = _groupedByDay();
    final out = <Widget>[];
    for (var i = 0; i < groups.length; i++) {
      final day = groups[i].$1;
      final list = groups[i].$2;
      out.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, i == 0 ? 0 : 20, 20, 10),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: SportsAppColors.cyan,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  DateFormat('EEEE, MMM d').format(day),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: SportsAppColors.accentBlue900,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      out.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final e = list[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _MatchScheduleRow(
                    event: e,
                    distanceKm: _distanceKm(e),
                    sportIcon: widget.iconForSport(e.sportType),
                    badge: widget.statusLabel(e.status),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => EventDetailScreen(event: e),
                        ),
                      );
                    },
                  ),
                );
              },
              childCount: list.length,
            ),
          ),
        ),
      );
    }
    out.add(const SliverToBoxAdapter(child: SizedBox(height: 100)));
    return out;
  }
}

class _MatchDayChip extends StatelessWidget {
  const _MatchDayChip({
    required this.top,
    required this.bottom,
    required this.selected,
    required this.onTap,
    this.compactBottom = false,
  });

  final String top;
  final String bottom;
  final bool selected;
  final VoidCallback onTap;
  final bool compactBottom;

  static const _skyTint = Color(0xFFE0F2FE);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(12);

    final Color topColor = selected
        ? SportsAppColors.accentBlue900
        : SportsAppColors.textMuted;
    final Color bottomColor = selected
        ? SportsAppColors.accentBlue800.withValues(alpha: 0.88)
        : SportsAppColors.textMuted.withValues(alpha: 0.85);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: compactBottom ? 44 : 52,
          maxWidth: compactBottom ? 52 : 82,
        ),
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: bottom.isEmpty ? 9 : 7,
            horizontal: 10,
          ),
          decoration: BoxDecoration(
            color: selected ? _skyTint : SportsAppColors.card,
            borderRadius: radius,
            border: Border.all(
              color: selected
                  ? SportsAppColors.cyan.withValues(alpha: 0.45)
                  : SportsAppColors.border.withValues(alpha: 0.75),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                top,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  height: 1.05,
                  letterSpacing: bottom.isEmpty ? 0 : 0.2,
                  color: topColor,
                ),
              ),
              if (bottom.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  bottom,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                    height: 1.1,
                    color: bottomColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MatchScheduleRow extends StatelessWidget {
  const _MatchScheduleRow({
    required this.event,
    required this.distanceKm,
    required this.sportIcon,
    required this.badge,
    required this.onTap,
  });

  final SportEvent event;
  final double distanceKm;
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
                      '${event.sportType} · ${distanceKm.toStringAsFixed(1)} km · ${formatInr(event.price)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: SportsAppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    statusLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
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

class _MatchesEmptyState extends StatelessWidget {
  const _MatchesEmptyState({required this.hasFilters});

  final bool hasFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_available_rounded,
              size: 56,
              color: SportsAppColors.textMuted.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            Text(
              hasFilters ? 'No events match your filters' : 'No events yet',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: SportsAppColors.accentBlue900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilters
                  ? 'Try clearing search or sport filter from Home.'
                  : 'Pull to refresh or check back soon.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: SportsAppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchesEmptyDay extends StatelessWidget {
  const _MatchesEmptyDay({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 48,
              color: SportsAppColors.textMuted.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            Text(
              'Nothing on ${DateFormat('EEE, MMM d').format(day)}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: SportsAppColors.accentBlue900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pick another date or view All.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: SportsAppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveFeaturedCard extends StatelessWidget {
  const _LiveFeaturedCard({
    required this.event,
    required this.distanceKm,
    required this.sportIcon,
    required this.onTap,
  });

  final SportEvent event;
  final double distanceKm;
  final IconData sportIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        overlayColor: sportsAppInkNoHoverOverlay(),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                SportsAppColors.card,
                SportsAppColors.cyan.withValues(alpha: 0.06),
              ],
            ),
            border: Border.all(
              color: SportsAppColors.liveRed.withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: SportsAppColors.liveRed.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: SportsAppColors.liveRed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'LIVE NOW',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: SportsAppColors.liveRed,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: SportsAppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${distanceKm.toStringAsFixed(1)} km',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: SportsAppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _TeamCircle(icon: sportIcon, color: SportsAppColors.cyan),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          event.title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: SportsAppColors.accentBlue900,
                          ),
                        ),
                      ),
                    ),
                    _TeamCircle(
                      icon: Icons.sports_rounded,
                      color: SportsAppColors.accentBlue800,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    event.sportType,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: SportsAppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamCircle extends StatelessWidget {
  const _TeamCircle({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Icon(icon, color: color, size: 26),
    );
  }
}

class _SportIconButton extends StatelessWidget {
  const _SportIconButton({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        overlayColor: sportsAppInkNoHoverOverlay(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 52,
          height: 52,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected
                ? SportsAppColors.cyan.withValues(alpha: 0.18)
                : SportsAppColors.card,
            border: Border.all(
              color: selected ? SportsAppColors.cyan : SportsAppColors.border,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: SportsAppColors.navy.withValues(
                  alpha: selected ? 0.1 : 0.05,
                ),
                blurRadius: selected ? 10 : 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Icon(
              icon,
              size: 26,
              color: selected
                  ? SportsAppColors.accentBlue900
                  : SportsAppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturedImageCard extends StatelessWidget {
  const _FeaturedImageCard({
    required this.imagePath,
    required this.title,
    required this.subtitle,
    required this.sportLabel,
    required this.sportIcon,
    required this.onTap,
  });

  final String imagePath;
  final String title;
  final String subtitle;
  final String sportLabel;
  final IconData sportIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        overlayColor: sportsAppInkNoHoverOverlay(),
        child: Ink(
          width: 240,
          decoration: sportsCardDecoration(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    imagePath,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Image.asset(
                      'assets/images/sports_hero.jpg',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          SportsAppColors.navyDark.withValues(alpha: 0.18),
                          SportsAppColors.navyDark.withValues(alpha: 0.72),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _sportCardFrostChip(
                            context,
                            sportLabel.toUpperCase(),
                            withIcon: sportIcon,
                          ),
                          const Spacer(),
                          _sportCardFrostChip(context, 'FEATURED'),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HorizontalMatchCard extends StatelessWidget {
  const _HorizontalMatchCard({
    required this.event,
    required this.distanceKm,
    required this.sportIcon,
    required this.imagePath,
    required this.onTap,
  });

  final SportEvent event;
  final double distanceKm;
  final IconData sportIcon;
  final String imagePath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeStr = DateFormat(
      'EEE · h:mm a',
    ).format(event.startTime.toLocal());
    final status = switch (event.status) {
      3 => 'LIVE',
      2 => 'FULL',
      1 => 'OPEN',
      0 => 'DRAFT',
      _ => 'DONE',
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        overlayColor: sportsAppInkNoHoverOverlay(),
        child: Ink(
          width: 240,
          decoration: sportsCardDecoration(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    imagePath,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Image.asset(
                      'assets/images/sports_hero.jpg',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          SportsAppColors.navyDark.withValues(alpha: 0.18),
                          SportsAppColors.navyDark.withValues(alpha: 0.72),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _sportCardFrostChip(
                            context,
                            event.sportType.toUpperCase(),
                            withIcon: sportIcon,
                          ),
                          const Spacer(),
                          _sportCardFrostChip(context, status),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$timeStr · ${distanceKm.toStringAsFixed(1)} km · ${formatInr(event.price)}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EventListTileCard extends StatelessWidget {
  const _EventListTileCard({
    required this.event,
    required this.distanceKm,
    required this.statusLabel,
    required this.statusColor,
    required this.sportIcon,
    required this.imagePath,
    required this.onTap,
  });

  final SportEvent event;
  final double distanceKm;
  final String statusLabel;
  final Color statusColor;
  final IconData sportIcon;
  final String imagePath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeStr = DateFormat(
      'MMM d · h:mm a',
    ).format(event.startTime.toLocal());

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: sportsCardDecoration(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 84,
                height: 84,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        imagePath,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Image.asset(
                          'assets/images/sports_hero.jpg',
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                SportsAppColors.textPrimary.withValues(alpha: 0.35),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: SportsAppColors.navy.withValues(alpha: 0.12),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Icon(
                            sportIcon,
                            size: 16,
                            color: SportsAppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            event.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: SportsAppColors.textPrimary,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            statusLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (event.venueName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        event.venueName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: SportsAppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${event.sportType} · $timeStr',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: SportsAppColors.textPrimary.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.near_me_outlined,
                          size: 15,
                          color: SportsAppColors.textPrimary.withValues(alpha: 0.55),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${distanceKm.toStringAsFixed(1)} km',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: SportsAppColors.textPrimary.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          formatInr(event.price),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: SportsAppColors.textPrimary,
                            fontWeight: FontWeight.w900,
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
