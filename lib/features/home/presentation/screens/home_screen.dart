import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/home/presentation/widgets/wishlist_summary_card.dart';
import 'package:wishiz/features/home/presentation/widgets/glassmorphic_bottom_nav.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';
import 'package:wishiz/features/wishlists/presentation/screens/wishlist_detail_screen.dart';
import 'package:wishiz/features/wishlists/presentation/screens/wishlist_editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
  });

  final WishlistRepository repository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  Future<void> _openWishlistEditor({Wishlist? wishlist}) async {
    final wishlistId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => WishlistEditorScreen(
          repository: widget.repository,
          wishlist: wishlist,
        ),
      ),
    );

    if (!mounted || wishlistId == null || wishlist != null) {
      return;
    }

    await _openWishlistDetails(wishlistId);
  }

  Future<void> _openWishlistDetails(String wishlistId) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WishlistDetailScreen(
          repository: widget.repository,
          wishlistId: wishlistId,
        ),
      ),
    );
  }

  Widget _buildHomeTab(List<Wishlist> activeWishlists) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacing4,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: AppConstants.spacing6),
                
                // Brand Header
                Text(
                  'Wishiz',
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: AppConstants.spacing8),
                
                // My Lists Section
                Text(
                  'My lists',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Organize your inspirations and curated desires.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppConstants.spacing4),

                if (activeWishlists.isEmpty)
                  _buildEmptyState(
                    title: 'No lists yet',
                    description:
                        'Create your first list to turn this editorial shell into a working collection.',
                  )
                else
                  ...activeWishlists.map(
                    (wishlist) => WishlistSummaryCard(
                      title: wishlist.title,
                      itemCount: wishlist.itemCount,
                      lastUpdated: _formatRelativeDate(wishlist.updatedAt),
                      coverImageUrl: wishlist.coverImageUrl,
                      onTap: () => _openWishlistDetails(wishlist.id),
                    ),
                  ),

                const SizedBox(height: AppConstants.spacing6),

                Text(
                  'New Wishlist',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Give your curated collection a name to get started.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppConstants.spacing4),
                
                // Primary CTA Button
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colorScheme.primary, colorScheme.primaryContainer],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: ElevatedButton(
                    onPressed: () => _openWishlistEditor(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: AppConstants.spacing4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                      ),
                    ),
                    child: Text(
                      'Create List',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),

                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionTab({
    required String title,
    required String description,
    required List<Wishlist> wishlists,
    required String emptyTitle,
    required String emptyDescription,
  }) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacing4,
          AppConstants.spacing6,
          AppConstants.spacing4,
          100,
        ),
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppConstants.spacing4),
          if (wishlists.isEmpty)
            _buildEmptyState(
              title: emptyTitle,
              description: emptyDescription,
            )
          else
            ...wishlists.map(
              (wishlist) => WishlistSummaryCard(
                title: wishlist.title,
                itemCount: wishlist.itemCount,
                lastUpdated: _formatRelativeDate(wishlist.updatedAt),
                coverImageUrl: wishlist.coverImageUrl,
                onTap: () => _openWishlistDetails(wishlist.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required String title,
    required String description,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.all(AppConstants.spacing4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  String _formatRelativeDate(DateTime updatedAt) {
    final difference = DateTime.now().difference(updatedAt);

    if (difference.inDays >= 2) {
      return '${difference.inDays} days ago';
    }
    if (difference.inDays == 1) {
      return 'yesterday';
    }
    if (difference.inHours >= 1) {
      return '${difference.inHours}h ago';
    }
    if (difference.inMinutes >= 1) {
      return '${difference.inMinutes}m ago';
    }
    return 'just now';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Wishlist>>(
      valueListenable: widget.repository.watchWishlists(),
      builder: (context, wishlists, _) {
        final activeWishlists = wishlists
            .where((wishlist) => !wishlist.isArchived)
            .toList(growable: false);
        final sharedWishlists = wishlists
            .where((wishlist) => wishlist.isShared && !wishlist.isArchived)
            .toList(growable: false);
        final archivedWishlists = wishlists
            .where((wishlist) => wishlist.isArchived)
            .toList(growable: false);

        return Scaffold(
          extendBody: true,
          body: IndexedStack(
            index: _currentIndex,
            children: [
              _buildHomeTab(activeWishlists),
              _buildCollectionTab(
                title: 'Shared',
                description:
                    'Collections that are collaborative, visible, and ready for shared planning.',
                wishlists: sharedWishlists,
                emptyTitle: 'Nothing shared yet',
                emptyDescription:
                    'Lists marked as shared will appear here without changing your current design system.',
              ),
              _buildCollectionTab(
                title: 'Past lists',
                description:
                    'Archived collections stay available here so the active space remains clean.',
                wishlists: archivedWishlists,
                emptyTitle: 'No archived lists',
                emptyDescription:
                    'Archive a finished list to move it here while keeping its details intact.',
              ),
            ],
          ),
          bottomNavigationBar: GlassmorphicBottomNav(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
          ),
        );
      },
    );
  }
}
