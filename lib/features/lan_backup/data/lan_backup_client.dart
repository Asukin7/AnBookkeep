import 'dart:io';

import 'package:flutter/services.dart';

final class LanBackupClient {
  const LanBackupClient();

  static const _channel = MethodChannel('com.an.anbookkeep/lan_backup');

  Future<void> prepare(
    ({String fingerprint, String encodedKey}) key, {
    ({InternetAddress address, int port})? directEndpoint,
    required bool requireLan,
  }) => _channel.invokeMethod<void>('prepare', {
    'key': key.encodedKey,
    'fingerprint': key.fingerprint,
    if (requireLan) 'requireLan': true,
    if (directEndpoint != null) ...{
      'address': directEndpoint.address.rawAddress,
      'port': directEndpoint.port,
    },
  });

  Future<void> upload({required String path, required String name}) =>
      _channel.invokeMethod<void>('upload', {'path': path, 'name': name});

  Future<void> cancel() => _channel.invokeMethod<void>('cancel');
}
