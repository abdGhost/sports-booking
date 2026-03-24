import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/app_onboarding_screen.dart';
import '../theme/sports_app_theme.dart';

/// Shows [AppOnboardingScreen] once, then [child] (permissions gate → auth).
class AppOnboardingGate extends StatefulWidget {
  const AppOnboardingGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppOnboardingGate> createState() => _AppOnboardingGateState();
}

class _AppOnboardingGateState extends State<AppOnboardingGate> {
  bool? _showIntro;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final done =
        prefs.getBool(kAppIntroOnboardingCompletedKey) == true;
    if (!mounted) {
      return;
    }
    setState(() => _showIntro = !done);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!kIsWeb) {
        FlutterNativeSplash.remove();
      }
    });
  }

  void _onIntroFinished() {
    setState(() => _showIntro = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_showIntro == null) {
      return Scaffold(
        backgroundColor: SportsAppColors.navy,
        body: const Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: SportsAppColors.cyan,
            ),
          ),
        ),
      );
    }
    if (_showIntro!) {
      return AppOnboardingScreen(onCompleted: _onIntroFinished);
    }
    return widget.child;
  }
}
