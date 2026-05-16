import 'package:flutter/material.dart';
import '../models/starter_pack.dart';
import 'starter_pack_card.dart';

class StarterPackCarousel extends StatelessWidget {
  const StarterPackCarousel({
    super.key,
    required this.packs,
    required this.onGrab,
    this.onPackTap,
  });

  final List<StarterPack> packs;
  final void Function(StarterPack pack) onGrab;
  final void Function(StarterPack pack)? onPackTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 440,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: packs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final p = packs[i];
          return StarterPackCard(
            pack: p,
            onTap: onPackTap == null ? null : () => onPackTap!(p),
            onGrab: () => onGrab(p),
          );
        },
      ),
    );
  }
}
