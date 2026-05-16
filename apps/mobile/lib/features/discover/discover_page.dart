import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wishiz/core/theme/app_colors.dart';
import 'models/product.dart';
import 'models/starter_pack.dart';
import 'widgets/product_carousel.dart';
import 'widgets/section_header.dart';
import 'widgets/starter_pack_carousel.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  // TODO: replace with calls to your Go/Postgres backend
  late List<StarterPack> _packs;
  late List<Product> _trending;
  late List<Product> _forYou;

  @override
  void initState() {
    super.initState();
    _packs = StarterPack.sample;
    _trending = List.of(Product.sample.take(4));
    _forYou = List.of(Product.sample.skip(4).take(4));
  }

  void _handleToggleSave(Product p, bool isSaved) {
    setState(() {
      _trending = _trending
          .map((x) => x.id == p.id
              ? x.copyWith(
                  isSavedByUser: isSaved,
                  saves: x.saves + (isSaved ? 1 : -1),
                )
              : x)
          .toList();
      _forYou = _forYou
          .map((x) => x.id == p.id
              ? x.copyWith(
                  isSavedByUser: isSaved,
                  saves: x.saves + (isSaved ? 1 : -1),
                )
              : x)
          .toList();
    });
    // TODO: backend
    //   if (isSaved) await api.saveProduct(p.id);
    //   else         await api.unsaveProduct(p.id);
  }

  void _handleGrabPack(StarterPack pack) {
    HapticFeedback.mediumImpact();
    // TODO: backend — copy pack contents into a new user list
    //   final list = await api.createListFromPack(pack.id);
    //   context.push('/lists/${list.id}');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.onSurface,
        behavior: SnackBarBehavior.floating,
        content: Text('Added "${pack.title}" to your lists'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: Stack(
        children: [
          const _AmbientBackdrop(),
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: _DisplayTitle()),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              const SliverToBoxAdapter(child: _SearchBar()),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),

              const SliverToBoxAdapter(
                child: SectionHeader(
                  label: 'Starter Packs',
                  eyebrow: 'Curated collections, ready to grab',
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              SliverToBoxAdapter(
                child: StarterPackCarousel(
                  packs: _packs,
                  onGrab: _handleGrabPack,
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              const SliverToBoxAdapter(
                child: SectionHeader(
                  label: 'Trending now',
                  eyebrow: 'What women are saving this week',
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              SliverToBoxAdapter(
                child: ProductCarousel(
                  products: _trending,
                  onToggleSave: _handleToggleSave,
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              const SliverToBoxAdapter(
                child: SectionHeader(
                  label: 'For you',
                  eyebrow: 'Based on your saved items',
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              SliverToBoxAdapter(
                child: ProductCarousel(
                  products: _forYou,
                  onToggleSave: _handleToggleSave,
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 110)),
            ],
          ),
        ],
      ),
    );
  }
}

class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -100,
            right: -120,
            child: _Blob(
              size: 320,
              color: const Color(0xFF9396FF).withValues(alpha: 0.32),
            ),
          ),
          Positioned(
            top: 280,
            left: -140,
            child: _Blob(
              size: 280,
              color: const Color(0xFFE1D8FF).withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
          stops: const [0, 0.7],
        ),
      ),
    );
  }
}

class _DisplayTitle extends StatelessWidget {
  const _DisplayTitle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FOR YOU · CURATED DAILY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: const TextSpan(
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: AppColors.onSurface,
                letterSpacing: -0.7,
                height: 1.02,
              ),
              children: [
                TextSpan(text: 'Discover\n'),
                TextSpan(
                  text: 'your boutique.',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w400,
                    fontSize: 38,
                    letterSpacing: -1,
                    color: AppColors.primary,
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

class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.surfaceVariant),
        ),
        child: const Row(
          children: [
            Icon(Icons.search_rounded, size: 20, color: AppColors.primary),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Search products or brands',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
