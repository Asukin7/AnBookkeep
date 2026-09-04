import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/features/smart_bookkeeping/presentation/ai_bookkeeping_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AI settings uses one endpoint configuration without providers', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(home: AiBookkeepingSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('智谱GLM'), findsNothing);
    expect(find.text('OpenAI兼容'), findsNothing);
    expect(find.text('服务商'), findsNothing);
    expect(find.text('服务商名称'), findsNothing);
    expect(find.text('API地址'), findsOneWidget);
    expect(find.text('视觉模型'), findsOneWidget);
    expect(find.text('文本模型'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('文本模型')).dy,
      lessThan(tester.getTopLeft(find.text('视觉模型')).dy),
    );
    expect(find.byKey(const ValueKey('testTextModelButton')), findsOneWidget);
    expect(find.byKey(const ValueKey('testVisionModelButton')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('model inputs remain visible on a narrow phone screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(home: AiBookkeepingSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, '文本模型'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '视觉模型'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
