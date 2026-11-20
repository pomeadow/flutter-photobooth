import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_photobooth/services/gif_service.dart';
import 'package:flutter_photobooth/services/session_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

const red = Color(0xFFFF0000);
const green = Color(0xFF00FF00);
const blue = Color(0xFF0000FF);
const yellow = Color(0xFFFFFF00);

late Directory tmp;

/// Solid-colour PNG photo of [w]×[h].
Future<String> photo(
  String name,
  Color colour, {
  int w = 1920,
  int h = 1080,
}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = colour,
  );
  final image = await recorder.endRecording().toImage(w, h);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final path = p.join(tmp.path, '$name.png');
  await File(path).writeAsBytes(png!.buffer.asUint8List());
  return path;
}

/// Raw frame delays (1/100 s) from each Graphic Control Extension
/// (`0x21 0xF9 0x04 flags delay-LE16 …`) — what GIF viewers actually use.
List<int> rawDelays(Uint8List gif) => [
  for (var i = 0; i + 5 < gif.length; i++)
    if (gif[i] == 0x21 && gif[i + 1] == 0xF9 && gif[i + 2] == 0x04)
      gif[i + 4] | (gif[i + 5] << 8),
];

/// Dominant channel of a frame's centre pixel: 'r', 'g', 'b' or 'y'.
String centreColour(img.Image frame) {
  final px = frame.getPixel(frame.width ~/ 2, frame.height ~/ 2);
  final r = px.r > 128, g = px.g > 128, b = px.b > 128;
  if (r && g && !b) return 'y';
  if (r) return 'r';
  if (g) return 'g';
  if (b) return 'b';
  return '?';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const gifs = GifService();

  setUpAll(
    () async => tmp = await Directory.systemTemp.createTemp('gif_test_'),
  );
  tearDownAll(() => tmp.delete(recursive: true));

  test('4 photos → 640×360 looping GIF, frames in order, 0.5 s each', () async {
    final paths = [
      await photo('a', red),
      await photo('b', green),
      await photo('c', blue),
      await photo('d', yellow),
    ];
    final bytes = await gifs.create(paths);

    expect(String.fromCharCodes(bytes.sublist(0, 6)), 'GIF89a');
    expect(
      String.fromCharCodes(bytes),
      contains('NETSCAPE2.0'),
      reason: 'loop extension',
    );

    final gif = img.decodeGif(bytes)!;
    expect([gif.width, gif.height], [640, 360]);
    expect(gif.numFrames, 4);
    expect([for (final f in gif.frames) centreColour(f)], ['r', 'g', 'b', 'y']);
    // The decoder reports ms; the file stores 1/100 s.
    expect(gif.frames.first.frameDuration, 500);
    expect(rawDelays(bytes), [50, 50, 50, 50]);
  });

  test('boomerang plays 1→4 then 3→2', () async {
    final paths = [
      await photo('r', red),
      await photo('g', green),
      await photo('b', blue),
      await photo('y', yellow),
    ];
    final gif = img.decodeGif(
      await gifs.create(paths, options: const GifOptions(boomerang: true)),
    )!;
    expect(
      [for (final f in gif.frames) centreColour(f)],
      ['r', 'g', 'b', 'y', 'b', 'g'],
    );
  });

  test('options: width, speed, play once', () async {
    final paths = [await photo('w1', red), await photo('w2', blue)];
    final bytes = await gifs.create(
      paths,
      options: const GifOptions(
        width: 320,
        frameDelay: Duration(milliseconds: 1000),
        loop: false,
      ),
    );
    final gif = img.decodeGif(bytes)!;
    expect([gif.width, gif.height], [320, 180]);
    expect(gif.frames.first.frameDuration, 1000);
    expect(rawDelays(bytes), [100, 100]);
    expect(String.fromCharCodes(bytes), isNot(contains('NETSCAPE2.0')));
    expect(gif.numFrames, 2, reason: 'still a valid 2-frame GIF');
  });

  test(
    'photos of a different shape are centre-cropped to one frame size',
    () async {
      final paths = [
        await photo('wide', red),
        await photo('square', green, w: 800, h: 800),
      ];
      final gif = img.decodeGif(await gifs.create(paths))!;
      expect(gif.numFrames, 2);
      for (final f in gif.frames) {
        expect([f.width, f.height], [640, 360]);
      }
    },
  );

  test('empty list is rejected', () {
    expect(() => gifs.create([]), throwsArgumentError);
  });

  test(
    'SessionService.saveGif names it animation_*.gif; not listed as a photo',
    () async {
      final root = await Directory.systemTemp.createTemp('gif_session_');
      addTearDown(() => root.delete(recursive: true));
      final session = SessionService(
        root: root,
        clock: () => DateTime(2026, 11, 21, 10, 30, 5),
      );
      await session.createSession();
      final a = await session.saveGif(Uint8List.fromList([1]));
      final b = await session.saveGif(Uint8List.fromList([2]));
      expect(p.basename(a.path), 'animation_20261121_103005.gif');
      expect(p.basename(b.path), 'animation_20261121_103005_2.gif');
      expect(await session.listPhotos(), isEmpty);
    },
  );
}
