import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/utils/currency_utils.dart';
import 'package:wishiz/core/utils/error_utils.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';

class WishlistItemEditorScreen extends StatefulWidget {
  const WishlistItemEditorScreen({
    super.key,
    required this.repository,
    required this.wishlistId,
    required this.preferredCurrencyCode,
    required this.preferredCurrencySymbol,
    this.item,
    this.initialTitle,
    this.initialNotes,
    this.initialPriceLabel,
    this.initialImageUrl,
    this.initialProductUrl,
    this.isSharedImport = false,
  });

  final WishlistRepository repository;
  final String wishlistId;
  final String preferredCurrencyCode;
  final String preferredCurrencySymbol;
  final WishlistItem? item;
  final String? initialTitle;
  final String? initialNotes;
  final String? initialPriceLabel;
  final String? initialImageUrl;
  final String? initialProductUrl;
  final bool isSharedImport;

  bool get isEditing => item != null;

  @override
  State<WishlistItemEditorScreen> createState() =>
      _WishlistItemEditorScreenState();
}

class _WishlistItemEditorScreenState extends State<WishlistItemEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();

  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final TextEditingController _priceController;
  late final TextEditingController _imageUrlController;
  late final TextEditingController _productUrlController;
  late String _selectedPriority;
  late String _selectedStatus;
  bool _showImageValidationError = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.item?.title ?? widget.initialTitle ?? '',
    );
    _notesController = TextEditingController(
      text: widget.item?.notes ?? widget.initialNotes ?? '',
    );
    _priceController = TextEditingController(text: _normalizeExistingPrice());
    _imageUrlController = TextEditingController(
      text: widget.item?.imageUrl ?? widget.initialImageUrl ?? '',
    );
    _productUrlController = TextEditingController(
      text: widget.item?.productUrl ?? widget.initialProductUrl ?? '',
    );
    _selectedPriority = widget.item?.priority ?? WishlistItem.priorities[1];
    _selectedStatus = widget.item?.status ?? WishlistItem.statuses.first;

    if (!widget.isEditing && _productUrlController.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _applyLinkDefaults();
        }
      });
    }
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

  Future<void> _pickItemImage() async {
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) {
      return;
    }

    setState(() {
      _imageUrlController.text = image.path;
      _showImageValidationError = false;
    });
  }

  void _applyLinkDefaults() {
    final productUrl = _optionalValue(_productUrlController.text);
    if (productUrl == null) {
      return;
    }

    final uri = Uri.tryParse(productUrl);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return;
    }

    final inferredTitle = _inferTitleFromProductUri(uri);
    final inferredNotes = _inferNotesFromProductUri(uri);

    setState(() {
      if (_titleController.text.trim().isEmpty && inferredTitle != null) {
        _titleController.text = inferredTitle;
      }
      if (_notesController.text.trim().isEmpty && inferredNotes != null) {
        _notesController.text = inferredNotes;
      }
    });
  }

  Future<void> _saveItem() async {
    final formValid = _formKey.currentState!.validate();
    final missingImage =
        widget.isSharedImport && _imageUrlController.text.trim().isEmpty;

    if (!formValid || missingImage) {
      if (_showImageValidationError != missingImage) {
        setState(() {
          _showImageValidationError = missingImage;
        });
      }
      return;
    }

    if (_showImageValidationError) {
      setState(() {
        _showImageValidationError = false;
      });
    }

    final title = _titleController.text.trim();
    final notes = _optionalValue(_notesController.text);
    final priceLabel = _normalizePriceLabel(_priceController.text);
    final imageUrl = _optionalValue(_imageUrlController.text);
    final productUrl = _optionalValue(_productUrlController.text);

    try {
      if (widget.isEditing) {
        await widget.repository.updateWishlistItem(
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
        await widget.repository.addWishlistItem(
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
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              formatErrorMessage(
                error,
                fallbackMessage: 'Could not save this item.',
              ),
            ),
          ),
        );
      return;
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

  String _normalizeExistingPrice() {
    return CurrencyUtils.convertPriceLabel(
          widget.item?.priceLabel ?? widget.initialPriceLabel,
          targetCurrencyCode: widget.preferredCurrencyCode,
        ) ??
        '';
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
            padding: const EdgeInsets.fromLTRB(
              AppConstants.pagePadding,
              AppConstants.pagePadding,
              AppConstants.pagePadding,
              120,
            ),
            children: [
              Text(
                widget.isEditing
                    ? 'Refresh the details of this saved piece without changing the surrounding look.'
                    : widget.isSharedImport
                        ? 'Wishiz imported the product link and any metadata it could find. Fill in anything still missing, then save it to this list.'
                        : 'Add a new object to this collection while keeping the same editorial feel.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppConstants.sectionGap),
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
              const SizedBox(height: AppConstants.itemGap),
              _buildFieldCard(
                context,
                child: TextFormField(
                  controller: _notesController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    hintText:
                        'Why it fits the collection or what to compare before buying.',
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.itemGap),
              _buildFieldCard(
                context,
                child: TextFormField(
                  controller: _priceController,
                  decoration: InputDecoration(
                    labelText: 'Price',
                    hintText: '${widget.preferredCurrencySymbol}120',
                    border: InputBorder.none,
                  ),
                  validator: _validatePrice,
                ),
              ),
              const SizedBox(height: AppConstants.itemGap),
              _buildFieldCard(
                context,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedPriority,
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
              const SizedBox(height: AppConstants.itemGap),
              _buildFieldCard(
                context,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedStatus,
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
              const SizedBox(height: AppConstants.itemGap),
              if (_imageUrlController.text.isNotEmpty) ...[
                _buildImagePreview(context),
                const SizedBox(height: AppConstants.itemGap),
              ],
              Wrap(
                spacing: AppConstants.spacing2,
                runSpacing: AppConstants.spacing2,
                children: [
                  TextButton.icon(
                    onPressed: _pickItemImage,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choose From Gallery'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _imageUrlController.clear();
                        _showImageValidationError = false;
                      });
                    },
                    icon: const Icon(Icons.clear_outlined),
                    label: const Text('Clear Image'),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.itemGap),
              _buildFieldCard(
                context,
                child: TextFormField(
                  controller: _imageUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Image URL or local path',
                    hintText: 'https://image.jpg or local file path',
                    border: InputBorder.none,
                  ),
                  validator: _validateImageSource,
                  onChanged: (_) {
                    if (_showImageValidationError) {
                      setState(() {
                        _showImageValidationError = false;
                      });
                    } else {
                      setState(() {});
                    }
                  },
                ),
              ),
              if (_showImageValidationError) ...[
                const SizedBox(height: 8),
                Text(
                  'Please add an image before saving this shared item.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.error,
                      ),
                ),
              ],
              const SizedBox(height: AppConstants.itemGap),
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
                  validator: _validateProductUrl,
                  onEditingComplete: _applyLinkDefaults,
                ),
              ),
              const SizedBox(height: AppConstants.itemGap),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _applyLinkDefaults,
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: const Text('Use Link Defaults'),
                ),
              ),
              const SizedBox(height: AppConstants.sectionGap),
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
        horizontal: AppConstants.cardPadding,
        vertical: AppConstants.itemGap,
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

    final normalizedAmount = trimmed.replaceFirst(RegExp(r'^[^\d]+'), '');
    final amount = double.tryParse(normalizedAmount.replaceAll(',', ''));
    if (amount == null) {
      return trimmed;
    }

    return CurrencyUtils.formatAmount(amount, widget.preferredCurrencyCode);
  }

  String? _validateOptionalPrice(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }

    final normalized = trimmed.replaceFirst(RegExp(r'^[^\d]+'), '');
    final isValid =
        RegExp(r'^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$').hasMatch(
      normalized,
    );
    return isValid ? null : 'Use a valid amount like 120 or 120.00.';
  }

  String? _validatePrice(String? value) {
    final trimmed = value?.trim() ?? '';
    if (widget.isSharedImport && trimmed.isEmpty) {
      return 'Please add a price for this shared item.';
    }

    return _validateOptionalPrice(value);
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

  String? _validateProductUrl(String? value) {
    final trimmed = value?.trim() ?? '';
    if (widget.isSharedImport && trimmed.isEmpty) {
      return 'Please add the product URL.';
    }

    return _validateOptionalUrl(value);
  }

  String? _validateImageSource(String? value) {
    final trimmed = value?.trim() ?? '';
    if (widget.isSharedImport && trimmed.isEmpty) {
      return 'Please add an image URL for this shared item.';
    }

    if (trimmed.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(trimmed);
    final isRemote = uri != null && uri.hasScheme && uri.hasAuthority;
    final isLocalPath = trimmed.startsWith('/') || trimmed.contains(r'\');
    return isRemote || isLocalPath
        ? null
        : 'Please enter a valid image URL or file path.';
  }

  Widget _buildImagePreview(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final source = _imageUrlController.text.trim();
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

  String? _inferTitleFromProductUri(Uri uri) {
    final pathSegments =
        uri.pathSegments.where((segment) => segment.isNotEmpty);
    for (final segment in pathSegments.toList().reversed) {
      final decoded = Uri.decodeComponent(segment)
          .replaceAll(RegExp(r'[-_+]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final cleaned = decoded
          .replaceAll(RegExp(r'\b\d+\b'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (cleaned.isNotEmpty && cleaned.length > 2) {
        return _toTitleCase(cleaned);
      }
    }

    return null;
  }

  String? _inferNotesFromProductUri(Uri uri) {
    final host = uri.host.replaceFirst(RegExp(r'^www\.'), '').trim();
    if (host.isEmpty) {
      return null;
    }

    return 'Imported from $host.';
  }

  String _toTitleCase(String value) {
    return value.split(' ').where((word) => word.isNotEmpty).map((word) {
      final lower = word.toLowerCase();
      return '${lower[0].toUpperCase()}${lower.substring(1)}';
    }).join(' ');
  }
}
