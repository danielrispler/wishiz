import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/wishlists/shared/widgets/editor_utils.dart';

class ItemImageSection extends StatelessWidget {
  const ItemImageSection({
    super.key,
    required this.imageUrl,
    required this.isBusy,
    required this.onPickImage,
    required this.onClearImage,
    required this.onPasteImageUrl,
  });

  final String imageUrl;
  final bool isBusy;
  final VoidCallback onPickImage;
  final VoidCallback onClearImage;
  final VoidCallback onPasteImageUrl;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasImage) ...[
          _ImagePreview(
            imageUrl: imageUrl,
            onClear: onClearImage,
          ),
          const SizedBox(height: AppConstants.itemGap),
        ],
        FilledButton.icon(
          onPressed: isBusy ? null : onPickImage,
          icon: Icon(
            hasImage ? Icons.photo_camera_back_outlined : Icons.upload_outlined,
          ),
          label: Text(hasImage ? 'Change Image' : 'Upload Image'),
        ),
        const SizedBox(height: AppConstants.spacing2),
        OutlinedButton.icon(
          onPressed: isBusy ? null : onPasteImageUrl,
          icon: const Icon(Icons.link_rounded),
          label: const Text('Paste Image URL'),
        ),
      ],
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.imageUrl, required this.onClear});

  final String imageUrl;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final uri = Uri.tryParse(imageUrl);
    final isRemote = isRemoteUri(uri);
    final fallback = Container(
      color: colorScheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: colorScheme.onSurfaceVariant),
    );

    final image = kIsWeb || isRemote
        ? Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback)
        : Image.file(File(imageUrl), fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback);

    return Stack(
      children: [
        InkWell(
          onTap: () => _openImageViewer(context, imageUrl, isRemote),
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
            child: AspectRatio(aspectRatio: 16 / 9, child: image),
          ),
        ),
        Positioned(
          top: AppConstants.spacing3,
          right: AppConstants.spacing3,
          child: Material(
            color: Colors.black.withValues(alpha: 0.45),
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
              color: Colors.white,
              tooltip: 'Remove image',
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openImageViewer(BuildContext context, String source, bool isRemote) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            SafeArea(
              child: Center(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: kIsWeb || isRemote
                      ? Image.network(source, fit: BoxFit.contain)
                      : Image.file(File(source), fit: BoxFit.contain),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
