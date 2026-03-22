import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/location_provider.dart';
import '../screens/permissions_onboarding_screen.dart';

/// Shows [PermissionsOnboardingScreen] once; skipped on web or if already completed.
class FirstLaunchGate extends StatefulWidget {
  const FirstLaunchGate({super.key, required this.child});

  final Widget child;

  @override
  State<FirstLaunchGate> createState() => _FirstLaunchGateState();
}

class _FirstLaunchGateState extends State<FirstLaunchGate> {
  bool? _needsOnboarding;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (kIsWeb) {
      setState(() => _needsOnboarding = false);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final done =
        prefs.getBool(LocationProvider.permissionsOnboardingPrefsKey) == true;
    final legacyCoords =
        prefs.getDouble('user_last_lat') != null &&
            prefs.getDouble('user_last_lng') != null;
    if (!mounted) {
      return;
    }
    setState(() => _needsOnboarding = !(done || legacyCoords));
  }

  void _onOnboardingFinished() {
    setState(() => _needsOnboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_needsOnboarding == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_needsOnboarding!) {
      return PermissionsOnboardingScreen(onFinished: _onOnboardingFinished);
    }
    return widget.child;
  }
}
