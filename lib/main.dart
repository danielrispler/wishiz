import 'package:flutter/material.dart';
import 'package:wishiz/core/theme/app_theme.dart';
import 'package:wishiz/features/wishlists/data/repositories/persistent_wishlist_repository.dart';
import 'package:wishiz/features/wishlists/data/storage/shared_preferences_wishlist_storage.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';
import 'package:wishiz/features/home/presentation/screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = await SharedPreferencesWishlistStorage.create();
  final repository = await PersistentWishlistRepository.create(storage: storage);

  runApp(WishizApp(repository: repository));
}

class WishizApp extends StatelessWidget {
  WishizApp({
    super.key,
    required this.repository,
  });

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
