import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/shared/widgets/wishiz_wordmark.dart';

class WishizAppBar extends StatelessWidget implements PreferredSizeWidget {
  const WishizAppBar({
    super.key,
    this.titleText,
    this.useWordmark = false,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.centerTitle = false,
  });

  final String? titleText;
  final bool useWordmark;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final bool centerTitle;

  @override
  Size get preferredSize => const Size.fromHeight(64.0);

  @override
  Widget build(BuildContext context) {
    final ModalRoute<dynamic>? parentRoute = ModalRoute.of(context);
    final bool canPop = parentRoute?.canPop ?? false;
    final bool showLeading = leading != null || (automaticallyImplyLeading && canPop);
    final theme = Theme.of(context);

    return Container(
      color: theme.colorScheme.surface,
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
      ),
      child: Container(
        height: preferredSize.height,
        padding: const EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (showLeading) ...[
              leading ??
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                    color: theme.colorScheme.onSurface,
                  ),
              const SizedBox(width: AppConstants.spacing2),
            ],
            Expanded(
              child: useWordmark
                  ? Transform.translate(
                      offset: const Offset(-8, 0),
                      child: const WishizWordmark(height: 44),
                    )
                  : (titleText != null
                      ? Text(
                          titleText!,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                          textAlign: centerTitle ? TextAlign.center : TextAlign.start,
                          overflow: TextOverflow.ellipsis,
                        )
                      : const SizedBox.shrink()),
            ),
            if (actions != null) ...actions!,
          ],
        ),
      ),
    );
  }
}
