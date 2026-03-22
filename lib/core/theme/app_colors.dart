import 'package:flutter/material.dart';

class AppColors {
  // Base Layer
  static const Color surface = Color(0xFFFAF4FF);
  // Secondary Tier
  static const Color surfaceContainerLow = Color(0xFFF4EEFF);
  // Primary Content Tier (Cards)
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);

  // Primary Gradient & CTA
  static const Color primary = Color(0xFF4647D3);
  static const Color primaryContainer = Color(0xFF9396FF);
  static const Color onPrimary = Color(0xFFF4F1FF);

  // Text & Icons
  static const Color onSurface = Color(0xFF302950);
  static const Color onSurfaceVariant = Color(0xFF5E5680);

  // Effects & Dividers
  static const Color surfaceVariant = Color(0xFFE1D8FF); // for glassmorphism
  static const Color outlineVariant =
      Color(0xFFB0A7D6); // 15% opacity for ghost borders

  // Others based on Stitch MCP
  static const Color errorContainer = Color(0xFFF74B6D);
  static const Color onErrorContainer = Color(0xFF510017);
  static const Color tertiary = Color(0xFF006A2D);
}
