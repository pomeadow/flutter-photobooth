import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// A photo slot in a frame, in frame pixels (300 DPI).
class PhotoSlot {
  const PhotoSlot(this.x, this.y, this.width, this.height);

  final int x;
  final int y;
  final int width;
  final int height;

  int get right => x + width;
  int get bottom => y + height;

  @override
  String toString() => 'PhotoSlot($x, $y, $width×$height)';
}

/// The two frame layouts. Slot tables are copied exactly from py-photobooth
/// `config/load_metadata.py` — do not "tidy" them.
enum FrameLayout {
  /// Horizontal frame, 1800×1200, 2×2 grid. Used when **2** photos are
  /// selected: slots get p1, p2, p1, p2 (left column = right column).
  grid2x2(
    photosToSelect: 2,
    displayText: '2 x 2',
    size: Size(1800, 1200),
    slots: [
      PhotoSlot(40, 40, 840, 540), // top-left
      PhotoSlot(40, 620, 840, 540), // bottom-left
      PhotoSlot(920, 40, 840, 540), // top-right
      PhotoSlot(920, 620, 840, 540), // bottom-right
    ],
  ),

  /// Vertical frame, 1200×1800, two identical 4-photo strips (the print is
  /// cut in half). Used when **4** photos are selected.
  strip2x4(
    photosToSelect: 4,
    displayText: '2 x 4',
    size: Size(1200, 1800),
    slots: [
      PhotoSlot(50, 85, 500, 333),
      PhotoSlot(50, 475, 500, 333),
      PhotoSlot(50, 865, 500, 333),
      PhotoSlot(50, 1255, 500, 333),
      PhotoSlot(650, 85, 500, 333),
      PhotoSlot(650, 475, 500, 333),
      PhotoSlot(650, 865, 500, 333),
      PhotoSlot(650, 1255, 500, 333),
    ],
  );

  const FrameLayout({
    required this.photosToSelect,
    required this.displayText,
    required this.size,
    required this.slots,
  });

  /// "horizontal" or "vertical" — matches the frame and swatch filenames.
  String get orientation => this == grid2x2 ? 'horizontal' : 'vertical';

  /// How many photos the guest selects to use this layout.
  final int photosToSelect;
  final String displayText;

  /// Expected frame image size in pixels.
  final Size size;
  final List<PhotoSlot> slots;

  /// Python rule: a filename containing "horizontal" is the 2×2 grid,
  /// anything else is the vertical strip.
  static FrameLayout fromFileName(String path) =>
      path.toLowerCase().contains('horizontal') ? grid2x2 : strip2x4;

  /// Layout for a selection count, or null if the count isn't 2 or 4.
  static FrameLayout? forSelectionCount(int count) {
    for (final layout in values) {
      if (layout.photosToSelect == count) return layout;
    }
    return null;
  }
}

/// One frame image plus everything the app needs to know about it.
class FrameTemplate {
  const FrameTemplate({
    required this.asset,
    required this.layout,
    required this.designNumber,
    required this.colour,
  });

  /// e.g. `assets/templates/photo_frame_vertical_02.png`.
  final String asset;
  final FrameLayout layout;

  /// The trailing number (1–6). Horizontal and vertical frames with the same
  /// number share a design (colour + pattern).
  final int designNumber;

  /// Pixel (10,10) — the frame's main colour. Swatch fallback.
  final Color colour;

  List<PhotoSlot> get slots => layout.slots;

  /// Swatch image for the frame picker, per orientation:
  /// `assets/swatches/swatch_{horizontal|vertical}_0N.png` (120×120).
  String get swatchAsset =>
      'assets/swatches/swatch_${layout.orientation}_'
      '${designNumber.toString().padLeft(2, '0')}.png';

  @override
  String toString() => 'FrameTemplate($asset, ${layout.name}, $colour)';
}

/// All frames found in [directory], sorted by path (as Python did).
///
/// Load once at startup with [TemplateCatalog.load].
class TemplateCatalog {
  TemplateCatalog(List<FrameTemplate> templates)
    : templates = List.unmodifiable(templates);

  static const String directory = 'assets/templates/';

  /// Pixel sampled for each frame's colour (py-photobooth used (10,10)).
  static const Offset colourPixel = Offset(10, 10);

  final List<FrameTemplate> templates;

  /// Frames usable for [count] selected photos, in path order. The first is
  /// the default. Empty if [count] isn't 2 or 4.
  List<FrameTemplate> forSelectionCount(int count) {
    final layout = FrameLayout.forSelectionCount(count);
    return [
      for (final t in templates)
        if (t.layout == layout) t,
    ];
  }

  /// Finds every `*.png` under [directory] in the asset bundle, checks its
  /// size matches its layout, and samples its colour.
  ///
  /// Throws [StateError] with a clear message if a frame is the wrong size
  /// (e.g. a designer exported a replacement at the wrong resolution), since
  /// the hard-coded slots would then land in the wrong place.
  static Future<TemplateCatalog> load([AssetBundle? bundle]) async {
    bundle ??= rootBundle;
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    final paths =
        manifest
            .listAssets()
            .where((p) => p.startsWith(directory) && p.endsWith('.png'))
            .toList()
          ..sort();

    final templates = <FrameTemplate>[];
    for (final path in paths) {
      final layout = FrameLayout.fromFileName(path);
      final data = await bundle.load(path);
      final image = await _decode(data);
      try {
        final actual = Size(image.width.toDouble(), image.height.toDouble());
        if (actual != layout.size) {
          throw StateError(
            '$path is ${image.width}×${image.height}, but the '
            '${layout.name} layout needs '
            '${layout.size.width.toInt()}×${layout.size.height.toInt()}.',
          );
        }
        templates.add(
          FrameTemplate(
            asset: path,
            layout: layout,
            designNumber: _designNumber(path),
            colour: await _pixel(image, colourPixel),
          ),
        );
      } finally {
        image.dispose();
      }
    }
    return TemplateCatalog(templates);
  }

  static int _designNumber(String path) {
    final match = RegExp(r'(\d+)\.png$').firstMatch(path);
    if (match == null) {
      throw StateError('$path has no trailing design number (e.g. _01.png).');
    }
    return int.parse(match.group(1)!);
  }

  static Future<ui.Image> _decode(ByteData data) async {
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  static Future<Color> _pixel(ui.Image image, Offset at) async {
    final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final i = (at.dy.toInt() * image.width + at.dx.toInt()) * 4;
    return Color.fromARGB(
      255,
      rgba.getUint8(i),
      rgba.getUint8(i + 1),
      rgba.getUint8(i + 2),
    );
  }
}
