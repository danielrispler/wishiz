import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/wishlists/data/api/wishlist_api_client.dart';
import 'package:wishiz/features/wishlists/data/repositories/http_wishlist_repository.dart';

void main() {
  group('HttpWishlistRepository', () {
    test('loads wishlists from the backend during creation', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        expect(request.method, 'GET');
        expect(request.uri.path, '/wishlists');
        await _writeJsonResponse(
          request.response,
          HttpStatus.ok,
          [
            _wishlistJson(
              id: 'travel',
              title: 'Travel',
              description: 'Carry-on ideas',
              year: 2027,
            ),
          ],
        );
      });

      final repository = await HttpWishlistRepository.create(
        apiClient: WishlistApiClient(baseUri: _serverUri(server)),
        currentUserId: 'user-1',
      );

      expect(repository.getWishlists(), hasLength(1));
      expect(repository.findById('travel')?.title, 'Travel');
      expect(repository.findById('travel')?.description, 'Carry-on ideas');
      expect(repository.findById('travel')?.ownerUserId, 'api-user');
    });

    test('creates a wishlist and updates the local cache', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        if (request.method == 'GET' && request.uri.path == '/wishlists') {
          await _writeJsonResponse(request.response, HttpStatus.ok, const []);
          return;
        }

        if (request.method == 'POST' && request.uri.path == '/wishlists') {
          final body = await utf8.decoder.bind(request).join();
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          expect(decoded['title'], 'Hosting');
          expect(decoded['year'], 2026);

          await _writeJsonResponse(
            request.response,
            HttpStatus.created,
            _wishlistJson(
              id: 'hosting',
              title: decoded['title'] as String,
              description: decoded['description'] as String,
              year: decoded['year'] as int,
              isShared: decoded['isShared'] as bool? ?? false,
            ),
          );
          return;
        }

        fail('Unexpected request: ${request.method} ${request.uri.path}');
      });

      final repository = await HttpWishlistRepository.create(
        apiClient: WishlistApiClient(baseUri: _serverUri(server)),
        currentUserId: 'user-1',
      );

      final created = await repository.createWishlist(
        title: 'Hosting',
        description: 'Candles and plates',
        year: 2026,
      );

      expect(created.id, 'hosting');
      expect(repository.findById('hosting'), isNotNull);
      expect(repository.getWishlists().first.title, 'Hosting');
    });

    test('updates local cache after adding an item without refetching', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      var detailRequestCount = 0;
      server.listen((request) async {
        if (request.method == 'GET' && request.uri.path == '/wishlists') {
          await _writeJsonResponse(
            request.response,
            HttpStatus.ok,
            [
              _wishlistJson(
                id: 'home',
                title: 'Home',
                description: 'Decor',
                year: 2026,
              ),
            ],
          );
          return;
        }

        if (request.method == 'POST' &&
            request.uri.path == '/wishlists/home/items') {
          await _writeJsonResponse(
            request.response,
            HttpStatus.created,
            _itemJson(
              id: 'lamp',
              title: 'Marble lamp',
              rank: 1,
            ),
          );
          return;
        }

        fail('Unexpected request: ${request.method} ${request.uri.path}');
      });

      final repository = await HttpWishlistRepository.create(
        apiClient: WishlistApiClient(baseUri: _serverUri(server)),
        currentUserId: 'user-1',
      );

      final createdItem = await repository.addWishlistItem(
        wishlistId: 'home',
        title: 'Marble lamp',
      );

      expect(detailRequestCount, 0);
      expect(createdItem.id, 'lamp');
      expect(repository.findById('home')?.items, hasLength(1));
      expect(repository.findById('home')?.items.first.title, 'Marble lamp');
    });

    test('falls back to the current user id when ownerUserId is missing', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        expect(request.method, 'GET');
        expect(request.uri.path, '/wishlists');
        await _writeJsonResponse(
          request.response,
          HttpStatus.ok,
          [
            _wishlistJson(
              id: 'travel',
              title: 'Travel',
              description: 'Carry-on ideas',
              year: 2027,
              includeOwnerUserId: false,
            ),
          ],
        );
      });

      final repository = await HttpWishlistRepository.create(
        apiClient: WishlistApiClient(baseUri: _serverUri(server)),
        currentUserId: 'fallback-user',
      );

      expect(repository.findById('travel')?.ownerUserId, 'fallback-user');
    });

    test('updates local cache after editing an item without refetching', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      var detailRequestCount = 0;
      server.listen((request) async {
        if (request.method == 'GET' && request.uri.path == '/wishlists') {
          await _writeJsonResponse(
            request.response,
            HttpStatus.ok,
            [
              _wishlistJson(
                id: 'home',
                title: 'Home',
                description: 'Decor',
                year: 2026,
                items: [
                  _itemJson(
                    id: 'lamp',
                    title: 'Old lamp',
                    rank: 1,
                  ),
                ],
              ),
            ],
          );
          return;
        }

        if (request.method == 'PATCH' &&
            request.uri.path == '/wishlists/home/items/lamp') {
          await _writeJsonResponse(
            request.response,
            HttpStatus.ok,
            _itemJson(
              id: 'lamp',
              title: 'New lamp',
              rank: 1,
              status: 'Purchased',
            ),
          );
          return;
        }

        if (request.method == 'GET' && request.uri.path == '/wishlists/home') {
          detailRequestCount += 1;
        }

        fail('Unexpected request: ${request.method} ${request.uri.path}');
      });

      final repository = await HttpWishlistRepository.create(
        apiClient: WishlistApiClient(baseUri: _serverUri(server)),
        currentUserId: 'user-1',
      );

      final updatedItem = await repository.updateWishlistItemStatus(
        wishlistId: 'home',
        itemId: 'lamp',
        status: 'Purchased',
      );

      expect(detailRequestCount, 0);
      expect(updatedItem?.title, 'New lamp');
      expect(updatedItem?.status, 'Purchased');
      expect(repository.findById('home')?.items.first.status, 'Purchased');
    });

    test('updates local cache after deleting an item without refetching', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      var detailRequestCount = 0;
      server.listen((request) async {
        if (request.method == 'GET' && request.uri.path == '/wishlists') {
          await _writeJsonResponse(
            request.response,
            HttpStatus.ok,
            [
              _wishlistJson(
                id: 'home',
                title: 'Home',
                description: 'Decor',
                year: 2026,
                items: [
                  _itemJson(
                    id: 'lamp',
                    title: 'Lamp',
                    rank: 1,
                  ),
                ],
              ),
            ],
          );
          return;
        }

        if (request.method == 'DELETE' &&
            request.uri.path == '/wishlists/home/items/lamp') {
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
          return;
        }

        if (request.method == 'GET' && request.uri.path == '/wishlists/home') {
          detailRequestCount += 1;
        }

        fail('Unexpected request: ${request.method} ${request.uri.path}');
      });

      final repository = await HttpWishlistRepository.create(
        apiClient: WishlistApiClient(baseUri: _serverUri(server)),
        currentUserId: 'user-1',
      );

      final deleted = await repository.deleteWishlistItem(
        wishlistId: 'home',
        itemId: 'lamp',
      );

      expect(deleted, isTrue);
      expect(detailRequestCount, 0);
      expect(repository.findById('home')?.items, isEmpty);
    });
  });
}

Uri _serverUri(HttpServer server) {
  return Uri.parse('http://${server.address.host}:${server.port}');
}

Map<String, dynamic> _wishlistJson({
  required String id,
  required String title,
  required String description,
  required int year,
  bool isArchived = false,
  bool isShared = false,
  bool includeOwnerUserId = true,
  List<Map<String, dynamic>> items = const [],
}) {
  final payload = <String, dynamic>{
    'id': id,
    'title': title,
    'description': description,
    'year': year,
    'coverImageUrl': null,
    'createdAt': '2026-01-01T00:00:00Z',
    'updatedAt': '2026-01-02T00:00:00Z',
    'isArchived': isArchived,
    'isShared': isShared,
    'sharedUsers': const [],
    'items': items,
  };

  if (includeOwnerUserId) {
    payload['ownerUserId'] = 'api-user';
  }

  return payload;
}

Map<String, dynamic> _itemJson({
  required String id,
  required String title,
  required int rank,
  String status = 'Saved',
}) {
  return {
    'id': id,
    'title': title,
    'rank': rank,
    'notes': null,
    'priceLabel': null,
    'priority': 'Medium',
    'status': status,
    'imageUrl': null,
    'productUrl': null,
    'purchasedAt': null,
    'createdAt': '2026-01-01T00:00:00Z',
    'updatedAt': '2026-01-02T00:00:00Z',
  };
}

Future<void> _writeJsonResponse(
  HttpResponse response,
  int statusCode,
  Object payload,
) async {
  response.statusCode = statusCode;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(payload));
  await response.close();
}
