import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/utils/currency_utils.dart';
import 'package:wishiz/core/utils/error_utils.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_enums.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/repositories/shared_product_repository.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';
import 'package:wishiz/features/wishlists/presentation/widgets/editor_widgets.dart';

class WishlistItemEditorScreen extends StatefulWidget {
  const WishlistItemEditorScreen({
    super.key,
    required this.repository,
    this.wishlistId,
    required this.preferredCurrencyCode,
    required this.preferredCurrencySymbol,
    this.sharedProductRepository,
    this.onSelectWishlist,
    this.item,
    this.initialTitle,
    this.initialNotes,
    this.initialPriceLabel,
    this.initialImageUrl,
    this.initialProductUrl,
    this.isSharedImport = false,
  });

  final WishlistRepository repository;
  final String? wishlistId;
  final String preferredCurrencyCode;
  final String preferredCurrencySymbol;
  final SharedProductRepository? sharedProductRepository;
  final Future<String?> Function()? onSelectWishlist;
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
  late WishlistItemPriority _selectedPriority;
  late WishlistItemStatus _selectedStatus;
  late bool _isLinkPreview;
  XFile? _selectedItemImage;
  bool _showImageValidationError = false;
  bool _isGeneratingFromLink = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.item?.title ?? widget.initialTitle ?? '',
    )..addListener(_refreshUi);
    _notesController = TextEditingController(
      text: widget.item?.notes ?? widget.initialNotes ?? '',
    )..addListener(_refreshUi);
    _priceController = TextEditingController(text: _normalizeExistingPrice())
      ..addListener(_refreshUi);
    _imageUrlController = TextEditingController(
      text: widget.item?.imageUrl ?? widget.initialImageUrl ?? '',
    )..addListener(_refreshUi);
    _productUrlController = TextEditingController(
      text: widget.item?.productUrl ?? widget.initialProductUrl ?? '',
    )..addListener(_refreshUi);
    _selectedPriority = widget.item?.priority ?? WishlistItem.priorities[1];
    _selectedStatus = widget.item?.status ?? WishlistItem.statuses.first;
    _isLinkPreview = widget.isSharedImport;

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
    _titleController
      ..removeListener(_refreshUi)
      ..dispose();
    _notesController
      ..removeListener(_refreshUi)
      ..dispose();
    _priceController
      ..removeListener(_refreshUi)
      ..dispose();
    _imageUrlController
      ..removeListener(_refreshUi)
      ..dispose();
    _productUrlController
      ..removeListener(_refreshUi)
      ..dispose();
    super.dispose();
  }

  void _refreshUi() {
    if (_selectedItemImage != null &&
        _imageUrlController.text.trim() != _selectedItemImage!.path) {
      _selectedItemImage = null;
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _pickItemImage() async {
    if (_isSaving || _isGeneratingFromLink) {
      return;
    }

    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) {
      return;
    }

    _selectedItemImage = image;
    _imageUrlController.text = image.path;
    if (_showImageValidationError) {
      setState(() {
        _showImageValidationError = false;
      });
    }
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
    if (_isSaving || _isGeneratingFromLink) {
      return;
    }

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
    final productUrl = _optionalValue(_productUrlController.text);

    String? resolvedWishlistId = widget.wishlistId;
    if (resolvedWishlistId == null) {
      resolvedWishlistId = await widget.onSelectWishlist?.call();
      if (!mounted || resolvedWishlistId == null) return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final imageUrl = await _resolveItemImageUrl();
      if (widget.isEditing) {
        await widget.repository.updateWishlistItem(
          wishlistId: resolvedWishlistId,
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
          wishlistId: resolvedWishlistId,
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

    setState(() {
      _isSaving = false;
    });

    final message = widget.isEditing ? 'Item updated.' : 'Item added.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).pop(true);
  }

  Future<void> _generateFromProductLink() async {
    if (_isGeneratingFromLink || _isSaving) {
      return;
    }

    final productUrl = _optionalValue(_productUrlController.text);
    final validationMessage = _validateProductUrl(productUrl);
    if (validationMessage != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(validationMessage)));
      return;
    }

    final sharedProductRepository = widget.sharedProductRepository;
    if (sharedProductRepository == null || productUrl == null) {
      return;
    }

    setState(() {
      _isGeneratingFromLink = true;
    });

    try {
      final draft = await sharedProductRepository.createDraftFromSharedText(
        productUrl,
        targetCurrencyCode: widget.preferredCurrencyCode,
      );

      if (!mounted) {
        return;
      }

      if (draft == null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Wishiz could not find a product link there.'),
            ),
          );
        return;
      }

      setState(() {
        if (draft.title != null) {
          _titleController.text = draft.title!;
        }
        _notesController.text = draft.notes ?? '';
        _priceController.text =
            CurrencyUtils.convertPriceLabel(
              draft.priceLabel,
              targetCurrencyCode: widget.preferredCurrencyCode,
            ) ??
            '';
        _imageUrlController.text = draft.imageUrl ?? '';
        _productUrlController.text = draft.productUrl;
        _isLinkPreview = true;
        _showImageValidationError = false;
      });

      if (!draft.hasCompleteRequiredFields) {
        final missingFields = draft.missingFieldLabels.join(', ');
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'We filled part of this product. Please add the missing $missingFields before saving.',
              ),
            ),
          );
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Product details generated.')),
        );
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
                fallbackMessage: 'Could not generate product details yet.',
              ),
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingFromLink = false;
        });
      }
    }
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
    final isBusy = _isGeneratingFromLink || _isSaving;
    final isReviewingImportedDetails = _isLinkPreview && !widget.isEditing;

    return Form(
      key: _formKey,
      child: EditorPageLayout(
        title: widget.isEditing
            ? 'Edit Item'
            : isReviewingImportedDetails
            ? 'Review Item'
            : 'Add Item',
        children: [
          EditorIntroCard(
            title: _buildIntroTitle(isReviewingImportedDetails),
            description: _buildIntroDescription(isReviewingImportedDetails),
            icon: _buildIntroIcon(isReviewingImportedDetails),
          ),
          const SizedBox(height: AppConstants.sectionGap),
          _buildPreviewCard(context),
          const SizedBox(height: AppConstants.sectionGap),
          if (!widget.isEditing) ...[
            _buildImportSection(context, isBusy: isBusy),
            const SizedBox(height: AppConstants.sectionGap),
          ],
          _buildDetailsSection(context),
          if (widget.isEditing) ...[
            const SizedBox(height: AppConstants.sectionGap),
            _buildOrganizeSection(context),
          ],
          if (widget.isEditing) ...[
            const SizedBox(height: AppConstants.sectionGap),
            _buildLinkSection(context),
          ],
          const SizedBox(height: AppConstants.sectionGap),
          EditorPrimaryButton(
            label: _isSaving
                ? 'Saving...'
                : widget.isEditing
                ? 'Save Item'
                : isReviewingImportedDetails
                ? 'Verify And Save'
                : 'Add Item',
            onPressed: isBusy ? null : _saveItem,
            helper: _isGeneratingFromLink
                ? 'Generating product details...'
                : 'Keep only the details that help someone decide quickly.',
          ),
        ],
      ),
    );
  }

  Widget _buildImportSection(BuildContext context, {required bool isBusy}) {
    return EditorSectionCard(
      title: 'Start from a product link',
      description:
          'Paste a store link to prefill the item. You can still change everything before saving.',
      child: Column(
        children: [
          EditorFieldCard(
            child: TextFormField(
              controller: _productUrlController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              decoration: const InputDecoration(
                labelText: 'Product link',
                hintText: 'https://',
                border: InputBorder.none,
              ),
              validator: _validateProductUrl,
              onEditingComplete: _applyLinkDefaults,
            ),
          ),
          const SizedBox(height: AppConstants.spacing3),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.sharedProductRepository == null || isBusy
                  ? null
                  : _generateFromProductLink,
              icon: Icon(
                _isGeneratingFromLink
                    ? Icons.hourglass_top_outlined
                    : Icons.auto_fix_high_outlined,
              ),
              label: Text(
                _isGeneratingFromLink
                    ? 'Generating Details...'
                    : 'Fill From Link',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSection(BuildContext context) {
    return EditorSectionCard(
      title: 'Item details',
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 640;

              if (!isWide) {
                return Column(
                  children: [
                    _buildTitleField(autofocus: !widget.isEditing),
                    const SizedBox(height: AppConstants.itemGap),
                    _buildNotesField(),
                    const SizedBox(height: AppConstants.itemGap),
                    _buildPriceField(),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        _buildTitleField(autofocus: !widget.isEditing),
                        const SizedBox(height: AppConstants.itemGap),
                        _buildPriceField(),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacing4),
                  Expanded(child: _buildNotesField()),
                ],
              );
            },
          ),
          const SizedBox(height: AppConstants.itemGap),
          _buildImageUploadButton(context),
        ],
      ),
    );
  }

  Widget _buildOrganizeSection(BuildContext context) {
    return EditorSectionCard(
      title: 'Priority and status',
      description: 'Large tap targets make this easier to adjust quickly.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Priority', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppConstants.spacing2),
          Wrap(
            spacing: AppConstants.spacing2,
            runSpacing: AppConstants.spacing2,
            children: WishlistItem.priorities
                .map(
                  (priority) => ChoiceChip(
                    label: Text(priority.label),
                    selected: _selectedPriority == priority,
                    onSelected: (_) {
                      setState(() {
                        _selectedPriority = priority;
                      });
                    },
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: AppConstants.spacing4),
          Text('Status', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppConstants.spacing2),
          Wrap(
            spacing: AppConstants.spacing2,
            runSpacing: AppConstants.spacing2,
            children: WishlistItem.statuses
                .map(
                  (status) => ChoiceChip(
                    label: Text(status.label),
                    selected: _selectedStatus == status,
                    onSelected: (_) {
                      setState(() {
                        _selectedStatus = status;
                      });
                    },
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _buildImageUploadButton(BuildContext context) {
    final hasImage = _imageUrlController.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasImage) ...[
          _buildImagePreview(context),
          const SizedBox(height: AppConstants.itemGap),
        ],
        FilledButton.icon(
          onPressed: _pickItemImage,
          icon: Icon(
            hasImage ? Icons.photo_camera_back_outlined : Icons.upload_outlined,
          ),
          label: Text(hasImage ? 'Change Image' : 'Upload Image'),
        ),
        if (_showImageValidationError) ...[
          const SizedBox(height: AppConstants.spacing2),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Please choose an image from your gallery before saving this shared item.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLinkSection(BuildContext context) {
    return EditorSectionCard(
      title: 'Store link',
      description:
          'Keep the original product page so it is easy to revisit later.',
      child: EditorFieldCard(
        child: TextFormField(
          controller: _productUrlController,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Product link',
            hintText: 'https://',
            border: InputBorder.none,
          ),
          validator: _validateProductUrl,
          onEditingComplete: _applyLinkDefaults,
        ),
      ),
    );
  }

  Widget _buildTitleField({required bool autofocus}) {
    return EditorFieldCard(
      child: TextFormField(
        controller: _titleController,
        autofocus: autofocus,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
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
    );
  }

  Widget _buildNotesField() {
    return EditorFieldCard(
      child: TextFormField(
        controller: _notesController,
        minLines: 5,
        maxLines: 7,
        decoration: const InputDecoration(
          labelText: 'Notes',
          hintText: 'Why it fits the list, what to compare, or who it is for.',
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildPriceField() {
    return EditorFieldCard(
      child: TextFormField(
        controller: _priceController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: 'Price',
          hintText: '${widget.preferredCurrencySymbol}120',
          border: InputBorder.none,
        ),
        validator: _validatePrice,
      ),
    );
  }

  Widget _buildPreviewCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = _titleController.text.trim().isEmpty
        ? 'Your item title'
        : _titleController.text.trim();
    final notes = _notesController.text.trim().isEmpty
        ? 'A short preview of how this item will look before saving.'
        : _notesController.text.trim();
    final price = _priceController.text.trim().isEmpty
        ? 'No price yet'
        : _normalizePriceLabel(_priceController.text) ??
              _priceController.text.trim();

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
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(18),
            ),
            clipBehavior: Clip.antiAlias,
            child: _imageUrlController.text.trim().isEmpty
                ? Icon(
                    Icons.shopping_bag_outlined,
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
                  price,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: colorScheme.primary),
                ),
                const SizedBox(height: AppConstants.spacing2),
                Text(
                  notes,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (_isLinkPreview) ...[
                  const SizedBox(height: AppConstants.spacing3),
                  _buildMetaPill(context, 'Imported'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaPill(BuildContext context, String label) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing3,
        vertical: AppConstants.spacing2,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }

  Widget _buildPreviewImage(BuildContext context) {
    final source = _imageUrlController.text.trim();
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

  String _buildIntroTitle(bool isReviewingImportedDetails) {
    if (widget.isEditing) {
      return 'Update the item';
    }
    if (isReviewingImportedDetails) {
      return 'Review imported details';
    }
    return 'Add an item people can scan quickly';
  }

  String _buildIntroDescription(bool isReviewingImportedDetails) {
    if (widget.isEditing) {
      return 'Refresh the title, notes, image, and status without losing the original context.';
    }
    if (isReviewingImportedDetails) {
      return 'Check the imported title, price, and image, then fix anything that looks wrong before saving.';
    }
    return 'Clear title first, short notes second, optional extras last. The form is ordered to reduce friction.';
  }

  IconData _buildIntroIcon(bool isReviewingImportedDetails) {
    if (widget.isEditing) {
      return Icons.edit_outlined;
    }
    if (isReviewingImportedDetails) {
      return Icons.fact_check_outlined;
    }
    return Icons.add_task_outlined;
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
    final isValid = RegExp(
      r'^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$',
    ).hasMatch(normalized);
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

  Future<String?> _resolveItemImageUrl() async {
    if (_selectedItemImage == null) {
      return _optionalValue(_imageUrlController.text);
    }

    final image = _selectedItemImage!;
    final uploadedUrl = await widget.repository.uploadImage(
      bytes: await image.readAsBytes(),
      fileName: image.name,
      contentType: _inferImageContentType(image.name),
    );
    _selectedItemImage = null;
    _imageUrlController.text = uploadedUrl;
    return uploadedUrl;
  }

  Widget _buildImagePreview(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final source = _imageUrlController.text.trim();
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
        InkWell(
          onTap: () => _openImageViewer(context, source),
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
              onPressed: () {
                _imageUrlController.clear();
                if (_showImageValidationError) {
                  setState(() {
                    _showImageValidationError = false;
                  });
                }
              },
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

  Future<void> _openImageViewer(BuildContext context, String imageSource) {
    final uri = Uri.tryParse(imageSource);
    final isRemote = isRemoteUri(uri);

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
                      ? Image.network(imageSource, fit: BoxFit.contain)
                      : Image.file(File(imageSource), fit: BoxFit.contain),
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

  String? _inferTitleFromProductUri(Uri uri) {
    final pathSegments = uri.pathSegments.where(
      (segment) => segment.isNotEmpty,
    );
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
    return value
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) {
          final lower = word.toLowerCase();
          return '${lower[0].toUpperCase()}${lower.substring(1)}';
        })
        .join(' ');
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
