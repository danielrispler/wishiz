import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';

class WishlistItemEditorScreen extends StatefulWidget {
  const WishlistItemEditorScreen({
    super.key,
    required this.repository,
    required this.wishlistId,
    this.item,
  });

  final WishlistRepository repository;
  final String wishlistId;
  final WishlistItem? item;

  bool get isEditing => item != null;

  @override
  State<WishlistItemEditorScreen> createState() => _WishlistItemEditorScreenState();
}

class _WishlistItemEditorScreenState extends State<WishlistItemEditorScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final TextEditingController _priceController;
  late final TextEditingController _imageUrlController;
  late final TextEditingController _productUrlController;
  late String _selectedPriority;
  late String _selectedStatus;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.item?.title ?? '');
    _notesController = TextEditingController(text: widget.item?.notes ?? '');
    _priceController = TextEditingController(text: widget.item?.priceLabel ?? '');
    _imageUrlController = TextEditingController(text: widget.item?.imageUrl ?? '');
    _productUrlController = TextEditingController(text: widget.item?.productUrl ?? '');
    _selectedPriority = widget.item?.priority ?? WishlistItem.priorities[1];
    _selectedStatus = widget.item?.status ?? WishlistItem.statuses.first;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _priceController.dispose();
    _imageUrlController.dispose();
    _productUrlController.dispose();
    super.dispose();
  }

  void _saveItem() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final title = _titleController.text.trim();
    final notes = _optionalValue(_notesController.text);
    final priceLabel = _normalizePriceLabel(_priceController.text);
    final imageUrl = _optionalValue(_imageUrlController.text);
    final productUrl = _optionalValue(_productUrlController.text);

    if (widget.isEditing) {
      widget.repository.updateWishlistItem(
        wishlistId: widget.wishlistId,
        itemId: widget.item!.id,
        title: title,
        notes: notes,
        priceLabel: priceLabel,
        priority: _selectedPriority,
        status: _selectedStatus,
        imageUrl: imageUrl,
        productUrl: productUrl,
      );
    } else {
      widget.repository.addWishlistItem(
        wishlistId: widget.wishlistId,
        title: title,
        notes: notes,
        priceLabel: priceLabel,
        priority: _selectedPriority,
        status: _selectedStatus,
        imageUrl: imageUrl,
        productUrl: productUrl,
      );
    }

    if (!mounted) {
      return;
    }

    final message = widget.isEditing ? 'Item updated.' : 'Item added.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
      );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Item' : 'Add Item'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppConstants.spacing4),
            children: [
              Text(
                widget.isEditing
                    ? 'Refresh the details of this saved piece without changing the surrounding look.'
                    : 'Add a new object to this collection while keeping the same editorial feel.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppConstants.spacing4),
              _buildFieldCard(
                context,
                child: TextFormField(
                  controller: _titleController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Item title',
                    hintText: 'Stoneware bowl set',
                    border: InputBorder.none,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please add an item title.';
                    }

                    return null;
                  },
                ),
              ),
              const SizedBox(height: AppConstants.spacing3),
              _buildFieldCard(
                context,
                child: TextFormField(
                  controller: _notesController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    hintText: 'Why it fits the collection or what to compare before buying.',
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spacing3),
              _buildFieldCard(
                context,
                child: TextFormField(
                  controller: _priceController,
                  decoration: const InputDecoration(
                    labelText: 'Price',
                    hintText: '\$120',
                    border: InputBorder.none,
                  ),
                  validator: _validateOptionalPrice,
                ),
              ),
              const SizedBox(height: AppConstants.spacing3),
              _buildFieldCard(
                context,
                child: DropdownButtonFormField<String>(
                  value: _selectedPriority,
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    border: InputBorder.none,
                  ),
                  items: WishlistItem.priorities.map((priority) {
                    return DropdownMenuItem(
                      value: priority,
                      child: Text(priority),
                    );
                  }).toList(growable: false),
                  onChanged: (value) {
                    setState(() {
                      _selectedPriority = value ?? WishlistItem.priorities[1];
                    });
                  },
                ),
              ),
              const SizedBox(height: AppConstants.spacing3),
              _buildFieldCard(
                context,
                child: DropdownButtonFormField<String>(
                  value: _selectedStatus,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: InputBorder.none,
                  ),
                  items: WishlistItem.statuses.map((status) {
                    return DropdownMenuItem(
                      value: status,
                      child: Text(status),
                    );
                  }).toList(growable: false),
                  onChanged: (value) {
                    setState(() {
                      _selectedStatus = value ?? WishlistItem.statuses.first;
                    });
                  },
                ),
              ),
              const SizedBox(height: AppConstants.spacing3),
              _buildFieldCard(
                context,
                child: TextFormField(
                  controller: _imageUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Image URL',
                    hintText: 'https://',
                    border: InputBorder.none,
                  ),
                  validator: _validateOptionalUrl,
                ),
              ),
              const SizedBox(height: AppConstants.spacing3),
              _buildFieldCard(
                context,
                child: TextFormField(
                  controller: _productUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Product link',
                    hintText: 'https://',
                    border: InputBorder.none,
                  ),
                  validator: _validateOptionalUrl,
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
                  onPressed: _saveItem,
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
                    widget.isEditing ? 'Save Item' : 'Add Item',
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

  String? _normalizePriceLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    return trimmed.startsWith('\$') ? trimmed : '\$$trimmed';
  }

  String? _validateOptionalPrice(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }

    final normalized = trimmed.startsWith('\$')
        ? trimmed.substring(1)
        : trimmed;
    final isValid = RegExp(r'^\d+([.,]\d{1,2})?$').hasMatch(normalized);
    return isValid ? null : 'Use a valid amount like 120 or 120.00.';
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
