import 'package:anbookkeep/app/router/app_router.dart';
import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/core/widgets/app_card.dart';
import 'package:anbookkeep/core/widgets/app_dialog.dart';
import 'package:anbookkeep/features/smart_bookkeeping/data/prompt_repository.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/prompt_template.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class PromptManagementPage extends ConsumerWidget {
  const PromptManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(promptLibraryProvider);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          style: IconButton.styleFrom(backgroundColor: Colors.transparent),
        ),
        title: const Text('提示词管理'),
        actions: [
          IconButton(
            tooltip: '恢复默认提示词',
            onPressed: library.activeId == defaultPromptId
                ? null
                : () => ref
                      .read(promptLibraryProvider.notifier)
                      .setActive(defaultPromptId),
            style: IconButton.styleFrom(backgroundColor: Colors.transparent),
            icon: const Icon(Icons.restore_rounded),
          ),
        ],
      ),
      body: ListView.separated(
        padding: AppSpacing.pagePadding,
        itemCount: library.templates.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: AppSpacing.controlGap),
        itemBuilder: (context, index) {
          final template = library.templates[index];
          final active = template.id == library.activeId;
          return AppCard(
            child: ListTile(
              contentPadding: AppSpacing.cardPadding,
              onTap: () => ref
                  .read(promptLibraryProvider.notifier)
                  .setActive(template.id),
              leading: Icon(
                active ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: active ? Theme.of(context).colorScheme.primary : null,
              ),
              title: Text(template.name),
              subtitle: Text(template.isBuiltIn ? '内置提示词' : '自定义提示词'),
              trailing: PopupMenuButton<_PromptAction>(
                icon: const Icon(Icons.more_horiz_rounded),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _PromptAction.edit,
                    child: Text('查看或编辑'),
                  ),
                  const PopupMenuItem(
                    value: _PromptAction.duplicate,
                    child: Text('复制'),
                  ),
                  if (!template.isBuiltIn)
                    const PopupMenuItem(
                      value: _PromptAction.delete,
                      child: Text('删除'),
                    ),
                ],
                onSelected: (action) =>
                    _handleAction(context, ref, template, action),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: AppSpacing.bottomActionPadding,
          child: FilledButton.icon(
            onPressed: () => context.push(AppRoutes.aiPromptEditor),
            icon: const Icon(Icons.add_rounded),
            label: const Text('新增提示词'),
          ),
        ),
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    PromptTemplate template,
    _PromptAction action,
  ) async {
    switch (action) {
      case _PromptAction.edit:
        await context.push(AppRoutes.aiPromptEditor, extra: template);
      case _PromptAction.duplicate:
        final copy = await ref
            .read(promptLibraryProvider.notifier)
            .duplicate(template);
        if (context.mounted) {
          await context.push(AppRoutes.aiPromptEditor, extra: copy);
        }
      case _PromptAction.delete:
        final confirmed = await showAppConfirmDialog(
          context,
          title: '删除提示词',
          message: '确定删除“${template.name}”吗？',
          confirmLabel: '删除',
        );
        if (confirmed) {
          await ref.read(promptLibraryProvider.notifier).delete(template.id);
        }
    }
  }
}

enum _PromptAction { edit, duplicate, delete }
