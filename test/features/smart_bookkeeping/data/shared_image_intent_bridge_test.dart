import 'package:anbookkeep/features/smart_bookkeeping/data/shared_image_intent_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/shared_images');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('decodes pending shared image sessions from the platform', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'consumePendingShares');
          return [
            {
              'sessionId': 'session-1',
              'paths': ['C:/cache/one.img', 'C:/cache/two.img'],
              'receivedAt': 1788336000000,
              'rejectedCount': 1,
            },
          ];
        });

    final sessions = await SharedImageIntentBridge(channel: channel)
        .consumePending();

    expect(sessions, hasLength(1));
    expect(sessions.single.sessionId, 'session-1');
    expect(sessions.single.paths, hasLength(2));
    expect(sessions.single.rejectedCount, 1);
    expect(sessions.single.errorCode, isNull);
  });

  test('preserves a native validation error without image paths', () {
    final session = SharedImageSession.fromMap({
      'sessionId': 'session-2',
      'paths': <String>[],
      'receivedAt': 1788336000000,
      'rejectedCount': 21,
      'errorCode': 'too_many_images',
    });

    expect(session.paths, isEmpty);
    expect(session.rejectedCount, 21);
    expect(session.errorCode, 'too_many_images');
  });

  test('rejects malformed native payloads', () {
    expect(
      () => SharedImageSession.fromMap({
        'sessionId': 'session-3',
        'paths': 'not-a-list',
        'receivedAt': 1788336000000,
      }),
      throwsFormatException,
    );
  });
}
