import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class AppBottomSheetLayout extends StatelessWidget {
  const AppBottomSheetLayout({
    required this.title,
    required this.child,
    this.actions,
    this.expandContent = false,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? actions;
  final bool expandContent;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: AppSpacing.sheetPadding,
        child: Column(
          mainAxisSize: expandContent ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.componentGap),
            if (expandContent) Expanded(child: child) else child,
            if (actions != null) ...[
              const SizedBox(height: AppSpacing.componentGap),
              actions!,
            ],
          ],
        ),
      ),
    );
  }
}
