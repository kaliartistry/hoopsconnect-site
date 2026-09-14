import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/widgets/app_form_controls.dart';
import '../../core/widgets/app_state_message.dart';
import '../../providers/auth_providers.dart';
import 'auth_error_message.dart';

abstract interface class PasswordRecoveryActions {
  Future<void> sendResetEmail(String email);
}

class RepositoryPasswordRecoveryActions implements PasswordRecoveryActions {
  const RepositoryPasswordRecoveryActions(this._ref);

  final Ref _ref;

  @override
  Future<void> sendResetEmail(String email) {
    return _ref.read(authRepositoryProvider).sendPasswordResetEmail(email);
  }
}

final passwordRecoveryActionsProvider = Provider<PasswordRecoveryActions>((
  ref,
) {
  return RepositoryPasswordRecoveryActions(ref);
});

class PasswordRecoveryScreen extends ConsumerStatefulWidget {
  const PasswordRecoveryScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  ConsumerState<PasswordRecoveryScreen> createState() =>
      _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState
    extends ConsumerState<PasswordRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(
      text: widget.initialEmail?.trim() ?? '',
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _sending = true;
      _error = null;
      _sent = false;
    });
    try {
      await ref
          .read(passwordRecoveryActionsProvider)
          .sendResetEmail(_emailController.text.trim());
      if (mounted) setState(() => _sent = true);
    } catch (error) {
      if (!mounted) return;
      if (passwordResetShouldAppearSuccessful(error)) {
        setState(() => _sent = true);
        return;
      }
      setState(() {
        _error =
            friendlyAuthErrorMessage(error) ??
            'The reset was cancelled. You can try again when you are ready.';
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.paddingLg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'Get back into your account',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'For an email and password account, we will send a reset link. If you normally use Google or Apple, return to sign in and choose that provider.',
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      key: const Key('recovery-email-field'),
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isEmpty) return 'Enter your email';
                        if (!RegExp(
                          r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                        ).hasMatch(email)) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                      onChanged: (_) {
                        if (_error != null || _sent) {
                          setState(() {
                            _error = null;
                            _sent = false;
                          });
                        }
                      },
                      onFieldSubmitted: (_) => _send(),
                    ),
                    if (_sent) ...[
                      const SizedBox(height: 16),
                      const AppStateMessage(
                        title: 'Check your email',
                        message:
                            'If an email account matches that address, a password reset link is on its way.',
                        tone: AppStateTone.success,
                        compact: true,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      AppStateMessage(
                        title: 'We could not send the reset link',
                        message: _error!,
                        tone: AppStateTone.error,
                        compact: true,
                      ),
                    ],
                    const SizedBox(height: 20),
                    AppAsyncActionButton(
                      key: const Key('recovery-submit-button'),
                      label: _sent ? 'Send another link' : 'Send Reset Link',
                      busyLabel: 'Sending reset link',
                      isBusy: _sending,
                      onPressed: _send,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _sending ? null : () => context.go('/login'),
                      child: const Text('Back to sign in'),
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
}
