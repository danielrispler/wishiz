import 'package:flutter/material.dart';
import 'package:wishiz/core/theme/app_colors.dart';

/// A skeleton placeholder box with a brand-tinted gradient sweeping across it.
///
/// Used while content is loading (e.g. an import tile waiting for the scraper).
/// The sweep is a single repeating [AnimationController] driving a translated
/// [LinearGradient]; it is cheap and self-contained, so it can stand in for any
/// rectangular slot — a thumbnail, a ghost title line, a ghost price line.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
  });

  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(8);
    return ClipRRect(
      borderRadius: radius,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // Slide the highlight band from off-left to off-right and back.
          final t = _controller.value;
          final dx = -1.0 + 3.0 * t;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(dx - 1, 0),
                end: Alignment(dx + 1, 0),
                colors: const [
                  AppColors.surfaceContainerLow,
                  AppColors.surfaceVariant,
                  AppColors.surfaceContainerLow,
                ],
                stops: const [0.35, 0.5, 0.65],
              ),
            ),
            child: SizedBox(width: widget.width, height: widget.height),
          );
        },
      ),
    );
  }
}
