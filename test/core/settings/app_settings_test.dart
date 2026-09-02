import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('uses the product default colors when no preference exists', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    final settings = container.read(appSettingsProvider);
    expect(settings.themeColor, const Color(0xFF26AAFF));
    expect(settings.incomeColor, const Color(0xFFFF1122));
    expect(settings.expenseColor, const Color(0xFF11CD22));
    expect(settings.historyNoteSmartSort, isFalse);
  });

  test(
    'loads persisted settings synchronously from the provider override',
    () async {
      SharedPreferences.setMockInitialValues({
        'settings.themeMode': 'dark',
        'settings.customThemeColor': 0xFFFFFFFF,
      });
      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(container.dispose);

      final settings = container.read(appSettingsProvider);
      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.themeColor.toARGB32(), 0xFFFFFFFF);
    },
  );

  test('persists the historical note smart sort switch', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final first = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    await first
        .read(appSettingsProvider.notifier)
        .setHistoryNoteSmartSort(true);
    first.dispose();

    final restored = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(restored.dispose);
    expect(restored.read(appSettingsProvider).historyNoteSmartSort, isTrue);
  });

  test(
    'persists income and expense colors across provider recreation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final first = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      final subscription = first.listen(
        appSettingsProvider,
        (previous, next) {},
        fireImmediately: true,
      );
      await first
          .read(appSettingsProvider.notifier)
          .setIncomeColor(const Color(0xFF123456));
      await first
          .read(appSettingsProvider.notifier)
          .setExpenseColor(const Color(0xFFABCDEF));
      subscription.close();
      first.dispose();

      final restored = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(restored.dispose);

      expect(
        restored.read(appSettingsProvider).incomeColor,
        const Color(0xFF123456),
      );
      expect(
        restored.read(appSettingsProvider).expenseColor,
        const Color(0xFFABCDEF),
      );
    },
  );
}
