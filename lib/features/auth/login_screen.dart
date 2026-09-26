import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_route_contract.dart';
import '../../core/constants/app_constants.dart';
import '../../core/time/league_time.dart';
import '../../core/widgets/app_form_controls.dart';
import '../../core/widgets/app_state_message.dart';
import '../../models/public_league_snapshot.dart';
import '../../platform/presentation_preview_environment.dart';
import '../../providers/public_league_provider.dart';
import 'auth_error_message.dart';
import 'login_auth_actions.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    super.key,
    this.requestedLocation,
    this.presentationPreview = PresentationPreviewEnvironment.enabled,
  });

  final String? requestedLocation;
  final bool presentationPreview;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _memberAccessKey = GlobalKey();
  final _scrollController = ScrollController();
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

  bool get _openedForFollowingTeams =>
      Uri.tryParse(
        AppRouteContract.safeRequestedLocation(widget.requestedLocation) ?? '',
      )?.path ==
      '/settings';

  @override
  void initState() {
    super.initState();
    if (_openedForFollowingTeams) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final memberAccessContext = _memberAccessKey.currentContext;
        if (!mounted || memberAccessContext == null) return;
        Scrollable.ensureVisible(
          memberAccessContext,
          alignment: 0.08,
          duration: Duration.zero,
        );
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
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
    if (widget.presentationPreview ||
        _loading ||
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

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
    if (widget.presentationPreview || _loading) return;
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
    if (widget.presentationPreview || _loading) return;
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
    final followingTeams = _openedForFollowingTeams;

    final overlayStyle = theme.brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              key: const Key('login-scroll-view'),
              controller: _scrollController,
              padding: EdgeInsets.symmetric(
                horizontal: ((MediaQuery.sizeOf(context).width - 480) / 2)
                    .clamp(AppSizes.paddingLg, double.infinity),
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
                        color: theme.brightness == Brightness.dark
                            ? AppColors.accent
                            : AppColors.primaryDark,
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
                    if (followingTeams) ...[
                      const SizedBox(height: 12),
                      const AppStateMessage(
                        key: Key('follow-teams-login-context'),
                        title: 'Follow your teams',
                        message:
                            'Sign in or create a fan account, then choose teams and score notifications.',
                        icon: Icons.notifications_active_outlined,
                        compact: true,
                      ),
                    ],
                    const SizedBox(height: 20),
                    _LeagueSneakPeek(
                      snapshot: publicSnapshot,
                      enabled: !_loading,
                      onBrowse: () => context.go(PublicRoutePaths.games),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      key: _memberAccessKey,
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
                    if (widget.presentationPreview) ...[
                      const SizedBox(height: 12),
                      const AppStateMessage(
                        key: Key('presentation-preview-account-notice'),
                        title: 'Presentation preview',
                        message:
                            'Member access is shown for review. Account actions are disabled on this public preview.',
                        icon: Icons.visibility_outlined,
                        compact: true,
                      ),
                    ],
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
                              enabled: !widget.presentationPreview,
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
                              onFieldSubmitted: (_) =>
                                  _emailFocus.requestFocus(),
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextFormField(
                            key: const Key('login-email-field'),
                            controller: _emailController,
                            enabled: !widget.presentationPreview,
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
                            enabled: !widget.presentationPreview,
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
                        busyLabel: _isSignUp
                            ? 'Creating account'
                            : 'Signing in',
                        isBusy: _loading,
                        onPressed: widget.presentationPreview
                            ? null
                            : _submitEmailPassword,
                        disabledHint: widget.presentationPreview
                            ? 'Account actions are disabled on this presentation preview.'
                            : null,
                      ),
                    ),
                    if (!_isSignUp) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          key: const Key('forgot-password-link'),
                          onPressed: _loading || widget.presentationPreview
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
                            onPressed: _loading || widget.presentationPreview
                                ? null
                                : _signInWithGoogle,
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
                            onPressed: _loading || widget.presentationPreview
                                ? null
                                : _signInWithApple,
                            icon: const Icon(Icons.apple, size: 22),
                            label: const Text('Apple'),
                          ),
                        ),
                      ],
                    ),
                    if (kIsWeb &&
                        !_isSignUp &&
                        !widget.presentationPreview) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Assigned a staff account? Sign in with its email first, then connect Google or Apple in Profile to keep your access.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: _loading || widget.presentationPreview
                          ? null
                          : () => context.go('/join'),
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
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        key: const Key('league-sneak-peek'),
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryDark, AppColors.primary],
          ),
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(height: 4, color: AppColors.accent),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.sports_basketball,
                        color: AppColors.accent,
                        size: 22,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'JBA Scoreboard',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                      Text(
                        'NO SIGN-IN',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.9,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  const SizedBox(height: 14),
                  snapshot.when(
                    loading: () => Text(
                      'Loading the latest public league update…',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    error: (_, _) => Text(
                      'Public updates are temporarily unavailable. Open the full scoreboard to try again.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    data: (data) => _LeaguePeekContent(snapshot: data),
                  ),
                ],
              ),
            ),
            Semantics(
              button: true,
              enabled: enabled,
              excludeSemantics: true,
              label: 'Full scores and schedule. No account needed.',
              child: Material(
                color: enabled ? AppColors.primary : AppColors.textSecondary,
                child: InkWell(
                  key: const Key('browse-public-league-button'),
                  onTap: enabled ? onBrowse : null,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Full scores & schedule',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
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
          _LeaguePeekGame(
            label: 'LATEST RESULT',
            leagueName: data
                .leagueForDivision(finals.first.divisionId)
                .shortName,
            game: finals.first,
          ),
        if (finals.isNotEmpty && scheduled.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Divider(
              height: 1,
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
        if (scheduled.isNotEmpty)
          _LeaguePeekGame(
            label: 'UP NEXT',
            leagueName: data
                .leagueForDivision(scheduled.first.divisionId)
                .shortName,
            game: scheduled.first,
          ),
      ],
    );
  }

  Widget _fallback(BuildContext context) => Text(
    'Published league updates will appear here as soon as they are available.',
    style: Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
  );
}

class _LeaguePeekGame extends StatelessWidget {
  const _LeaguePeekGame({
    required this.label,
    required this.leagueName,
    required this.game,
  });

  final String label;
  final String leagueName;
  final PublicGame game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final home = game.homeTeamName ?? 'Home team';
    final away = game.awayTeamName ?? 'Away team';
    final isFinal = game.status == PublicGameStatus.finalResult;
    final timing = isFinal
        ? LeagueTime.formatJamaicaDate(game.startTime, pattern: 'MMM d')
        : '${LeagueTime.formatJamaicaDate(game.startTime, pattern: 'EEE, MMM d')} · ${LeagueTime.formatJamaicaTime(game.startTime)}';
    final spokenTiming = isFinal
        ? timing
        : '${LeagueTime.formatJamaicaDate(game.startTime, pattern: 'EEE, MMM d')} '
              'at ${LeagueTime.formatJamaicaTime(game.startTime, includeZone: false)}';
    final homeWon =
        isFinal &&
        game.homeScore != null &&
        game.awayScore != null &&
        game.homeScore! > game.awayScore!;
    final awayWon =
        isFinal &&
        game.homeScore != null &&
        game.awayScore != null &&
        game.awayScore! > game.homeScore!;
    final venue = game.venue?.trim();
    final semanticLabel = isFinal
        ? '$label. $leagueName. Final. $away ${game.awayScore ?? 'not available'}, away. '
              '$home ${game.homeScore ?? 'not available'}, home. $spokenTiming.'
        : '$label. $leagueName. $away, away, at $home, home. $spokenTiming Jamaica time.'
              '${venue == null || venue.isEmpty ? '' : ' Venue: $venue.'}';

    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                child: Text(
                  leagueName.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 9,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isFinal ? 'FINAL · $timing' : timing.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (isFinal) ...[
            _ScoreboardTeamRow(
              name: away,
              score: game.awayScore,
              isWinner: awayWon,
            ),
            const SizedBox(height: 7),
            _ScoreboardTeamRow(
              name: home,
              score: game.homeScore,
              isWinner: homeWon,
            ),
          ] else ...[
            _UpcomingTeamRow(name: away, location: 'AWAY'),
            const SizedBox(height: 7),
            _UpcomingTeamRow(name: home, location: 'HOME'),
            if (game.venue != null && game.venue!.trim().isNotEmpty) ...[
              const SizedBox(height: 7),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: AppColors.textMuted,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      game.venue!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ScoreboardTeamRow extends StatelessWidget {
  const _ScoreboardTeamRow({
    required this.name,
    required this.score,
    required this.isWinner,
  });

  final String name;
  final int? score;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 3,
          height: 20,
          color: isWinner ? AppColors.accent : Colors.transparent,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: isWinner ? Colors.white : const Color(0xFFD1D5DB),
              fontWeight: isWinner ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          score?.toString() ?? '–',
          style: theme.textTheme.titleLarge?.copyWith(
            color: isWinner ? Colors.white : const Color(0xFFD1D5DB),
            fontWeight: FontWeight.w800,
            height: 1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _UpcomingTeamRow extends StatelessWidget {
  const _UpcomingTeamRow({required this.name, required this.location});

  final String name;
  final String location;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          location,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.textMuted,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}
