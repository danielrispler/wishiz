import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/shared/widgets/wishiz_app_bar.dart';

class EditorPageLayout extends StatelessWidget {
  const EditorPageLayout({
    super.key,
    required this.title,
    required this.children,
    this.footer,
  });

  final String title;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: WishizAppBar(titleText: title),
      body: Stack(
        children: [
          Positioned(
            top: -120,
            right: -40,
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      colorScheme.primary.withValues(alpha: 0.14),
                      colorScheme.primary.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      AppConstants.pagePadding,
                      AppConstants.pagePadding,
                      AppConstants.pagePadding,
                      footer == null
                          ? AppConstants.spacing8
                          : AppConstants.spacing5,
                    ),
                    children: [
                      for (final child in children)
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: child,
                          ),
                        ),
                    ],
                  ),
                ),
                if (footer != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppConstants.pagePadding,
                      0,
                      AppConstants.pagePadding,
                      AppConstants.pagePadding,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: footer,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
