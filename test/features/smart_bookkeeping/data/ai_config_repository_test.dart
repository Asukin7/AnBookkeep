import 'package:anbookkeep/features/smart_bookkeeping/data/ai_config_repository.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/ai_provider_config.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('stores API key in secure storage instead of preferences', () async {
    final preferences = await SharedPreferences.getInstance();
    const secureStorage = FlutterSecureStorage();
    final repository = AiConfigRepository(preferences, secureStorage);

    await repository.save(
      const AiProviderConfig(
        enabled: true,
        apiKey: 'secret-key',
        allowImageUpload: true,
        imageUploadConsent: true,
      ),
    );

    expect(
      preferences.getKeys().where((key) => key.contains('apiKey')),
      isEmpty,
    );
    expect(
      await secureStorage.read(key: 'smartBookkeeping.ai.apiKey'),
      'secret-key',
    );
    final loaded = await repository.load();
    expect(loaded.enabled, isTrue);
    expect(loaded.apiKey, 'secret-key');
    expect(loaded.imageUploadConsent, isTrue);
  });

  test('loads one endpoint configuration', () async {
    SharedPreferences.setMockInitialValues({
      'smartBookkeeping.ai.baseUrl': 'https://example.com/v1',
      'smartBookkeeping.ai.visionModel': 'vision-model',
      'smartBookkeeping.ai.textModel': 'text-model',
    });
    final preferences = await SharedPreferences.getInstance();
    final repository = AiConfigRepository(
      preferences,
      const FlutterSecureStorage(),
    );

    final loaded = await repository.load();

    expect(loaded.baseUrl, 'https://example.com/v1');
    expect(loaded.visionModel, 'vision-model');
    expect(loaded.textModel, 'text-model');
  });
}
