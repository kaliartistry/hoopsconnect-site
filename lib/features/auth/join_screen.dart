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
    if (code.isEmpty) return;

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

  Future<void> _joinTeam() async {
    if (_validatedCode == null || _validatedSecret == null) return;
    final existingAuth = ref.read(authRepositoryProvider).currentUser != null;
    if (_nameController.text.trim().isEmpty ||
        (!existingAuth &&
            (_emailController.text.trim().isEmpty ||
                _passwordController.text.isEmpty))) {
      setState(() => _error = 'Please fill in all fields');
      return;
    }

    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!existingAuth && !emailRegex.hasMatch(_emailController.text.trim())) {
      setState(() => _error = 'Please enter a valid email address');
      return;
    }

    if (!existingAuth && _passwordController.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final authRepository = ref.read(authRepositoryProvider);
      if (authRepository.currentUser == null) {
        await authRepository.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        _ownsPendingAuthIdentity = true;
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
          ownsPendingIdentity: _ownsPendingAuthIdentity,
          error: e,
        )) {
          await ref.read(authRepositoryProvider).deleteCurrentAuthUser();
        }
        _codeController.clear();
        _validatedSecret = null;
        _redeemOperationId = null;
        _ownsPendingAuthIdentity = false;
      }
      if (mounted) {
        setState(() {
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

                // Invite code input
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

                if (_validatedCode == null)
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

                // Code verified — show form
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
                        const Text(
                          'Code verified',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.infoDark,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'Joining as ${_validatedCode!.role.toUpperCase()}',
                          style: const TextStyle(
                            color: AppColors.info,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
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
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
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
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _joinTeam,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Join Team'),
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
                if (existingAuth == null)
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
