import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/smart_bookkeeping/data/local_ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = LocalOcrService();

  test('extracts payment amount, merchant and time from OCR text', () {
    final result = service.parse('''微信支付
支付成功
安安咖啡店
实付 ￥28.50
交易时间 2026-08-31 18:30''');

    expect(result.type, EntryType.expense);
    expect(result.amount?.minorUnits, 2850);
    expect(result.note, '安安咖啡店');
    expect(result.occurredAt?.value, '2026-08-31 18:30');
  });

  test('recognizes an incoming payment as income', () {
    final result = service.parse('收款成功\n安安工作室\n到账￥100.00');

    expect(result.type, EntryType.income);
    expect(result.amount?.minorUnits, 10000);
  });

  test('does not normalize an invalid OCR date', () {
    final result = service.parse('支付成功\n2026-02-30 10:20\n实付￥10.00');

    expect(result.occurredAt, isNull);
  });
}
