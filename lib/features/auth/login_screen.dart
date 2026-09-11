import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_form_controls.dart';
import '../../core/widgets/app_state_message.dart';
import '../../providers/auth_providers.dart';
import '../public/public_league_screen.dart';

typedef LoginEmailPasswordHandler =
    Future<void> Function({
      required String email,
      required String password,
      String? displayName,
    });

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.onEmailPasswordSubmit});

  /// Optional transport seam used by screen-level tests and embedders. Normal
  /// application routing uses [authRepositoryProvider].
  final LoginEmailPasswordHandler? onEmailPasswordSubmit;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode(debugLabel: 'login-name');
  final _emailFocus = FocusNode(debugLabel: 'login-email');
  final _passwordFocus = FocusNode(debugLabel: 'login-password');
  final _signInModeFocus = FocusNode(debugLabel: 'login-mode-sign-in');
  final _createAccountModeFocus = FocusNode(
    debugLabel: 'login-mode-create-account',
  );
  bool _loading = false;
  String? _error;
  bool _isSignUp = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _signInModeFocus.dispose();
    _createAccountModeFocus.dispose();
    super.dispose();
  }

  void _clearTransportError() {
    if (_error != null) setState(() => _error = null);
  }

  void _setSignUp(bool value) {
    if (_loading || value == _isSignUp) return;
    setState(() {
      _isSignUp = value;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (_isSignUp ? _nameFocus : _emailFocus).requestFocus();
    });
  }

  Future<void> _submitEmailPassword() async {
    if (_loading || !(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final handler = widget.onEmailPasswordSubmit;
      if (handler != null) {
        await handler(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          displayName: _isSignUp ? _nameController.text.trim() : null,
        );
      } else if (_isSignUp) {
        await ref
            .read(authRepositoryProvider)
            .signUpFan(
              email: _emailController.text.trim(),
              password: _passwordController.text,
              displayName: _nameController.text.trim(),
            );
      } else {
        await ref
            .read(authRepositoryProvider)
            .signIn(
              email: _emailController.text.trim(),
              password: _passwordController.text,
            );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _friendlyError(error.toString()));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } catch (error) {
      if (mounted) {
        setState(() => _error = _friendlyError(error.toString()));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithApple() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithApple();
    } catch (error) {
      if (mounted) {
        setState(() => _error = _friendlyError(error.toString()));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(String error) {
    if (error.contains('user-not-found')) {
      return 'No account found with that email';
    }
    if (error.contains('wrong-password')) return 'Incorrect password';
    if (error.contains('email-already-in-use')) {
      return 'An account already exists with that email';
    }
    if (error.contains('weak-password')) {
      return 'Password must be at least 6 characters';
    }
    if (error.contains('invalid-email')) {
      return 'Please enter a valid email address';
    }
    if (error.contains('invalid-credential')) {
      return 'Invalid email or password';
    }
    return error.replaceAll(RegExp(r'\[.*?\]'), '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: ((MediaQuery.sizeOf(context).width - 480) / 2).clamp(
                AppSizes.paddingLg,
                double.infinity,
              ),
              vertical: AppSizes.paddingLg,
            ),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                key: const Key('login-form-content'),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/jba_logo.png',
                    width: 100,
                    height: 100,
                    semanticLabel: 'Jamaica Basketball Association logo',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'HoopsConnect',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: context.semanticColors.warning,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    header: true,
                    child: Text(
                      'Jamaica HoopsConnect',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Stay connected with your league',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: _tabButton(
                          'Sign In',
                          !_isSignUp,
                          () => _setSignUp(false),
                          focusNode: _signInModeFocus,
                          key: const Key('login-mode-sign-in'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _tabButton(
                          'Create Account',
                          _isSignUp,
                          () => _setSignUp(true),
                          focusNode: _createAccountModeFocus,
                          key: const Key('login-mode-create-account'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_isSignUp) ...[
                    TextFormField(
                      key: const Key('login-name-field'),
                      controller: _nameController,
                      focusNode: _nameFocus,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person_outlined),
                      ),
                      validator: (value) =>
                          _isSignUp && (value == null || value.trim().isEmpty)
                          ? 'Enter your name'
                          : null,
                      onChanged: (_) => _clearTransportError(),
                      onFieldSubmitted: (_) => _emailFocus.requestFocus(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    key: const Key('login-email-field'),
                    controller: _emailController,
                    focusNode: _emailFocus,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [
                      AutofillHints.username,
                      AutofillHints.email,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Enter your email';
                      }
                      final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                      if (!emailRegex.hasMatch(value.trim())) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                    onChanged: (_) => _clearTransportError(),
                    onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('login-password-field'),
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outlined),
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Enter your password'
                        : null,
                    onChanged: (_) => _clearTransportError(),
                    onFieldSubmitted: (_) {
                      if (!_loading) unawaited(_submitEmailPassword());
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    AppStateMessage(
                      title: _isSignUp
                          ? 'We could not create your account'
                          : 'We could not sign you in',
                      message: _error!,
                      tone: AppStateTone.error,
                      compact: true,
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: AppAsyncActionButton(
                      key: const Key('login-submit-button'),
                      label: _isSignUp ? 'Create Account' : 'Sign In',
                      busyLabel: _isSignUp ? 'Creating account' : 'Signing in',
                      isBusy: _loading,
                      onPressed: _submitEmailPassword,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _loading
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const PublicLeagueScreen(),
                              ),
                            ),
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Browse scores & schedule as a guest'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or continue with',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : _signInWithGoogle,
                          icon: const Text(
                            'G',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: AppColors.google,
                            ),
                          ),
                          label: const Text('Google'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : _signInWithApple,
                          icon: const Icon(Icons.apple, size: 22),
                          label: const Text('Apple'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: _loading ? null : () => context.go('/join'),
                    child: const Text('Have an invite code? Join your team'),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () => context.push('/legal/terms'),
                        child: const Text('Terms of Use'),
                      ),
                      Text(
                        '•',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () => context.push('/legal/privacy'),
                        child: const Text('Privacy Policy'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabButton(
    String label,
    bool active,
    VoidCallback onTap, {
    required FocusNode focusNode,
    required Key key,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        key: key,
        focusNode: focusNode,
        onTap: _loading ? null : onTap,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? colorScheme.primary
                : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
            border: Border.all(
              color: active ? colorScheme.primary : colorScheme.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active
                  ? colorScheme.onPrimary
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
