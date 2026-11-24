import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/app/theme/app_tokens.dart';
import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/errors/app_error_message.dart';
import 'package:anbookkeep/core/widgets/app_card.dart';
import 'package:anbookkeep/core/widgets/app_dialog.dart';
import 'package:anbookkeep/core/widgets/app_color_picker.dart';
import 'package:anbookkeep/core/widgets/app_segmented_control.dart';
import 'package:anbookkeep/core/widgets/category_icon.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CategoryEditorArgs {
  const CategoryEditorArgs({required this.type, this.category});

  final EntryType type;
  final CategoryRow? category;
}

class CategoryEditorPage extends ConsumerStatefulWidget {
  const CategoryEditorPage({required this.args, super.key});

  final CategoryEditorArgs args;

  @override
  ConsumerState<CategoryEditorPage> createState() => _CategoryEditorPageState();
}

class _CategoryEditorPageState extends ConsumerState<CategoryEditorPage>
    with SingleTickerProviderStateMixin {
  late final _nameController = TextEditingController(
    text: widget.args.category?.name ?? '',
  );
  late String _iconCode =
      widget.args.category?.iconCode ?? categoryIconCodes.first;
  late Color _color = widget.args.category == null
      ? randomVividAppColor()
      : Color(widget.args.category!.colorValue);
  late CategoryIconGroup _iconGroup;
  late final TabController _iconGroupController;
  bool _isSaving = false;
  bool _isUsed = false;
  bool _loadingUsage = false;

  bool get _isEditing => widget.args.category != null;

  @override
  void initState() {
    super.initState();
    _iconGroup =
        categoryIconOptionForCode(_iconCode)?.group ??
        CategoryIconGroup.values.first;
    _iconGroupController = TabController(
      length: CategoryIconGroup.values.length,
      initialIndex: CategoryIconGroup.values.indexOf(_iconGroup),
      vsync: this,
    );
    if (_isEditing) _loadUsage();
  }

  @override
  void dispose() {
    _iconGroupController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadUsage() async {
    setState(() => _loadingUsage = true);
    try {
      _isUsed = await ref
          .read(bookkeepingRepositoryProvider)
          .isCategoryUsed(widget.args.category!.id);
    } on Object {
      // Be conservative when usage cannot be determined.
      _isUsed = true;
    } finally {
      if (mounted) setState(() => _loadingUsage = false);
    }
  }

  Future<void> _selectColor() async {
    final value = await showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      builder: (context) => AppColorPickerSheet(title: '分类颜色', current: _color),
    );
    if (value != null && mounted) setState(() => _color = value);
  }

  Future<void> _delete() async {
    if (widget.args.category == null) return;
    if (_loadingUsage) {
      _showMessage('正在检查分类使用情况，请稍后');
      return;
    }
    if (_isUsed) {
      _showMessage('该分类已被账单使用，不能删除');
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context,
      title: '删除分类',
      message: '确定删除“${widget.args.category!.name}”吗？',
      confirmLabel: '删除',
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(bookkeepingRepositoryProvider)
          .deleteCategory(widget.args.category!.id);
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) {
        _showMessage(appErrorMessage(error, fallback: '删除分类失败，请重试'));
      }
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('请输入分类名称');
      return;
    }
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final repository = ref.read(bookkeepingRepositoryProvider);
      final category = widget.args.category;
      if (category == null) {
        await repository.createCategory(
          type: widget.args.type,
          name: name,
          iconCode: _iconCode,
          colorValue: _color.toARGB32(),
        );
      } else {
        await repository.updateCategory(
          id: category.id,
          name: name,
          iconCode: _iconCode,
          colorValue: _color.toARGB32(),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showMessage(appErrorMessage(error, fallback: '保存分类失败，请重试'));
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEditing ? '编辑分类' : '新增分类';
    final iconOptions = categoryIconOptionsForGroup(_iconGroup);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          style: IconButton.styleFrom(backgroundColor: Colors.transparent),
        ),
        title: Text(title),
        actions: [
          if (_isEditing)
            IconButton(
              key: const ValueKey('category-delete-button'),
              tooltip: '删除分类',
              onPressed: _delete,
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          AppCard(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameController,
                    maxLength: 32,
                    autofocus: !_isEditing,
                    decoration: const InputDecoration(labelText: '分类名称'),
                  ),
                  const SizedBox(height: AppSpacing.controlGap),
                  Text('分类图标', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.controlGap),
                  AppSegmentedSurface(
                    child: TabBar(
                      controller: _iconGroupController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      indicatorPadding: const EdgeInsets.all(
                        AppSpacing.tabIndicatorInset,
                      ),
                      tabs: [
                        for (final group in CategoryIconGroup.values)
                          Tab(text: group.label),
                      ],
                      onTap: (index) {
                        setState(() {
                          _iconGroup = CategoryIconGroup.values[index];
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.controlGap),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: iconOptions.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          mainAxisSpacing: AppSpacing.controlGap,
                          crossAxisSpacing: AppSpacing.controlGap,
                          childAspectRatio: 1,
                        ),
                    itemBuilder: (context, index) {
                      final code = iconOptions[index].code;
                      return InkWell(
                        onTap: () => setState(() => _iconCode = code),
                        customBorder: const CircleBorder(),
                        child: CategoryIcon(
                          code: code,
                          color: _color,
                          size: AppSizes.categoryIconLarge,
                          selected: code == _iconCode,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.componentGap),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: AppSizes.settingIcon,
                      height: AppSizes.settingIcon,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _color,
                      ),
                    ),
                    title: const Text('分类颜色'),
                    subtitle: Text(appColorHex(_color)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _selectColor,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: AppSpacing.bottomActionPadding,
        child: FilledButton(
          onPressed: _isSaving ? null : _save,
          child: Text(_isSaving ? '保存中…' : '保存'),
        ),
      ),
    );
  }
}
