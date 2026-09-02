import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class AppDialogActions extends StatelessWidget {
  const AppDialogActions({
    required this.onCancel,
    required this.onConfirm,
    this.cancelLabel = '取消',
    this.confirmLabel = '确认',
    super.key,
  });

  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;
  final String cancelLabel;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(onPressed: onCancel, child: Text(cancelLabel)),
        ),
        const SizedBox(width: AppSpacing.componentGap),
        Expanded(
          child: FilledButton(onPressed: onConfirm, child: Text(confirmLabel)),
        ),
      ],
    );
  }
}

Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确认',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      titlePadding: AppSpacing.dialogTitlePadding,
      contentPadding: AppSpacing.dialogContentPadding,
      actionsPadding: AppSpacing.dialogActionsPadding,
      title: Text(title),
      content: Text(message),
      actions: [
        AppDialogActions(
          onCancel: () => Navigator.pop(dialogContext, false),
          onConfirm: () => Navigator.pop(dialogContext, true),
          confirmLabel: confirmLabel,
        ),
      ],
    ),
  );
  return result == true;
}
