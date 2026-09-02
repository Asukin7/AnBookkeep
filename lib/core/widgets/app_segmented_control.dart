import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';

/// Shared soft track used by tabs and segmented controls.
class AppSegmentedSurface extends StatelessWidget {
  const AppSegmentedSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSizes.segmentedControl,
          ),
          child: child,
        ),
      ),
    );
  }
}

class AppSegmentedButton<T> extends StatelessWidget {
  const AppSegmentedButton({
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    super.key,
  });

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>> onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cardColor = theme.cardTheme.color ?? colorScheme.surface;
    final selectedShadow = colorScheme.primary.withAlpha(
      theme.brightness == Brightness.light
          ? AppAlpha.pressed
          : AppAlpha.selectedShadowDark,
    );
    return AppSegmentedSurface(
      child: SizedBox(
        height: AppSizes.segmentedControl,
        child: Row(
          children: [
            for (final segment in segments)
              Expanded(
                child: _AppSegment<T>(
                  segment: segment,
                  selected: selected.contains(segment.value),
                  cardColor: cardColor,
                  selectedShadow: selectedShadow,
                  onTap: () => onSelectionChanged({segment.value}),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AppSegment<T> extends StatelessWidget {
  const _AppSegment({
    required this.segment,
    required this.selected,
    required this.cardColor,
    required this.selectedShadow,
    required this.onTap,
  });

  final ButtonSegment<T> segment;
  final bool selected;
  final Color cardColor;
  final Color selectedShadow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected ? scheme.primary : scheme.onSurfaceVariant;
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (segment.icon != null) ...[
          IconTheme(
            data: IconThemeData(
              color: foreground,
              size: AppSizes.iconAuxiliary,
            ),
            child: segment.icon!,
          ),
          if (segment.label != null)
            const SizedBox(width: AppSpacing.controlGap),
        ],
        if (segment.label != null)
          DefaultTextStyle.merge(
            style: theme.textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            child: segment.label!,
          ),
      ],
    );
    return Semantics(
      button: true,
      selected: selected,
      enabled: segment.enabled,
      label: segment.tooltip,
      child: Material(
        color: selected ? cardColor : Colors.transparent,
        elevation: selected ? AppElevation.selected : AppElevation.none,
        shadowColor: selectedShadow,
        borderRadius: BorderRadius.circular(AppRadii.compact),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: segment.enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppRadii.compact),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
