import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
    <meta property="og:title" content="Acme Stainless Steel Kettle Deluxe" />
    <meta property="product:brand" content="Acme" />
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
      expect(draft?.title, 'Stainless Steel Kettle, Acme');
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
        "name": "Nimbus Floor Lamp Matte",
        "brand": {
          "@type": "Brand",
          "name": "Nimbus"
        },
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

      expect(draft?.title, 'Floor Lamp Matte, Nimbus');
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

    test('falls back to first page image and visible price text', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write('''
<!doctype html>
<html>
  <head>
    <title>Soft Cotton Throw Blanket Extra Cozy</title>
    <meta property="product:brand" content="Cozy Home" />
  </head>
  <body>
    <img src="/assets/logo.png" />
    <main>
      <img src="/images/blanket-main.webp" />
      <div class="price compare-price">USD 299.00</div>
      <div class="price current-price">USD 249.00</div>
    </main>
  </body>
</html>
''');
        await request.response.close();
      });

      final repository = HttpSharedProductRepository();
      final productUrl = _serverUrl(server, '/items/throw-blanket');

      final draft = await repository.createDraftFromSharedText(productUrl);

      expect(draft?.title, 'Soft Cotton Throw, Cozy Home');
      expect(draft?.priceLabel, 'USD 249.00');
      expect(draft?.imageUrl, _serverUrl(server, '/images/blanket-main.webp'));
    });

    test('formats clothing titles as type plus brand', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write('''
<!doctype html>
<html>
  <head>
    <meta property="og:title" content="Nike White Crew Socks 3 Pack" />
    <meta property="product:brand" content="Nike" />
    <meta property="og:image" content="/images/socks.jpg" />
    <meta property="product:price:amount" content="19.90" />
    <meta property="product:price:currency" content="USD" />
  </head>
  <body></body>
</html>
''');
        await request.response.close();
      });

      final repository = HttpSharedProductRepository();
      final draft = await repository.createDraftFromSharedText(
        _serverUrl(server, '/items/socks'),
      );

      expect(draft?.title, 'White Crew Socks, Nike');
      expect(draft?.priceLabel, 'USD 19.90');
      expect(draft?.imageUrl, _serverUrl(server, '/images/socks.jpg'));
    });

    test('infers brand from shared Chrome title when page brand is missing',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write('''
<!doctype html>
<html>
  <head>
    <meta property="og:image" content="/images/shirt.jpg" />
    <meta property="product:price:amount" content="39.90" />
    <meta property="product:price:currency" content="USD" />
  </head>
  <body></body>
</html>
''');
        await request.response.close();
      });

      final repository = HttpSharedProductRepository();
      final productUrl = _serverUrl(server, '/items/shirt');

      final draft = await repository.createDraftFromSharedText(
        'H&M Basic T-Shirt Men\n$productUrl',
      );

      expect(draft?.title, 'Basic T Shirt, H&M');
      expect(draft?.priceLabel, 'USD 39.90');
      expect(draft?.imageUrl, _serverUrl(server, '/images/shirt.jpg'));
    });

    test('extracts lazy image url and selector based sale price', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write('''
<!doctype html>
<html>
  <head>
    <meta property="og:title" content="Nike White Running Socks" />
    <meta property="product:brand" content="Nike" />
  </head>
  <body>
    <img src="/logo.png" />
    <img data-old-hires="/images/running-socks.jpg" />
    <span class="price compare-price">USD 24.00</span>
    <span class="a-price">
      <span class="a-offscreen">USD 19.99</span>
    </span>
  </body>
</html>
''');
        await request.response.close();
      });

      final repository = HttpSharedProductRepository();
      final draft = await repository.createDraftFromSharedText(
        _serverUrl(server, '/items/running-socks'),
      );

      expect(draft?.title, 'White Running Socks, Nike');
      expect(draft?.priceLabel, 'USD 19.99');
      expect(
        draft?.imageUrl,
        _serverUrl(server, '/images/running-socks.jpg'),
      );
    });

    test('returns null when the shared text has no valid URL', () async {
      final repository = HttpSharedProductRepository();

      final draft = await repository.createDraftFromSharedText(
        'Look at this lamp please',
      );

      expect(draft, isNull);
    });

    test('does not crash on encoded product urls that fail to decode cleanly',
        () async {
      final repository = HttpSharedProductRepository(
        client: MockClient((request) async {
          return http.Response('blocked', 403);
        }),
      );

      final draft = await repository.createDraftFromSharedText(
        'https://www.zara.com/il/he/%D7%A9%D7%9E%D7%9C%D7%AA-%ZZ-p02743300.html?v1=537293431&v2=2546081',
      );

      expect(draft, isNotNull);
      expect(draft?.productUrl, isNotEmpty);
    });
  });
}

String _serverUrl(HttpServer server, String path) {
  return 'http://${server.address.host}:${server.port}$path';
}
