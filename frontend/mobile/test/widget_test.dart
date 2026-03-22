import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sports_booking/providers/auth_provider.dart';
import 'package:sports_booking/providers/event_provider.dart';
import 'package:sports_booking/widgets/auth_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Auth gate shows sign in when logged out', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthProvider();
    await auth.init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider(create: (_) => EventProvider()),
        ],
        child: const MaterialApp(home: AuthGate()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Sports Booking'), findsOneWidget);
  });
}
