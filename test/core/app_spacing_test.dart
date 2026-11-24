import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/app/theme/app_theme.dart';
import 'package:anbookkeep/app/theme/app_tokens.dart';
import 'package:anbookkeep/core/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared spacing follows the project visual rhythm', () {
    expect(
      [
        AppSpacing.xxs,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
      ],
      [4, 8, 12, 16, 24, 32],
    );
    expect(AppSpacing.pagePadding, const EdgeInsets.fromLTRB(16, 4, 16, 24));
    expect(AppSpacing.cardPadding, const EdgeInsets.all(16));
    expect(AppSpacing.compactCardPadding, const EdgeInsets.all(12));
  });

  test('AppCard does not add hidden external spacing', () {
    const card = AppCard(child: SizedBox.shrink());
    expect(card.margin, EdgeInsets.zero);
  });

  test('visual tokens define one component system', () {
    expect(
      [
        AppRadii.small,
        AppRadii.compact,
        AppRadii.segmentIndicator,
        AppRadii.control,
        AppRadii.card,
      ],
      [4, 8, 12, 16, 20],
    );
    expect(
      AppRadii.control - AppRadii.tabIndicator,
      AppSpacing.segmentedTrackInset + AppSpacing.tabIndicatorInset,
    );
    expect(AppSizes.control, 48);
    expect(AppSizes.iconStandard, 24);
    expect(AppMotion.fast, const Duration(milliseconds: 120));
    expect(AppMotion.standard, const Duration(milliseconds: 180));
  });

  test('theme applies typography and modal standards', () {
    final theme = AppTheme.light();
    expect(theme.textTheme.titleLarge?.fontSize, 20);
    expect(theme.textTheme.titleLarge?.height, 28 / 20);
    expect(theme.textTheme.bodyMedium?.fontSize, 14);
    expect(theme.textTheme.bodyMedium?.height, 20 / 14);
    expect(theme.textTheme.labelSmall?.fontSize, 10);
    expect(
      AppTypography.summaryNumber(theme.textTheme).fontWeight,
      FontWeight.w700,
    );
    expect(AppTypography.summaryNumber(theme.textTheme).fontFeatures, [
      const FontFeature.tabularFigures(),
    ]);
    expect(theme.colorScheme.primary, AppColors.seed);
    expect(theme.colorScheme.onPrimary, Colors.black);
    expect(theme.bottomSheetTheme.showDragHandle, isTrue);
    expect(theme.filledButtonTheme.style?.minimumSize?.resolve({})?.height, 48);
    expect(theme.colorScheme.error, AppColors.deleteLight);
    expect(
      theme.appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
      Brightness.dark,
    );
    expect(theme.iconTheme.color, theme.colorScheme.onSurface);

    final darkTheme = AppTheme.dark();
    expect(
      AppTheme.dark(seedColor: const Color(0xFF222222)).colorScheme.onPrimary,
      Colors.white,
    );
    expect(darkTheme.colorScheme.error, AppColors.deleteDark);
    expect(
      darkTheme.appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
      Brightness.light,
    );
    expect(darkTheme.iconTheme.color, darkTheme.colorScheme.onSurface);
  });

  test('medium blues use white on primary in both modes', () {
    for (final blue in const [Color(0xFF2277FF), Color(0xFF3377FF)]) {
      for (final theme in [
        AppTheme.light(seedColor: blue),
        AppTheme.dark(seedColor: blue),
      ]) {
        expect(theme.colorScheme.primary, blue);
        expect(theme.colorScheme.onPrimary, Colors.white);
      }
    }
  });
}
