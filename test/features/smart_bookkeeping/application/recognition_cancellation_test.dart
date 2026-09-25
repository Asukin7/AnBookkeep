import 'package:anbookkeep/features/smart_bookkeeping/application/recognition_cancellation.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/recognition_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cancels both cooperative stages and the network request', () {
    final cancellation = RecognitionCancellation();

    cancellation.cancel('test');

    expect(cancellation.isCancelled, isTrue);
    expect(cancellation.reason, 'test');
    expect(cancellation.networkToken.isCancelled, isTrue);
    expect(
      cancellation.throwIfCancelled,
      throwsA(
        isA<SmartRecognitionException>().having(
          (error) => error.message,
          'message',
          '识别已取消',
        ),
      ),
    );
  });

  test('keeps the first cancellation reason', () {
    final cancellation = RecognitionCancellation()
      ..cancel('first')
      ..cancel('second');

    expect(cancellation.reason, 'first');
  });
}
