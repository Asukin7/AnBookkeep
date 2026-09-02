import 'package:flutter/services.dart';

final class SharedImageSession {
  const SharedImageSession({
    required this.sessionId,
    required this.paths,
    required this.receivedAt,
    this.rejectedCount = 0,
    this.errorCode,
  });

  factory SharedImageSession.fromMap(Map<Object?, Object?> value) {
    final sessionId = value['sessionId'];
    final rawPaths = value['paths'];
    final receivedAt = value['receivedAt'];
    if (sessionId is! String || rawPaths is! List || receivedAt is! int) {
      throw const FormatException('无效的图片分享任务');
    }
    return SharedImageSession(
      sessionId: sessionId,
      paths: [
        for (final path in rawPaths)
          if (path is String) path,
      ],
      receivedAt: DateTime.fromMillisecondsSinceEpoch(receivedAt),
      rejectedCount: switch (value['rejectedCount']) {
        final int count => count,
        _ => 0,
      },
      errorCode: value['errorCode'] is String
          ? value['errorCode']! as String
          : null,
    );
  }

  final String sessionId;
  final List<String> paths;
  final DateTime receivedAt;
  final int rejectedCount;
  final String? errorCode;
}

final class SharedImageIntentBridge {
  SharedImageIntentBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.an.anbookkeep/shared_images';
  static const _consumeMethod = 'consumePendingShares';
  static const _availableMethod = 'sharedImagesAvailable';

  final MethodChannel _channel;

  void start(Future<void> Function() onAvailable) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == _availableMethod) await onAvailable();
    });
  }

  Future<List<SharedImageSession>> consumePending() async {
    final raw = await _channel.invokeMethod<List<Object?>>(_consumeMethod);
    if (raw == null) return const [];
    return [
      for (final item in raw)
        if (item is Map<Object?, Object?>) SharedImageSession.fromMap(item),
    ];
  }

  void dispose() => _channel.setMethodCallHandler(null);
}
