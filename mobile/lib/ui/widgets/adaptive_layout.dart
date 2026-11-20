import 'dart:ui' show DisplayFeature, DisplayFeatureType;

import 'package:material_ui/material_ui.dart';

/// Adaptive layout that supports portrait phones, narrow foldable cover screens,
/// landscape orientation, tablets, and dual-screen / foldable devices (Galaxy Z Fold,
/// Pixel Fold, Surface Duo) by detecting physical vertical hinges via
/// [MediaQuery.displayFeaturesOf] and placing panes cleanly on either side of the fold.
class AdaptiveTwoPaneLayout extends StatelessWidget {
  static const double wideBreakpoint = 680.0;
  static const double minHingeGutter = 16.0;
  static const double defaultTwoPaneGap = 20.0;

  final WidgetBuilder portraitBuilder;
  final WidgetBuilder leftPaneBuilder;
  final WidgetBuilder rightPaneBuilder;
  final EdgeInsetsGeometry padding;

  const AdaptiveTwoPaneLayout({
    super.key,
    required this.portraitBuilder,
    required this.leftPaneBuilder,
    required this.rightPaneBuilder,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 32),
  });

  /// Returns the vertical hinge or fold [Rect] when a foldable/dual-screen device
  /// splits the viewport left-to-right, or `null` otherwise.
  static Rect? findVerticalHinge(List<DisplayFeature> features, double viewportWidth) {
    for (final feature in features) {
      final isFoldOrHinge =
          feature.type == DisplayFeatureType.hinge || feature.type == DisplayFeatureType.fold;
      final bounds = feature.bounds;
      if (isFoldOrHinge &&
          bounds.height > bounds.width &&
          bounds.left > 0 &&
          bounds.right < viewportWidth) {
        return bounds;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final hinge = findVerticalHinge(mediaQuery.displayFeatures, screenWidth);

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;

          if (hinge != null) {
            final safeLeftInset = mediaQuery.padding.left;
            final leftWidth = (hinge.left - safeLeftInset).clamp(160.0, maxWidth - 160.0);
            final gutterWidth = hinge.width < minHingeGutter ? minHingeGutter : hinge.width;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: leftWidth,
                  child: SingleChildScrollView(
                    padding: padding,
                    child: leftPaneBuilder(context),
                  ),
                ),
                SizedBox(width: gutterWidth),
                Expanded(
                  child: SingleChildScrollView(
                    padding: padding,
                    child: rightPaneBuilder(context),
                  ),
                ),
              ],
            );
          }

          if (maxWidth >= wideBreakpoint) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 48,
                  child: SingleChildScrollView(
                    padding: padding,
                    child: leftPaneBuilder(context),
                  ),
                ),
                const SizedBox(width: defaultTwoPaneGap),
                Expanded(
                  flex: 52,
                  child: SingleChildScrollView(
                    padding: padding,
                    child: rightPaneBuilder(context),
                  ),
                ),
              ],
            );
          }

          return SingleChildScrollView(
            padding: padding,
            child: portraitBuilder(context),
          );
        },
      ),
    );
  }
}
