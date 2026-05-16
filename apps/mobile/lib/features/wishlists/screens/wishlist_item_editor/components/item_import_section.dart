import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/wishlists/shared/widgets/editor_field_card.dart';
import 'package:wishiz/features/wishlists/shared/widgets/editor_section_card.dart';

class ItemImportSection extends StatelessWidget {
  const ItemImportSection({
    super.key,
    required this.productUrlController,
    required this.hasSharedProductRepository,
    required this.isBusy,
    required this.isGeneratingFromLink,
    required this.validateProductUrl,
    required this.onApplyLinkDefaults,
    required this.onGenerateFromLink,
  });

  final TextEditingController productUrlController;
  final bool hasSharedProductRepository;
  final bool isBusy;
  final bool isGeneratingFromLink;
  final String? Function(String?) validateProductUrl;
  final VoidCallback onApplyLinkDefaults;
  final VoidCallback onGenerateFromLink;

  @override
  Widget build(BuildContext context) {
    return EditorSectionCard(
      title: 'Start from a product link',
      description:
          'Paste a store link to prefill the item. You can still change everything before saving.',
      child: Column(
        children: [
          EditorFieldCard(
            child: TextFormField(
              controller: productUrlController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              decoration: const InputDecoration(
                labelText: 'Product link',
                hintText: 'https://',
                border: InputBorder.none,
              ),
              validator: validateProductUrl,
              onEditingComplete: onApplyLinkDefaults,
            ),
          ),
          const SizedBox(height: AppConstants.spacing3),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: !hasSharedProductRepository || isBusy ? null : onGenerateFromLink,
              icon: Icon(
                isGeneratingFromLink
                    ? Icons.hourglass_top_outlined
                    : Icons.auto_fix_high_outlined,
              ),
              label: Text(
                isGeneratingFromLink ? 'Generating Details...' : 'Fill From Link',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
