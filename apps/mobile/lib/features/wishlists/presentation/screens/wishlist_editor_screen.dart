import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';

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
  late final TextEditingController _yearController;
  late bool _isShared;

  @override
  void initState() {
    super.initState();
    _titleController =
        TextEditingController(text: widget.wishlist?.title ?? '');
    _descriptionController = TextEditingController(
      text: widget.wishlist?.description ?? '',
    );
    _coverImageUrlController = TextEditingController(
      text: widget.wishlist?.coverImageUrl ?? '',
    );
    _yearController = TextEditingController(
      text: (widget.wishlist?.year ?? DateTime.now().year).toString(),
    );
    _isShared = widget.wishlist?.isShared ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _coverImageUrlController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  Future<void> _pickCoverImage() async {
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) {
      return;
    }

    setState(() {
      _coverImageUrlController.text = image.path;
    });
  }

  Future<void> _saveWishlist() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final coverImageUrl = _optionalValue(_coverImageUrlController.text);
    final year = int.parse(_yearController.text.trim());

    final savedWishlist = widget.isEditing
        ? await widget.repository.updateWishlist(
            id: widget.wishlist!.id,
            title: title,
            description: description,
            year: year,
            coverImageUrl: coverImageUrl,
            isShared: _isShared,
          )
        : await widget.repository.createWishlist(
            title: title,
            description: description,
            year: year,
            coverImageUrl: coverImageUrl,
            isShared: _isShared,
          );

    if (!mounted || savedWishlist == null) {
      return;
    }

    final message = widget.isEditing ? 'List updated.' : 'List created.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
      );
    Navigator.of(context).pop(savedWishlist.id);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit List' : 'Create List'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppConstants.spacing4),
            children: [
              Text(
                widget.isEditing
                    ? 'Update the list details, year, and cover image without waiting for a backend upload flow.'
                    : 'Create a list with a title, year, and gallery cover so it already feels like a real collection.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppConstants.spacing4),
              _buildFieldCard(
                context,
                child: TextFormField(
                  controller: _titleController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'List title',
                    hintText: 'Home Objects',
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
              const SizedBox(height: AppConstants.spacing3),
              _buildFieldCard(
                context,
                child: TextFormField(
                  controller: _yearController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Year',
                    hintText: '2026',
                    border: InputBorder.none,
                  ),
                  validator: _validateYear,
                ),
              ),
              const SizedBox(height: AppConstants.spacing3),
              _buildFieldCard(
                context,
                child: TextFormField(
                  controller: _descriptionController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText:
                        'A calm, minimal collection with tactile materials.',
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spacing3),
              if (_coverImageUrlController.text.isNotEmpty) ...[
                _buildImagePreview(context),
                const SizedBox(height: AppConstants.spacing3),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _pickCoverImage,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choose From Gallery'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _coverImageUrlController.clear();
                      });
                    },
                    icon: const Icon(Icons.clear_outlined),
                    label: const Text('Clear Image'),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spacing3),
              _buildFieldCard(
                context,
                child: TextFormField(
                  controller: _coverImageUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Cover image path or URL',
                    hintText: 'https:// or local image path',
                    border: InputBorder.none,
                  ),
                  validator: _validateOptionalImageSource,
                ),
              ),
              const SizedBox(height: AppConstants.spacing3),
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                ),
                padding: const EdgeInsets.all(AppConstants.spacing4),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Shared list',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    'Enable member sharing and link-based invites for this list.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  value: _isShared,
                  onChanged: (value) {
                    setState(() {
                      _isShared = value;
                    });
                  },
                ),
              ),
              const SizedBox(height: AppConstants.spacing6),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary,
                      colorScheme.primaryContainer,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: ElevatedButton(
                  onPressed: _saveWishlist,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppConstants.spacing4,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                    ),
                  ),
                  child: Text(
                    widget.isEditing ? 'Save Changes' : 'Create List',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFieldCard(
    BuildContext context, {
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing4,
        vertical: AppConstants.spacing3,
      ),
      child: child,
    );
  }

  Widget _buildImagePreview(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final source = _coverImageUrlController.text.trim();
    final uri = Uri.tryParse(source);
    final isRemote = uri != null &&
        (uri.scheme == 'http' ||
            uri.scheme == 'https' ||
            uri.scheme == 'blob' ||
            uri.scheme == 'data');

    final image = kIsWeb || isRemote
        ? Image.network(
            source,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _imageFallback(
              colorScheme,
            ),
          )
        : Image.file(
            File(source),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _imageFallback(
              colorScheme,
            ),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: image,
      ),
    );
  }

  Widget _imageFallback(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  String? _optionalValue(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _validateOptionalImageSource(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(trimmed);
    final isRemote = uri != null && uri.hasScheme && uri.hasAuthority;
    final isLocalFile = !kIsWeb && File(trimmed).existsSync();
    return isRemote || isLocalFile
        ? null
        : 'Enter a valid image URL or pick a gallery image.';
  }

  String? _validateYear(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 2000 || parsed > 2100) {
      return 'Please enter a valid year.';
    }
    return null;
  }
}
