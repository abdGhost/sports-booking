import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/event_provider.dart';
import 'providers/location_provider.dart';
import 'theme/sports_app_theme.dart';
import 'widgets/auth_gate.dart';
import 'widgets/first_launch_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = AuthProvider();
  await auth.init();
  final location = LocationProvider(auth);
  await location.init();
  runApp(SportsBookingApp(auth: auth, location: location));
}

class SportsBookingApp extends StatelessWidget {
  const SportsBookingApp({
    super.key,
    required this.auth,
    required this.location,
  });

  final AuthProvider auth;
  final LocationProvider location;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: location),
        ChangeNotifierProvider(create: (_) => EventProvider()),
      ],
      child: MaterialApp(
        title: 'Sports Booking',
        theme: SportsAppTheme.build(),
        themeMode: ThemeMode.light,
        debugShowCheckedModeBanner: false,
        home: const FirstLaunchGate(child: AuthGate()),
      ),
    );
  }
}
