import 'package:flutter/material.dart';

abstract final class AppRadii {
  static const double small = 4;
  static const double compact = 10;
  static const double control = 14;
  static const double input = 16;
  static const double card = 20;
}

abstract final class AppSizes {
  static const double iconAuxiliary = 18;
  static const double iconControl = 20;
  static const double iconStandard = 24;

  static const double iconButton = 40;
  static const double segmentedControl = 40;
  static const double segmentedControlCompact = 32;
  static const double control = 48;
  static const double calculatorButton = 58;
  static const double calculatorRow = 64;

  static const double settingIcon = 36;
  static const double categoryIconSmall = 30;
  static const double categoryIcon = 36;
  static const double categoryIconLarge = 44;
  static const double colorPreview = 56;
  static const double dragHandleWidth = 32;
  static const double dragHandleHeight = 4;
}

abstract final class AppElevation {
  static const double none = 0;
  static const double subtle = 1;
  static const double selected = 2;
  static const double floating = 4;
}

abstract final class AppAlpha {
  static const int subtleShadow = 18;
  static const int pressed = 20;
  static const int quietFill = 24;
  static const int glowLight = 34;
  static const int selectedShadowDark = 36;
  static const int glowDark = 58;
  static const int selectedFill = 55;
  static const int emphasisShadow = 70;
  static const int overlayStrong = 235;
}

abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 180);
}

abstract final class AppShadows {
  static BoxShadow subtle(Color color) => BoxShadow(
    color: color.withAlpha(AppAlpha.subtleShadow),
    blurRadius: 16,
    offset: const Offset(0, 4),
  );

  static BoxShadow selected(Color color) =>
      BoxShadow(color: color, blurRadius: 10, offset: const Offset(0, 3));

  static BoxShadow emphasis(Color color) => BoxShadow(
    color: color.withAlpha(AppAlpha.emphasisShadow),
    blurRadius: 16,
    offset: const Offset(0, 4),
  );
}

abstract final class AppTypography {
  static TextStyle calculator(TextTheme textTheme) =>
      textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w500);

  static TextTheme textTheme(Brightness brightness) {
    final base = brightness == Brightness.light
        ? Typography.material2021().black
        : Typography.material2021().white;
    return base.copyWith(
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.4,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.2,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        height: 1.2,
      ),
    );
  }
}
