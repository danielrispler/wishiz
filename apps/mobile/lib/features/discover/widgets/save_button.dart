import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wishiz/core/theme/app_colors.dart';

class SaveButton extends StatefulWidget {
  const SaveButton({
    super.key,
    required this.isSaved,
    required this.onToggle,
    this.size = 44,
  });

  final bool isSaved;
  final ValueChanged<bool> onToggle;
  final double size;

  @override
  State<SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<SaveButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    // Quick down-then-overshoot: 1 → 0.86 → 1.12 → 1
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.86), weight: 25),
      TweenSequenceItem(
        tween: Tween(begin: 0.86, end: 1.12).chain(
          CurveTween(curve: Curves.easeOut),
        ),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.12, end: 1.0).chain(
          CurveTween(curve: Curves.easeIn),
        ),
        weight: 30,
      ),
    ]).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.lightImpact();
    _ctrl.forward(from: 0);
    widget.onToggle(!widget.isSaved);
  }

  @override
  Widget build(BuildContext context) {
    final saved = widget.isSaved;
    final s = widget.size;

    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
            gradient: saved ? null : AppColors.primaryGradient,
            color: saved ? Colors.white : null,
            shape: BoxShape.circle,
            border: saved
                ? Border.all(color: AppColors.primary, width: 2)
                : null,
            boxShadow: [
              BoxShadow(
                color: saved
                    ? const Color(0x1F302950)
                    : const Color(0x664647D3),
                blurRadius: saved ? 16 : 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: saved
                ? const Icon(
                    Icons.bookmark_rounded,
                    color: AppColors.primary,
                    size: 20,
                  )
                : const Icon(
                    Icons.add_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
          ),
        ),
      ),
    );
  }
}
