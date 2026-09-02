import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest exposes single and multiple image share targets', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    expect(manifest, contains('android.intent.action.SEND"'));
    expect(manifest, contains('android.intent.action.SEND_MULTIPLE'));
    expect(manifest, contains('android:mimeType="image/*"'));
  });
}
