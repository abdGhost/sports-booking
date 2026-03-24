import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/sports_app_theme.dart';
import '../widgets/sports_components.dart';

/// Help center: getting started, FAQs, and contact. Replace [_supportEmail] for production.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  /// Set this to your real support inbox before shipping.
  static const String supportEmail = 'support@sportsbooking.app';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: SportsAppColors.pageBackground,
      appBar: AppBar(
        title: const Text('Help & support'),
        backgroundColor: SportsAppColors.card,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: SportsAppColors.border.withValues(alpha: 0.85),
          ),
        ),
      ),
      body: SportsBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _IntroCard(theme: theme),
              const SizedBox(height: 20),
              const SportsSectionTitle(
                'Players',
                bottomSpacing: 10,
                color: SportsAppColors.accentBlue900,
              ),
              _BulletCard(
                theme: theme,
                icon: Icons.sports_soccer_rounded,
                items: const [
                  'Browse nearby events on the Home tab and filter by sport.',
                  'Open an event to read details, fee, and venue before you book.',
                  'Team events: create or join a squad name so teammates land in the same group.',
                  'After booking, use My bookings to see what you have signed up for.',
                ],
              ),
              const SizedBox(height: 20),
              const SportsSectionTitle(
                'Organizers',
                bottomSpacing: 10,
                color: SportsAppColors.accentBlue900,
              ),
              _BulletCard(
                theme: theme,
                icon: Icons.event_available_rounded,
                items: const [
                  'Create an event from the organizer flow; set registration dates and team vs individual mode.',
                  'Share the event so players can book — squads appear under Squads & roster on the organizer dashboard.',
                  'Publish matchups and edit the schedule; knockout events only allow one game per pair unless rules say otherwise.',
                  'Use check-in tools on match day as your workflow allows.',
                ],
              ),
              const SizedBox(height: 20),
              const SportsSectionTitle(
                'Common issues',
                bottomSpacing: 10,
                color: SportsAppColors.accentBlue900,
              ),
              Container(
                decoration: BoxDecoration(
                  color: SportsAppColors.card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    width: 0.5,
                    color: SportsAppColors.border.withValues(alpha: 0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: SportsAppColors.navy.withValues(alpha: 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _FaqTile(
                      title: 'I do not see any events',
                      body:
                          'Allow location when prompted so we can show games near you. '
                          'You can still open search and adjust filters. If the list is empty, '
                          'try widening the distance or check back when organizers publish new events.',
                    ),
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: SportsAppColors.border.withValues(alpha: 0.45),
                    ),
                    _FaqTile(
                      title: 'Login failed or wrong account',
                      body:
                          'Confirm you are using the same email you registered with. '
                          'Organizers and players use the same login screen — pick the role that matches your account.',
                    ),
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: SportsAppColors.border.withValues(alpha: 0.45),
                    ),
                    _FaqTile(
                      title: 'Schedule or matchup will not save',
                      body:
                          'Team events need at least two registered squads. Knockout formats usually allow only one '
                          'fixture between the same two teams; leagues may allow a home-and-away pair. '
                          'If a squad already lost a finished knockout game, they cannot be scheduled again for a later kickoff. '
                          'Read the on-screen message — it explains what to change.',
                    ),
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: SportsAppColors.border.withValues(alpha: 0.45),
                    ),
                    _FaqTile(
                      title: 'Location or map issues',
                      body:
                          'Enable location permission in system settings for this app. On the web, the browser may ask separately. '
                          'You can still browse events if you deny location, but nearby sorting may be limited.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const SportsSectionTitle(
                'Contact us',
                bottomSpacing: 10,
                color: SportsAppColors.accentBlue900,
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: sportsCardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Questions or bugs? Email us and include what you were trying to do and your app role (player or organizer).',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: SportsAppColors.textMuted,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Material(
                      color: SportsAppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: () async {
                          await Clipboard.setData(
                            const ClipboardData(text: supportEmail),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Email address copied'),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: SportsAppColors.navy,
                              ),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.email_outlined,
                                color: SportsAppColors.cyan.withValues(alpha: 0.95),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SelectableText(
                                  supportEmail,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: SportsAppColors.accentBlue900,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.copy_rounded,
                                size: 20,
                                color: SportsAppColors.textMuted.withValues(alpha: 0.85),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Tap to copy the address',
                      style: theme.textTheme.labelSmall?.copyWith(
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
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SportsAppColors.navy.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: SportsAppColors.cyan.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.support_agent_rounded,
            size: 32,
            color: SportsAppColors.cyan.withValues(alpha: 0.95),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How can we help?',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: SportsAppColors.accentBlue900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Quick tips for booking games and running events. Expand a topic below if something goes wrong.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: SportsAppColors.textMuted,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
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

class _BulletCard extends StatelessWidget {
  const _BulletCard({
    required this.theme,
    required this.icon,
    required this.items,
  });

  final ThemeData theme;
  final IconData icon;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: sportsCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: SportsAppColors.cyan.withValues(alpha: 0.9), size: 22),
          const SizedBox(height: 10),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: SportsAppColors.cyan,
                    fontWeight: FontWeight.w900,
                    height: 1.4,
                  ),
                ),
                Expanded(
                  child: Text(
                    items[i],
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: SportsAppColors.textPrimary,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: SportsAppColors.cyan.withValues(alpha: 0.08),
      ),
      child: ExpansionTile(
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        iconColor: SportsAppColors.navy,
        collapsedIconColor: SportsAppColors.textMuted,
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: SportsAppColors.accentBlue900,
          ),
        ),
        children: [
          Text(
            body,
            style: theme.textTheme.bodySmall?.copyWith(
              color: SportsAppColors.textMuted,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
