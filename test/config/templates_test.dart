import 'package:flutter/services.dart';

import 'package:flutter_photobooth/config/templates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FrameLayout', () {
    test('filename rule: "horizontal" → 2×2 grid, else vertical strips', () {
      expect(
        FrameLayout.fromFileName(
          'assets/templates/Photo_Frame_HORIZONTAL_1.png',
        ),
        FrameLayout.grid2x2,
      );
      expect(
        FrameLayout.fromFileName(
          'assets/templates/photo_frame_vertical_01.png',
        ),
        FrameLayout.strip2x4,
      );
    });

    test('selection count → layout (2 → grid, 4 → strips, else none)', () {
      expect(FrameLayout.forSelectionCount(2), FrameLayout.grid2x2);
      expect(FrameLayout.forSelectionCount(4), FrameLayout.strip2x4);
      for (final n in [0, 1, 3, 5]) {
        expect(FrameLayout.forSelectionCount(n), isNull);
      }
    });

    test('slot tables match py-photobooth exactly', () {
      String fmt(FrameLayout l) =>
          l.slots.map((s) => '${s.x},${s.y},${s.width},${s.height}').join(' ');
      expect(
        fmt(FrameLayout.grid2x2),
        '40,40,840,540 40,620,840,540 920,40,840,540 920,620,840,540',
      );
      expect(
        fmt(FrameLayout.strip2x4),
        '50,85,500,333 50,475,500,333 50,865,500,333 50,1255,500,333 '
        '650,85,500,333 650,475,500,333 650,865,500,333 650,1255,500,333',
      );
    });

    test('every slot fits inside its frame', () {
      for (final layout in FrameLayout.values) {
        for (final slot in layout.slots) {
          expect(slot.x, greaterThanOrEqualTo(0));
          expect(slot.y, greaterThanOrEqualTo(0));
          expect(slot.right, lessThanOrEqualTo(layout.size.width));
          expect(slot.bottom, lessThanOrEqualTo(layout.size.height));
        }
      }
    });
  });

  group('TemplateCatalog.load (real assets)', () {
    late TemplateCatalog catalog;
    setUpAll(() async => catalog = await TemplateCatalog.load());

    test('finds all 12 frames, sorted by path', () {
      final paths = catalog.templates.map((t) => t.asset).toList();
      expect(paths.length, 12);
      expect(paths, [...paths]..sort());
    });

    test('2 photos → 6 horizontal frames, 4 photos → 6 vertical', () {
      final two = catalog.forSelectionCount(2);
      final four = catalog.forSelectionCount(4);
      expect(two.length, 6);
      expect(four.length, 6);
      expect(two.every((t) => t.asset.contains('horizontal')), isTrue);
      expect(four.every((t) => t.asset.contains('vertical')), isTrue);
      expect(two.first.asset, endsWith('horizontal_01.png'), reason: 'default');
      expect(catalog.forSelectionCount(3), isEmpty);
    });

    test('colours at (10,10) match the sampled values', () {
      const navy = Color(0xFF162D3E);
      const red = Color(0xFF82151C);
      const green = Color(0xFF083F1F);
      const byDesign = {1: navy, 2: navy, 3: red, 4: red, 5: green, 6: green};
      for (final t in catalog.templates) {
        expect(t.colour, byDesign[t.designNumber], reason: t.asset);
      }
    });

    test('design numbers and per-orientation swatch paths', () {
      String swatchOf(String suffix) => catalog.templates
          .firstWhere((t) => t.asset.endsWith(suffix))
          .swatchAsset;
      final v4 = catalog.templates.firstWhere(
        (t) => t.asset.endsWith('vertical_04.png'),
      );
      expect(v4.designNumber, 4);
      expect(
        swatchOf('vertical_04.png'),
        'assets/swatches/swatch_vertical_04.png',
      );
      expect(
        swatchOf('horizontal_01.png'),
        'assets/swatches/swatch_horizontal_01.png',
      );
    });

    test('every frame has its swatch image in the bundle', () async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest.listAssets().toSet();
      for (final t in catalog.templates) {
        expect(assets, contains(t.swatchAsset), reason: t.asset);
      }
    });
  });
}
