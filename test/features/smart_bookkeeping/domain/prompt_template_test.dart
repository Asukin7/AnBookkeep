import 'package:anbookkeep/features/smart_bookkeeping/domain/prompt_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('renders supported prompt variables', () {
    final rendered = renderPromptTemplate(
      '{{CURRENT_TIME}} | {{OCR_TEXT}} | {{INPUT_SOURCE}}',
      values: const {
        'CURRENT_TIME': '2026-08-31 18:30',
        'OCR_TEXT': '￥28.50',
        'INPUT_SOURCE': '相册图片',
      },
    );

    expect(rendered, '2026-08-31 18:30 | ￥28.50 | 相册图片');
  });

  test('reports unknown variables case-insensitively', () {
    expect(
      unknownPromptVariables('{{CURRENT_TIME}} {{UNKNOWN}} {{bad_name}}'),
      {'UNKNOWN', 'bad_name'},
    );
  });

  test('invalid stored custom prompts fall back to an empty list', () {
    expect(decodeCustomPrompts('not-json'), isEmpty);
  });
}
