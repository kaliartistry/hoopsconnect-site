import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// Animated shimmer effect for skeleton loading placeholders.
class _ShimmerEffect extends StatefulWidget {
  final Widget child;
  const _ShimmerEffect({required this.child});

  @override
  State<_ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<_ShimmerEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: Theme.of(context).brightness == Brightness.dark
                  ? const [
                      Color(0xFF2C2C2C),
                      Color(0xFF3A3A3A),
                      Color(0xFF2C2C2C),
                    ]
                  : const [
                      Color(0xFFE5E7EB),
                      Color(0xFFF3F4F6),
                      Color(0xFFE5E7EB),
                    ],
              stops: [
                _animation.value - 0.3,
                _animation.value,
                _animation.value + 0.3,
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// A single rounded rectangle placeholder block.
class _SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const _SkeletonBox({
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 6,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Skeleton placeholder for board post cards.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return _ShimmerEffect(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author row
            Row(
              children: [
                _SkeletonBox(width: 32, height: 32, borderRadius: 16),
                SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBox(width: 100, height: 12),
                    SizedBox(height: 4),
                    _SkeletonBox(width: 60, height: 10),
                  ],
                ),
              ],
            ),
            SizedBox(height: 12),
            // Title
            _SkeletonBox(width: 200, height: 14),
            SizedBox(height: 8),
            // Body lines
            _SkeletonBox(height: 12),
            SizedBox(height: 6),
            _SkeletonBox(height: 12),
            SizedBox(height: 6),
            _SkeletonBox(width: 160, height: 12),
          ],
        ),
      ),
    );
  }
}

/// Skeleton placeholder for standings / leaderboard rows.
class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({super.key});

  @override
  Widget build(BuildContext context) {
    return _ShimmerEffect(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.border, width: 0.5),
          ),
        ),
        child: const Row(
          children: [
            _SkeletonBox(width: 24, height: 16),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonBox(width: 120, height: 14),
                  SizedBox(height: 4),
                  _SkeletonBox(width: 80, height: 10),
                ],
              ),
            ),
            _SkeletonBox(width: 40, height: 18),
          ],
        ),
      ),
    );
  }
}

/// Skeleton placeholder for stat entry grid.
class SkeletonStatGrid extends StatelessWidget {
  const SkeletonStatGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return _ShimmerEffect(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Score header placeholder
            Builder(
              builder: (context) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return Container(
                  height: 72,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF2C2C2C)
                        : const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            // Table header
            const _SkeletonBox(height: 28),
            const SizedBox(height: 8),
            // Player rows
            for (int i = 0; i < 5; i++) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    _SkeletonBox(width: 80, height: 20),
                    SizedBox(width: 8),
                    Expanded(child: _SkeletonBox(height: 20)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Convenience: builds a column of skeleton cards for loading lists.
class SkeletonCardList extends StatelessWidget {
  final int count;
  const SkeletonCardList({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      itemBuilder: (_, _) => const SkeletonCard(),
    );
  }
}

/// Convenience: builds a column of skeleton list tiles.
class SkeletonListTileList extends StatelessWidget {
  final int count;
  const SkeletonListTileList({super.key, this.count = 8});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      itemBuilder: (_, _) => const SkeletonListTile(),
    );
  }
}
