import 'package:flutter/material.dart';
import 'package:wishiz/core/theme/app_theme.dart';
import 'package:wishiz/features/auth/data/repositories/local_auth_repository.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/auth/presentation/screens/login_screen.dart';
import 'package:wishiz/features/auth/presentation/screens/signup_screen.dart';
import 'package:wishiz/features/home/presentation/screens/home_screen.dart';
import 'package:wishiz/features/wishlists/data/repositories/persistent_wishlist_repository.dart';
import 'package:wishiz/features/wishlists/data/storage/shared_preferences_wishlist_storage.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = await SharedPreferencesWishlistStorage.create();
  final repository =
      await PersistentWishlistRepository.create(storage: storage);
  final authRepository = await LocalAuthRepository.create();

  runApp(
    WishizApp(
      wishlistRepository: repository,
      authRepository: authRepository,
    ),
  );
}

class WishizApp extends StatelessWidget {
  const WishizApp({
    super.key,
    required this.wishlistRepository,
    required this.authRepository,
  });

  final WishlistRepository wishlistRepository;
  final AuthRepository authRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wishiz',
      theme: AppTheme.lightTheme,
      home: _RootScreen(
        wishlistRepository: wishlistRepository,
        authRepository: authRepository,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class _RootScreen extends StatefulWidget {
  const _RootScreen({
    required this.wishlistRepository,
    required this.authRepository,
  });

  final WishlistRepository wishlistRepository;
  final AuthRepository authRepository;

  @override
  State<_RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<_RootScreen> with WidgetsBindingObserver {
  bool _showSignup = false;
  String? _pendingWishlistId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pendingWishlistId = _extractWishlistId(
      WidgetsBinding.instance.platformDispatcher.defaultRouteName,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPushRoute(String route) async {
    final wishlistId = _extractWishlistId(route);
    if (wishlistId == null) {
      return false;
    }

    setState(() {
      _pendingWishlistId = wishlistId;
    });
    return true;
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async {
    final location = routeInformation.uri.toString();
    final wishlistId = _extractWishlistId(location);
    if (wishlistId == null) {
      return false;
    }

    setState(() {
      _pendingWishlistId = wishlistId;
    });
    return true;
  }

  String? _extractWishlistId(String? route) {
    final value = route?.trim() ?? '';
    if (value.isEmpty || value == Navigator.defaultRouteName) {
      return null;
    }

    final uri = Uri.tryParse(value);
    if (uri == null) {
      return null;
    }

    if (uri.scheme == 'wishiz' && uri.host == 'lists' && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }

    if (uri.pathSegments.length >= 2 && uri.pathSegments.first == 'lists') {
      return uri.pathSegments[1];
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUser?>(
      valueListenable: widget.authRepository.watchCurrentUser(),
      builder: (context, user, _) {
        if (user == null) {
          if (_showSignup) {
            return SignupScreen(
              authRepository: widget.authRepository,
              onShowLogin: () {
                setState(() {
                  _showSignup = false;
                });
              },
            );
          }

          return LoginScreen(
            authRepository: widget.authRepository,
            onShowSignUp: () {
              setState(() {
                _showSignup = true;
              });
            },
          );
        }

        return HomeScreen(
          repository: widget.wishlistRepository,
          authRepository: widget.authRepository,
          currentUser: user,
          initialWishlistId: _pendingWishlistId,
          onInitialWishlistHandled: () {
            if (_pendingWishlistId == null) {
              return;
            }
            setState(() {
              _pendingWishlistId = null;
            });
          },
        );
      },
    );
  }
}
