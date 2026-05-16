import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/utils/error_utils.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';
import 'package:wishiz/features/wishlists/presentation/widgets/editor_widgets.dart';

class WishlistEditorScreen extends StatefulWidget {
  const WishlistEditorScreen({
    super.key,
    required this.repository,
    this.wishlist,
  });

  final WishlistRepository repository;
  final Wishlist? wishlist;

  bool get isEditing => wishlist != null;

  @override
  State<WishlistEditorScreen> createState() => _WishlistEditorScreenState();
}

class _WishlistEditorScreenState extends State<WishlistEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _coverImageUrlController;
  XFile? _selectedCoverImage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.wishlist?.title ?? '')
      ..addListener(_refreshPreview);
    _descriptionController = TextEditingController(
      text: widget.wishlist?.description ?? '',
    )..addListener(_refreshPreview);
    _coverImageUrlController = TextEditingController(
      text: widget.wishlist?.coverImageUrl ?? '',
    )..addListener(_refreshPreview);
  }

  @override
  void dispose() {
    _titleController
      ..removeListener(_refreshPreview)
      ..dispose();
    _descriptionController
      ..removeListener(_refreshPreview)
      ..dispose();
    _coverImageUrlController
      ..removeListener(_refreshPreview)
      ..dispose();
    super.dispose();
  }

  void _refreshPreview() {
    if (_selectedCoverImage != null &&
        _coverImageUrlController.text.trim() != _selectedCoverImage!.path) {
      _selectedCoverImage = null;
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _pickCoverImage() async {
    if (_isSaving) {
      return;
    }

    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) {
      return;
    }

    _selectedCoverImage = image;
    _coverImageUrlController.text = image.path;
  }

  Future<void> _saveWishlist() async {
    if (_isSaving || !_formKey.currentState!.validate()) {
      return;
    }

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final year = widget.isEditing ? widget.wishlist!.year : DateTime.now().year;

    setState(() {
      _isSaving = true;
    });

    final Wishlist? savedWishlist;
    try {
      final coverImageUrl = await _resolveCoverImageUrl();
      savedWishlist = widget.isEditing
          ? await widget.repository.updateWishlist(
              id: widget.wishlist!.id,
              title: title,
              description: description,
              year: year,
              coverImageUrl: coverImageUrl,
            )
          : await widget.repository.createWishlist(
              title: title,
              description: description,
              year: year,
              coverImageUrl: coverImageUrl,
            );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              formatErrorMessage(
                error,
                fallbackMessage: 'Could not save this list.',
              ),
            ),
          ),
        );
      return;
    }

    if (!mounted || savedWishlist == null) {
      return;
    }

    final message = widget.isEditing ? 'List updated.' : 'List created.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).pop(savedWishlist.id);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: EditorPageLayout(
        title: widget.isEditing ? 'Edit List' : 'Create List',
        children: [
          EditorIntroCard(
            title: widget.isEditing
                ? 'Update the list'
                : 'Start with the basics',
            description: widget.isEditing
                ? 'Make the title and cover easier to recognize at a glance.'
                : 'Create a list people of any age can understand quickly: clear title and an optional cover.',
            icon: widget.isEditing
                ? Icons.edit_outlined
                : Icons.auto_awesome_outlined,
          ),
          const SizedBox(height: AppConstants.sectionGap),
          _buildPreviewCard(context),
          const SizedBox(height: AppConstants.sectionGap),
          EditorSectionCard(
            title: 'List details',
            description:
                'These fields help people understand the collection immediately.',
            child: Column(
              children: [
                EditorFieldCard(
                  child: TextFormField(
                    controller: _titleController,
                    autofocus: !widget.isEditing,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'List title',
                      hintText: 'Birthday ideas',
                      border: InputBorder.none,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please add a title.';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: AppConstants.itemGap),
                EditorFieldCard(
                  child: TextFormField(
                    controller: _descriptionController,
                    minLines: 3,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: 'Short note',
                      hintText:
                          'Who this list is for, the style, or what belongs here.',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.itemGap),
                _buildImageUploadButton(context),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.sectionGap),
          EditorPrimaryButton(
            label: _isSaving
                ? 'Saving...'
                : widget.isEditing
                ? 'Save Changes'
                : 'Create List',
            onPressed: _isSaving ? null : _saveWishlist,
            helper:
                'Keep it short and easy to scan. You can refine the details later.',
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = _titleController.text.trim().isEmpty
        ? 'Your list title'
        : _titleController.text.trim();
    final year = (widget.wishlist?.year ?? DateTime.now().year).toString();
    final description = _descriptionController.text.trim().isEmpty
        ? 'A simple preview of how this list will read before you save it.'
        : _descriptionController.text.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacing5),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(18),
            ),
            clipBehavior: Clip.antiAlias,
            child: _coverImageUrlController.text.trim().isEmpty
                ? Icon(
                    Icons.collections_bookmark_outlined,
                    color: colorScheme.primary,
                    size: 28,
                  )
                : _buildPreviewImage(context),
          ),
          const SizedBox(width: AppConstants.spacing4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppConstants.spacing1),
                Text(
                  year,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: colorScheme.primary),
                ),
                const SizedBox(height: AppConstants.spacing2),
                Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewImage(BuildContext context) {
    final source = _coverImageUrlController.text.trim();
    final uri = Uri.tryParse(source);
    final isRemote = isRemoteUri(uri);

    return kIsWeb || isRemote
        ? Image.network(
            source,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _imageFallback(Theme.of(context).colorScheme),
          )
        : Image.file(
            File(source),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _imageFallback(Theme.of(context).colorScheme),
          );
  }

  Widget _buildImageUploadButton(BuildContext context) {
    final hasImage = _coverImageUrlController.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasImage) ...[
          _buildImagePreview(context),
          const SizedBox(height: AppConstants.itemGap),
        ],
        FilledButton.icon(
          onPressed: _pickCoverImage,
          icon: Icon(
            hasImage ? Icons.photo_camera_back_outlined : Icons.upload_outlined,
          ),
          label: Text(hasImage ? 'Change Image' : 'Upload Image'),
        ),
      ],
    );
  }

  Widget _buildImagePreview(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final source = _coverImageUrlController.text.trim();
    final uri = Uri.tryParse(source);
    final isRemote = isRemoteUri(uri);

    final image = kIsWeb || isRemote
        ? Image.network(
            source,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _imageFallback(colorScheme),
          )
        : Image.file(
            File(source),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _imageFallback(colorScheme),
          );

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
          child: AspectRatio(aspectRatio: 16 / 9, child: image),
        ),
        Positioned(
          top: AppConstants.spacing3,
          right: AppConstants.spacing3,
          child: Material(
            color: Colors.black.withValues(alpha: 0.45),
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: () => _coverImageUrlController.clear(),
              icon: const Icon(Icons.close_rounded),
              color: Colors.white,
              tooltip: 'Remove image',
            ),
          ),
        ),
      ],
    );
  }

  Widget _imageFallback(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: colorScheme.onSurfaceVariant),
    );
  }

  String? _optionalValue(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<String?> _resolveCoverImageUrl() async {
    if (_selectedCoverImage == null) {
      return _optionalValue(_coverImageUrlController.text);
    }

    final image = _selectedCoverImage!;
    final uploadedUrl = await widget.repository.uploadImage(
      bytes: await image.readAsBytes(),
      fileName: image.name,
      contentType: _inferImageContentType(image.name),
    );
    _selectedCoverImage = null;
    _coverImageUrlController.text = uploadedUrl;
    return uploadedUrl;
  }
}

String? _inferImageContentType(String fileName) {
  final normalized = fileName.toLowerCase();
  if (normalized.endsWith('.jpg') || normalized.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (normalized.endsWith('.png')) {
    return 'image/png';
  }
  if (normalized.endsWith('.webp')) {
    return 'image/webp';
  }
  if (normalized.endsWith('.gif')) {
    return 'image/gif';
  }
  return null;
}
