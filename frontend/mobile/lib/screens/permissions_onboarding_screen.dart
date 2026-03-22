import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../providers/location_provider.dart';
import '../theme/sports_app_theme.dart';

/// First launch: explains network + location, then requests location permission.
class PermissionsOnboardingScreen extends StatefulWidget {
  const PermissionsOnboardingScreen({
    super.key,
    required this.onFinished,
  });

  final VoidCallback onFinished;

  @override
  State<PermissionsOnboardingScreen> createState() =>
      _PermissionsOnboardingScreenState();
}

class _PermissionsOnboardingScreenState extends State<PermissionsOnboardingScreen> {
  bool _busy = false;

  Future<bool> _hasNetwork() async {
    if (kIsWeb) {
      return true;
    }
    try {
      final response = await http
          .head(Uri.parse('https://clients3.google.com/generate_204'))
          .timeout(const Duration(seconds: 4));
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _onContinue() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final online = await _hasNetwork();
      if (!mounted) {
        return;
      }
      if (!online) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Connect to Wi‑Fi or mobile data, then try again.',
            ),
          ),
        );
        return;
      }
      await context.read<LocationProvider>().completePermissionsOnboarding();
      if (!mounted) {
        return;
      }
      widget.onFinished();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Something went wrong: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: SportsAppColors.pageBackground,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
        child: SportsAuthBackground(
          imageAsset: 'assets/images/sports_auth_bg.jpg',
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Welcome',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'A quick setup so Sports Booking can load events and nearby games.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.82),
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                      decoration: sportsCardDecoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Bullet(
                            icon: Icons.wifi_rounded,
                            title: 'Internet',
                            body:
                                'The app uses your network to sign in, load matches, and sync your profile. No extra permission is required on your phone.',
                          ),
                          const SizedBox(height: 20),
                          _Bullet(
                            icon: Icons.location_on_rounded,
                            title: 'Location',
                            body:
                                'We use your approximate location to show games near you and to label your area on the map. You can change this anytime in system settings.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _onContinue,
                      style: FilledButton.styleFrom(
                        backgroundColor: SportsAppColors.navy,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 18,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Continue',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Next, your phone may ask for location access — choose what you’re comfortable with.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: SportsAppColors.cyan.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: SportsAppColors.cyan, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: SportsAppColors.accentBlue900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: SportsAppColors.textMuted,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
