import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/wishlists/data/repositories/http_shared_product_repository.dart';

void main() {
  group('HttpSharedProductRepository', () {
    test('creates a draft from shared text and page metadata', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write('''
<!doctype html>
<html>
  <head>
    <title>Ignored title</title>
    <meta property="og:title" content="Acme Kettle" />
    <meta property="og:image" content="/images/kettle.jpg" />
    <meta property="product:price:amount" content="129.90" />
    <meta property="product:price:currency" content="USD" />
    <meta property="og:description" content="Steel kettle in brushed silver." />
  </head>
  <body></body>
</html>
''');
        await request.response.close();
      });

      final repository = HttpSharedProductRepository();
      final productUrl = _serverUrl(server, '/products/kettle');

      final draft = await repository.createDraftFromSharedText(
        'Take a look at this\n$productUrl',
      );

      expect(draft, isNotNull);
      expect(draft?.productUrl, productUrl);
      expect(draft?.title, 'Acme Kettle');
      expect(draft?.priceLabel, 'USD 129.90');
      expect(draft?.imageUrl, _serverUrl(server, '/images/kettle.jpg'));
      expect(draft?.notes, 'Take a look at this');
      expect(draft?.hasCompleteRequiredFields, isTrue);
    });

    test('uses schema.org metadata when meta tags are missing', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write('''
<!doctype html>
<html>
  <head>
    <script type="application/ld+json">
      {
        "@context": "https://schema.org",
        "@type": "Product",
        "name": "Nimbus Lamp",
        "image": "https://cdn.example.com/lamp.png",
        "offers": {
          "@type": "Offer",
          "priceCurrency": "EUR",
          "price": "89.50"
        }
      }
    </script>
  </head>
  <body></body>
</html>
''');
        await request.response.close();
      });

      final repository = HttpSharedProductRepository();
      final productUrl = _serverUrl(server, '/p/lamp');

      final draft = await repository.createDraftFromSharedText(productUrl);

      expect(draft?.title, 'Nimbus Lamp');
      expect(draft?.priceLabel, 'EUR 89.50');
      expect(draft?.imageUrl, 'https://cdn.example.com/lamp.png');
    });

    test(
        'returns a draft with missing required fields when metadata is partial',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write('''
<!doctype html>
<html>
  <head>
    <meta property="og:title" content="Minimal Chair" />
  </head>
  <body></body>
</html>
''');
        await request.response.close();
      });

      final repository = HttpSharedProductRepository();
      final productUrl = _serverUrl(server, '/items/minimal-chair');

      final draft = await repository.createDraftFromSharedText(
        'Minimal chair\n$productUrl',
      );

      expect(draft, isNotNull);
      expect(draft?.title, 'Minimal Chair');
      expect(draft?.priceLabel, isNull);
      expect(draft?.imageUrl, isNull);
      expect(draft?.hasCompleteRequiredFields, isFalse);
      expect(draft?.missingFieldLabels, ['price', 'image']);
    });

    test('returns null when the shared text has no valid URL', () async {
      final repository = HttpSharedProductRepository();

      final draft = await repository.createDraftFromSharedText(
        'Look at this lamp please',
      );

      expect(draft, isNull);
    });
  });
}

String _serverUrl(HttpServer server, String path) {
  return 'http://${server.address.host}:${server.port}$path';
}
