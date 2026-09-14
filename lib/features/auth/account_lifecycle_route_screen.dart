import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum AccountLifecycleDestination { request, status, reconcileDeviceWork }

class AccountLifecycleRouteScreen extends StatelessWidget {
  const AccountLifecycleRouteScreen({
    super.key,
    required this.destination,
    required this.isSignedIn,
  });

  final AccountLifecycleDestination destination;
  final bool isSignedIn;

  @override
  Widget build(BuildContext context) {
    final (title, message) = switch (destination) {
      AccountLifecycleDestination.request => (
        'Account deletion',
        'The secure deletion request flow is being connected to this route. No account changes have been made.',
      ),
      AccountLifecycleDestination.status => (
        'Deletion status',
        'This route will show coarse cleanup progress using the deletion status capability, even after sign-in has been removed.',
      ),
      AccountLifecycleDestination.reconcileDeviceWork => (
        'Review work saved on this device',
        'Official game work must be submitted, handed off, or explicitly discarded before account cleanup can continue.',
      ),
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.manage_accounts_outlined, size: 52),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                if (!isSignedIn &&
                    destination != AccountLifecycleDestination.status)
                  FilledButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Sign in'),
                  )
                else
                  FilledButton.tonal(
                    onPressed: () =>
                        context.go(isSignedIn ? '/profile' : '/login'),
                    child: Text(
                      isSignedIn ? 'Back to profile' : 'Back to sign in',
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
