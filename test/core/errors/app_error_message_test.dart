import 'package:anbookkeep/core/errors/app_error_message.dart';
import 'package:flutter_test/flutter_test.dart';

final class _SafeException implements UserFacingException {
  const _SafeException(this.message);

  @override
  final String message;
}

void main() {
  test('keeps only explicitly user-facing messages', () {
    expect(
      appErrorMessage(const AppValidationException('文件格式错误'), fallback: '失败'),
      '文件格式错误',
    );
    expect(
      appErrorMessage(const _SafeException('连接配置错误'), fallback: '失败'),
      '连接配置错误',
    );
  });

  test('hides unexpected implementation details', () {
    expect(
      appErrorMessage(
        Exception('C:/private/database.sqlite'),
        fallback: '操作失败',
      ),
      '操作失败',
    );
    expect(
      appErrorMessage(
        const FormatException('third-party parser details'),
        fallback: '操作失败',
      ),
      '操作失败',
    );
  });
}
