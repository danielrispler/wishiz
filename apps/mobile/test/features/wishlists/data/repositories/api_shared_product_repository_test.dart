import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/wishlists/data/api/shared_product_api_client.dart';
import 'package:wishiz/features/wishlists/data/repositories/api_shared_product_repository.dart';

void main() {
  group('ApiSharedProductRepository', () {
    test('maps scrape response into a shared product draft', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        expect(request.method, 'GET');
        expect(request.uri.path, '/scrape');
        expect(
          request.uri.queryParameters['url'],
          'https://www.nike.com/il/t/shox-tl-older-shoes-LbcQ88p0/IO4645-006',
        );
        expect(request.uri.queryParameters['targetCurrencyCode'], 'ILS');

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'name': 'Nike Shox TL',
            'priceAmount': '599.90',
            'priceCurrency': 'ILS',
            'imageUrl': 'https://static.nike.com/hero.png',
            'source': 'headless',
          }),
        );
        await request.response.close();
      });

      final repository = ApiSharedProductRepository(
        apiClient: SharedProductApiClient(
          baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
        ),
      );

      final draft = await repository.createDraftFromSharedText(
        'Check this out\nhttps://www.nike.com/il/t/shox-tl-older-shoes-LbcQ88p0/IO4645-006',
        targetCurrencyCode: 'ILS',
      );

      expect(draft, isNotNull);
      expect(draft?.title, 'Nike Shox TL');
      expect(draft?.priceLabel, 'ILS 599.90');
      expect(draft?.imageUrl, 'https://static.nike.com/hero.png');
      expect(draft?.notes, 'Check this out');
    });

    test('returns null when shared text has no URL', () async {
      final repository = ApiSharedProductRepository(
        apiClient: SharedProductApiClient(
          baseUri: Uri.parse('http://127.0.0.1:9999'),
        ),
      );

      final draft = await repository.createDraftFromSharedText(
        'Just some text',
      );

      expect(draft, isNull);
    });
  });
}
