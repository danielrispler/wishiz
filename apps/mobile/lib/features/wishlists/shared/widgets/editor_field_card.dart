import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';

class EditorFieldCard extends StatelessWidget {
  const EditorFieldCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.cardPadding,
        vertical: AppConstants.itemGap,
      ),
      child: child,
    );
  }
}
