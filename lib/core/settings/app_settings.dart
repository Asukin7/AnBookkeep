import 'package:anbookkeep/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TimePrecision { date, minute }

enum AmountDisplayFormat { grouped, plain }

@immutable
final class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.timePrecision = TimePrecision.minute,
    this.amountDisplayFormat = AmountDisplayFormat.grouped,
    this.themeColor = AppColors.seed,
    this.incomeColor = AppColors.income,
    this.expenseColor = AppColors.expense,
    this.historyNoteSmartSort = false,
  });

  final ThemeMode themeMode;
  final TimePrecision timePrecision;
  final AmountDisplayFormat amountDisplayFormat;
  final Color themeColor;
  final Color incomeColor;
  final Color expenseColor;
  final bool historyNoteSmartSort;

  AppSettings copyWith({
    ThemeMode? themeMode,
    TimePrecision? timePrecision,
    AmountDisplayFormat? amountDisplayFormat,
    Color? themeColor,
    Color? incomeColor,
    Color? expenseColor,
    bool? historyNoteSmartSort,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      timePrecision: timePrecision ?? this.timePrecision,
      amountDisplayFormat: amountDisplayFormat ?? this.amountDisplayFormat,
      themeColor: themeColor ?? this.themeColor,
      incomeColor: incomeColor ?? this.incomeColor,
      expenseColor: expenseColor ?? this.expenseColor,
      historyNoteSmartSort: historyNoteSmartSort ?? this.historyNoteSmartSort,
    );
  }
}

final class AppSettingsNotifier extends Notifier<AppSettings> {
  static const _themeModeKey = 'settings.themeMode';
  static const _timePrecisionKey = 'settings.timePrecision';
  static const _amountFormatKey = 'settings.amountFormat';
  static const _customThemeColorKey = 'settings.customThemeColor';
  static const _incomeColorKey = 'settings.incomeColor';
  static const _expenseColorKey = 'settings.expenseColor';
  static const _historyNoteSmartSortKey = 'settings.historyNoteSmartSort';
  SharedPreferences? _preferencesInstance;

  @override
  AppSettings build() {
    final preferences = ref.watch(sharedPreferencesProvider);
    _preferencesInstance = preferences;
    if (preferences == null) return const AppSettings();
    final themeName = preferences.getString(_themeModeKey);
    final precisionName = preferences.getString(_timePrecisionKey);
    final amountName = preferences.getString(_amountFormatKey);
    final customThemeColorValue = preferences.getInt(_customThemeColorKey);
    final incomeColorValue = preferences.getInt(_incomeColorKey);
    final expenseColorValue = preferences.getInt(_expenseColorKey);
    return AppSettings(
      themeMode: switch (themeName) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      timePrecision: precisionName == 'date'
          ? TimePrecision.date
          : TimePrecision.minute,
      amountDisplayFormat: amountName == 'plain'
          ? AmountDisplayFormat.plain
          : AmountDisplayFormat.grouped,
      themeColor: customThemeColorValue == null
          ? AppColors.seed
          : Color(customThemeColorValue),
      incomeColor: incomeColorValue == null
          ? AppColors.income
          : Color(incomeColorValue),
      expenseColor: expenseColorValue == null
          ? AppColors.expense
          : Color(expenseColorValue),
      historyNoteSmartSort:
          preferences.getBool(_historyNoteSmartSortKey) ?? false,
    );
  }

  Future<void> setThemeMode(ThemeMode value) async {
    final preferences = await _preferences();
    state = state.copyWith(themeMode: value);
    await preferences.setString(_themeModeKey, value.name);
  }

  Future<void> setTimePrecision(TimePrecision value) async {
    final preferences = await _preferences();
    state = state.copyWith(timePrecision: value);
    await preferences.setString(_timePrecisionKey, value.name);
  }

  Future<void> setAmountDisplayFormat(AmountDisplayFormat value) async {
    final preferences = await _preferences();
    state = state.copyWith(amountDisplayFormat: value);
    await preferences.setString(_amountFormatKey, value.name);
  }

  Future<void> setCustomThemeColor(Color value) async {
    final preferences = await _preferences();
    state = state.copyWith(themeColor: value);
    await preferences.setInt(_customThemeColorKey, value.toARGB32());
  }

  Future<void> setIncomeColor(Color value) async {
    final preferences = await _preferences();
    state = state.copyWith(incomeColor: value);
    await preferences.setInt(_incomeColorKey, value.toARGB32());
  }

  Future<void> setExpenseColor(Color value) async {
    final preferences = await _preferences();
    state = state.copyWith(expenseColor: value);
    await preferences.setInt(_expenseColorKey, value.toARGB32());
  }

  Future<void> setHistoryNoteSmartSort(bool value) async {
    final preferences = await _preferences();
    state = state.copyWith(historyNoteSmartSort: value);
    await preferences.setBool(_historyNoteSmartSortKey, value);
  }

  Future<SharedPreferences> _preferences() async {
    return _preferencesInstance ??= await SharedPreferences.getInstance();
  }
}

/// Overridden by `main` so settings are available before the first frame.
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);
