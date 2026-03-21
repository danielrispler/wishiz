import 'package:flutter/material.dart';
import 'package:wishiz/core/theme/app_theme.dart';
import 'package:wishiz/features/wishlists/data/repositories/in_memory_wishlist_repository.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';
import 'package:wishiz/features/home/presentation/screens/home_screen.dart';

void main() {
  runApp(WishizApp());
}

class WishizApp extends StatelessWidget {
  WishizApp({
    super.key,
    WishlistRepository? repository,
  }) : repository = repository ?? InMemoryWishlistRepository();

  final WishlistRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wishiz',
      theme: AppTheme.lightTheme,
      home: HomeScreen(repository: repository),
      debugShowCheckedModeBanner: false,
    );
  }
}
