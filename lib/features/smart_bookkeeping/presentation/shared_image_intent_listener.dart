import 'dart:async';
import 'dart:collection';

import 'package:anbookkeep/app/router/app_router.dart';
import 'package:anbookkeep/core/logging/app_logger.dart';
import 'package:anbookkeep/features/bookkeeping/application/ledger_change_notifier.dart';
import 'package:anbookkeep/features/smart_bookkeeping/application/smart_bookkeeping_service.dart';
import 'package:anbookkeep/features/smart_bookkeeping/data/shared_image_intent_bridge.dart';
import 'package:anbookkeep/features/smart_bookkeeping/presentation/smart_bookkeeping_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

class SharedImageIntentListener extends ConsumerStatefulWidget {
  const SharedImageIntentListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SharedImageIntentListener> createState() =>
      _SharedImageIntentListenerState();
}

class _SharedImageIntentListenerState
    extends ConsumerState<SharedImageIntentListener> {
  final _bridge = SharedImageIntentBridge();
  final Queue<SharedImageSession> _queue = Queue();
  var _draining = false;
  var _drainRequested = false;
  var _handling = false;

  @override
  void initState() {
    super.initState();
    _bridge.start(_drain);
    SmartBookkeepingLauncher.busyListenable.addListener(_onBusyChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_drain()));
  }

  @override
  void dispose() {
    SmartBookkeepingLauncher.busyListenable.removeListener(_onBusyChanged);
    _bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  Future<void> _drain() async {
    if (!mounted) return;
    if (_draining) {
      _drainRequested = true;
      return;
    }
    _draining = true;
    try {
      final sessions = await _bridge.consumePending();
      for (final session in sessions) {
        await _enqueue(session);
      }
    } on MissingPluginException {
      // Non-Android test and preview environments do not provide the channel.
    } on Object catch (error, stackTrace) {
      _log.error('share_bridge_failed', cause: error, stackTrace: stackTrace);
    } finally {
      _draining = false;
      if (_drainRequested && mounted) {
        _drainRequested = false;
        unawaited(_drain());
      }
    }
  }

  Future<void> _enqueue(SharedImageSession session) async {
    _log.info(
      'share_intent_received',
      operationId: _operationId(session),
      fields: {
        'imageCount': session.paths.length,
        'rejectedCount': session.rejectedCount,
        'hasError': session.errorCode != null,
      },
    );
    if ((_handling || SmartBookkeepingLauncher.isBusy) && _queue.isNotEmpty) {
      await _deletePaths(session.paths);
      _showMessage('已有待处理的分享图片，请稍后重试');
      _log.warning(
        'share_session_rejected_while_busy',
        operationId: _operationId(session),
      );
      return;
    }
    _queue.add(session);
    if (_handling || SmartBookkeepingLauncher.isBusy) {
      _showMessage('已收到新的分享图片，将在当前任务结束后处理');
      return;
    }
    unawaited(_handleQueue());
  }

  Future<void> _handleQueue() async {
    if (_handling || SmartBookkeepingLauncher.isBusy) return;
    _handling = true;
    try {
      while (mounted && _queue.isNotEmpty) {
        final session = _queue.removeFirst();
        final context = await _navigationContext();
        if (context == null || !context.mounted) {
          await _deletePaths(session.paths);
          continue;
        }
        final message = _messageFor(session);
        if (session.paths.isEmpty) {
          _showMessage(message ?? '分享内容中没有可识别的图片');
          continue;
        }
        if (message != null) _showMessage(message);
        try {
          final saved = await SmartBookkeepingLauncher.shared(
            context,
            ref,
            paths: session.paths,
          );
          if (saved && mounted) {
            ref.read(ledgerChangeRevisionProvider.notifier).notifyChanged();
          }
          _log.info(
            'share_session_consumed',
            operationId: _operationId(session),
            fields: {'imageCount': session.paths.length, 'saved': saved},
          );
        } on Object catch (error, stackTrace) {
          await _deletePaths(session.paths);
          _log.error(
            'share_session_failed',
            operationId: _operationId(session),
            cause: error,
            stackTrace: stackTrace,
          );
          _showMessage('图片记账无法启动，请稍后重试');
        }
      }
    } finally {
      _handling = false;
    }
  }

  void _onBusyChanged() {
    if (!SmartBookkeepingLauncher.isBusy && !_handling && _queue.isNotEmpty) {
      unawaited(_handleQueue());
    }
  }

  Future<BuildContext?> _navigationContext() async {
    var context = rootNavigatorKey.currentContext;
    if (context != null) return context;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return null;
    context = rootNavigatorKey.currentContext;
    return context;
  }

  Future<void> _deletePaths(Iterable<String> paths) async {
    final service = ref.read(smartBookkeepingServiceProvider);
    await Future.wait([
      for (final path in paths) service.deleteTemporaryImage(path),
    ]);
  }

  void _showMessage(String message) {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static String? _messageFor(SharedImageSession session) {
    if (session.errorCode != null) {
      return switch (session.errorCode) {
        'too_many_images' => '一次最多处理20张图片，请减少图片后重新分享',
        'total_too_large' => '分享图片总大小超过200 MB，无法处理',
        'permission_denied' => '无法读取分享的图片，请重新分享',
        'read_failed' => '读取分享图片失败，请重新分享',
        'no_images' || 'no_valid_images' => '分享内容中没有可识别的图片',
        _ => '图片分享处理失败，请重新分享',
      };
    }
    if (session.rejectedCount > 0) {
      return '已跳过${session.rejectedCount}张无法读取或不支持的图片';
    }
    return null;
  }

  static String _operationId(SharedImageSession session) =>
      session.sessionId.length <= 8
      ? session.sessionId
      : session.sessionId.substring(0, 8);
}

const _log = AppLogger('SharedImageIntent');
