import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/sports_app_theme.dart';

const String kAppIntroOnboardingCompletedKey = 'app_intro_onboarding_v1_completed';

/// Product intro shown once before permissions + login (see [AppOnboardingGate]).
class AppOnboardingScreen extends StatefulWidget {
  const AppOnboardingScreen({super.key, required this.onCompleted});

  final VoidCallback onCompleted;

  @override
  State<AppOnboardingScreen> createState() => _AppOnboardingScreenState();
}

class _AppOnboardingScreenState extends State<AppOnboardingScreen> {
  final PageController _pageController = PageController();
  int _page = 0;

  static const _pages = <_IntroPage>[
    _IntroPage(
      imageAsset: 'assets/images/sports_hero.jpg',
      title: 'Find games near you',
      body:
          'Browse football, basketball, tennis, and more. See slots, venues, and skill levels in one place.',
    ),
    _IntroPage(
      imageAsset: 'assets/images/feature_soccer.jpg',
      title: 'Register your squad',
      body:
          'Create a team or join with a squad ID from your captain — perfect for leagues and weekend cups.',
    ),
    _IntroPage(
      imageAsset: 'assets/images/feature_tennis.jpg',
      title: 'Book and show up',
      body:
          'Secure your spot, pay when it matters, and stay on top of every match.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kAppIntroOnboardingCompletedKey, true);
    if (!mounted) {
      return;
    }
    widget.onCompleted();
  }

  void _next() {
    if (_page < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    } else {
      _complete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: SportsAppColors.navyDark,
        body: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pageController,
              onPageChanged: (i) => setState(() => _page = i),
              itemCount: _pages.length,
              itemBuilder: (context, index) {
                return _OnboardingSlide(
                  page: _pages[index],
                  pageIndex: index,
                  totalPages: _pages.length,
                  currentPage: _page,
                  theme: theme,
                  onPrimary: _next,
                  primaryLabel:
                      index < _pages.length - 1 ? 'Next' : 'Get started',
                );
              },
            ),
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 4),
                  child: TextButton(
                    onPressed: _complete,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    child: Text(
                      'Skip',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        shadows: [
                          Shadow(
                            color: SportsAppColors.navy.withValues(alpha: 0.65),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({
    required this.page,
    required this.pageIndex,
    required this.totalPages,
    required this.currentPage,
    required this.theme,
    required this.onPrimary,
    required this.primaryLabel,
  });

  final _IntroPage page;
  final int pageIndex;
  final int totalPages;
  final int currentPage;
  final ThemeData theme;
  final VoidCallback onPrimary;
  final String primaryLabel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          page.imageAsset,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (_, __, ___) => ColoredBox(
            color: SportsAppColors.navy,
            child: Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                size: 48,
                color: Colors.white.withValues(alpha: 0.4),
              ),
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
                  SportsAppColors.navyDark.withValues(alpha: 0.55),
                  Colors.transparent,
                  SportsAppColors.navyDark.withValues(alpha: 0.88),
                ],
                stops: const [0.0, 0.42, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                decoration: sportsCardDecoration(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 4,
                          height: 26,
                          margin: const EdgeInsets.only(top: 2),
                          decoration: BoxDecoration(
                            color: SportsAppColors.cyan,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            page.title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: SportsAppColors.accentBlue900,
                              height: 1.2,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      page.body,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: SportsAppColors.textMuted,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        totalPages,
                        (i) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            width: i == currentPage ? 24 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == currentPage
                                  ? SportsAppColors.cyan
                                  : SportsAppColors.border.withValues(
                                      alpha: 0.95,
                                    ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: FilledButton(
                        onPressed: onPrimary,
                        style: FilledButton.styleFrom(
                          elevation: 0,
                          backgroundColor: SportsAppColors.cyan,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                        child: Text(primaryLabel),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _IntroPage {
  const _IntroPage({
    required this.imageAsset,
    required this.title,
    required this.body,
  });

  final String imageAsset;
  final String title;
  final String body;
}
