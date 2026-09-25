import 'package:anbookkeep/features/smart_bookkeeping/domain/recognition_result.dart';
import 'package:dio/dio.dart';

/// A cancellation signal shared by preprocessing, local OCR and online AI.
///
/// PaddleOCR cannot interrupt a native inference already in progress. Callers
/// therefore check this signal on both sides of the native call and discard a
/// result as soon as control returns to Dart.
final class RecognitionCancellation {
  final CancelToken networkToken = CancelToken();
  bool _isCancelled = false;
  String? _reason;

  bool get isCancelled => _isCancelled;
  String? get reason => _reason;

  void cancel([String reason = '用户取消']) {
    if (_isCancelled) return;
    _isCancelled = true;
    _reason = reason;
    networkToken.cancel(reason);
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw const SmartRecognitionException('识别已取消');
    }
  }
}
