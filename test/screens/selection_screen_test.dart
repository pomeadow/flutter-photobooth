import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_photobooth/config/templates.dart';
import 'package:flutter_photobooth/screens/selection_screen.dart';
import 'package:flutter_photobooth/widgets/selectable_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

FrameTemplate frame(String orientation, int n) => FrameTemplate(
  asset: 'assets/templates/photo_frame_${orientation}_0$n.png',
  layout: orientation == 'horizontal'
      ? FrameLayout.grid2x2
      : FrameLayout.strip2x4,
  designNumber: n,
  colour: const Color(0xFF162D3E),
);

final catalog = TemplateCatalog([
  for (final o in ['horizontal', 'vertical'])
    for (var n = 1; n <= 3; n++) frame(o, n),
]);

const photos = ['p1.jpg', 'p2.jpg', 'p3.jpg', 'p4.jpg'];

/// 1×1 image, created synchronously (no async engine work in widget tests).
ui.Image tinyImage() {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 1, 1),
    Paint()..color = const Color(0xFFFF0000),
  );
  return recorder.endRecording().toImageSync(1, 1);
}

void main() {
  late List<({String frame, List<String> photos})> previews;
  late List<Selection> nexts;
  late int startOvers;
  Completer<void>? gate;

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    previews = [];
    nexts = [];
    startOvers = 0;
    gate = null;

    await tester.pumpWidget(
      MaterialApp(
        home: SelectionScreen(
          photoPaths: photos,
          catalog: catalog,
          imageFor: (_) => MemoryImage(Uint8List.fromList(kTransparentImage)),
          buildPreview: (t, p) async {
            previews.add((frame: t.asset.split('/').last, photos: p));
            if (gate != null) await gate!.future;
            return tinyImage();
          },
          onNext: nexts.add,
          onStartOver: () => startOvers++,
        ),
      ),
    );
  }

  Finder tile(String path) => find.byKey(ValueKey(path));

  Future<void> tap(WidgetTester tester, String path) async {
    await tester.tap(tile(path));
    await tester.pump();
    await tester.pump();
  }

  bool nextEnabled(WidgetTester tester) => tester
      .widget<TextButton>(
        find.ancestor(of: find.text('Next'), matching: find.byType(TextButton)),
      )
      .enabled;

  testWidgets('shows all photos; Next disabled until a valid selection', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.byType(SelectableImage), findsNWidgets(4));
    expect(find.text('Select 2 or all 4 photos'), findsOneWidget);
    expect(nextEnabled(tester), isFalse);

    await tap(tester, 'p1.jpg');
    expect(previews, isEmpty, reason: '1 photo is not a valid count');
    expect(nextEnabled(tester), isFalse);
  });

  testWidgets('2 photos → first horizontal frame, in tap order', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tap(tester, 'p3.jpg');
    await tap(tester, 'p1.jpg');
    expect(previews.single.frame, 'photo_frame_horizontal_01.png');
    expect(previews.single.photos, ['p3.jpg', 'p1.jpg']);
    expect(nextEnabled(tester), isTrue);

    await tester.tap(find.text('Next'));
    expect(nexts.single.photos, ['p3.jpg', 'p1.jpg']);
    expect(nexts.single.template.layout, FrameLayout.grid2x2);
  });

  testWidgets('4 photos → first vertical frame; 3 → no preview', (
    tester,
  ) async {
    await pumpScreen(tester);
    for (final p in photos.take(3)) {
      await tap(tester, p);
    }
    expect(nextEnabled(tester), isFalse, reason: '3 photos');
    await tap(tester, 'p4.jpg');
    expect(previews.last.frame, 'photo_frame_vertical_01.png');
    expect(previews.last.photos, photos);
    expect(nextEnabled(tester), isTrue);
  });

  testWidgets('tapping a swatch switches frame and rebuilds the preview', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tap(tester, 'p1.jpg');
    await tap(tester, 'p2.jpg');
    await tester.tap(find.bySemanticsLabel('Frame 3'));
    await tester.pump();
    await tester.pump();
    expect(previews.last.frame, 'photo_frame_horizontal_03.png');

    await tester.tap(find.text('Next'));
    expect(nexts.single.template.designNumber, 3);
  });

  testWidgets('deselecting back to 1 clears the preview', (tester) async {
    await pumpScreen(tester);
    await tap(tester, 'p1.jpg');
    await tap(tester, 'p2.jpg');
    expect(nextEnabled(tester), isTrue);
    await tap(tester, 'p2.jpg');
    expect(nextEnabled(tester), isFalse);
    expect(find.text('Pick your photos'), findsOneWidget);
  });

  testWidgets('Next stays disabled while the preview is being built', (
    tester,
  ) async {
    await pumpScreen(tester);
    gate = Completer<void>();
    await tap(tester, 'p1.jpg');
    await tap(tester, 'p2.jpg');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(nextEnabled(tester), isFalse);

    gate!.complete();
    await tester.pump();
    await tester.pump();
    expect(nextEnabled(tester), isTrue);
  });

  testWidgets('initialSelection restores picks and frame (Back from print)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final built = <String>[];
    Selection? next;
    await tester.pumpWidget(
      MaterialApp(
        home: SelectionScreen(
          photoPaths: photos,
          catalog: catalog,
          imageFor: (_) => MemoryImage(Uint8List.fromList(kTransparentImage)),
          initialSelection: Selection(
            photos: const ['p2.jpg', 'p4.jpg'],
            template: catalog.forSelectionCount(2)[2],
          ),
          buildPreview: (t, p) async {
            built.add(t.asset.split('/').last);
            return tinyImage();
          },
          onNext: (s) => next = s,
          onStartOver: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(built, ['photo_frame_horizontal_03.png']);

    await tester.tap(find.text('Next'));
    expect(next!.photos, ['p2.jpg', 'p4.jpg']);
    expect(next!.template.designNumber, 3);
  });

  testWidgets('Start Over calls onStartOver', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Start Over'));
    expect(startOvers, 1);
  });
}

/// 1×1 transparent PNG.
const kTransparentImage = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
