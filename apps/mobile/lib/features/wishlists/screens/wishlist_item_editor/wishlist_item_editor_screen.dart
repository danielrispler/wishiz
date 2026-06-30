import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/utils/currency_utils.dart';
import 'package:wishiz/core/utils/error_utils.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_enums.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/repositories/shared_product_repository.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';
import 'package:wishiz/features/wishlists/shared/widgets/editor_field_card.dart';
import 'package:wishiz/features/wishlists/shared/widgets/editor_page_layout.dart';
import 'package:wishiz/features/wishlists/shared/widgets/editor_primary_button.dart';
import 'package:wishiz/features/wishlists/shared/widgets/editor_section_card.dart';
import 'components/item_details_section.dart';
import 'components/item_import_section.dart';
import 'components/item_organize_section.dart';
import 'components/item_preview_card.dart';

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
        if (mounted) _applyLinkDefaults();
      });
    }
  }

  @override
  void dispose() {
    _titleController..removeListener(_refreshUi)..dispose();
    _notesController..removeListener(_refreshUi)..dispose();
    _priceController..removeListener(_refreshUi)..dispose();
    _imageUrlController..removeListener(_refreshUi)..dispose();
    _productUrlController..removeListener(_refreshUi)..dispose();
    super.dispose();
  }

  void _refreshUi() {
    if (_selectedItemImage != null &&
        _imageUrlController.text.trim() != _selectedItemImage!.path) {
      _selectedItemImage = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickItemImage() async {
    if (_isSaving || _isGeneratingFromLink) return;
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    _selectedItemImage = image;
    _imageUrlController.text = image.path;
  }

  void _clearImage() {
    _imageUrlController.clear();
  }

  Future<void> _pasteImageUrl() async {
    if (_isSaving || _isGeneratingFromLink) return;
    final urlController = TextEditingController(text: _imageUrlController.text);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Paste image URL'),
          content: TextField(
            controller: urlController,
            keyboardType: TextInputType.url,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'https://'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Apply'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        final url = urlController.text.trim();
        if (url.isNotEmpty) {
          _selectedItemImage = null;
          _imageUrlController.text = url;
        }
      }
    } finally {
      urlController.dispose();
    }
  }

  void _applyLinkDefaults() {
    final productUrl = _optionalValue(_productUrlController.text);
    if (productUrl == null) return;
    final uri = Uri.tryParse(productUrl);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return;
    setState(() {
      if (_titleController.text.trim().isEmpty) {
        _titleController.text = _inferTitleFromProductUri(uri) ?? _titleController.text;
      }
      if (_notesController.text.trim().isEmpty) {
        _notesController.text = _inferNotesFromProductUri(uri) ?? _notesController.text;
      }
    });
  }

  Future<void> _saveItem() async {
    if (_isSaving || _isGeneratingFromLink) return;
    final formValid = _formKey.currentState!.validate();
    if (!formValid) return;

    final title = _titleController.text.trim();
    final notes = _optionalValue(_notesController.text);
    final priceLabel = _normalizePriceLabel(_priceController.text);
    final productUrl = _optionalValue(_productUrlController.text);

    String? resolvedWishlistId = widget.wishlistId;
    if (resolvedWishlistId == null) {
      resolvedWishlistId = await widget.onSelectWishlist?.call();
      if (!mounted || resolvedWishlistId == null) return;
    }

    setState(() => _isSaving = true);

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
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(formatErrorMessage(error, fallbackMessage: 'Could not save this item.')),
        ));
      return;
    }

    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(widget.isEditing ? 'Item updated.' : 'Item added.')));
    Navigator.of(context).pop(true);
  }

  Future<void> _generateFromProductLink() async {
    if (_isGeneratingFromLink || _isSaving) return;
    final productUrl = _optionalValue(_productUrlController.text);
    final validationMessage = _validateProductUrl(productUrl);
    if (validationMessage != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(validationMessage)));
      return;
    }
    final sharedProductRepository = widget.sharedProductRepository;
    if (sharedProductRepository == null || productUrl == null) return;

    setState(() => _isGeneratingFromLink = true);
    try {
      final draft = await sharedProductRepository.createDraftFromSharedText(
        productUrl,
        targetCurrencyCode: widget.preferredCurrencyCode,
      );
      if (!mounted) return;
      if (draft == null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Wishiz could not find a product link there.')));
        return;
      }
      setState(() {
        if (draft.title != null) _titleController.text = draft.title!;
        _notesController.text = draft.notes ?? '';
        _priceController.text = CurrencyUtils.convertPriceLabel(
              draft.priceLabel, targetCurrencyCode: widget.preferredCurrencyCode) ?? '';
        _imageUrlController.text = draft.imageUrl ?? '';
        _productUrlController.text = draft.productUrl;
        _isLinkPreview = true;
      });
      if (!draft.hasCompleteRequiredFields) {
        final missingFields = draft.missingFieldLabels.join(', ');
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('We filled part of this product. Please add the missing $missingFields before saving.'),
          ));
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Product details generated.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(formatErrorMessage(error, fallbackMessage: 'Could not generate product details yet.')),
        ));
    } finally {
      if (mounted) setState(() => _isGeneratingFromLink = false);
    }
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
          ItemPreviewCard(
            title: _titleController.text.trim(),
            notes: _notesController.text.trim(),
            price: _normalizePriceLabel(_priceController.text) ?? _priceController.text.trim(),
            imageUrl: _imageUrlController.text.trim(),
            isLinkPreview: _isLinkPreview,
          ),
          const SizedBox(height: AppConstants.sectionGap),
          if (!widget.isEditing) ...[
            ItemImportSection(
              productUrlController: _productUrlController,
              hasSharedProductRepository: widget.sharedProductRepository != null,
              isBusy: isBusy,
              isGeneratingFromLink: _isGeneratingFromLink,
              validateProductUrl: _validateProductUrl,
              onApplyLinkDefaults: _applyLinkDefaults,
              onGenerateFromLink: _generateFromProductLink,
            ),
            const SizedBox(height: AppConstants.sectionGap),
          ],
          ItemDetailsSection(
            titleController: _titleController,
            notesController: _notesController,
            priceController: _priceController,
            priceHelperText: _detectedRangeHelper(),
            imageUrl: _imageUrlController.text.trim(),
            isBusy: isBusy,
            autofocusTitle: !widget.isEditing,
            preferredCurrencySymbol: widget.preferredCurrencySymbol,
            onPickImage: _pickItemImage,
            onClearImage: _clearImage,
            onPasteImageUrl: _pasteImageUrl,
            validateTitle: (value) {
              if (value == null || value.trim().isEmpty) return 'Please add an item title.';
              return null;
            },
            validatePrice: _validatePrice,
          ),
          if (widget.isEditing) ...[
            const SizedBox(height: AppConstants.sectionGap),
            ItemOrganizeSection(
              selectedPriority: _selectedPriority,
              selectedStatus: _selectedStatus,
              onPriorityChanged: (p) => setState(() => _selectedPriority = p),
              onStatusChanged: (s) => setState(() => _selectedStatus = s),
            ),
            const SizedBox(height: AppConstants.sectionGap),
            _buildLinkSection(),
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

  Widget _buildLinkSection() {
    return EditorSectionCard(
      title: 'Store link',
      description: 'Keep the original product page so it is easy to revisit later.',
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

  String? _optionalValue(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _normalizePriceLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final normalizedAmount = trimmed.replaceFirst(RegExp(r'^[^\d]+'), '');
    final amount = double.tryParse(normalizedAmount.replaceAll(',', ''));
    if (amount == null) return trimmed;
    return CurrencyUtils.formatAmount(amount, widget.preferredCurrencyCode);
  }

  String? _validateOptionalPrice(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final normalized = trimmed.replaceFirst(RegExp(r'^[^\d]+'), '');
    final isValid = RegExp(r'^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$').hasMatch(normalized);
    return isValid ? null : 'Use a valid amount like 120 or 120.00.';
  }

  String? _validatePrice(String? value) {
    final trimmed = value?.trim() ?? '';
    if (widget.isSharedImport && trimmed.isEmpty) return 'Please add a price for this shared item.';
    return _validateOptionalPrice(value);
  }

  String? _validateOptionalUrl(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    final isValid = uri != null && uri.hasScheme && uri.hasAuthority;
    return isValid ? null : 'Please enter a valid URL.';
  }

  String? _validateProductUrl(String? value) {
    final trimmed = value?.trim() ?? '';
    if (widget.isSharedImport && trimmed.isEmpty) return 'Please add the product URL.';
    return _validateOptionalUrl(value);
  }

  Future<String?> _resolveItemImageUrl() async {
    if (_selectedItemImage == null) return _optionalValue(_imageUrlController.text);
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

  String _normalizeExistingPrice() {
    final item = widget.item;
    // A range item prefills the LOW/"starting" bound (converted): the user edits to
    // their chosen variant, and saving the single value collapses the item to a
    // fixed price (the backend clears the stored max). The full range is surfaced as
    // helper text. Scalar / manually-entered items keep the label path.
    if (item != null && item.priceAmount != null && item.priceCurrencyCode != null) {
      final low = CurrencyUtils.formatRange(
        item.priceAmount,
        null,
        fromCurrencyCode: item.priceCurrencyCode!,
        targetCurrencyCode: widget.preferredCurrencyCode,
      );
      if (low != null) return low;
    }
    return CurrencyUtils.convertPriceLabel(
          widget.item?.priceLabel ?? widget.initialPriceLabel,
          targetCurrencyCode: widget.preferredCurrencyCode,
        ) ?? '';
  }

  /// Full detected range ("Detected range: $579 – $1,598", converted) shown under
  /// the price field for a range item, so editing the price to one variant is clear.
  /// Null for scalar items.
  String? _detectedRangeHelper() {
    final item = widget.item;
    if (item == null || item.priceAmountMax == null || item.priceCurrencyCode == null) {
      return null;
    }
    final range = CurrencyUtils.formatRange(
      item.priceAmount,
      item.priceAmountMax,
      fromCurrencyCode: item.priceCurrencyCode!,
      targetCurrencyCode: widget.preferredCurrencyCode,
    );
    return range == null ? null : 'Detected range: $range';
  }

  String? _inferTitleFromProductUri(Uri uri) {
    final pathSegments = uri.pathSegments.where((s) => s.isNotEmpty);
    for (final segment in pathSegments.toList().reversed) {
      final decoded = Uri.decodeComponent(segment)
          .replaceAll(RegExp(r'[-_+]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final cleaned = decoded
          .replaceAll(RegExp(r'\b\d+\b'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (cleaned.isNotEmpty && cleaned.length > 2) return _toTitleCase(cleaned);
    }
    return null;
  }

  String? _inferNotesFromProductUri(Uri uri) {
    final host = uri.host.replaceFirst(RegExp(r'^www\.'), '').trim();
    if (host.isEmpty) return null;
    return 'Imported from $host.';
  }

  String _toTitleCase(String value) {
    return value.split(' ').where((w) => w.isNotEmpty).map((w) {
      final lower = w.toLowerCase();
      return '${lower[0].toUpperCase()}${lower.substring(1)}';
    }).join(' ');
  }
}

String? _inferImageContentType(String fileName) {
  final normalized = fileName.toLowerCase();
  if (normalized.endsWith('.jpg') || normalized.endsWith('.jpeg')) return 'image/jpeg';
  if (normalized.endsWith('.png')) return 'image/png';
  if (normalized.endsWith('.webp')) return 'image/webp';
  return null;
}
