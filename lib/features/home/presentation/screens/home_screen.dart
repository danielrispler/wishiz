import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/home/presentation/widgets/wishlist_summary_card.dart';
import 'package:wishiz/features/home/presentation/widgets/glassmorphic_bottom_nav.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  void _showPlaceholderMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildHomeTab() {
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
                
                // Static Data Setup
                WishlistSummaryCard(
                  title: 'Home Decor',
                  itemCount: 12,
                  lastUpdated: '2 days ago',
                  onTap: () => _showPlaceholderMessage('Opening Home Decor list...'),
                ),
                WishlistSummaryCard(
                  title: 'Tech Gear 2024',
                  itemCount: 5,
                  lastUpdated: 'yesterday',
                  onTap: () => _showPlaceholderMessage('Opening Tech Gear 2024 list...'),
                ),
                
                const SizedBox(height: AppConstants.spacing6),
                
                // New Wishlist Section
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
                    onPressed: () => _showPlaceholderMessage('Create List flow coming next.'),
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
                
                // Provide padding for glassmorphic nav bar overlay
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderTab(String title) {
    return SafeArea(
      child: Center(
        child: Text(
          '$title tab placeholder',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          _buildPlaceholderTab('Shared'),
          _buildPlaceholderTab('Past lists'),
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
  }
}
