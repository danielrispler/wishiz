import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wishiz/core/theme/app_colors.dart';
import 'package:wishiz/features/discover/models/starter_pack.dart';

class StarterPackCard extends StatelessWidget {
  const StarterPackCard({
    super.key,
    required this.pack,
    required this.onGrab,
    this.onTap,
  });

  final StarterPack pack;
  final VoidCallback onGrab;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 244,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.surfaceVariant),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A302950),
              blurRadius: 32,
              offset: Offset(0, 14),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Cover(pack: pack),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pack.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
                      fontStyle: FontStyle.italic,
                      color: AppColors.onSurface,
                      letterSpacing: -0.4,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    pack.subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  _GrabButton(onPressed: onGrab),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.pack});
  final StarterPack pack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            pack.coverImageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFE8E0FF), Color(0xFFA8A4F0)],
                ),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0x8C302950), Color(0x10302950), Colors.transparent],
                stops: [0, 0.5, 0.7],
              ),
            ),
          ),
          if (pack.tag != null)
            Positioned(
              top: 14,
              left: 14,
              child: _GradientTag(label: pack.tag!),
            ),
          Positioned(
            top: 14,
            right: 14,
            child: _CountBadge(count: pack.itemCount),
          ),
          Positioned(
            left: 14,
            bottom: 14,
            child: _PreviewStack(pack: pack),
          ),
        ],
      ),
    );
  }
}

class _GradientTag extends StatelessWidget {
  const _GradientTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A302950),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ShaderMask(
        shaderCallback: (r) => AppColors.primaryGradient.createShader(r),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.9,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A302950),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

class _PreviewStack extends StatelessWidget {
  const _PreviewStack({required this.pack});
  final StarterPack pack;

  @override
  Widget build(BuildContext context) {
    final shown = pack.previewItems.take(3).toList();
    final remaining = pack.itemCount - shown.length;
    return Row(
      children: [
        for (var i = 0; i < shown.length; i++)
          Transform.translate(
            offset: Offset(-10.0 * i, 0),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                image: DecorationImage(
                  image: NetworkImage(shown[i]),
                  fit: BoxFit.cover,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26302950),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        if (remaining > 0)
          Transform.translate(
            offset: Offset(-10.0 * shown.length + 4, 0),
            child: Text(
              '+$remaining',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.1,
                shadows: [Shadow(color: Color(0x66000000), blurRadius: 3)],
              ),
            ),
          ),
      ],
    );
  }
}

class _GrabButton extends StatelessWidget {
  const _GrabButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onPressed();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x4D4647D3),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 18),
            SizedBox(width: 6),
            Text(
              'Grab this list',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
