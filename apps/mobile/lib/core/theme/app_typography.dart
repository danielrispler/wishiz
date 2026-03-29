import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wishiz/core/theme/app_colors.dart';

class AppTypography {
  static TextTheme get textTheme {
    return TextTheme(
      // Display & Headlines (Manrope) - Editorial Voice
      displayMedium: GoogleFonts.manrope(
        fontSize: 44, // 2.75rem ~ 44px
        fontWeight: FontWeight.w700,
        color: AppColors.onSurface,
        letterSpacing: -0.5,
      ),
      headlineSmall: GoogleFonts.manrope(
        fontSize: 24, // 1.5rem ~ 24px
        fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      ),
      titleMedium: GoogleFonts.manrope(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      ),
      titleSmall: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.onPrimary,
      ),
      // Body & Labels (Inter) - Functional Voice
      bodyLarge: GoogleFonts.inter(
        fontSize: 16, // 1rem ~ 16px
        fontWeight: FontWeight.w400,
        color: AppColors.onSurface,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.onSurfaceVariant,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12, // 0.75rem ~ 12px
        fontWeight: FontWeight.w500,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }
}
