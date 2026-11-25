import 'dart:async';

import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/core/errors/app_error_message.dart';
import 'package:anbookkeep/core/logging/app_logger.dart';
import 'package:anbookkeep/core/widgets/app_card.dart';
import 'package:anbookkeep/features/lan_backup/application/lan_backup_coordinator.dart';
import 'package:anbookkeep/features/lan_backup/domain/lan_backup_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LanBackupPage extends ConsumerStatefulWidget {
  const LanBackupPage({super.key});

  @override
  ConsumerState<LanBackupPage> createState() => _LanBackupPageState();
}

class _LanBackupPageState extends ConsumerState<LanBackupPage> {
  static const _log = AppLogger('LanBackupSettings');
  final _key = TextEditingController();
  final _fileName = TextEditingController();
  final _directAddress = TextEditingController();
  late final LanBackupCoordinator _coordinator;
  Timer? _autoSave;
  Timer? _clearFeedback;
  bool _ready = false;
  bool _enabled = false;
  bool _busy = false;
  bool _obscureKey = true;
  String? _feedback;
  String? _loadError;

  bool get _nameValid => LanBackupSettings.validName(_fileName.text);

  LanBackupSettings get _draft => LanBackupSettings(
    enabled: _enabled,
    key: _key.text.trim(),
    fileName: _nameValid ? _fileName.text : '',
    directAddress: _directAddress.text.trim(),
  );

  @override
  void initState() {
    super.initState();
    _coordinator = ref.read(lanBackupCoordinatorProvider);
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final settings = await _coordinator.settings();
      if (!mounted) return;
      _key.text = settings.key;
      _fileName.text = settings.fileName;
      _directAddress.text = settings.directAddress;
      setState(() {
        _enabled = settings.enabled;
        _ready = true;
      });
    } on Object catch (error) {
      _log.error('lan_backup_settings_load_failed', cause: error);
      if (mounted) setState(() => _loadError = '无法读取备份设置');
    }
  }

  void _changed(String _) {
    setState(() => _feedback = null);
    _autoSave?.cancel();
    _autoSave = Timer(const Duration(milliseconds: 400), _saveDraft);
  }

  void _saveDraft() {
    _autoSave?.cancel();
    _autoSave = null;
    if (_ready) unawaited(_save(_draft));
  }

  Future<void> _save(LanBackupSettings settings) async {
    try {
      await _coordinator.updateSettings(settings);
    } on Object catch (error) {
      _log.error('lan_backup_settings_save_failed', cause: error);
      _showFeedback('设置保存失败');
    }
  }

  Future<void> _backupNow() async {
    _autoSave?.cancel();
    _autoSave = null;
    _clearFeedback?.cancel();
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      await _coordinator.updateSettings(_draft);
      await _coordinator.backupNow();
      _showFeedback('备份成功');
    } on Object catch (error) {
      _showFeedback(_backupError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showFeedback(String value) {
    if (!mounted) return;
    _clearFeedback?.cancel();
    setState(() => _feedback = value);
    _clearFeedback = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  String _backupError(Object error) {
    if (error is! PlatformException) {
      return appErrorMessage(error, fallback: '备份失败，请稍后再试');
    }
    return switch (error.code) {
      'receiver_unavailable' => '未找到备份电脑，请检查局域网连接',
      'receiver_address_unavailable' => '已发现电脑，但未能获取地址',
      'receiver_unreachable' => '无法连接备份电脑，请检查 IP 和端口',
      'invalid_direct_address' => '直连地址格式无效',
      'discovery_failed' => '无法搜索局域网备份电脑',
      'invalid_backup_key' => 'Key 验证失败，请复制电脑端显示的 Key',
      'receiver_identity_mismatch' => '电脑身份与 Key 不匹配，请检查地址或重新复制 Key',
      'network_permission_denied' => '无法访问局域网',
      'connection_lost' => '连接中断，请重试',
      'receiver_busy' => '电脑端正忙，请稍后再试',
      'backup_in_progress' => '已有备份正在执行',
      'insufficient_space' => '电脑备份目录空间不足',
      'atomic_replace_unavailable' => '电脑备份目录无法安全替换文件',
      'write_failed' => '电脑写入失败，请检查目录或文件占用',
      'cancelled' => '备份已取消',
      _ => '备份失败，请稍后再试',
    };
  }

  @override
  void dispose() {
    if (_autoSave?.isActive == true && _ready) {
      unawaited(
        _coordinator.updateSettings(_draft).catchError((Object error) {
          _log.error('lan_backup_settings_save_failed', cause: error);
        }),
      );
    }
    _autoSave?.cancel();
    _clearFeedback?.cancel();
    _key.dispose();
    _fileName.dispose();
    _directAddress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          style: IconButton.styleFrom(backgroundColor: Colors.transparent),
        ),
        title: const Text('局域网备份'),
      ),
      body: _ready
          ? ListView(
              padding: AppSpacing.pagePadding,
              children: [
                AppCard(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('开启备份'),
                        value: _enabled,
                        onChanged: (enabled) {
                          setState(() => _enabled = enabled);
                          _saveDraft();
                        },
                      ),
                      Padding(
                        padding: AppSpacing.cardPadding,
                        child: Column(
                          children: [
                            TextField(
                              controller: _key,
                              obscureText: _obscureKey,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: InputDecoration(
                                labelText: 'Key',
                                errorText:
                                    draft.key.isNotEmpty &&
                                        draft.connectionKey == null
                                    ? '请复制电脑端显示的完整 Key'
                                    : null,
                                suffixIcon: IconButton(
                                  tooltip: _obscureKey ? '显示 Key' : '隐藏 Key',
                                  onPressed: () => setState(
                                    () => _obscureKey = !_obscureKey,
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                  ),
                                  icon: Icon(
                                    _obscureKey
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              onChanged: _changed,
                              onSubmitted: (_) => _saveDraft(),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextField(
                              controller: _fileName,
                              autocorrect: false,
                              decoration: InputDecoration(
                                labelText: '备份文件名',
                                suffixIcon: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  child: Center(
                                    widthFactor: 1,
                                    child: Text('.xlsx'),
                                  ),
                                ),
                                errorText:
                                    _fileName.text.isNotEmpty && !_nameValid
                                    ? '请输入有效的文件名主体'
                                    : null,
                              ),
                              onChanged: _changed,
                              onSubmitted: (_) => _saveDraft(),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextField(
                              controller: _directAddress,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: InputDecoration(
                                labelText: '直连地址（选填）',
                                hintText: '192.168.1.10:18765',
                                helperText: '留空时自动搜索电脑',
                                errorText:
                                    draft.directAddress.isNotEmpty &&
                                        draft.directEndpoint == null
                                    ? '请输入有效的 IP 地址和端口'
                                    : null,
                              ),
                              onChanged: _changed,
                              onSubmitted: (_) => _saveDraft(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Center(
              child: _loadError == null
                  ? const CircularProgressIndicator()
                  : Text(_loadError!),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: AppSpacing.bottomActionPadding,
          child: FilledButton(
            onPressed: _ready && !_busy && draft.canBackUp ? _backupNow : null,
            child: Text(_busy ? '备份中…' : _feedback ?? '立即备份'),
          ),
        ),
      ),
    );
  }
}
