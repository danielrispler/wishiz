import 'package:flutter/material.dart';

class WishizWordmark extends StatelessWidget {
  const WishizWordmark({
    super.key,
    this.height = 56,
    this.alignment = Alignment.centerLeft,
  });

  final double height;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Image.asset(
        'assets/branding/wishiz_wordmark.png',
        height: height,
        fit: BoxFit.contain,
      ),
    );
  }
}
