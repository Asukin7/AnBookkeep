import 'dart:math' as math;

import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/app/theme/app_tokens.dart';
import 'package:anbookkeep/core/widgets/app_bottom_sheet.dart';
import 'package:anbookkeep/core/widgets/app_dialog.dart';
import 'package:flutter/material.dart';

const _colorSwatchSelectionInset = 2.0;
const _colorPaletteDiameter = 196.0;
const _paletteIndicatorRadius = 8.0;
const _paletteIndicatorStrokeWidth = 3.0;

String appColorHex(Color color) =>
    '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

Color? parseAppColorHex(String value) {
  final normalized = value.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) return null;
  return Color(int.parse('FF$normalized', radix: 16));
}

/// Generates an opaque, vivid color suitable for categories and swatches.
Color randomVividAppColor([math.Random? source]) {
  final random = source ?? math.Random();
  return HSVColor.fromAHSV(
    1,
    random.nextDouble() * 360,
    .72 + random.nextDouble() * .24,
    .82 + random.nextDouble() * .15,
  ).toColor();
}

class AppColorPickerSheet extends StatefulWidget {
  const AppColorPickerSheet({
    required this.title,
    required this.current,
    super.key,
  });

  final String title;
  final Color current;

  @override
  State<AppColorPickerSheet> createState() => _AppColorPickerSheetState();
}

class _AppColorPickerSheetState extends State<AppColorPickerSheet> {
  late Color _selected = widget.current;

  late final List<Color> colors = _randomColors(widget.current);

  static List<Color> _randomColors(Color current) {
    final random = math.Random();
    final offset = random.nextDouble() * 36;
    return [
      current,
      for (var index = 0; index < 9; index++)
        HSVColor.fromAHSV(
          1,
          (offset + index * 36 + random.nextDouble() * 18) % 360,
          .78 + random.nextDouble() * .18,
          .82 + random.nextDouble() * .15,
        ).toColor(),
    ];
  }

  void _select(Color color) {
    setState(() => _selected = color);
  }

  Future<void> _editHex() async {
    final value = await showDialog<Color>(
      context: context,
      builder: (context) => _HexColorDialog(initial: _selected),
    );
    if (value != null && mounted) _select(value);
  }

  void _pickFromPalette(Offset point, _ColorPaletteGeometry geometry) {
    final delta = point - geometry.center;
    final distance = delta.distance;
    if (distance > geometry.radius) return;
    final hue = (delta.direction * 180 / math.pi) % 360;
    _select(_paletteColor(hue, geometry.saturationAt(distance)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: AppBottomSheetLayout(
        title: widget.title,
        actions: AppDialogActions(
          onCancel: () => Navigator.pop(context),
          onConfirm: () => Navigator.pop(context, _selected),
          confirmLabel: '使用此颜色',
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: _editHex,
              borderRadius: BorderRadius.circular(AppRadii.control),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.controlGap),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: AppMotion.standard,
                      width: AppSizes.colorPreview,
                      height: AppSizes.colorPreview,
                      decoration: BoxDecoration(
                        color: _selected,
                        shape: BoxShape.circle,
                        boxShadow: [AppShadows.emphasis(_selected)],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.componentGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('当前颜色'),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            appColorHex(_selected),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.edit_outlined,
                      size: AppSizes.iconAuxiliary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: colors.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: AppSpacing.componentGap,
                crossAxisSpacing: AppSpacing.componentGap,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                final color = colors[index];
                final selected = color.toARGB32() == _selected.toARGB32();
                return InkWell(
                  onTap: () => _select(color),
                  customBorder: const CircleBorder(),
                  child: AnimatedContainer(
                    duration: AppMotion.standard,
                    margin: const EdgeInsets.all(_colorSwatchSelectionInset),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      border: Border.all(
                        color: selected ? scheme.onSurface : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Text('自定义颜色', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.controlGap),
            SizedBox.square(
              dimension: _colorPaletteDiameter,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final geometry = _ColorPaletteGeometry(constraints.biggest);
                  return GestureDetector(
                    onTapDown: (details) =>
                        _pickFromPalette(details.localPosition, geometry),
                    onPanUpdate: (details) =>
                        _pickFromPalette(details.localPosition, geometry),
                    child: CustomPaint(
                      painter: _ColorPalettePainter(selected: _selected),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HexColorDialog extends StatefulWidget {
  const _HexColorDialog({required this.initial});

  final Color initial;

  @override
  State<_HexColorDialog> createState() => _HexColorDialogState();
}

class _HexColorDialogState extends State<_HexColorDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: appColorHex(widget.initial),
  );
  Color? _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: AppSpacing.dialogTitlePadding,
      contentPadding: AppSpacing.dialogContentPadding,
      actionsPadding: AppSpacing.dialogActionsPadding,
      title: const Text('输入 RGB 颜色'),
      content: TextField(
        autofocus: true,
        controller: _controller,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(
          hintText: '#FFFFFF',
          prefixIcon: Icon(Icons.tag_rounded),
        ),
        onChanged: (value) => setState(() => _value = parseAppColorHex(value)),
      ),
      actions: [
        AppDialogActions(
          onCancel: () => Navigator.pop(context),
          onConfirm: _value == null
              ? null
              : () => Navigator.pop(context, _value),
        ),
      ],
    );
  }
}

Color _paletteColor(double hue, double saturation) =>
    HSVColor.fromAHSV(1, hue, saturation, 1).toColor();

class _ColorPaletteGeometry {
  const _ColorPaletteGeometry(this.size);

  final Size size;

  Offset get center => size.center(Offset.zero);
  double get radius => size.shortestSide / 2;

  // Leave room for the whole indicator stroke at full saturation.
  double get selectionRadius => math.max(
    0.0,
    radius - _paletteIndicatorRadius - _paletteIndicatorStrokeWidth / 2,
  );

  double saturationAt(double distance) =>
      selectionRadius == 0 ? 0.0 : math.min(distance / selectionRadius, 1.0);
}

class _ColorPalettePainter extends CustomPainter {
  const _ColorPalettePainter({required this.selected});

  final Color selected;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = _ColorPaletteGeometry(size);
    final center = geometry.center;
    final radius = geometry.radius;
    final selectionRadius = geometry.selectionRadius;
    if (selectionRadius == 0) {
      canvas.drawCircle(center, radius, Paint()..color = Colors.white);
      return;
    }
    final rect = Rect.fromCircle(center: center, radius: radius);
    final hueColors = [
      for (var i = 0; i <= 360; i += 30) _paletteColor(i.toDouble(), 1),
    ];
    canvas.drawCircle(
      center,
      radius,
      Paint()..shader = SweepGradient(colors: hueColors).createShader(rect),
    );
    final lightnessPaint = Paint()
      ..shader = RadialGradient(
        radius: selectionRadius / rect.shortestSide,
        colors: [Colors.white, Colors.white.withAlpha(0)],
      ).createShader(rect);
    canvas.drawCircle(center, radius, lightnessPaint);
    final selection = HSVColor.fromColor(selected);
    final indicatorRadius = selectionRadius * selection.saturation;
    final angle = selection.hue * math.pi / 180;
    final indicator =
        center + Offset(math.cos(angle), math.sin(angle)) * indicatorRadius;
    final indicatorBackground = _paletteColor(
      selection.hue,
      selection.saturation,
    );
    final indicatorBrightness = ThemeData.estimateBrightnessForColor(
      indicatorBackground,
    );
    canvas.drawCircle(
      indicator,
      _paletteIndicatorRadius,
      Paint()
        ..color = indicatorBrightness == Brightness.light
            ? Colors.black
            : Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = _paletteIndicatorStrokeWidth,
    );
  }

  @override
  bool shouldRepaint(_ColorPalettePainter oldDelegate) =>
      oldDelegate.selected != selected;
}
