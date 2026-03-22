import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../theme/sports_app_theme.dart';

/// Sign up flow aligned with [LoginScreen]: same field chrome, card weight, and
/// keyboard-aware hero / compact header.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  String _role = 'player';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _submitting = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.register(
      name: _name.text,
      email: _email.text,
      password: _password.text,
      role: _role,
    );
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    if (!ok && auth.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.lastError!)),
      );
    } else if (ok) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required Widget prefixIcon,
    Widget? suffixIcon,
    String? helperText,
    TextStyle? helperStyle,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      helperText: helperText,
      helperStyle: helperStyle,
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
          imageAsset: 'assets/images/feature_soccer.jpg',
          child: SafeArea(
            child: GestureDetector(
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              behavior: HitTestBehavior.deferToChild,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      horizontalPad,
                      keyboardOpen ? 4 : 0,
                      horizontalPad,
                      32 + bottomInset,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!keyboardOpen) ...[
                            const SizedBox(height: 12),
                            _signupBrandHero(theme),
                          ],
                          if (keyboardOpen) ...[
                            const SizedBox(height: 8),
                            _signupBrandCompact(theme),
                          ],
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
                                          'Create account',
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: SportsAppColors.accentBlue900,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.person_add_alt_1_outlined,
                                        size: 22,
                                        color: SportsAppColors.textMuted.withValues(alpha: 0.7),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 22),
                                  Text(
                                    'I am a',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: SportsAppColors.accentBlue900,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  SegmentedButton<String>(
                                    segments: const [
                                      ButtonSegment(
                                        value: 'player',
                                        label: Text('Player'),
                                        icon: Icon(Icons.person_outline_rounded, size: 18),
                                      ),
                                      ButtonSegment(
                                        value: 'organizer',
                                        label: Text('Organizer'),
                                        icon: Icon(Icons.emoji_events_outlined, size: 18),
                                      ),
                                    ],
                                    selected: {_role},
                                    onSelectionChanged: (s) {
                                      setState(() => _role = s.first);
                                    },
                                    showSelectedIcon: false,
                                    expandedInsets: EdgeInsets.zero,
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    'Your details',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: SportsAppColors.accentBlue900,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _name,
                                    textCapitalization: TextCapitalization.words,
                                    textInputAction: TextInputAction.next,
                                    style: const TextStyle(
                                      color: SportsAppColors.textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    decoration: _fieldDecoration(
                                      label: 'Full name',
                                      prefixIcon: const Icon(
                                        Icons.badge_outlined,
                                        color: SportsAppColors.accentBlue800,
                                      ),
                                    ),
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return 'Enter your name';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 20),
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
                                    autofillHints: const [AutofillHints.newPassword],
                                    textInputAction: TextInputAction.next,
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
                                      helperText: 'At least 8 characters',
                                      helperStyle: TextStyle(
                                        color: SportsAppColors.textMuted.withValues(alpha: 0.9),
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
                                      if (v == null || v.length < 8) {
                                        return 'Password must be at least 8 characters';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 20),
                                  TextFormField(
                                    controller: _confirm,
                                    obscureText: _obscure,
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
                                      label: 'Confirm password',
                                      prefixIcon: const Icon(
                                        Icons.verified_user_outlined,
                                        color: SportsAppColors.accentBlue800,
                                      ),
                                    ),
                                    validator: (v) {
                                      if (v != _password.text) {
                                        return 'Passwords do not match';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  Semantics(
                                    button: true,
                                    label: 'Create account',
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
                                            : const Text('Create account'),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            alignment: WrapAlignment.center,
                            spacing: 4,
                            runSpacing: 6,
                            children: [
                              Text(
                                'Already have an account?',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.78),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  Navigator.of(context).pop();
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
                                  'Sign in',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: SportsAppColors.cyan,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _signupBrandHero(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
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
            'Pick how you play, then add your details.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _signupBrandCompact(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Create account',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -0.3,
            fontSize: 20,
          ),
        ),
        Text(
          'Join players near you',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.78),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
