import 'package:flutter/material.dart';

/// Shared visual spacing scale for pages and reusable components.
///
/// Structural sizes such as chart heights, grid cell extents and minimum touch
/// targets intentionally live with their owning widgets instead of here.
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  static const double pageHorizontal = md;
  static const double pageTop = xxs;
  static const double pageBottom = lg;
  static const double componentGap = sm;
  static const double controlGap = xs;
  static const double segmentedTrackInset = xxs;
  static const double tabIndicatorInset = segmentedTrackInset / 2;

  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(
    pageHorizontal,
    pageTop,
    pageHorizontal,
    pageBottom,
  );
  static const EdgeInsets cardPadding = EdgeInsets.all(md);
  static const EdgeInsets compactCardPadding = EdgeInsets.all(sm);
  static const EdgeInsets sheetPadding = EdgeInsets.fromLTRB(md, 0, md, md);
  static const EdgeInsets bottomActionPadding = EdgeInsets.fromLTRB(
    md,
    xs,
    md,
    md,
  );
  static const EdgeInsets dialogTitlePadding = EdgeInsets.fromLTRB(
    lg,
    lg,
    lg,
    0,
  );
  static const EdgeInsets dialogContentPadding = EdgeInsets.fromLTRB(
    lg,
    sm,
    lg,
    0,
  );
  static const EdgeInsets dialogActionsPadding = EdgeInsets.all(lg);
}
