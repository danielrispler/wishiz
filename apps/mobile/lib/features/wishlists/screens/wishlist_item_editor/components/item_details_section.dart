import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/wishlists/shared/widgets/editor_field_card.dart';
import 'package:wishiz/features/wishlists/shared/widgets/editor_section_card.dart';
import 'item_image_section.dart';

class ItemDetailsSection extends StatelessWidget {
  const ItemDetailsSection({
    super.key,
    required this.titleController,
    required this.notesController,
    required this.priceController,
    required this.imageUrl,
    required this.showImageValidationError,
    required this.isBusy,
    required this.autofocusTitle,
    required this.preferredCurrencySymbol,
    required this.onPickImage,
    required this.onClearImage,
    required this.validateTitle,
    required this.validatePrice,
  });

  final TextEditingController titleController;
  final TextEditingController notesController;
  final TextEditingController priceController;
  final String imageUrl;
  final bool showImageValidationError;
  final bool isBusy;
  final bool autofocusTitle;
  final String preferredCurrencySymbol;
  final VoidCallback onPickImage;
  final VoidCallback onClearImage;
  final String? Function(String?) validateTitle;
  final String? Function(String?) validatePrice;

  @override
  Widget build(BuildContext context) {
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
                    _TitleField(controller: titleController, autofocus: autofocusTitle, validator: validateTitle),
                    const SizedBox(height: AppConstants.itemGap),
                    _NotesField(controller: notesController),
                    const SizedBox(height: AppConstants.itemGap),
                    _PriceField(controller: priceController, currencySymbol: preferredCurrencySymbol, validator: validatePrice),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        _TitleField(controller: titleController, autofocus: autofocusTitle, validator: validateTitle),
                        const SizedBox(height: AppConstants.itemGap),
                        _PriceField(controller: priceController, currencySymbol: preferredCurrencySymbol, validator: validatePrice),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacing4),
                  Expanded(child: _NotesField(controller: notesController)),
                ],
              );
            },
          ),
          const SizedBox(height: AppConstants.itemGap),
          ItemImageSection(
            imageUrl: imageUrl,
            showValidationError: showImageValidationError,
            isBusy: isBusy,
            onPickImage: onPickImage,
            onClearImage: onClearImage,
          ),
        ],
      ),
    );
  }
}

class _TitleField extends StatelessWidget {
  const _TitleField({required this.controller, required this.autofocus, required this.validator});

  final TextEditingController controller;
  final bool autofocus;
  final String? Function(String?) validator;

  @override
  Widget build(BuildContext context) {
    return EditorFieldCard(
      child: TextFormField(
        controller: controller,
        autofocus: autofocus,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Item title',
          hintText: 'Stoneware bowl set',
          border: InputBorder.none,
        ),
        validator: validator,
      ),
    );
  }
}

class _NotesField extends StatelessWidget {
  const _NotesField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return EditorFieldCard(
      child: TextFormField(
        controller: controller,
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
}

class _PriceField extends StatelessWidget {
  const _PriceField({required this.controller, required this.currencySymbol, required this.validator});

  final TextEditingController controller;
  final String currencySymbol;
  final String? Function(String?) validator;

  @override
  Widget build(BuildContext context) {
    return EditorFieldCard(
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: 'Price',
          hintText: '${currencySymbol}120',
          border: InputBorder.none,
        ),
        validator: validator,
      ),
    );
  }
}
