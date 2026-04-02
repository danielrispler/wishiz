import 'package:flutter/material.dart';
import 'package:wishiz/core/config/api_config.dart';
import 'package:wishiz/core/theme/app_theme.dart';
import 'package:wishiz/core/utils/error_utils.dart';
import 'package:wishiz/features/auth/data/repositories/local_auth_repository.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/auth/presentation/screens/login_screen.dart';
import 'package:wishiz/features/auth/presentation/screens/signup_screen.dart';
import 'package:wishiz/features/home/presentation/screens/home_screen.dart';
import 'package:wishiz/features/wishlists/data/api/wishlist_api_client.dart';
import 'package:wishiz/features/wishlists/data/repositories/http_wishlist_repository.dart';
import 'package:wishiz/features/wishlists/data/repositories/persistent_wishlist_repository.dart';
import 'package:wishiz/features/wishlists/data/storage/shared_preferences_wishlist_storage.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  WishlistRepository? repository;
  Object? bootstrapError;

  try {
    repository = await _createWishlistRepository();
  } catch (error) {
    bootstrapError = error;
  }

  final authRepository = await LocalAuthRepository.create();

  runApp(
    repository == null
        ? BootstrapErrorApp(error: bootstrapError)
        : WishizApp(
            wishlistRepository: repository,
            authRepository: authRepository,
          ),
  );
}

Future<WishlistRepository> _createWishlistRepository() async {
  final baseUrl = ApiConfig.baseUrl;
  if (baseUrl != null) {
    final apiClient = WishlistApiClient(baseUri: Uri.parse(baseUrl));
    return HttpWishlistRepository.create(apiClient: apiClient);
  }

  final storage = await SharedPreferencesWishlistStorage.create();
  return PersistentWishlistRepository.create(storage: storage);
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

class BootstrapErrorApp extends StatelessWidget {
  const BootstrapErrorApp({
    super.key,
    this.error,
  });

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wishiz',
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Could not connect to the wishlist backend.',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Check that Docker is running, the API is listening on the base URL you passed, and then relaunch the app.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        formatErrorMessage(
                          error!,
                          fallbackMessage: 'Startup failed.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
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
  Future<bool> didPushRouteInformation(
      RouteInformation routeInformation) async {
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

    if (uri.scheme == 'wishiz' &&
        uri.host == 'lists' &&
        uri.pathSegments.isNotEmpty) {
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
