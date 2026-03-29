import 'package:flutter/material.dart';
import 'package:wishiz/core/theme/app_colors.dart';
import 'package:wishiz/core/theme/app_typography.dart';
import 'package:wishiz/core/constants/app_constants.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        primaryContainer: AppColors.primaryContainer,
      ),
      scaffoldBackgroundColor: AppColors.surface,
      textTheme: AppTypography.textTheme,
      cardTheme: const CardThemeData(
        color: AppColors.surfaceContainerLowest,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.all(Radius.circular(AppConstants.radiusXl)),
        ),
      ),
    );
  }
}
