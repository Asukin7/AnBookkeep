import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/app/router/app_router.dart';
import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/app/theme/app_tokens.dart';
import 'package:anbookkeep/core/widgets/app_bottom_sheet.dart';
import 'package:anbookkeep/core/widgets/app_card.dart';
import 'package:anbookkeep/core/widgets/app_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          style: IconButton.styleFrom(backgroundColor: Colors.transparent),
        ),
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(
          top: AppSpacing.pageTop,
          bottom: AppSpacing.pageBottom,
        ),
        children: [
          const _SectionTitle('外观'),
          AppCard(
            margin: const EdgeInsets.fromLTRB(
              AppSpacing.pageHorizontal,
              0,
              AppSpacing.pageHorizontal,
              AppSpacing.componentGap,
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const _SettingIcon(Icons.brightness_6_outlined),
                  title: const Text('外观模式'),
                  subtitle: Text(_themeLabel(settings.themeMode)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () =>
                      _selectTheme(context, settings.themeMode, notifier),
                ),
                ListTile(
                  leading: _SettingIcon(
                    Icons.palette_outlined,
                    color: settings.themeColor,
                  ),
                  title: const Text('主题颜色'),
                  subtitle: const Text('全局主题色'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () =>
                      _selectPalette(context, settings.themeColor, notifier),
                ),
                ListTile(
                  leading: _SettingIcon(
                    Icons.trending_up_rounded,
                    color: settings.incomeColor,
                  ),
                  title: const Text('收入颜色'),
                  subtitle: const Text('用于收入金额和统计标识'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _selectColor(
                    context,
                    '收入颜色',
                    settings.incomeColor,
                    notifier.setIncomeColor,
                  ),
                ),
                ListTile(
                  leading: _SettingIcon(
                    Icons.trending_down_rounded,
                    color: settings.expenseColor,
                  ),
                  title: const Text('支出颜色'),
                  subtitle: const Text('用于支出金额和统计标识'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _selectColor(
                    context,
                    '支出颜色',
                    settings.expenseColor,
                    notifier.setExpenseColor,
                  ),
                ),
              ],
            ),
          ),
          const _SectionTitle('记账'),
          AppCard(
            margin: const EdgeInsets.fromLTRB(
              AppSpacing.pageHorizontal,
              0,
              AppSpacing.pageHorizontal,
              AppSpacing.componentGap,
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const _SettingIcon(Icons.schedule_outlined),
                  title: const Text('记账时间精度'),
                  subtitle: Text(
                    settings.timePrecision == TimePrecision.date ? '日期' : '分钟',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _selectPrecision(
                    context,
                    settings.timePrecision,
                    notifier,
                  ),
                ),
                ListTile(
                  leading: const _SettingIcon(Icons.numbers_outlined),
                  title: const Text('金额显示格式'),
                  subtitle: Text(
                    settings.amountDisplayFormat == AmountDisplayFormat.grouped
                        ? '123,456.78'
                        : '123456.78',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _selectAmountFormat(
                    context,
                    settings.amountDisplayFormat,
                    notifier,
                  ),
                ),
                ListTile(
                  leading: const _SettingIcon(Icons.category_outlined),
                  title: const Text('记账分类'),
                  subtitle: const Text('管理记账分类'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(AppRoutes.categories),
                ),
                ListTile(
                  leading: const _SettingIcon(Icons.history_rounded),
                  title: const Text('历史备注智能排序'),
                  subtitle: Text(
                    settings.historyNoteSmartSort
                        ? '结合历史使用与当前记账信息排序'
                        : '按使用次数排序',
                  ),
                  trailing: Switch.adaptive(
                    value: settings.historyNoteSmartSort,
                    onChanged: notifier.setHistoryNoteSmartSort,
                  ),
                  onTap: () => notifier.setHistoryNoteSmartSort(
                    !settings.historyNoteSmartSort,
                  ),
                ),
              ],
            ),
          ),
          const _SectionTitle('数据与智能'),
          AppCard(
            margin: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pageHorizontal,
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const _SettingIcon(Icons.storage_outlined),
                  title: const Text('数据管理'),
                  subtitle: const Text('导入或导出账单数据'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(AppRoutes.dataManagement),
                ),
                ListTile(
                  leading: const _SettingIcon(Icons.auto_awesome_outlined),
                  title: const Text('AI记账'),
                  subtitle: const Text('在线AI、本地OCR与提示词'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(AppRoutes.aiBookkeeping),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _selectTheme(
    BuildContext context,
    ThemeMode current,
    AppSettingsNotifier notifier,
  ) async {
    final value = await showModalBottomSheet<ThemeMode>(
      context: context,
      builder: (context) => _ChoiceSheet<ThemeMode>(
        title: '外观模式',
        current: current,
        values: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
        label: _themeLabel,
      ),
    );
    if (value != null) await notifier.setThemeMode(value);
  }

  static Future<void> _selectPrecision(
    BuildContext context,
    TimePrecision current,
    AppSettingsNotifier notifier,
  ) async {
    final value = await showModalBottomSheet<TimePrecision>(
      context: context,
      builder: (context) => _ChoiceSheet<TimePrecision>(
        title: '记账时间精度',
        current: current,
        values: const [TimePrecision.date, TimePrecision.minute],
        label: (value) => value == TimePrecision.date ? '日期' : '分钟',
      ),
    );
    if (value != null) await notifier.setTimePrecision(value);
  }

  static Future<void> _selectAmountFormat(
    BuildContext context,
    AmountDisplayFormat current,
    AppSettingsNotifier notifier,
  ) async {
    final value = await showModalBottomSheet<AmountDisplayFormat>(
      context: context,
      builder: (context) => _ChoiceSheet<AmountDisplayFormat>(
        title: '金额显示格式',
        current: current,
        values: const [AmountDisplayFormat.grouped, AmountDisplayFormat.plain],
        label: (value) =>
            value == AmountDisplayFormat.grouped ? '123,456.78' : '123456.78',
      ),
    );
    if (value != null) await notifier.setAmountDisplayFormat(value);
  }

  static Future<void> _selectPalette(
    BuildContext context,
    Color current,
    AppSettingsNotifier notifier,
  ) async {
    final value = await showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          AppColorPickerSheet(title: '主题颜色', current: current),
    );
    if (value != null) await notifier.setCustomThemeColor(value);
  }

  static Future<void> _selectColor(
    BuildContext context,
    String title,
    Color current,
    Future<void> Function(Color) onChanged,
  ) async {
    final value = await showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      builder: (context) => AppColorPickerSheet(title: title, current: current),
    );
    if (value != null) await onChanged(value);
  }

  static String _themeLabel(ThemeMode value) => switch (value) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '亮色模式',
    ThemeMode.dark => '暗黑模式',
  };
}

class _ChoiceSheet<T> extends StatelessWidget {
  const _ChoiceSheet({
    required this.title,
    required this.current,
    required this.values,
    required this.label,
  });

  final String title;
  final T current;
  final List<T> values;
  final String Function(T) label;

  @override
  Widget build(BuildContext context) {
    return AppBottomSheetLayout(
      title: title,
      child: RadioGroup<T>(
        groupValue: current,
        onChanged: (value) {
          if (value != null) Navigator.pop(context, value);
        },
        child: Column(
          children: [
            for (final value in values)
              RadioListTile<T>(value: value, title: Text(label(value))),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageHorizontal,
        AppSpacing.componentGap,
        AppSpacing.pageHorizontal,
        AppSpacing.controlGap,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _SettingIcon extends StatelessWidget {
  const _SettingIcon(this.icon, {this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color ?? scheme.primary;
    return Container(
      width: AppSizes.settingIcon,
      height: AppSizes.settingIcon,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tint.withAlpha(AppAlpha.quietFill),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: AppSizes.iconAuxiliary, color: tint),
    );
  }
}
