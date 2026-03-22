import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/home_screen.dart';
import '../theme/sports_app_theme.dart';

/// Shows a loading state, then [LoginScreen] or [HomeScreen] based on auth.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.loading) {
          return Scaffold(
            body: SportsBackground(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: SportsAppColors.accent.withValues(alpha: 0.4),
                          width: 2,
                        ),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Loading…',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: SportsAppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (!auth.isLoggedIn) {
          return const LoginScreen();
        }
        return const HomeScreen();
      },
    );
  }
}
