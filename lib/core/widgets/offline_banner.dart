import 'package:flutter/material.dart';

/// A small persistent banner displayed when the device is offline.
/// Animates in/out with a slide + size transition.
class OfflineBanner extends StatelessWidget {
  final bool isOffline;

  const OfflineBanner({super.key, required this.isOffline});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: isOffline
          ? MaterialBanner(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              backgroundColor: const Color(0xFFF59E0B), // amber-500
              leading: const Icon(
                Icons.cloud_off,
                color: Colors.white,
                size: 20,
              ),
              content: const Text(
                "You're offline \u2014 changes will sync when reconnected",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              actions: const [SizedBox.shrink()],
            )
          : const SizedBox.shrink(),
    );
  }
}
