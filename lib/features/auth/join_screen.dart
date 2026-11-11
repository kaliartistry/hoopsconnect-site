import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../models/invite_code_model.dart';
import '../../providers/auth_providers.dart';
import '../../services/repositories/invite_code_repository.dart';

class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key});

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _reviewing = false;
  bool _joinAttempted = false;
  String? _reviewedUid;
  String? _error;
  InviteCodeModel? _validatedCode;
  String? _validatedSecret;
  String? _redeemOperationId;
  bool _ownsPendingAuthIdentity = false;

  @override
  void dispose() {
    _validatedSecret = null;
    _redeemOperationId = null;
    _codeController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _validateCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || _loading || _validatedCode != null) return;

    setState(() {
      _loading = true;
      _error = null;
      _validatedCode = null;
      _validatedSecret = null;
      _redeemOperationId = null;
    });

    try {
      final inviteCode = await ref
          .read(inviteCodeRepositoryProvider)
          .validateCode(code);
      if (!mounted) return;
      if (inviteCode == null) {
        setState(() {
          _error = 'Invalid or expired invite code';
          _validatedSecret = null;
        });
      } else {
        final existingName = ref
            .read(authRepositoryProvider)
            .currentUser
            ?.displayName;
        if (_nameController.text.isEmpty && existingName != null) {
          _nameController.text = existingName;
        }
        setState(() {
          _validatedCode = inviteCode;
          // The inspection callable never echoes the bearer. Keep exactly the
          // inspected entry only in this screen's transient state.
          _validatedSecret = code;
          _redeemOperationId = newInviteOperationId();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _reviewJoin() {
    final authUser = ref.read(authRepositoryProvider).currentUser;
    final name = _nameController.text.trim();
    if (name.isEmpty ||
        (authUser == null &&
            (_emailController.text.trim().isEmpty ||
                _passwordController.text.isEmpty))) {
      setState(() => _error = 'Please fill in all fields');
      return;
    }
    if (name.length > 120) {
      setState(() => _error = 'Use up to 120 characters for your name');
      return;
    }

    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (authUser == null &&
        !emailRegex.hasMatch(_emailController.text.trim())) {
      setState(() => _error = 'Please enter a valid email address');
      return;
    }

    if (authUser == null && _passwordController.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _reviewedUid = authUser?.uid;
      _reviewing = true;
      _error = null;
    });
  }

  Future<void> _joinTeam() async {
    if (_loading || !_reviewing || _validatedSecret == null) return;
    final authRepository = ref.read(authRepositoryProvider);
    if (authRepository.currentUser?.uid != _reviewedUid) {
      setState(() {
        _error = 'The signed-in account changed. Review your details again.';
        _reviewing = false;
        _joinAttempted = false;
        _ownsPendingAuthIdentity = false;
        _redeemOperationId = newInviteOperationId();
      });
      return;
    }

    setState(() {
      _loading = true;
      _joinAttempted = true;
      _error = null;
    });

    try {
      if (authRepository.currentUser == null) {
        final credential = await authRepository.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        _reviewedUid = credential.user?.uid;
        _ownsPendingAuthIdentity = _reviewedUid != null;
        if (_reviewedUid == null ||
            authRepository.currentUser?.uid != _reviewedUid) {
          throw StateError(
            'Sign in to the new account and verify your invite again.',
          );
        }
      }

      await ref
          .read(inviteCodeRepositoryProvider)
          .redeemCode(
            code: _validatedSecret!,
            displayName: _nameController.text.trim(),
            operationId: _redeemOperationId ??= newInviteOperationId(),
          );
      _codeController.clear();
      _validatedSecret = null;
      _redeemOperationId = null;
      _ownsPendingAuthIdentity = false;
    } catch (e) {
      final disposition = inviteFailureDisposition(e);
      if (disposition == InviteFailureDisposition.terminal) {
        if (shouldDeletePendingAuthIdentity(
          ownsPendingIdentity:
              _ownsPendingAuthIdentity &&
              authRepository.currentUser?.uid == _reviewedUid,
          error: e,
        )) {
          await authRepository.deleteCurrentAuthUser();
        }
        _codeController.clear();
        _validatedSecret = null;
        _redeemOperationId = null;
        _ownsPendingAuthIdentity = false;
      }
      if (mounted) {
        setState(() {
          if (disposition == InviteFailureDisposition.terminal) {
            _validatedCode = null;
            _reviewing = false;
            _joinAttempted = false;
          }
          _error = disposition == InviteFailureDisposition.ambiguous
              ? 'We could not confirm the result. Your account was kept safe; tap Join again to resume the same request.'
              : _friendlyInviteError(e);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyInviteError(Object error) {
    final text = error.toString();
    if (text.contains('failed-precondition') || text.contains('not-found')) {
      return 'This invite is invalid, expired, revoked, or already used.';
    }
    if (text.contains('already-exists')) {
      return 'This account already has a league membership.';
    }
    if (text.contains('email-already-in-use')) {
      return 'An account already exists with that email. Sign in first.';
    }
    return text.replaceAll(RegExp(r'\[.*?\]'), '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final existingAuth = ref.watch(authStateProvider).value;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.paddingLg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                  child: Image.asset(
                    'assets/images/jba_logo.png',
                    width: 80,
                    height: 80,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'HoopsConnect',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accent,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Join Jamaica HoopsConnect',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Stay connected with your league',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 32),

                if (_validatedCode == null) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'INVITE CODE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _codeController,
                    enabled: !_loading,
                    autocorrect: false,
                    enableSuggestions: false,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      fontFamily: 'monospace',
                    ),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 2,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _validateCode(),
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _loading ? null : _validateCode,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Verify Code'),
                    ),
                  ),
                ],

                if (_validatedCode != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.infoBg,
                      border: Border.all(color: AppColors.infoBorder),
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _reviewing
                              ? 'Review your details'
                              : 'Invite verified',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.infoDark,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'Joining as ${_validatedCode!.role == 'rep' ? 'team representative' : _validatedCode!.role}',
                          style: const TextStyle(
                            color: AppColors.info,
                            fontSize: 12,
                          ),
                        ),
                        if (_validatedCode!.teamName case final teamName?)
                          Text(teamName),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_reviewing) ...[
                    Text(
                      _nameController.text.trim(),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      existingAuth?.email ??
                          (_reviewedUid == null
                              ? _emailController.text.trim()
                              : 'Signed-in account'),
                    ),
                  ] else ...[
                    TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person_outlined),
                      ),
                    ),
                    if (existingAuth == null) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock_outlined),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      Text(
                        'Continue as ${existingAuth.email ?? 'the signed-in account'}',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading
                          ? null
                          : _reviewing
                          ? _joinTeam
                          : _reviewJoin,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_reviewing ? 'Join Team' : 'Review details'),
                    ),
                  ),
                  if (!_loading && !_joinAttempted)
                    TextButton(
                      onPressed: () => setState(() {
                        _error = null;
                        if (_reviewing) {
                          _reviewing = false;
                        } else {
                          _validatedCode = null;
                          _validatedSecret = null;
                          _redeemOperationId = null;
                        }
                      }),
                      child: Text(
                        _reviewing ? 'Edit details' : 'Use a different code',
                      ),
                    ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.urgent,
                      fontSize: 13,
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                if (_loading)
                  const SizedBox.shrink()
                else if (existingAuth == null)
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text(
                      'Already have an account? Sign in',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  )
                else
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => ref.read(authRepositoryProvider).signOut(),
                    child: const Text(
                      'Sign out and use another account',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
