import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_route_contract.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/time/league_time.dart';
import '../../core/widgets/app_form_controls.dart';
import '../../core/widgets/app_state_message.dart';
import '../../models/public_league_snapshot.dart';
import '../../providers/public_league_provider.dart';
import 'auth_error_message.dart';
import 'login_auth_actions.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

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
      final actions = ref.read(loginAuthActionsProvider);
      if (_isSignUp) {
        await actions.signUpFan(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          displayName: _nameController.text.trim(),
        );
      } else {
        await actions.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = friendlyAuthErrorMessage(error));
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
      await ref.read(loginAuthActionsProvider).signInWithGoogle();
    } catch (error) {
      if (mounted) {
        setState(() => _error = friendlyAuthErrorMessage(error));
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
      await ref.read(loginAuthActionsProvider).signInWithApple();
    } catch (error) {
      if (mounted) {
        setState(() => _error = friendlyAuthErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final publicSnapshot = ref.watch(publicLeagueSnapshotProvider);

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
                  const SizedBox(height: 20),
                  _LeagueSneakPeek(
                    snapshot: publicSnapshot,
                    enabled: !_loading,
                    onBrowse: () => context.go(PublicRoutePaths.games),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'member access',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 20),
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
                  AutofillGroup(
                    child: Column(
                      children: [
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
                                _isSignUp &&
                                    (value == null || value.trim().isEmpty)
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
                            final emailRegex = RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            );
                            if (!emailRegex.hasMatch(value.trim())) {
                              return 'Enter a valid email address';
                            }
                            return null;
                          },
                          onChanged: (_) => _clearTransportError(),
                          onFieldSubmitted: (_) =>
                              _passwordFocus.requestFocus(),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const Key('login-password-field'),
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          autofillHints: [
                            _isSignUp
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
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
                      ],
                    ),
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
                  if (!_isSignUp) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        key: const Key('forgot-password-link'),
                        onPressed: _loading
                            ? null
                            : () {
                                final email = _emailController.text.trim();
                                context.push(
                                  Uri(
                                    path: '/recover-password',
                                    queryParameters: email.isEmpty
                                        ? null
                                        : {'email': email},
                                  ).toString(),
                                );
                              },
                        child: const Text('Forgot password?'),
                      ),
                    ),
                  ],
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
    return MergeSemantics(
      child: Semantics(
        selected: active,
        child: ListenableBuilder(
          listenable: focusNode,
          builder: (context, child) {
            final focused = focusNode.hasFocus;
            final borderColor = focused
                ? active
                      ? colorScheme.onPrimary
                      : colorScheme.primary
                : active
                ? colorScheme.primary
                : colorScheme.outlineVariant;
            final shape = RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              side: BorderSide(color: borderColor, width: focused ? 3 : 1),
            );

            return Material(
              key: key,
              color: active
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerLow,
              shape: shape,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                focusNode: focusNode,
                onTap: _loading ? null : onTap,
                customBorder: shape,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
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
          },
        ),
      ),
    );
  }
}

class _LeagueSneakPeek extends StatelessWidget {
  const _LeagueSneakPeek({
    required this.snapshot,
    required this.enabled,
    required this.onBrowse,
  });

  final AsyncValue<PublicLeagueSnapshot?> snapshot;
  final bool enabled;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semanticColors = context.semanticColors;
    return Semantics(
      container: true,
      label:
          'League sneak peek. Public scores and schedule. No account needed.',
      child: Container(
        key: const Key('league-sneak-peek'),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: semanticColors.warningContainer,
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          border: Border.all(color: semanticColors.warning, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.sports_basketball,
                  color: semanticColors.warning,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'League sneak peek',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: semanticColors.onWarningContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Latest scores and what is coming up. No sign-in needed.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: semanticColors.onWarningContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            snapshot.when(
              loading: () => Text(
                'Loading the latest public league update…',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: semanticColors.onWarningContainer,
                ),
              ),
              error: (_, _) => Text(
                'Public updates are temporarily unavailable. You can still open the league page and try again.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: semanticColors.onWarningContainer,
                ),
              ),
              data: (data) => _LeaguePeekContent(snapshot: data),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('browse-public-league-button'),
                onPressed: enabled ? onBrowse : null,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('View scores & schedule'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaguePeekContent extends StatelessWidget {
  const _LeaguePeekContent({required this.snapshot});

  final PublicLeagueSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final data = snapshot;
    if (data == null || data.version.state != PublicReleaseState.published) {
      return _fallback(context);
    }

    final finals =
        data.schedule
            .where((game) => game.status == PublicGameStatus.finalResult)
            .toList(growable: false)
          ..sort((a, b) => b.startTime.compareTo(a.startTime));
    final now = DateTime.now().toUtc();
    final scheduled =
        data.schedule
            .where(
              (game) =>
                  game.status == PublicGameStatus.scheduled &&
                  game.startTime.isAfter(now),
            )
            .toList(growable: false)
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
    if (finals.isEmpty && scheduled.isEmpty) return _fallback(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (finals.isNotEmpty)
          _LeaguePeekGame(label: 'LATEST RESULT', game: finals.first),
        if (finals.isNotEmpty && scheduled.isNotEmpty)
          const SizedBox(height: 10),
        if (scheduled.isNotEmpty)
          _LeaguePeekGame(label: 'NEXT GAME', game: scheduled.first),
      ],
    );
  }

  Widget _fallback(BuildContext context) => Text(
    'Published league updates will appear here as soon as they are available.',
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: context.semanticColors.onWarningContainer,
    ),
  );
}

class _LeaguePeekGame extends StatelessWidget {
  const _LeaguePeekGame({required this.label, required this.game});

  final String label;
  final PublicGame game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = context.semanticColors.onWarningContainer;
    final home = game.homeTeamName ?? 'Home team';
    final away = game.awayTeamName ?? 'Away team';
    final isFinal = game.status == PublicGameStatus.finalResult;
    final matchup = isFinal
        ? '$home ${game.homeScore ?? '–'}  ·  ${game.awayScore ?? '–'} $away'
        : '$home vs $away';
    final timing = isFinal
        ? LeagueTime.formatJamaicaDate(game.startTime, pattern: 'MMM d')
        : '${LeagueTime.formatJamaicaDate(game.startTime, pattern: 'EEE, MMM d')} · ${LeagueTime.formatJamaicaTime(game.startTime)}';

    return Semantics(
      label: '$label. $matchup. $timing.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            matchup,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            timing,
            style: theme.textTheme.bodySmall?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}
