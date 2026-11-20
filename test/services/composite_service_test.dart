import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_photobooth/config/templates.dart';
import 'package:flutter_photobooth/services/composite_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const red = Color(0xFFFF0000);
const green = Color(0xFF00FF00);
const blue = Color(0xFF0000FF);
const yellow = Color(0xFFFFFF00);

late Directory tmp;
late TemplateCatalog catalog;
late CompositeService service;

/// Writes a PNG of [size] made of equal-width vertical [bands].
Future<String> photo(String name, Size size, List<Color> bands) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final bandW = size.width / bands.length;
  for (var i = 0; i < bands.length; i++) {
    canvas.drawRect(
      Rect.fromLTWH(i * bandW, 0, bandW, size.height),
      Paint()..color = bands[i],
    );
  }
  final image = await recorder.endRecording().toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final path = p.join(tmp.path, '$name.png');
  await File(path).writeAsBytes(png!.buffer.asUint8List());
  return path;
}

Future<Color Function(int x, int y)> pixels(ui.Image image) async {
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return (x, y) {
    final i = (y * image.width + x) * 4;
    return Color.fromARGB(
      rgba.getUint8(i + 3),
      rgba.getUint8(i),
      rgba.getUint8(i + 1),
      rgba.getUint8(i + 2),
    );
  };
}

Color centreOf(Color Function(int, int) px, PhotoSlot s) =>
    px(s.x + s.width ~/ 2, s.y + s.height ~/ 2);

FrameTemplate first(FrameLayout layout) =>
    catalog.templates.firstWhere((t) => t.layout == layout);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('composite_test_');
    catalog = await TemplateCatalog.load();
  });
  setUp(() => service = CompositeService());
  tearDown(() => service.clearCache());
  tearDownAll(() => tmp.delete(recursive: true));

  test('2 photos → horizontal 1800×1200, slots p1,p2,p1,p2', () async {
    final template = first(FrameLayout.grid2x2);
    final paths = [
      await photo('red', const Size(600, 400), [red]),
      await photo('blue', const Size(600, 400), [blue]),
    ];

    final image = await service.compose(template, paths);
    expect([image.width, image.height], [1800, 1200]);

    final px = await pixels(image);
    expect(template.slots.map((s) => centreOf(px, s)).toList(), [
      red,
      blue,
      red,
      blue,
    ]);
    expect(px(10, 10), template.colour, reason: 'frame visible outside slots');
    image.dispose();
  });

  test('4 photos → vertical 1200×1800, both strips p1…p4', () async {
    final template = first(FrameLayout.strip2x4);
    final colours = [red, green, blue, yellow];
    final paths = [
      for (var i = 0; i < 4; i++)
        await photo('c$i', const Size(600, 400), [colours[i]]),
    ];

    final image = await service.compose(template, paths);
    expect([image.width, image.height], [1200, 1800]);

    final px = await pixels(image);
    expect(template.slots.map((s) => centreOf(px, s)).toList(), [
      ...colours,
      ...colours,
    ]);
    image.dispose();
  });

  test(
    'cover-crop: wide photo is scaled to height and centre-cropped',
    () async {
      // 3000×1000 red|green|blue into an 840×540 slot: scale 0.54, keeps the
      // middle 1556 px → ~150 px red, 540 green, ~150 blue across the slot.
      final template = first(FrameLayout.grid2x2);
      final path = await photo('rgb', const Size(3000, 1000), [
        red,
        green,
        blue,
      ]);

      final image = await service.compose(template, [path]);
      final px = await pixels(image);
      final s = template.slots.first;
      final midY = s.y + s.height ~/ 2;
      expect(px(s.x + 20, midY), red);
      expect(px(s.x + s.width ~/ 2, midY), green);
      expect(px(s.right - 20, midY), blue);
      expect(
        px(s.x + 200, midY),
        green,
        reason: 'red band is ~150 px, not more',
      );
      image.dispose();
    },
  );

  test('small photo is upscaled to fill the slot edge to edge', () async {
    final template = first(FrameLayout.grid2x2);
    final path = await photo('tiny', const Size(80, 60), [green]);

    final image = await service.compose(template, [path]);
    final px = await pixels(image);
    final s = template.slots.first;
    for (final (x, y) in [
      (s.x + 2, s.y + 2),
      (s.right - 3, s.y + 2),
      (s.x + 2, s.bottom - 3),
      (s.right - 3, s.bottom - 3),
    ]) {
      expect(px(x, y), green, reason: 'corner ($x, $y)');
    }
    image.dispose();
  });

  test('coverCrop matches Python _resize_photo_to_slot', () {
    final crop = CompositeService.coverCrop(
      const Size(6000, 4000),
      const Size(500, 333),
    );
    // scale = max(500/6000, 333/4000) = 0.08333 → keep 6000×3996, centred.
    expect(crop.width, closeTo(6000, 0.5));
    expect(crop.height, closeTo(3996, 0.5));
    expect(crop.left, closeTo(0, 0.5));
    expect(crop.top, closeTo(2, 0.5));
  });

  test('preview strip is the left half of the composite', () async {
    final template = first(FrameLayout.grid2x2);
    final paths = [
      await photo('r', const Size(600, 400), [red]),
      await photo('b', const Size(600, 400), [blue]),
    ];
    final composite = await service.compose(template, paths);
    final strip = await service.previewStrip(composite);
    expect([strip.width, strip.height], [900, 1200]);

    final full = await pixels(composite);
    final half = await pixels(strip);
    for (final (x, y) in [(10, 10), (400, 300), (400, 900), (899, 1199)]) {
      expect(half(x, y), full(x, y), reason: '($x, $y)');
    }
    composite.dispose();
    strip.dispose();
  });

  test('PNG output declares 300 DPI and still decodes', () async {
    final template = first(FrameLayout.grid2x2);
    final path = await photo('g', const Size(600, 400), [green]);
    final image = await service.compose(template, [path]);
    final png = await service.encodePng(image);

    // pHYs right after IHDR: 11811 px/m both axes, unit 1.
    final view = ByteData.sublistView(png);
    expect(String.fromCharCodes(png, 37, 41), 'pHYs');
    expect(view.getUint32(41), 11811);
    expect(view.getUint32(45), 11811);
    expect(png[49], 1);

    final codec = await ui.instantiateImageCodec(png);
    final decoded = (await codec.getNextFrame()).image;
    expect([decoded.width, decoded.height], [1800, 1200]);
    image.dispose();
  });

  test('withDpi replaces an existing pHYs rather than duplicating', () async {
    final template = first(FrameLayout.grid2x2);
    final path = await photo('g2', const Size(60, 40), [green]);
    final image = await service.compose(template, [path]);
    final once = await service.encodePng(image, dpi: 72);
    final twice = CompositeService.withDpi(once, 300);

    final text = String.fromCharCodes(twice);
    expect('pHYs'.allMatches(text).length, 1);
    expect(ByteData.sublistView(twice).getUint32(41), 11811);
    image.dispose();
  });

  test('empty photo list is rejected', () {
    expect(
      () => service.compose(first(FrameLayout.grid2x2), []),
      throwsArgumentError,
    );
  });
}
