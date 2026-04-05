import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wishiz/core/config/api_config.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/navigation/wishiz_app_link.dart';
import 'package:wishiz/core/services/share_intake_service.dart';
import 'package:wishiz/core/theme/app_theme.dart';
import 'package:wishiz/core/utils/error_utils.dart';
import 'package:wishiz/features/auth/data/api/auth_api_client.dart';
import 'package:wishiz/features/auth/data/repositories/api_auth_repository.dart';
import 'package:wishiz/features/auth/data/repositories/local_auth_repository.dart';
import 'package:wishiz/features/auth/data/storage/shared_preferences_auth_storage.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/auth/presentation/screens/login_screen.dart';
import 'package:wishiz/features/auth/presentation/screens/signup_screen.dart';
import 'package:wishiz/features/home/presentation/screens/home_screen.dart';
import 'package:wishiz/features/wishlists/data/api/shared_product_api_client.dart';
import 'package:wishiz/features/wishlists/data/api/wishlist_api_client.dart';
import 'package:wishiz/features/wishlists/data/repositories/api_shared_product_repository.dart';
import 'package:wishiz/features/wishlists/data/repositories/http_shared_product_repository.dart';
import 'package:wishiz/features/wishlists/data/repositories/http_wishlist_repository.dart';
import 'package:wishiz/features/wishlists/data/repositories/persistent_wishlist_repository.dart';
import 'package:wishiz/features/wishlists/data/storage/shared_preferences_wishlist_storage.dart';
import 'package:wishiz/features/wishlists/domain/repositories/shared_product_repository.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final authRepository = await _createAuthRepository();
  final sharedProductRepository = _createSharedProductRepository();

  runApp(
    WishizApp(
      wishlistRepositoryLoader: _createWishlistRepositoryLoader(authRepository),
      authRepository: authRepository,
      sharedProductRepository: sharedProductRepository,
    ),
  );
}

typedef WishlistRepositoryLoader =
    Future<WishlistRepository> Function(AppUser user);

Future<AuthRepository> _createAuthRepository() async {
  final baseUrl = ApiConfig.baseUrl;
  if (baseUrl != null) {
    final storage = await SharedPreferencesAuthStorage.create();
    return ApiAuthRepository.create(
      storage: storage,
      apiClient: AuthApiClient(baseUri: Uri.parse(baseUrl)),
    );
  }

  return LocalAuthRepository.create();
}

WishlistRepositoryLoader _createWishlistRepositoryLoader(
  AuthRepository authRepository,
) {
  final baseUrl = ApiConfig.baseUrl;
  if (baseUrl != null) {
    return (user) {
      final tokenProvider = authRepository is SessionTokenProvider
          ? authRepository as SessionTokenProvider
          : null;
      final authToken = tokenProvider?.getSessionToken();
      if (authToken == null || authToken.isEmpty) {
        throw StateError('No authenticated API session is available.');
      }
      final apiClient = WishlistApiClient(
        baseUri: Uri.parse(baseUrl),
        authToken: authToken,
      );
      return HttpWishlistRepository.create(
        apiClient: apiClient,
        currentUserId: user.id,
      );
    };
  }

  return (user) async {
    final storage = await SharedPreferencesWishlistStorage.create(
      userId: user.id,
    );
    return PersistentWishlistRepository.create(
      storage: storage,
      ownerUserId: user.id,
    );
  };
}

SharedProductRepository _createSharedProductRepository() {
  final baseUrl = ApiConfig.baseUrl;
  if (baseUrl != null) {
    final apiClient = SharedProductApiClient(baseUri: Uri.parse(baseUrl));
    return ApiSharedProductRepository(apiClient: apiClient);
  }

  return HttpSharedProductRepository();
}

class WishizApp extends StatelessWidget {
  const WishizApp({
    super.key,
    required this.wishlistRepositoryLoader,
    required this.authRepository,
    required this.sharedProductRepository,
    this.shareIntakeService = const ShareIntakeService(),
  });

  final WishlistRepositoryLoader wishlistRepositoryLoader;
  final AuthRepository authRepository;
  final SharedProductRepository sharedProductRepository;
  final ShareIntakeService shareIntakeService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wishiz',
      theme: AppTheme.lightTheme,
      home: _RootScreen(
        wishlistRepositoryLoader: wishlistRepositoryLoader,
        authRepository: authRepository,
        sharedProductRepository: sharedProductRepository,
        shareIntakeService: shareIntakeService,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class BootstrapErrorApp extends StatelessWidget {
  const BootstrapErrorApp({super.key, this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.pagePadding),
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
                  const SizedBox(height: AppConstants.itemGap),
                  Text(
                    'Check that Docker is running, the API is listening on the base URL you passed, and then relaunch the app.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: AppConstants.itemGap),
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
    );
  }
}

class _RootScreen extends StatefulWidget {
  const _RootScreen({
    required this.wishlistRepositoryLoader,
    required this.authRepository,
    required this.sharedProductRepository,
    required this.shareIntakeService,
  });

  final WishlistRepositoryLoader wishlistRepositoryLoader;
  final AuthRepository authRepository;
  final SharedProductRepository sharedProductRepository;
  final ShareIntakeService shareIntakeService;

  @override
  State<_RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<_RootScreen> with WidgetsBindingObserver {
  bool _showSignup = false;
  String? _pendingWishlistId;
  String? _pendingSharedText;
  StreamSubscription<String>? _sharedTextSubscription;
  WishlistRepository? _wishlistRepository;
  Object? _wishlistRepositoryError;
  String? _wishlistRepositoryUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.authRepository.watchCurrentUser().addListener(
      _handleCurrentUserChanged,
    );
    _pendingWishlistId = _extractWishlistId(
      WidgetsBinding.instance.platformDispatcher.defaultRouteName,
    );
    _consumePendingSharedText();
    _sharedTextSubscription = widget.shareIntakeService
        .watchSharedText()
        .listen(_storePendingSharedText);
    _handleCurrentUserChanged();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.authRepository.watchCurrentUser().removeListener(
      _handleCurrentUserChanged,
    );
    _sharedTextSubscription?.cancel();
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
    RouteInformation routeInformation,
  ) async {
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }

    _consumePendingSharedText();
  }

  String? _extractWishlistId(String? route) {
    return WishizAppLink.extractWishlistId(route);
  }

  Future<void> _consumePendingSharedText() async {
    final sharedText = await widget.shareIntakeService
        .consumePendingSharedText();
    if (!mounted || sharedText == null) {
      return;
    }

    _storePendingSharedText(sharedText);
  }

  void _storePendingSharedText(String sharedText) {
    final normalized = sharedText.trim();
    if (normalized.isEmpty) {
      return;
    }

    final wishlistId = _extractWishlistId(normalized);

    setState(() {
      if (wishlistId != null) {
        _pendingWishlistId = wishlistId;
        _pendingSharedText = null;
        return;
      }

      _pendingSharedText = normalized;
    });
  }

  void _handleCurrentUserChanged() {
    final user = widget.authRepository.getCurrentUser();
    if (user == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _wishlistRepository = null;
        _wishlistRepositoryError = null;
        _wishlistRepositoryUserId = null;
      });
      return;
    }

    if (_wishlistRepositoryUserId == user.id && _wishlistRepository != null) {
      return;
    }

    final requestedUserId = user.id;
    setState(() {
      _wishlistRepository = null;
      _wishlistRepositoryError = null;
      _wishlistRepositoryUserId = requestedUserId;
    });

    widget
        .wishlistRepositoryLoader(user)
        .then((repository) {
          if (!mounted || _wishlistRepositoryUserId != requestedUserId) {
            return;
          }

          setState(() {
            _wishlistRepository = repository;
          });
        })
        .catchError((error) {
          if (!mounted || _wishlistRepositoryUserId != requestedUserId) {
            return;
          }

          setState(() {
            _wishlistRepositoryError = error;
          });
        });
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

        if (_wishlistRepositoryError != null) {
          return BootstrapErrorApp(error: _wishlistRepositoryError);
        }

        final repository = _wishlistRepository;
        if (repository == null) {
          return const Scaffold(
            body: SafeArea(child: Center(child: CircularProgressIndicator())),
          );
        }

        return HomeScreen(
          repository: repository,
          sharedProductRepository: widget.sharedProductRepository,
          authRepository: widget.authRepository,
          currentUser: user,
          initialWishlistId: _pendingWishlistId,
          initialSharedText: _pendingSharedText,
          onInitialWishlistHandled: () {
            if (_pendingWishlistId == null) {
              return;
            }
            setState(() {
              _pendingWishlistId = null;
            });
          },
          onInitialSharedTextHandled: () {
            if (_pendingSharedText == null) {
              return;
            }
            setState(() {
              _pendingSharedText = null;
            });
          },
        );
      },
    );
  }
}
