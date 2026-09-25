import 'dart:io';

import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/logging/app_logger.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/smart_bookkeeping/data/ai_config_repository.dart';
import 'package:anbookkeep/features/smart_bookkeeping/data/ai_response_parser.dart';
import 'package:anbookkeep/features/smart_bookkeeping/data/image_preprocessor.dart';
import 'package:anbookkeep/features/smart_bookkeeping/data/local_ocr_service.dart';
import 'package:anbookkeep/features/smart_bookkeeping/data/online_ai_client.dart';
import 'package:anbookkeep/features/smart_bookkeeping/data/prompt_repository.dart';
import 'package:anbookkeep/features/smart_bookkeeping/application/recognition_cancellation.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/ai_provider_config.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/prompt_template.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/recognition_result.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/smart_bookkeeping_draft.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/smart_draft_merger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

final class SmartBookkeepingService {
  SmartBookkeepingService(
    this._bookkeepingRepository,
    this._configRepository,
    this._promptRepository, {
    ImagePreprocessor? imagePreprocessor,
    LocalOcrService? localOcrService,
    OnlineAiClient? onlineAiClient,
    this._aiResponseParser = const AiResponseParser(),
    this._uuid = const Uuid(),
  }) : _imagePreprocessor = imagePreprocessor ?? ImagePreprocessor(),
       _localOcrService = localOcrService ?? LocalOcrService(),
       _onlineAiClient = onlineAiClient ?? OnlineAiClient();

  final BookkeepingRepository _bookkeepingRepository;
  final AiConfigRepository _configRepository;
  final PromptRepository _promptRepository;
  final ImagePreprocessor _imagePreprocessor;
  final LocalOcrService _localOcrService;
  final OnlineAiClient _onlineAiClient;
  final AiResponseParser _aiResponseParser;
  final Uuid _uuid;

  Future<RecognitionContext> loadRecognitionContext() async {
    final promptContent = _promptRepository.load().active.content;
    final values = await Future.wait<Object>([
      _allCategories(),
      _configRepository.load(),
    ]);
    return RecognitionContext(
      config: values[1] as AiProviderConfig,
      categories: values[0] as List<CategoryRow>,
      promptContent: _truncate(promptContent, _maxPromptTemplateChars),
    );
  }

  Future<SmartBookkeepingDraft> recognize({
    required String sourcePath,
    required SmartBookkeepingSource source,
    RecognitionCancellation? cancellation,
    RecognitionContext? context,
    bool allowOnline = true,
  }) async {
    final draftId = _uuid.v7();
    final operationId = draftId.substring(0, 8);
    final stopwatch = Stopwatch()..start();
    File? prepared;
    _log.info(
      'recognition_started',
      operationId: operationId,
      fields: {'source': source.name, 'allowOnline': allowOnline},
    );
    try {
      cancellation?.throwIfCancelled();
      prepared = await _imagePreprocessor.prepare(
        sourcePath,
        operationId: operationId,
        cancellation: cancellation,
      );
      cancellation?.throwIfCancelled();
      LocalOcrResult local;
      Object? localError;
      try {
        local = await _localOcrService.recognize(
          prepared,
          operationId: operationId,
          cancellation: cancellation,
        );
      } on SmartRecognitionException {
        rethrow;
      } on Object catch (error) {
        localError = error;
        local = const LocalOcrResult(rawText: '');
      }
      final recognitionContext = context ?? await loadRecognitionContext();
      cancellation?.throwIfCancelled();
      final categories = recognitionContext.categories;
      final config = recognitionContext.config;
      _log.info(
        'recognition_context_loaded',
        operationId: operationId,
        fields: {
          'categoryCount': categories.length,
          'aiEnabled': config.enabled,
          'hasApiKey': config.hasApiKey,
          'allowImageUpload': config.allowImageUpload,
          'hasOcrText': local.rawText.isNotEmpty,
        },
      );
      AiRecognitionResult? ai;
      SmartRecognitionException? aiError;
      if (allowOnline && config.enabled && config.hasApiKey) {
        try {
          final canUploadImage =
              config.allowImageUpload && config.imageUploadConsent;
          if (canUploadImage || local.rawText.isNotEmpty) {
            ai = await _recognizeOnline(
              config: config,
              image: prepared,
              local: local,
              categories: categories,
              source: source,
              promptContent: recognitionContext.promptContent,
              cancellation: cancellation,
              operationId: operationId,
            );
          } else {
            aiError = const SmartRecognitionException('本地OCR未识别到可供AI分析的文字');
          }
        } on SmartRecognitionException catch (error) {
          if (error.message == '识别已取消') rethrow;
          aiError = error;
          _log.warning(
            'online_ai_fallback_to_local',
            operationId: operationId,
            fields: {'isGlobal': error.isGlobal},
          );
        } on FormatException {
          aiError = const SmartRecognitionException('AI返回内容无法解析');
          _log.warning(
            'online_ai_fallback_to_local',
            operationId: operationId,
            fields: {'reason': 'invalidResponse'},
          );
        }
      } else {
        _log.info(
          'online_ai_skipped',
          operationId: operationId,
          fields: {
            'allowOnline': allowOnline,
            'aiEnabled': config.enabled,
            'hasApiKey': config.hasApiKey,
          },
        );
      }
      final merged = SmartDraftMerger.merge(
        draftId: draftId,
        imagePath: prepared.path,
        source: source,
        local: local,
        ai: ai,
        categories: categories,
        onlineError: aiError,
        localError: localError,
      );
      _log.info(
        'recognition_completed',
        operationId: operationId,
        fields: {
          'elapsedMs': stopwatch.elapsedMilliseconds,
          'usedOnlineAi': merged.usedOnlineAi,
          'status': merged.status.name,
          'hasType': merged.type != null,
          'hasAmount': merged.amount != null,
          'hasCategory': merged.categoryId != null,
          'hasNote': merged.note.isNotEmpty,
          'hasTime': merged.occurredAt != null,
        },
      );
      return merged;
    } on SmartRecognitionException catch (error, stackTrace) {
      _log.warning(
        error.message == '识别已取消'
            ? 'recognition_cancelled'
            : 'recognition_failed',
        operationId: operationId,
        fields: {'elapsedMs': stopwatch.elapsedMilliseconds},
      );
      if (prepared != null) await _imagePreprocessor.delete(prepared.path);
      if (error.message != '识别已取消') {
        _log.error(
          'recognition_failure_detail',
          operationId: operationId,
          cause: error,
          stackTrace: stackTrace,
        );
      }
      rethrow;
    } on Object catch (error, stackTrace) {
      _log.error(
        'recognition_unexpected_failure',
        operationId: operationId,
        cause: error,
        stackTrace: stackTrace,
        fields: {'elapsedMs': stopwatch.elapsedMilliseconds},
      );
      if (prepared != null) await _imagePreprocessor.delete(prepared.path);
      throw const SmartRecognitionException('图片识别失败，请重试');
    }
  }

  Future<void> deleteTemporaryImage(String path) =>
      _imagePreprocessor.delete(path);

  Future<void> cleanupExpiredImages() => _imagePreprocessor.cleanupExpired();

  Future<AiRecognitionResult> _recognizeOnline({
    required AiProviderConfig config,
    required File image,
    required LocalOcrResult local,
    required List<CategoryRow> categories,
    required SmartBookkeepingSource source,
    required String promptContent,
    RecognitionCancellation? cancellation,
    required String operationId,
  }) async {
    cancellation?.throwIfCancelled();
    final renderedPrompt = renderPromptTemplate(
      promptContent,
      values: {
        'CURRENT_TIME': LocalMinute.now().value,
        'OCR_TEXT': _truncate(local.rawText, _maxOcrPromptChars),
        'EXPENSE_CATEGORIES': _categoryPrompt(categories, EntryType.expense),
        'INCOME_CATEGORIES': _categoryPrompt(categories, EntryType.income),
        'INPUT_SOURCE': switch (source) {
          SmartBookkeepingSource.camera => '拍照图片',
          SmartBookkeepingSource.gallery => '相册图片',
          SmartBookkeepingSource.share => '外部分享图片',
        },
      },
    );
    final prompt = _truncate(renderedPrompt, _maxRenderedPromptChars);
    _log.sensitiveDebug(
      'online_ai_rendered_prompt',
      operationId: operationId,
      content: prompt,
    );
    final response = config.allowImageUpload && config.imageUploadConsent
        ? await _onlineAiClient.recognizeImage(
            config: config,
            image: image,
            prompt: prompt,
            cancelToken: cancellation?.networkToken,
            operationId: operationId,
          )
        : await _onlineAiClient.recognizeText(
            config: config,
            prompt: prompt,
            cancelToken: cancellation?.networkToken,
            operationId: operationId,
          );
    cancellation?.throwIfCancelled();
    _log.sensitiveDebug(
      'online_ai_raw_response',
      operationId: operationId,
      content: response,
    );
    return _aiResponseParser.parse(
      response,
      categoryTypes: {
        for (final category in categories)
          category.id: EntryType.fromDatabase(category.type),
      },
    );
  }

  Future<List<CategoryRow>> _allCategories() async {
    final values = await Future.wait([
      _bookkeepingRepository.getCategories(EntryType.expense),
      _bookkeepingRepository.getCategories(EntryType.income),
    ]);
    return [...values[0], ...values[1]];
  }

  static String _categoryPrompt(List<CategoryRow> categories, EntryType type) =>
      _truncate(
        categories
            .where((category) => category.type == type.databaseValue)
            .map((category) => '${category.id} | ${category.name}')
            .join('、'),
        _maxCategoryPromptChars,
      );

  static String _truncate(String value, int maxChars) =>
      value.length <= maxChars ? value : value.substring(0, maxChars);
}

final class RecognitionContext {
  RecognitionContext({
    required this.config,
    required List<CategoryRow> categories,
    required this.promptContent,
  }) : categories = List.unmodifiable(categories);

  final AiProviderConfig config;
  final List<CategoryRow> categories;
  final String promptContent;
}

const _maxPromptTemplateChars = 12000;
const _maxOcrPromptChars = 12000;
const _maxCategoryPromptChars = 8000;
const _maxRenderedPromptChars = 32000;

final onlineAiClientProvider = Provider<OnlineAiClient>((ref) {
  return OnlineAiClient();
});

const _log = AppLogger('SmartBookkeeping');

final smartBookkeepingServiceProvider = Provider<SmartBookkeepingService>((
  ref,
) {
  return SmartBookkeepingService(
    ref.watch(bookkeepingRepositoryProvider),
    ref.watch(aiConfigRepositoryProvider),
    ref.watch(promptRepositoryProvider),
    onlineAiClient: ref.watch(onlineAiClientProvider),
  );
});
