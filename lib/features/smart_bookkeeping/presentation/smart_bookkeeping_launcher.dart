import 'package:anbookkeep/app/router/app_router.dart';
import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/core/errors/app_error_message.dart';
import 'package:anbookkeep/core/logging/app_logger.dart';
import 'package:anbookkeep/core/widgets/app_dialog.dart';
import 'package:anbookkeep/features/smart_bookkeeping/application/smart_bookkeeping_service.dart';
import 'package:anbookkeep/features/smart_bookkeeping/data/ai_config_repository.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/recognition_result.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/smart_bookkeeping_draft.dart';
import 'package:anbookkeep/features/smart_bookkeeping/presentation/batch_recognition_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

abstract final class SmartBookkeepingLauncher {
  static final ValueNotifier<bool> busyListenable = ValueNotifier(false);

  static bool get isBusy => busyListenable.value;

  static Future<void> camera(BuildContext context, WidgetRef ref) async {
    if (!_begin(context)) return;
    try {
      await _camera(context, ref);
    } finally {
      _end();
    }
  }

  static Future<void> _camera(BuildContext context, WidgetRef ref) async {
    _log.info('camera_picker_opened');
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.camera,
        requestFullMetadata: false,
      );
      if (image == null || !context.mounted) {
        _log.info('camera_picker_cancelled');
        return;
      }
      _log.info('camera_image_selected');
      if (!await _confirmUpload(context, ref, imageCount: 1)) {
        _log.info('camera_recognition_cancelled_before_start');
        return;
      }
      if (!context.mounted) return;
      await _recognizeSingle(
        context,
        ref,
        path: image.path,
        source: SmartBookkeepingSource.camera,
      );
    } on PlatformException catch (error) {
      _log.error(
        'camera_picker_failed',
        cause: error,
        fields: {'code': error.code},
      );
      if (context.mounted) _showPickerError(context, error);
    } on Object catch (error, stackTrace) {
      _log.error('camera_launch_failed', cause: error, stackTrace: stackTrace);
      if (context.mounted) {
        _showError(context, appErrorMessage(error, fallback: '拍照记账无法启动，请稍后重试'));
      }
    }
  }

  static Future<void> gallery(BuildContext context, WidgetRef ref) async {
    if (!_begin(context)) return;
    try {
      await _gallery(context, ref);
    } finally {
      _end();
    }
  }

  static Future<void> _gallery(BuildContext context, WidgetRef ref) async {
    _log.info('gallery_picker_opened');
    try {
      final images = await ImagePicker().pickMultiImage(
        limit: 20,
        requestFullMetadata: false,
      );
      if (images.isEmpty || !context.mounted) {
        _log.info('gallery_picker_cancelled');
        return;
      }
      _log.info(
        'gallery_images_selected',
        fields: {'imageCount': images.length},
      );
      await _recognizePaths(
        context,
        ref,
        paths: [for (final image in images) image.path],
        source: SmartBookkeepingSource.gallery,
      );
    } on PlatformException catch (error) {
      _log.error(
        'gallery_picker_failed',
        cause: error,
        fields: {'code': error.code},
      );
      if (context.mounted) _showPickerError(context, error);
    } on Object catch (error, stackTrace) {
      _log.error('gallery_launch_failed', cause: error, stackTrace: stackTrace);
      if (context.mounted) {
        _showError(context, appErrorMessage(error, fallback: '图片记账无法启动，请稍后重试'));
      }
    }
  }

  static Future<bool> shared(
    BuildContext context,
    WidgetRef ref, {
    required List<String> paths,
  }) async {
    if (!_begin(context)) {
      final service = ref.read(smartBookkeepingServiceProvider);
      await Future.wait([
        for (final path in paths) service.deleteTemporaryImage(path),
      ]);
      return false;
    }
    _log.info('shared_images_received', fields: {'imageCount': paths.length});
    try {
      return await _recognizePaths(
        context,
        ref,
        paths: paths,
        source: SmartBookkeepingSource.share,
      );
    } finally {
      _end();
    }
  }

  static bool _begin(BuildContext context) {
    if (busyListenable.value) {
      _showError(context, '正在处理图片记账，请稍候');
      return false;
    }
    busyListenable.value = true;
    return true;
  }

  static void _end() => busyListenable.value = false;

  static Future<bool> _recognizePaths(
    BuildContext context,
    WidgetRef ref, {
    required List<String> paths,
    required SmartBookkeepingSource source,
  }) async {
    if (paths.isEmpty) return false;
    try {
      if (!await _confirmUpload(context, ref, imageCount: paths.length)) {
        _log.info(
          '${source.name}_recognition_cancelled_before_start',
          fields: {'imageCount': paths.length},
        );
        return false;
      }
      if (!context.mounted) return false;
      if (paths.length == 1) {
        return await _recognizeSingle(
          context,
          ref,
          path: paths.single,
          source: source,
        );
      } else {
        return await context.push<bool>(
              AppRoutes.batchRecognition,
              extra: BatchRecognitionArgs(paths: paths, source: source),
            ) ??
            false;
      }
    } finally {
      if (source == SmartBookkeepingSource.share) {
        final service = ref.read(smartBookkeepingServiceProvider);
        await Future.wait([
          for (final path in paths) service.deleteTemporaryImage(path),
        ]);
      }
    }
  }

  static Future<bool> _confirmUpload(
    BuildContext context,
    WidgetRef ref, {
    required int imageCount,
  }) async {
    final config = await ref.read(aiConfigProvider.future);
    if (!config.enabled || !config.allowImageUpload) {
      _log.info(
        'image_upload_confirmation_skipped',
        fields: {
          'aiEnabled': config.enabled,
          'allowImageUpload': config.allowImageUpload,
        },
      );
      return true;
    }
    if (!context.mounted) return false;
    if (!config.imageUploadConsent) {
      final confirmed = await showAppConfirmDialog(
        context,
        title: '允许上传账单图片',
        message: '识别时会将压缩后的账单图片发送给已配置的在线AI服务。图片可能包含交易和商户信息，并可能产生接口费用。是否继续？',
        confirmLabel: '允许并继续',
      );
      if (!confirmed) {
        _log.info('image_upload_consent_declined');
        return false;
      }
      await ref.read(aiConfigProvider.notifier).setImageUploadConsent(true);
      _log.info('image_upload_consent_granted');
    }
    if (imageCount <= 1 || !context.mounted) return true;
    return showAppConfirmDialog(
      context,
      title: '批量AI识别',
      message: '将向已配置的在线AI服务发送$imageCount张压缩图片，可能产生多次接口费用。',
      confirmLabel: '开始识别',
    );
  }

  static Future<bool> _recognizeSingle(
    BuildContext context,
    WidgetRef ref, {
    required String path,
    required SmartBookkeepingSource source,
  }) async {
    final draft = await showDialog<SmartBookkeepingDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _SingleRecognitionDialog(path: path, source: source),
    );
    if (draft == null || !context.mounted) {
      _log.info(
        'single_recognition_dialog_closed_without_result',
        fields: {'source': source.name},
      );
      return false;
    }
    _log.info(
      'single_recognition_opened_for_review',
      operationId: draft.id.substring(0, 8),
      fields: {'status': draft.status.name, 'usedOnlineAi': draft.usedOnlineAi},
    );
    try {
      return await context.push<bool>(
            AppRoutes.bookkeeping,
            extra: BookkeepingDraftPageArgs(draft: draft),
          ) ??
          false;
    } finally {
      await ref
          .read(smartBookkeepingServiceProvider)
          .deleteTemporaryImage(draft.imagePath);
    }
  }

  static void _showPickerError(BuildContext context, PlatformException error) {
    final denied =
        error.code.toLowerCase().contains('denied') ||
        error.code.toLowerCase().contains('access');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          denied
              ? '没有相机或相册访问权限，请在系统设置中允许'
              : '无法打开图片：${error.message ?? error.code}',
        ),
      ),
    );
  }

  static void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

const _log = AppLogger('SmartBookkeeping');

class _SingleRecognitionDialog extends ConsumerStatefulWidget {
  const _SingleRecognitionDialog({required this.path, required this.source});

  final String path;
  final SmartBookkeepingSource source;

  @override
  ConsumerState<_SingleRecognitionDialog> createState() =>
      _SingleRecognitionDialogState();
}

class _SingleRecognitionDialogState
    extends ConsumerState<_SingleRecognitionDialog> {
  final _cancelToken = CancelToken();
  String? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_recognize);
  }

  @override
  void dispose() {
    _cancelToken.cancel('弹窗关闭');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('识别账单'),
      content: _error == null
          ? const Row(
              children: [
                CircularProgressIndicator.adaptive(),
                SizedBox(width: AppSpacing.componentGap),
                Expanded(child: Text('正在识别账单，请稍候…')),
              ],
            )
          : Text(_error!),
      actions: [
        if (_error == null)
          OutlinedButton(
            onPressed: () {
              _cancelToken.cancel('用户取消');
              Navigator.pop(context);
            },
            child: const Text('取消'),
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ),
              const SizedBox(width: AppSpacing.componentGap),
              Expanded(
                child: FilledButton(
                  onPressed: _recognize,
                  child: const Text('重试'),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _recognize() async {
    if (mounted) setState(() => _error = null);
    try {
      final draft = await ref
          .read(smartBookkeepingServiceProvider)
          .recognize(
            sourcePath: widget.path,
            source: widget.source,
            cancelToken: _cancelToken,
          );
      if (mounted) Navigator.pop(context, draft);
    } on SmartRecognitionException catch (error) {
      if (mounted && error.message != '识别已取消') {
        setState(() => _error = error.message);
      }
    }
  }
}
