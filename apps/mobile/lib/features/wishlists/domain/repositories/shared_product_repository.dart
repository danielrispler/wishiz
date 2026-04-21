import 'package:wishiz/features/wishlists/domain/entities/shared_product_draft.dart';

abstract class SharedProductRepository {
  Future<SharedProductDraft?> createDraftFromSharedText(
    String sharedText, {
    String targetCurrencyCode = 'USD',
  });
}
