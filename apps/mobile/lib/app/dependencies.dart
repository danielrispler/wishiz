import 'package:flutter/material.dart';
import 'package:wishiz/app/app.dart' show WishizApp, WishlistRepositoryLoader, ProductImportRepositoryFactory, DiscoverRepositoryFactory, NotificationsRepositoryFactory, BootstrapErrorApp;
import 'package:wishiz/core/config/api_config.dart';
import 'package:wishiz/core/theme/app_theme.dart';
import 'package:wishiz/features/auth/data/api/auth_api_client.dart';
import 'package:wishiz/features/auth/data/repositories/api_auth_repository.dart';
import 'package:wishiz/features/auth/data/storage/shared_preferences_auth_storage.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/discover/data/api/discover_api_client.dart';
import 'package:wishiz/features/discover/data/repositories/api_discover_repository.dart';
import 'package:wishiz/features/notifications/data/api/notifications_api_client.dart';
import 'package:wishiz/features/notifications/data/repositories/api_notifications_repository.dart';
import 'package:wishiz/features/product_imports/data/api_product_import_repository.dart';
import 'package:wishiz/features/product_imports/data/product_import_api_client.dart';
import 'package:wishiz/features/wishlists/data/api/image_upload_api_client.dart';
import 'package:wishiz/features/wishlists/data/api/shared_product_api_client.dart';
import 'package:wishiz/features/wishlists/data/api/wishlist_api_client.dart';
import 'package:wishiz/features/wishlists/data/repositories/api_shared_product_repository.dart';
import 'package:wishiz/features/wishlists/data/repositories/http_wishlist_repository.dart';
import 'package:wishiz/features/wishlists/data/storage/shared_preferences_wishlist_storage.dart';
import 'package:wishiz/features/wishlists/domain/repositories/shared_product_repository.dart';

Future<Widget> createApp({
  String? baseUrlOverride,
  Future<AuthRepository> Function(String baseUrl)? authRepositoryFactory,
  SharedProductRepository Function(String baseUrl)?
  sharedProductRepositoryFactory,
  Future<void> Function()? clearLegacyWishlistStorage,
}) async {
  await (clearLegacyWishlistStorage ??
      SharedPreferencesWishlistStorage.clearLegacyData)();

  final baseUrl = baseUrlOverride ?? ApiConfig.baseUrl;
  try {
    final authRepository =
        await (authRepositoryFactory ?? _createAuthRepository)(baseUrl);
    final sharedProductRepository =
        (sharedProductRepositoryFactory ?? _createSharedProductRepository)(
          baseUrl,
        );

    return WishizApp(
      wishlistRepositoryLoader: _createWishlistRepositoryLoader(
        authRepository,
        baseUrl,
      ),
      productImportRepositoryFactory: _createProductImportRepositoryFactory(
        authRepository,
        baseUrl,
      ),
      notificationsRepositoryFactory: _createNotificationsRepositoryFactory(
        authRepository,
        baseUrl,
      ),
      discoverRepositoryFactory: _createDiscoverRepositoryFactory(
        authRepository,
        baseUrl,
      ),
      authRepository: authRepository,
      sharedProductRepository: sharedProductRepository,
    );
  } catch (error) {
    return _buildBootstrapApp(error: error);
  }
}

ProductImportRepositoryFactory _createProductImportRepositoryFactory(
  AuthRepository authRepository,
  String baseUrl,
) {
  return (user) {
    final tokenProvider = authRepository is SessionTokenProvider
        ? authRepository as SessionTokenProvider
        : null;
    final authToken = tokenProvider?.getSessionToken();
    if (authToken == null || authToken.isEmpty) {
      throw StateError('No authenticated API session is available.');
    }
    return ApiProductImportRepository(
      apiClient: ProductImportApiClient(
        baseUri: Uri.parse(baseUrl),
        authToken: authToken,
      ),
    );
  };
}

NotificationsRepositoryFactory _createNotificationsRepositoryFactory(
  AuthRepository authRepository,
  String baseUrl,
) {
  return (user) {
    final tokenProvider = authRepository is SessionTokenProvider
        ? authRepository as SessionTokenProvider
        : null;
    final authToken = tokenProvider?.getSessionToken();
    if (authToken == null || authToken.isEmpty) {
      throw StateError('No authenticated API session is available.');
    }
    return ApiNotificationsRepository(
      apiClient: NotificationsApiClient(
        baseUri: Uri.parse(baseUrl),
        authToken: authToken,
      ),
    );
  };
}

WishlistRepositoryLoader _createWishlistRepositoryLoader(
  AuthRepository authRepository,
  String baseUrl,
) {
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
      imageUploadApiClient: ImageUploadApiClient(
        baseUri: Uri.parse(baseUrl),
        authToken: authToken,
      ),
      currentUserId: user.id,
    );
  };
}

Future<AuthRepository> _createAuthRepository(String baseUrl) async {
  final storage = await SharedPreferencesAuthStorage.create();
  return ApiAuthRepository.create(
    storage: storage,
    apiClient: AuthApiClient(baseUri: Uri.parse(baseUrl)),
  );
}

DiscoverRepositoryFactory _createDiscoverRepositoryFactory(
  AuthRepository authRepository,
  String baseUrl,
) {
  return (user) {
    final tokenProvider = authRepository is SessionTokenProvider
        ? authRepository as SessionTokenProvider
        : null;
    final authToken = tokenProvider?.getSessionToken();
    if (authToken == null || authToken.isEmpty) {
      throw StateError('No authenticated API session is available.');
    }
    return ApiDiscoverRepository(
      apiClient: DiscoverApiClient(
        baseUri: Uri.parse(baseUrl),
        authToken: authToken,
      ),
    );
  };
}

SharedProductRepository _createSharedProductRepository(String baseUrl) {
  final apiClient = SharedProductApiClient(baseUri: Uri.parse(baseUrl));
  return ApiSharedProductRepository(apiClient: apiClient);
}

Widget _buildBootstrapApp({Object? error}) {
  return MaterialApp(
    title: 'Wishiz',
    theme: AppTheme.lightTheme,
    home: BootstrapErrorApp(error: error),
    debugShowCheckedModeBanner: false,
  );
}
