import 'package:anbookkeep/app/router/app_router.dart';
import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/core/errors/app_error_message.dart';
import 'package:anbookkeep/core/widgets/app_card.dart';
import 'package:anbookkeep/features/smart_bookkeeping/application/smart_bookkeeping_service.dart';
import 'package:anbookkeep/features/smart_bookkeeping/data/ai_config_repository.dart';
import 'package:anbookkeep/features/smart_bookkeeping/data/prompt_repository.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/ai_provider_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AiBookkeepingSettingsPage extends ConsumerStatefulWidget {
  const AiBookkeepingSettingsPage({super.key});

  @override
  ConsumerState<AiBookkeepingSettingsPage> createState() =>
      _AiBookkeepingSettingsPageState();
}

class _AiBookkeepingSettingsPageState
    extends ConsumerState<AiBookkeepingSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _visionModelController = TextEditingController();
  final _textModelController = TextEditingController();

  AiProviderConfig? _draft;
  bool _obscureApiKey = true;
  bool _saving = false;
  bool _testing = false;

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _visionModelController.dispose();
    _textModelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(aiConfigProvider);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          style: IconButton.styleFrom(backgroundColor: Colors.transparent),
        ),
        title: const Text('AI记账'),
      ),
      body: config.when(
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (error, stackTrace) => const Center(child: Text('AI设置加载失败')),
        data: (value) {
          _initializeDraft(value);
          return _buildForm(context);
        },
      ),
      bottomNavigationBar: _draft == null
          ? null
          : SafeArea(
              child: Padding(
                padding: AppSpacing.bottomActionPadding,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '保存中…' : '保存'),
                ),
              ),
            ),
    );
  }

  void _initializeDraft(AiProviderConfig value) {
    if (_draft != null) return;
    _draft = value;
    _baseUrlController.text = value.baseUrl;
    _apiKeyController.text = value.apiKey;
    _visionModelController.text = value.visionModel;
    _textModelController.text = value.textModel;
  }

  Widget _buildForm(BuildContext context) {
    final draft = _draft!;
    final prompt = ref.watch(promptLibraryProvider).active;
    return Form(
      key: _formKey,
      child: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          AppCard(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: AppSpacing.cardPadding,
                  title: const Text('启用在线AI'),
                  subtitle: const Text('关闭后仅使用本地OCR识别'),
                  value: draft.enabled,
                  onChanged: (value) =>
                      setState(() => _draft = draft.copyWith(enabled: value)),
                ),
                SwitchListTile(
                  contentPadding: AppSpacing.cardPadding,
                  title: const Text('允许向AI上传图片'),
                  subtitle: const Text('关闭后只向AI发送本地OCR文字'),
                  value: draft.allowImageUpload,
                  onChanged: draft.enabled
                      ? (value) => setState(
                          () => _draft = draft.copyWith(
                            allowImageUpload: value,
                            imageUploadConsent: value
                                ? draft.imageUploadConsent
                                : false,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.componentGap),
          TextFormField(
            controller: _baseUrlController,
            decoration: const InputDecoration(labelText: 'API地址'),
            keyboardType: TextInputType.url,
            autocorrect: false,
            validator: _validateBaseUrl,
          ),
          const SizedBox(height: AppSpacing.controlGap),
          TextFormField(
            controller: _apiKeyController,
            decoration: InputDecoration(
              labelText: 'API Key',
              suffixIcon: IconButton(
                tooltip: _obscureApiKey ? '显示' : '隐藏',
                onPressed: () =>
                    setState(() => _obscureApiKey = !_obscureApiKey),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                ),
                icon: Icon(
                  _obscureApiKey
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            obscureText: _obscureApiKey,
            autocorrect: false,
            enableSuggestions: false,
            validator: draft.enabled ? _required : null,
          ),
          const SizedBox(height: AppSpacing.controlGap),
          TextFormField(
            controller: _visionModelController,
            decoration: const InputDecoration(labelText: '视觉模型'),
            autocorrect: false,
            validator: draft.enabled && draft.allowImageUpload
                ? _required
                : null,
          ),
          const SizedBox(height: AppSpacing.controlGap),
          TextFormField(
            controller: _textModelController,
            decoration: const InputDecoration(labelText: '文本模型'),
            autocorrect: false,
            validator: draft.enabled && !draft.allowImageUpload
                ? _required
                : null,
          ),
          const SizedBox(height: AppSpacing.componentGap),
          AppCard(
            child: ListTile(
              contentPadding: AppSpacing.cardPadding,
              leading: const Icon(Icons.description_outlined),
              title: const Text('当前提示词'),
              subtitle: Text(prompt.name),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(AppRoutes.aiPrompts),
            ),
          ),
          const SizedBox(height: AppSpacing.controlGap),
          OutlinedButton.icon(
            onPressed: draft.enabled && !_testing ? _testConnection : null,
            icon: const Icon(Icons.network_check_rounded),
            label: Text(_testing ? '测试中…' : '测试连接'),
          ),
        ],
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '此项不能为空' : null;

  String? _validateBaseUrl(String? value) {
    final requiredError = _required(value);
    if (requiredError != null) return requiredError;
    final uri = Uri.tryParse(value!.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return '请输入有效的HTTPS地址';
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final value = _formValue();
    try {
      await ref.read(aiConfigProvider.notifier).save(value);
      if (!mounted) return;
      setState(() => _draft = value);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('AI记账设置已保存')));
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appErrorMessage(error, fallback: '设置保存失败，请重试')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  AiProviderConfig _formValue() => _draft!.copyWith(
    baseUrl: _baseUrlController.text,
    apiKey: _apiKeyController.text,
    visionModel: _visionModelController.text,
    textModel: _textModelController.text,
  );

  Future<void> _testConnection() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _testing = true);
    try {
      await ref.read(onlineAiClientProvider).testConnection(_formValue());
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('连接成功')));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appErrorMessage(error, fallback: '连接失败，请检查网络和配置')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }
}
