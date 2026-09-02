import 'package:anbookkeep/app/theme/app_tokens.dart';
import 'package:anbookkeep/app/theme/app_theme.dart';
import 'package:flutter/material.dart';

const _gradientEdgeWidth = 1.0;

/// A card with a subtle gradient edge instead of a solid border line.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.margin = EdgeInsets.zero,
    this.borderRadius = AppRadii.card,
    this.clipBehavior = Clip.none,
    this.backgroundGradient,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final Clip clipBehavior;
  final Gradient? backgroundGradient;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? AppColors.darkCardBackground
        : AppColors.lightCardBackground;
    final edgeColors = isDark
        ? [AppColors.darkCardEdgeStart, AppColors.darkCardEdgeEnd]
        : [AppColors.lightCardEdgeStart, AppColors.lightCardEdgeEnd];
    final radius = BorderRadius.circular(borderRadius);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: edgeColors,
        ),
        borderRadius: radius,
        boxShadow: [AppShadows.subtle(Theme.of(context).colorScheme.primary)],
      ),
      padding: const EdgeInsets.all(_gradientEdgeWidth),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius - _gradientEdgeWidth),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundGradient == null ? cardColor : null,
            gradient: backgroundGradient,
          ),
          child: Material(
            color: Colors.transparent,
            clipBehavior: clipBehavior,
            child: child,
          ),
        ),
      ),
    );
  }
}
