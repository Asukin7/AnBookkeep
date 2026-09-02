import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/ai_provider_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class AiConfigRepository {
  AiConfigRepository(this._preferences, this._secureStorage);

  static const _enabledKey = 'smartBookkeeping.ai.enabled';
  static const _baseUrlKey = 'smartBookkeeping.ai.baseUrl';
  static const _visionModelKey = 'smartBookkeeping.ai.visionModel';
  static const _textModelKey = 'smartBookkeeping.ai.textModel';
  static const _allowImageUploadKey = 'smartBookkeeping.ai.allowImageUpload';
  static const _imageUploadConsentKey =
      'smartBookkeeping.ai.imageUploadConsent';
  static const _apiKeyKey = 'smartBookkeeping.ai.apiKey';

  final SharedPreferences _preferences;
  final FlutterSecureStorage _secureStorage;

  Future<AiProviderConfig> load() async {
    final defaults = const AiProviderConfig();
    return AiProviderConfig(
      enabled: _preferences.getBool(_enabledKey) ?? defaults.enabled,
      baseUrl: _preferences.getString(_baseUrlKey) ?? defaults.baseUrl,
      apiKey: await _secureStorage.read(key: _apiKeyKey) ?? '',
      visionModel:
          _preferences.getString(_visionModelKey) ?? defaults.visionModel,
      textModel: _preferences.getString(_textModelKey) ?? defaults.textModel,
      allowImageUpload:
          _preferences.getBool(_allowImageUploadKey) ??
          defaults.allowImageUpload,
      imageUploadConsent:
          _preferences.getBool(_imageUploadConsentKey) ??
          defaults.imageUploadConsent,
    );
  }

  Future<void> save(AiProviderConfig config) async {
    await Future.wait([
      _preferences.setBool(_enabledKey, config.enabled),
      _preferences.setString(_baseUrlKey, config.baseUrl.trim()),
      _preferences.setString(_visionModelKey, config.visionModel.trim()),
      _preferences.setString(_textModelKey, config.textModel.trim()),
      _preferences.setBool(_allowImageUploadKey, config.allowImageUpload),
      _preferences.setBool(_imageUploadConsentKey, config.imageUploadConsent),
    ]);
    final key = config.apiKey.trim();
    if (key.isEmpty) {
      await _secureStorage.delete(key: _apiKeyKey);
    } else {
      await _secureStorage.write(key: _apiKeyKey, value: key);
    }
  }
}

final aiConfigRepositoryProvider = Provider<AiConfigRepository>((ref) {
  final preferences = ref.watch(sharedPreferencesProvider);
  if (preferences == null) {
    throw StateError('SharedPreferences尚未初始化');
  }
  return AiConfigRepository(preferences, const FlutterSecureStorage());
});

final class AiConfigNotifier extends AsyncNotifier<AiProviderConfig> {
  @override
  Future<AiProviderConfig> build() {
    return ref.watch(aiConfigRepositoryProvider).load();
  }

  Future<void> save(AiProviderConfig config) async {
    await ref.read(aiConfigRepositoryProvider).save(config);
    state = AsyncData(config);
  }

  Future<void> setImageUploadConsent(bool value) async {
    final current = state.value;
    if (current == null) return;
    await save(current.copyWith(imageUploadConsent: value));
  }
}

final aiConfigProvider =
    AsyncNotifierProvider<AiConfigNotifier, AiProviderConfig>(
      AiConfigNotifier.new,
    );
