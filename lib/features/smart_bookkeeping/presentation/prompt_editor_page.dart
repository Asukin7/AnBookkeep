import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/core/widgets/app_bottom_sheet.dart';
import 'package:anbookkeep/features/smart_bookkeeping/data/prompt_repository.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/prompt_template.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PromptEditorPage extends ConsumerStatefulWidget {
  const PromptEditorPage({this.template, super.key});

  final PromptTemplate? template;

  @override
  ConsumerState<PromptEditorPage> createState() => _PromptEditorPageState();
}

class _PromptEditorPageState extends ConsumerState<PromptEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _contentController;
  bool _saving = false;

  bool get _isBuiltIn => widget.template?.isBuiltIn ?? false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.template?.name ?? '自定义提示词',
    );
    _contentController = TextEditingController(
      text: widget.template?.content ?? defaultPromptContent,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          style: IconButton.styleFrom(backgroundColor: Colors.transparent),
        ),
        title: Text(_isBuiltIn ? '查看提示词' : '编辑提示词'),
        actions: [
          IconButton(
            tooltip: '预览',
            onPressed: _preview,
            style: IconButton.styleFrom(backgroundColor: Colors.transparent),
            icon: const Icon(Icons.preview_outlined),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: AppSpacing.pagePadding,
          children: [
            TextFormField(
              controller: _nameController,
              readOnly: _isBuiltIn,
              maxLength: 40,
              decoration: const InputDecoration(labelText: '提示词名称'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入提示词名称' : null,
            ),
            const SizedBox(height: AppSpacing.controlGap),
            TextFormField(
              controller: _contentController,
              readOnly: _isBuiltIn,
              minLines: 14,
              maxLines: null,
              maxLength: 10000,
              decoration: const InputDecoration(
                labelText: '提示词内容',
                alignLabelWithHint: true,
              ),
              validator: _validateContent,
            ),
            const SizedBox(height: AppSpacing.controlGap),
            Text('可用变量', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.controlGap),
            Wrap(
              spacing: AppSpacing.controlGap,
              runSpacing: AppSpacing.controlGap,
              children: [
                for (final variable in promptVariables)
                  ActionChip(
                    label: Text('{{$variable}}'),
                    onPressed: _isBuiltIn
                        ? null
                        : () => _insertVariable(variable),
                  ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: AppSpacing.bottomActionPadding,
          child: _isBuiltIn
              ? FilledButton(
                  onPressed: _duplicateBuiltIn,
                  child: const Text('复制为自定义提示词'),
                )
              : FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '保存中…' : '保存'),
                ),
        ),
      ),
    );
  }

  String? _validateContent(String? value) {
    if (value == null || value.trim().isEmpty) return '请输入提示词内容';
    final unknown = unknownPromptVariables(value);
    if (unknown.isNotEmpty) return '存在未知变量：${unknown.join('、')}';
    return null;
  }

  void _insertVariable(String variable) {
    final selection = _contentController.selection;
    final offset = selection.isValid
        ? selection.start
        : _contentController.text.length;
    final token = '{{$variable}}';
    _contentController.text = _contentController.text.replaceRange(
      offset,
      selection.isValid ? selection.end : offset,
      token,
    );
    _contentController.selection = TextSelection.collapsed(
      offset: offset + token.length,
    );
  }

  Future<void> _preview() async {
    final rendered = renderPromptTemplate(
      _contentController.text,
      values: const {
        'CURRENT_TIME': '2026-08-31 18:30',
        'OCR_TEXT': '微信支付\n支付成功 ￥28.50\n安安咖啡店',
        'EXPENSE_CATEGORIES': 'expense-food | 餐饮、expense-other | 其他',
        'INCOME_CATEGORIES': 'income-salary | 工资、income-other | 其他',
        'INPUT_SOURCE': '相册图片',
      },
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => AppBottomSheetLayout(
        title: '提示词预览',
        expandContent: true,
        child: SingleChildScrollView(child: SelectableText(rendered)),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final notifier = ref.read(promptLibraryProvider.notifier);
    if (widget.template == null) {
      await notifier.create(
        name: _nameController.text,
        content: _contentController.text,
      );
    } else {
      await notifier.update(
        widget.template!.copyWith(
          name: _nameController.text.trim(),
          content: _contentController.text,
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _duplicateBuiltIn() async {
    await ref.read(promptLibraryProvider.notifier).duplicate(widget.template!);
    if (mounted) Navigator.pop(context);
  }
}
