import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/utils/currency_utils.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';

class WishlistAnalytics {
  WishlistAnalytics(this._wishlist);

  final Wishlist _wishlist;

  double? get avgDaysOnList {
    final active = _wishlist.activeItems;
    if (active.isEmpty) return null;
    return active.map((i) => i.daysOnList).reduce((a, b) => a + b) /
        active.length;
  }

  double? get completionRate {
    if (_wishlist.itemCount == 0) return null;
    return _wishlist.purchasedItemCount / _wishlist.itemCount;
  }

  double? get avgDaysToPurchase {
    final purchased = _wishlist.purchasedItems
        .where((i) => i.purchasedAt != null)
        .toList();
    if (purchased.isEmpty) return null;
    final total = purchased.fold<int>(
      0,
      (sum, i) => sum + i.purchasedAt!.difference(i.createdAt).inDays.abs(),
    );
    return total / purchased.length;
  }

  WishlistItem? get mostExpensiveActiveItem {
    final active = _wishlist.activeItems
        .where((i) => _itemAmount(i) != null)
        .toList();
    if (active.isEmpty) return null;
    return active.reduce((a, b) => _toUsd(a) >= _toUsd(b) ? a : b);
  }

  /// Low-bound amount + currency for analytics. Prefers the structured priceAmount +
  /// priceCurrencyCode (the canonical low/"starting" bound — for a range this is the
  /// floor, never the concatenated range label). Falls back to parsing the display
  /// label for legacy / manually-entered items.
  ParsedCurrencyAmount? _itemAmount(WishlistItem item) {
    final amount = double.tryParse(item.priceAmount ?? '');
    final code = item.priceCurrencyCode;
    if (amount != null && code != null) {
      return ParsedCurrencyAmount(currencyCode: code, amount: amount);
    }
    return CurrencyUtils.parsePriceLabel(item.priceLabel);
  }

  String get dominantCurrency {
    final currencies = _wishlist.items
        .map((i) => _itemAmount(i)?.currencyCode)
        .whereType<String>()
        .toList();
    if (currencies.isEmpty) return 'USD';
    final freq = <String, int>{};
    for (final c in currencies) {
      freq[c] = (freq[c] ?? 0) + 1;
    }
    return freq.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  String? get totalActiveValue => _sumItems(_wishlist.activeItems);
  String? get totalPurchasedValue => _sumItems(_wishlist.purchasedItems);
  String? get totalValue => _sumItems(_wishlist.items);

  String? _sumItems(List<WishlistItem> items) {
    final currency = dominantCurrency;
    double total = 0;
    bool hasAny = false;
    for (final item in items) {
      final parsed = _itemAmount(item);
      if (parsed != null) {
        hasAny = true;
        total += CurrencyUtils.convertAmount(
          parsed.amount,
          fromCurrencyCode: parsed.currencyCode,
          toCurrencyCode: currency,
        );
      }
    }
    if (!hasAny) return null;
    return CurrencyUtils.formatAmount(total, currency);
  }

  double _toUsd(WishlistItem item) {
    final parsed = _itemAmount(item);
    if (parsed == null) return 0;
    return CurrencyUtils.convertAmount(
      parsed.amount,
      fromCurrencyCode: parsed.currencyCode,
      toCurrencyCode: 'USD',
    );
  }
}

void showWishlistAnalyticsSheet(BuildContext context, Wishlist wishlist) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => WishlistAnalyticsSheet(wishlist: wishlist),
  );
}

class WishlistAnalyticsSheet extends StatelessWidget {
  const WishlistAnalyticsSheet({super.key, required this.wishlist});

  final Wishlist wishlist;

  @override
  Widget build(BuildContext context) {
    final analytics = WishlistAnalytics(wishlist);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final completionRate = analytics.completionRate;
    final avgDays = analytics.avgDaysOnList;
    final avgToPurchase = analytics.avgDaysToPurchase;
    final totalActive = analytics.totalActiveValue;
    final totalPurchased = analytics.totalPurchasedValue;
    final mostExpensive = analytics.mostExpensiveActiveItem;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                children: [
                  Icon(Icons.bar_chart_rounded, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${wishlist.title} Analytics',
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (completionRate != null) ...[
                    _buildSectionHeader(context, 'Progress'),
                    const SizedBox(height: 8),
                    _buildProgressTile(context, analytics),
                    const SizedBox(height: 16),
                  ],
                  if (totalActive != null || totalPurchased != null) ...[
                    _buildSectionHeader(context, 'Value'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (totalActive != null)
                          Expanded(
                            child: _buildStatCard(
                              context,
                              label: 'Wishlist value',
                              value: totalActive,
                              icon: Icons.list_alt_rounded,
                            ),
                          ),
                        if (totalActive != null && totalPurchased != null)
                          const SizedBox(width: 8),
                        if (totalPurchased != null)
                          Expanded(
                            child: _buildStatCard(
                              context,
                              label: 'Already gifted',
                              value: totalPurchased,
                              icon: Icons.shopping_bag_outlined,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (avgDays != null || avgToPurchase != null) ...[
                    _buildSectionHeader(context, 'Time'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (avgDays != null)
                          Expanded(
                            child: _buildStatCard(
                              context,
                              label: 'Avg days on list',
                              value: '${avgDays.round()} days',
                              icon: Icons.hourglass_top_rounded,
                            ),
                          ),
                        if (avgDays != null && avgToPurchase != null)
                          const SizedBox(width: 8),
                        if (avgToPurchase != null)
                          Expanded(
                            child: _buildStatCard(
                              context,
                              label: 'Avg days to gift',
                              value: '${avgToPurchase.round()} days',
                              icon: Icons.timer_outlined,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (mostExpensive != null) ...[
                    _buildSectionHeader(context, 'Top Item'),
                    const SizedBox(height: 8),
                    _buildMostExpensiveTile(context, mostExpensive),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
    );
  }

  Widget _buildProgressTile(BuildContext context, WishlistAnalytics analytics) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final rate = analytics.completionRate!;
    final total = wishlist.itemCount;
    final purchased = wishlist.purchasedItemCount;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$purchased of $total items gifted',
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                '${(rate * 100).round()}%',
                style: textTheme.titleMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: rate,
              minHeight: 8,
              backgroundColor: colorScheme.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMostExpensiveTile(BuildContext context, WishlistItem item) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.star_rounded,
              color: colorScheme.onPrimaryContainer,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.priceLabel != null)
                  Text(
                    item.priceLabel!,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
