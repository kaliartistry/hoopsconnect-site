import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AccessDeniedScreen extends StatelessWidget {
  const AccessDeniedScreen({super.key, required this.startLocation});

  final String startLocation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shield_outlined, size: 48),
                const SizedBox(height: 16),
                Text(
                  'This tool is not available for your account',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your league access is working, but this destination needs a permission your current membership does not have. If your responsibilities changed, ask an association administrator to review your membership.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('access-denied-start'),
                  onPressed: () => context.go(startLocation),
                  child: const Text('Go to my start page'),
                ),
                TextButton(
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go(startLocation),
                  child: const Text('Go back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
