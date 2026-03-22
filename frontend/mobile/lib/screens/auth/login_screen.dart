import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../theme/sports_app_theme.dart';
import 'signup_screen.dart';

/// Mobile-first sign-in: strong hierarchy, keyboard-aware layout, autofill,
/// and recovery affordance.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _submitting = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.login(
      email: _email.text,
      password: _password.text,
    );
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    if (!ok && auth.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.lastError!)),
      );
    }
  }

  void _forgotPassword() {
    FocusManager.instance.primaryFocus?.unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password reset will be available in a future update.'),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required Widget prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: SportsAppColors.surfaceElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: SportsAppColors.border.withValues(alpha: 0.9)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: SportsAppColors.border.withValues(alpha: 0.9)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: SportsAppColors.cyan, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: SportsAppColors.liveRed.withValues(alpha: 0.85)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: SportsAppColors.liveRed.withValues(alpha: 0.85)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    final bottomInset = mq.viewInsets.bottom;
    final horizontalPad = mq.size.width < 360 ? 16.0 : 22.0;
    final keyboardOpen = bottomInset > 0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
        child: SportsAuthBackground(
          imageAsset: 'assets/images/sports_auth_bg.jpg',
          child: SafeArea(
            child: GestureDetector(
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              behavior: HitTestBehavior.deferToChild,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final padTop = keyboardOpen ? 8.0 : 12.0;
                  final padBottom = 16.0 + bottomInset;
                  final minScrollContentHeight = keyboardOpen
                      ? 0.0
                      : (constraints.maxHeight - padTop - padBottom)
                          .clamp(0.0, double.infinity);
                  return SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      horizontalPad,
                      padTop,
                      horizontalPad,
                      padBottom,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: minScrollContentHeight,
                      ),
                      child: Align(
                        alignment: keyboardOpen
                            ? Alignment.topCenter
                            : Alignment.center,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (!keyboardOpen) _loginBrandHero(theme),
                                if (keyboardOpen) _loginBrandCompact(theme),
                                SizedBox(height: keyboardOpen ? 12 : 8),
                                Container(
                                  padding: const EdgeInsets.fromLTRB(24, 30, 24, 34),
                                  decoration: sportsCardDecoration(),
                                  child: AutofillGroup(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              width: 4,
                                              height: 24,
                                              decoration: BoxDecoration(
                                                color: SportsAppColors.cyan,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                'Sign in',
                                                style: theme.textTheme.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.w900,
                                                  color: SportsAppColors.accentBlue900,
                                                  letterSpacing: -0.2,
                                                ),
                                              ),
                                            ),
                                            Icon(
                                              Icons.lock_person_outlined,
                                              size: 22,
                                              color: SportsAppColors.textMuted.withValues(alpha: 0.7),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 26),
                                        TextFormField(
                                          controller: _email,
                                          keyboardType: TextInputType.emailAddress,
                                          autofillHints: const [AutofillHints.email],
                                          textInputAction: TextInputAction.next,
                                          autocorrect: false,
                                          style: const TextStyle(
                                            color: SportsAppColors.textPrimary,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          decoration: _fieldDecoration(
                                            label: 'Email',
                                            prefixIcon: const Icon(
                                              Icons.alternate_email_rounded,
                                              color: SportsAppColors.accentBlue800,
                                            ),
                                          ),
                                          validator: (v) {
                                            if (v == null || v.trim().isEmpty) {
                                              return 'Enter your email';
                                            }
                                            if (!v.contains('@')) {
                                              return 'Enter a valid email';
                                            }
                                            return null;
                                          },
                                        ),
                                        const SizedBox(height: 20),
                                        TextFormField(
                                          controller: _password,
                                          obscureText: _obscure,
                                          autofillHints: const [AutofillHints.password],
                                          textInputAction: TextInputAction.done,
                                          onFieldSubmitted: (_) {
                                            if (!_submitting) {
                                              TextInput.finishAutofillContext();
                                              _submit();
                                            }
                                          },
                                          style: const TextStyle(
                                            color: SportsAppColors.textPrimary,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          decoration: _fieldDecoration(
                                            label: 'Password',
                                            prefixIcon: const Icon(
                                              Icons.key_rounded,
                                              color: SportsAppColors.accentBlue800,
                                            ),
                                            suffixIcon: IconButton(
                                              tooltip: _obscure ? 'Show password' : 'Hide password',
                                              icon: Icon(
                                                _obscure
                                                    ? Icons.visibility_outlined
                                                    : Icons.visibility_off_outlined,
                                                color: SportsAppColors.textMuted,
                                              ),
                                              onPressed: () =>
                                                  setState(() => _obscure = !_obscure),
                                            ),
                                          ),
                                          validator: (v) {
                                            if (v == null || v.isEmpty) {
                                              return 'Enter your password';
                                            }
                                            return null;
                                          },
                                        ),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton(
                                            onPressed: _forgotPassword,
                                            style: TextButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 10,
                                              ),
                                              minimumSize: Size.zero,
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            ),
                                            child: Text(
                                              'Forgot password?',
                                              style: theme.textTheme.labelLarge?.copyWith(
                                                color: SportsAppColors.accentBlue800,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Semantics(
                                          button: true,
                                          label: 'Sign in',
                                          child: SizedBox(
                                            width: double.infinity,
                                            height: 58,
                                            child: FilledButton(
                                              onPressed: _submitting ? null : _submit,
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
                                              child: _submitting
                                                  ? const SizedBox(
                                                      height: 24,
                                                      width: 24,
                                                      child: CircularProgressIndicator(
                                                        strokeWidth: 2.5,
                                                        color: Colors.white,
                                                      ),
                                                    )
                                                  : const Text('Sign in'),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Center(
                                  child: Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    alignment: WrapAlignment.center,
                                    spacing: 4,
                                    runSpacing: 6,
                                    children: [
                                      Text(
                                        'New here?',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: Colors.white.withValues(alpha: 0.78),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          FocusManager.instance.primaryFocus?.unfocus();
                                          Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) => const SignupScreen(),
                                            ),
                                          );
                                        },
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                          minimumSize: const Size(48, 48),
                                          tapTargetSize: MaterialTapTargetSize.padded,
                                        ),
                                        child: Text(
                                          'Create an account',
                                          style: theme.textTheme.titleSmall?.copyWith(
                                            color: SportsAppColors.cyan,
                                            fontWeight: FontWeight.w800,
                                          ),
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
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loginBrandHero(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      child: Column(
        children: [
          Text(
            'Sports Booking',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              fontSize: 26,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Book matches. Meet players. Play more.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _loginBrandCompact(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Sports Booking',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
          Text(
            'Sign in to continue',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
