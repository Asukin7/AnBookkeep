import 'dart:io';

import 'package:anbookkeep/features/smart_bookkeeping/data/online_ai_client.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/ai_provider_config.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/recognition_result.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('text recognition request never includes image data', () async {
    final dio = Dio();
    late RequestOptions captured;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.resolve(
            Response<Object?>(
              requestOptions: options,
              statusCode: 200,
              data: '{"choices":[{"message":{"content":"{\\"type\\":\\"expense\\"}"}}]}',
            ),
          );
        },
      ),
    );

    final response = await OnlineAiClient(dio: dio).recognizeText(
      config: const AiProviderConfig(
        enabled: true,
        apiKey: 'secret',
        textModel: 'text-model',
      ),
      prompt: 'OCR文字',
    );

    expect(response, '{"type":"expense"}');
    expect(captured.uri.toString(), endsWith('/chat/completions'));
    expect(captured.data.toString(), isNot(contains('image_url')));
    expect(captured.data.toString(), isNot(contains('base64')));
  });

  test(
    'text model test calls the configured text model without image',
    () async {
      final dio = Dio();
      late RequestOptions captured;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options;
            handler.resolve(
              Response<Object?>(
                requestOptions: options,
                statusCode: 200,
                data: '{"choices":[{"message":{"content":"OK"}}]}',
              ),
            );
          },
        ),
      );

      await OnlineAiClient(dio: dio).testTextModel(
        const AiProviderConfig(apiKey: 'secret', textModel: 'text-test-model'),
      );

      expect(captured.data['model'], 'text-test-model');
      expect(captured.data.toString(), isNot(contains('image_url')));
    },
  );

  test(
    'vision model test calls the configured vision model with image',
    () async {
      final dio = Dio();
      late RequestOptions captured;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options;
            handler.resolve(
              Response<Object?>(
                requestOptions: options,
                statusCode: 200,
                data: '{"choices":[{"message":{"content":"OK"}}]}',
              ),
            );
          },
        ),
      );

      await OnlineAiClient(dio: dio).testVisionModel(
        const AiProviderConfig(
          apiKey: 'secret',
          visionModel: 'vision-test-model',
        ),
      );

      expect(captured.data['model'], 'vision-test-model');
      expect(captured.data.toString(), contains('data:image/png;base64'));
    },
  );

  test('rejects non-HTTPS provider addresses before sending', () async {
    await expectLater(
      OnlineAiClient().testConnection(
        const AiProviderConfig(
          enabled: true,
          apiKey: 'secret',
          baseUrl: 'http://example.com/v1',
        ),
      ),
      throwsA(isA<SmartRecognitionException>()),
    );
  });

  test('parses a plain JSON response and disables redirects', () async {
    final dio = Dio();
    late RequestOptions captured;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.resolve(
            Response<Object?>(
              requestOptions: options,
              statusCode: 200,
              data: '{"choices":[{"message":{"content":"{\\"type\\":\\"income\\"}"}}]}',
            ),
          );
        },
      ),
    );

    final value = await OnlineAiClient(dio: dio).recognizeText(
      config: const AiProviderConfig(
        enabled: true,
        apiKey: 'secret',
        textModel: 'text-model',
      ),
      prompt: 'OCR文字',
    );

    expect(value, '{"type":"income"}');
    expect(captured.followRedirects, isFalse);
    expect(captured.maxRedirects, 0);
    expect(captured.responseType, ResponseType.plain);
  });

  test(
    'rejects provider addresses containing a query or credentials',
    () async {
      for (final address in [
        'https://example.com/v1?token=secret',
        'https://user:password@example.com/v1',
      ]) {
        await expectLater(
          OnlineAiClient().testConnection(
            AiProviderConfig(enabled: true, apiKey: 'secret', baseUrl: address),
          ),
          throwsA(isA<SmartRecognitionException>()),
        );
      }
    },
  );

  test('rejects an unexpectedly large AI response', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response<Object?>(
            requestOptions: options,
            statusCode: 200,
            data: 'x' * (1024 * 1024 + 1),
          ),
        ),
      ),
    );

    await expectLater(
      OnlineAiClient(dio: dio).recognizeText(
        config: const AiProviderConfig(
          enabled: true,
          apiKey: 'secret',
          textModel: 'text-model',
        ),
        prompt: 'OCR文字',
      ),
      throwsFormatException,
    );
  });

  test('rejects an oversized image before sending it to AI', () async {
    final directory = await Directory.systemTemp.createTemp(
      'anbookkeep_ai_test_',
    );
    final image = File('${directory.path}${Platform.pathSeparator}large.jpg');
    await image.writeAsBytes(List<int>.filled(8 * 1024 * 1024 + 1, 0));
    var requestSent = false;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestSent = true;
          handler.reject(
            DioException(requestOptions: options, message: 'unexpected'),
          );
        },
      ),
    );

    try {
      await expectLater(
        OnlineAiClient(dio: dio).recognizeImage(
          config: const AiProviderConfig(
            enabled: true,
            apiKey: 'secret',
            visionModel: 'vision-model',
          ),
          image: image,
          prompt: '识别账单',
        ),
        throwsA(isA<SmartRecognitionException>()),
      );
      expect(requestSent, isFalse);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
