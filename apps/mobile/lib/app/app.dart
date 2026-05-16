import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/navigation/wishiz_app_link.dart';
import 'package:wishiz/core/services/share_intake_service.dart';
import 'package:wishiz/core/theme/app_theme.dart';
import 'package:wishiz/core/utils/error_utils.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/auth/screens/login/login_screen.dart';
import 'package:wishiz/features/auth/screens/signup/signup_screen.dart';
import 'package:wishiz/features/home/screens/home/home_screen.dart';
import 'package:wishiz/features/product_imports/application/product_import_sync_service.dart';
import 'package:wishiz/features/product_imports/data/in_memory_product_import_repository.dart';
import 'package:wishiz/features/product_imports/domain/product_import_repository.dart';
import 'package:wishiz/features/wishlists/domain/repositories/shared_product_repository.dart';
import 'package:wishiz/features/discover/domain/repositories/discover_repository.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';

typedef WishlistRepositoryLoader =
    Future<WishlistRepository> Function(AppUser user);
typedef ProductImportRepositoryFactory =
    ProductImportRepository Function(AppUser user);
typedef DiscoverRepositoryFactory =
    DiscoverRepository Function(AppUser user);

class WishizApp extends StatelessWidget {
  const WishizApp({
    super.key,
    required this.wishlistRepositoryLoader,
    required this.authRepository,
    required this.sharedProductRepository,
    ProductImportRepositoryFactory? productImportRepositoryFactory,
    this.discoverRepositoryFactory,
    this.shareIntakeService = const ShareIntakeService(),
  }) : productImportRepositoryFactory =
           productImportRepositoryFactory ?? _defaultProductImportRepository;

  final WishlistRepositoryLoader wishlistRepositoryLoader;
  final ProductImportRepositoryFactory productImportRepositoryFactory;
  final DiscoverRepositoryFactory? discoverRepositoryFactory;
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
        productImportRepositoryFactory: productImportRepositoryFactory,
        discoverRepositoryFactory: discoverRepositoryFactory,
        authRepository: authRepository,
        sharedProductRepository: sharedProductRepository,
        shareIntakeService: shareIntakeService,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

ProductImportRepository _defaultProductImportRepository(AppUser user) {
  return InMemoryProductImportRepository();
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
    required this.productImportRepositoryFactory,
    required this.authRepository,
    required this.sharedProductRepository,
    required this.shareIntakeService,
    this.discoverRepositoryFactory,
  });

  final WishlistRepositoryLoader wishlistRepositoryLoader;
  final ProductImportRepositoryFactory productImportRepositoryFactory;
  final DiscoverRepositoryFactory? discoverRepositoryFactory;
  final AuthRepository authRepository;
  final SharedProductRepository sharedProductRepository;
  final ShareIntakeService shareIntakeService;

  @override
  State<_RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<_RootScreen> with WidgetsBindingObserver {
  bool _showSignup = false;
  String? _pendingWishlistId;
  String? _pendingInviteToken;
  String? _pendingSharedText;
  StreamSubscription<String>? _sharedTextSubscription;
  WishlistRepository? _wishlistRepository;
  ProductImportRepository? _productImportRepository;
  ProductImportSyncService? _productImportSyncService;
  DiscoverRepository? _discoverRepository;
  Object? _wishlistRepositoryError;
  String? _wishlistRepositoryUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.authRepository.watchCurrentUser().addListener(
      _handleCurrentUserChanged,
    );
    final initialRoute =
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    _pendingWishlistId = _extractWishlistId(initialRoute);
    _pendingInviteToken = _extractInviteToken(initialRoute);
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
    _disposeProductImportSyncService();
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
      _pendingInviteToken = _extractInviteToken(route);
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
      _pendingInviteToken = _extractInviteToken(location);
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

  String? _extractInviteToken(String? route) {
    return WishizAppLink.extractInviteToken(route);
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
    final inviteToken = _extractInviteToken(normalized);

    setState(() {
      if (wishlistId != null) {
        _pendingWishlistId = wishlistId;
        _pendingInviteToken = inviteToken;
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
      _disposeProductImportSyncService();
      setState(() {
        _wishlistRepository = null;
        _productImportRepository = null;
        _discoverRepository = null;
        _wishlistRepositoryError = null;
        _wishlistRepositoryUserId = null;
      });
      return;
    }

    if (_wishlistRepositoryUserId == user.id && _wishlistRepository != null) {
      return;
    }

    final requestedUserId = user.id;
    _disposeProductImportSyncService();
    setState(() {
      _wishlistRepository = null;
      _productImportRepository = null;
      _discoverRepository = null;
      _wishlistRepositoryError = null;
      _wishlistRepositoryUserId = requestedUserId;
    });

    widget
        .wishlistRepositoryLoader(user)
        .then((repository) {
          if (!mounted || _wishlistRepositoryUserId != requestedUserId) {
            return;
          }

          late final ProductImportRepository productImportRepository;
          late final ProductImportSyncService productImportSyncService;
          try {
            productImportRepository = widget.productImportRepositoryFactory(
              user,
            );
            productImportSyncService = ProductImportSyncService(
              repository: productImportRepository,
              onJobCompleted: (_) => repository.refresh(),
            )..start();
          } catch (error) {
            setState(() {
              _wishlistRepositoryError = error;
            });
            return;
          }

          final discoverRepository =
              widget.discoverRepositoryFactory?.call(user);

          setState(() {
            _wishlistRepository = repository;
            _productImportRepository = productImportRepository;
            _productImportSyncService = productImportSyncService;
            _discoverRepository = discoverRepository;
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

  void _disposeProductImportSyncService() {
    _productImportSyncService?.dispose();
    _productImportSyncService = null;
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
          productImportRepository: _productImportRepository!,
          sharedProductRepository: widget.sharedProductRepository,
          authRepository: widget.authRepository,
          discoverRepository: _discoverRepository,
          currentUser: user,
          initialWishlistId: _pendingWishlistId,
          initialInviteToken: _pendingInviteToken,
          initialSharedText: _pendingSharedText,
          onInitialWishlistHandled: () {
            if (_pendingWishlistId == null) {
              return;
            }
            setState(() {
              _pendingWishlistId = null;
              _pendingInviteToken = null;
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
