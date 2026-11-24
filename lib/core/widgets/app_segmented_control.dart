import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';

const _selectionCurve = Curves.easeOutCubic;

/// Shared soft track used by tabs and segmented controls.
class AppSegmentedSurface extends StatelessWidget {
  const AppSegmentedSurface({
    required this.child,
    this.compact = false,
    super.key,
  });

  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.segmentedTrackInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: compact
                ? AppSizes.segmentedControlCompact
                : AppSizes.segmentedControl,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A single-selection control with a shared sliding indicator.
class AppSegmentedButton<T> extends StatelessWidget {
  const AppSegmentedButton({
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.compact = false,
    super.key,
  });

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>> onSelectionChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    assert(selected.length <= 1);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cardColor = theme.cardTheme.color ?? colorScheme.surface;
    final selectedShadow = colorScheme.primary.withAlpha(
      theme.brightness == Brightness.light
          ? AppAlpha.pressed
          : AppAlpha.selectedShadowDark,
    );
    final selectedIndex = segments.indexWhere(
      (segment) => selected.contains(segment.value),
    );
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.standard;
    return AppSegmentedSurface(
      compact: compact,
      child: SizedBox(
        height: compact
            ? AppSizes.segmentedControlCompact
            : AppSizes.segmentedControl,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (selectedIndex >= 0)
              IgnorePointer(
                child: AnimatedAlign(
                  duration: duration,
                  curve: _selectionCurve,
                  alignment: AlignmentDirectional(
                    segments.length == 1
                        ? 0
                        : 2 * selectedIndex / (segments.length - 1) - 1,
                    0,
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 1 / segments.length,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(
                          AppRadii.segmentIndicator,
                        ),
                        boxShadow: [AppShadows.selected(selectedShadow)],
                      ),
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                for (final segment in segments)
                  Expanded(
                    child: _AppSegment<T>(
                      segment: segment,
                      selected: selected.contains(segment.value),
                      duration: duration,
                      onTap: () {
                        if (!selected.contains(segment.value)) {
                          onSelectionChanged({segment.value});
                        }
                      },
                    ),
                  ),
              ],
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
    required this.duration,
    required this.onTap,
  });

  final ButtonSegment<T> segment;
  final bool selected;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(AppRadii.segmentIndicator);
    return Semantics(
      button: true,
      selected: selected,
      enabled: segment.enabled,
      label: segment.tooltip,
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: segment.enabled ? onTap : null,
          borderRadius: radius,
          highlightColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: selected ? 1 : 0),
                duration: duration,
                curve: _selectionCurve,
                builder: (context, progress, _) {
                  final foreground = Color.lerp(
                    scheme.onSurfaceVariant,
                    scheme.primary,
                    progress,
                  );
                  return Row(
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
                            fontWeight: FontWeight.lerp(
                              FontWeight.w500,
                              FontWeight.w700,
                              progress,
                            ),
                          ),
                          child: segment.label!,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
