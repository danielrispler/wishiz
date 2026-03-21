import 'package:flutter/material.dart';
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

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _coverImageUrlController;
  late bool _isShared;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.wishlist?.title ?? '');
    _descriptionController = TextEditingController(
      text: widget.wishlist?.description ?? '',
    );
    _coverImageUrlController = TextEditingController(
      text: widget.wishlist?.coverImageUrl ?? '',
    );
    _isShared = widget.wishlist?.isShared ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _coverImageUrlController.dispose();
    super.dispose();
  }

  void _saveWishlist() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final coverImageUrl = _optionalValue(_coverImageUrlController.text);

    final savedWishlist = widget.isEditing
        ? widget.repository.updateWishlist(
            id: widget.wishlist!.id,
            title: title,
            description: description,
            coverImageUrl: coverImageUrl,
            isShared: _isShared,
          )
        : widget.repository.createWishlist(
            title: title,
            description: description,
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
                    ? 'Refine the collection without changing the overall visual identity.'
                    : 'Start a new collection while keeping the current curated tone.',
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
                  controller: _descriptionController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'A calm, minimal collection with tactile materials.',
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spacing3),
              _buildFieldCard(
                context,
                child: TextFormField(
                  controller: _coverImageUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Cover image URL',
                    hintText: 'https://',
                    border: InputBorder.none,
                  ),
                  validator: _validateOptionalUrl,
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
                    'Show this collection in the Shared tab too.',
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

  String? _optionalValue(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _validateOptionalUrl(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(trimmed);
    final isValid = uri != null && uri.hasScheme && uri.hasAuthority;
    return isValid ? null : 'Please enter a valid URL.';
  }
}
