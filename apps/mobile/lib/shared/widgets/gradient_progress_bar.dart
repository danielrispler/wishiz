import 'package:flutter/material.dart';
import 'package:wishiz/core/theme/app_colors.dart';

/// A brand-gradient progress bar.
///
/// - [value] in 0..1 → determinate: the gradient fill glides to the new value
///   (450ms easeOut) so polled jumps read as smooth motion.
/// - [value] == null → indeterminate: a gradient band sweeps across the track,
///   for the "just claimed, no percent yet" moment.
///
/// Replaces the stock gray [LinearProgressIndicator]; tests can read [value]
/// directly off the widget rather than depending on Material internals.
class GradientProgressBar extends StatefulWidget {
  const GradientProgressBar({super.key, this.value, this.height = 4});

  /// Fraction filled (0..1), or null for an indeterminate sweep.
  final double? value;
  final double height;

  @override
  State<GradientProgressBar> createState() => _GradientProgressBarState();
}

class _GradientProgressBarState extends State<GradientProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.height);
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: widget.height,
        child: DecoratedBox(
          decoration: const BoxDecoration(color: AppColors.surfaceVariant),
          child: widget.value == null ? _buildIndeterminate() : _buildFill(),
        ),
      ),
    );
  }

  Widget _buildFill() {
    final target = widget.value!.clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
      builder: (context, v, _) => Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: v == 0 ? 0.0001 : v,
          child: const DecoratedBox(
            decoration: BoxDecoration(gradient: AppColors.primaryGradient),
          ),
        ),
      ),
    );
  }

  Widget _buildIndeterminate() {
    return AnimatedBuilder(
      animation: _sweep,
      builder: (context, _) {
        // A ~40%-wide band travels left→right across the track. Alignment.x
        // -1 parks the band at the far left, +1 at the far right.
        final x = -1.0 + 2.0 * _sweep.value;
        return Align(
          alignment: Alignment(x, 0),
          child: FractionallySizedBox(
            widthFactor: 0.4,
            child: const DecoratedBox(
              decoration: BoxDecoration(gradient: AppColors.primaryGradient),
            ),
          ),
        );
      },
    );
  }
}
