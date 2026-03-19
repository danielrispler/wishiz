import 'package:flutter/material.dart';
import 'package:wishiz/core/theme/app_theme.dart';
import 'package:wishiz/features/home/presentation/screens/home_screen.dart';

void main() {
  runApp(const WishizApp());
}

class WishizApp extends StatelessWidget {
  const WishizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wishiz',
      theme: AppTheme.lightTheme,
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
