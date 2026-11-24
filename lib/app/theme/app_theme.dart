import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class AppColors {
  static const seed = Color(0xFF26AAFF);
  static const income = Color(0xFFFF1122);
  static const expense = Color(0xFF11CD22);
  static const deleteLight = Color(0xFFDD0000);
  static const deleteDark = Color(0xFFCC0000);
  static const lightBackground = Color(0xFFFFFFFF);
  static const darkBackground = Color(0xFF000000);
  static const lightCardBackground = Color(0xFFFFFFFF);
  static const darkCardBackground = Color(0xFF000000);
  static const lightCardEdgeStart = Color(0xFFF1F3F2);
  static const lightCardEdgeEnd = Color(0xFFE2E9E5);
  static const darkCardEdgeStart = Color(0xFF2A302D);
  static const darkCardEdgeEnd = Color(0xFF111412);
}

abstract final class AppTheme {
  static ThemeData light({Color seedColor = AppColors.seed}) =>
      _create(Brightness.light, seedColor);

  static ThemeData dark({Color seedColor = AppColors.seed}) =>
      _create(Brightness.dark, seedColor);

  static ThemeData _create(Brightness brightness, Color seedColor) {
    final isLight = brightness == Brightness.light;
    final generatedScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    final deleteColor = isLight ? AppColors.deleteLight : AppColors.deleteDark;
    final primaryBrightness = ThemeData.estimateBrightnessForColor(seedColor);
    // Keep the user's selected theme color exact. `fromSeed` intentionally
    // generates a tonal palette, which can otherwise turn #FFFFFF into a
    // different accent color.
    final colorScheme = generatedScheme.copyWith(
      primary: seedColor,
      onPrimary: primaryBrightness == Brightness.dark
          ? Colors.white
          : Colors.black,
      error: deleteColor,
      onError: Colors.white,
      surfaceTint: seedColor,
    );
    final cardBackground = isLight
        ? AppColors.lightCardBackground
        : AppColors.darkCardBackground;
    final selectedSegmentShadow = colorScheme.primary.withAlpha(
      isLight ? AppAlpha.pressed : AppAlpha.selectedShadowDark,
    );
    final textTheme = AppTypography.textTheme(brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: textTheme,
      iconTheme: IconThemeData(
        size: AppSizes.iconStandard,
        color: colorScheme.onSurface,
      ),
      primaryIconTheme: IconThemeData(
        size: AppSizes.iconStandard,
        color: colorScheme.onSurface,
      ),
      scaffoldBackgroundColor: isLight
          ? AppColors.lightBackground
          : AppColors.darkBackground,
      appBarTheme: AppBarThemeData(
        centerTitle: true,
        elevation: AppElevation.none,
        scrolledUnderElevation: AppElevation.none,
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        actionsIconTheme: IconThemeData(color: colorScheme.onSurface),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
          statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: isLight
              ? AppColors.lightBackground
              : AppColors.darkBackground,
          systemNavigationBarIconBrightness: isLight
              ? Brightness.dark
              : Brightness.light,
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(AppSizes.iconButton),
          iconSize: AppSizes.iconStandard,
          foregroundColor: colorScheme.onSurface,
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
          // Body icon buttons use a quiet surface by default. App-bar
          // leading/actions override this with a transparent background.
          backgroundColor: colorScheme.surfaceContainerLow,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicator: BoxDecoration(
          color: cardBackground,
          borderRadius: BorderRadius.circular(AppRadii.tabIndicator),
          boxShadow: [AppShadows.selected(selectedSegmentShadow)],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        labelStyle: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: textTheme.labelMedium,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      cardTheme: CardThemeData(
        elevation: AppElevation.subtle,
        shadowColor: colorScheme.primary.withAlpha(AppAlpha.subtleShadow),
        color: isLight
            ? AppColors.lightCardBackground
            : AppColors.darkCardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSizes.control),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          side: BorderSide.none,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSizes.control),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          side: BorderSide(color: colorScheme.primary, width: 1),
          foregroundColor: colorScheme.primary,
          backgroundColor: Colors.transparent,
          textStyle: textTheme.labelLarge,
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: AppElevation.floating,
        backgroundColor: cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: AppElevation.floating,
        modalElevation: AppElevation.floating,
        backgroundColor: cardBackground,
        modalBackgroundColor: cardBackground,
        showDragHandle: true,
        dragHandleColor: colorScheme.onSurfaceVariant,
        dragHandleSize: const Size(
          AppSizes.dragHandleWidth,
          AppSizes.dragHandleHeight,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.card),
          ),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        headerHeadlineStyle: textTheme.titleLarge,
        weekdayStyle: textTheme.labelMedium,
        dayStyle: textTheme.bodyMedium,
        yearStyle: textTheme.bodyMedium,
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        hourMinuteTextStyle: textTheme.headlineSmall,
        helpTextStyle: textTheme.labelLarge,
        dayPeriodTextStyle: textTheme.labelLarge,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: const CircleBorder(),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: AppElevation.floating,
        focusElevation: AppElevation.floating,
        hoverElevation: AppElevation.floating,
        highlightElevation: AppElevation.floating,
      ),
    );
  }
}
