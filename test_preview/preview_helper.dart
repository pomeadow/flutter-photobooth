// Shared helper for rendering widgets to PNGs in build/preview/.
//
// Lives outside test/ so `flutter test` doesn't run it with the unit tests.
// Run with: flutter test test_preview
import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String previewDir = 'build/preview';

/// Loads the macOS system Impact font so previews show the real font
/// (flutter test otherwise renders text with a placeholder font).
Future<void> loadPreviewFonts() async {
  const impact = '/System/Library/Fonts/Supplemental/Impact.ttf';
  if (File(impact).existsSync()) {
    final loader = FontLoader('Impact')
      ..addFont(
        Future.value(ByteData.sublistView(File(impact).readAsBytesSync())),
      );
    await loader.load();
  }
  final dynaPuff = File('assets/fonts/DynaPuff.ttf');
  final loader = FontLoader('DynaPuff')
    ..addFont(Future.value(ByteData.sublistView(dynaPuff.readAsBytesSync())));
  await loader.load();
}

/// Renders [child] on a [screen]-sized surface and writes
/// `build/preview/<name>.png`.
///
/// [precache] lists image providers (e.g. backgrounds) to load first, so they
/// appear in the render. [scale] shrinks the output PNG (0.5 for full screens).
/// [beforeCapture] runs just before the snapshot — use it to trigger and pump
/// animations (e.g. a flash) to a specific moment.
Future<void> renderPreview(
  WidgetTester tester, {
  required String name,
  required Widget child,
  Size screen = const Size(1000, 200),
  List<ImageProvider> precache = const [],
  double scale = 1,
  Future<void> Function(WidgetTester tester)? beforeCapture,
}) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(
        key: key,
        child: Material(color: Colors.white, child: child),
      ),
    ),
  );

  if (precache.isNotEmpty) {
    await tester.runAsync(() async {
      for (final image in precache) {
        await precacheImage(image, key.currentContext!);
      }
    });
    await tester.pump();
  }

  if (beforeCapture != null) await beforeCapture(tester);

  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: scale);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(previewDir).createSync(recursive: true);
    File('$previewDir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });

  // Let any animations started for the snapshot finish cleanly.
  await tester.pumpAndSettle();
}

/// Reads a (possibly huge) photo from disk and returns it re-encoded at most
/// [width] px wide as an in-memory image. Call inside `tester.runAsync`:
/// `FileImage` never completes on the widget-test fake clock.
Future<MemoryImage> shrunkPhoto(String path, {int width = 600}) async {
  final codec = await ui.instantiateImageCodec(
    File(path).readAsBytesSync(),
    targetWidth: width,
  );
  final image = (await codec.getNextFrame()).image;
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return MemoryImage(png!.buffer.asUint8List());
}
