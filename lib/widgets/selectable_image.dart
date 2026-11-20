import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

const _selectedBorder = BorderSide(color: AppColors.gold, width: 5);

/// Tap-to-toggle photo tile for the selection screen's 2×2 grid.
///
/// Port of py-photobooth `components/clickable_label.py` as used in
/// `ui/selection_screen.py`: 300×225, photo aspect-fit, 5 px gold border when
/// selected. The border is drawn *over* the photo so the photo never shifts.
///
/// [image] is decoded at most [decodeWidth] px wide — camera photos can be
/// 6000×4000, far more than a 300 px tile needs.
class SelectableImage extends StatelessWidget {
  const SelectableImage({
    super.key,
    required this.image,
    required this.selected,
    required this.onTap,
    this.width = 300,
    this.height = 225,
    this.decodeWidth = 600,
  });

  final ImageProvider image;
  final bool selected;
  final VoidCallback onTap;
  final double width;
  final double height;
  final int decodeWidth;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: selected ? 'Selected photo' : 'Photo',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: width,
            height: height,
            foregroundDecoration: selected
                ? const BoxDecoration(
                    border: Border.fromBorderSide(_selectedBorder),
                  )
                : null,
            child: Image(
              image: ResizeImage(
                image,
                width: decodeWidth,
                policy: ResizeImagePolicy.fit,
              ),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular frame picker for the selection screen.
///
/// Shows a designer-provided swatch image (120×120, masked to a circle) so
/// frames with the same colour but different patterns (navy stars vs navy
/// snowflakes) look different. Get the path from `FrameTemplate.swatchAsset`.
///
/// [fallbackColor] sits behind the image: it shows through transparent areas
/// of the swatch, and fills the whole circle if the image is missing or fails
/// to load (the py-photobooth look).
///
/// Selected = 5 px gold ring, as in Python.
class FrameSwatch extends StatelessWidget {
  const FrameSwatch({
    super.key,
    required this.swatch,
    required this.fallbackColor,
    required this.selected,
    required this.onTap,
    this.diameter = 60,
    this.semanticLabel,
  });

  /// Asset path of the swatch image (`FrameTemplate.swatchAsset`).
  final String swatch;

  /// Frame colour (sampled at pixel 10,10) used if [swatch] can't load.
  final Color fallbackColor;
  final bool selected;
  final VoidCallback onTap;
  final double diameter;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel ?? 'Frame',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: diameter,
            height: diameter,
            foregroundDecoration: selected
                ? const ShapeDecoration(
                    shape: CircleBorder(side: _selectedBorder),
                  )
                : null,
            child: ClipOval(
              child: ColoredBox(
                // Shown behind the image while loading, and if it fails.
                color: fallbackColor,
                child: Image.asset(
                  swatch,
                  width: diameter,
                  height: diameter,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) => const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
