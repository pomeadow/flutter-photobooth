// Renders every finished widget to build/preview/*.png.
// Run with: flutter test test_preview
//
// Add a testWidgets block here whenever a step adds a visible widget.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_photobooth/config/templates.dart';
import 'package:flutter_photobooth/screens/title_screen.dart';

import '../test/support/fake_camera.dart';

import 'package:flutter_photobooth/services/composite_service.dart';
import 'package:flutter_photobooth/widgets/badge_label.dart';
import 'package:flutter_photobooth/widgets/decorative_button.dart';
import 'package:flutter_photobooth/theme/app_theme.dart';
import 'package:flutter_photobooth/widgets/design_canvas.dart';
import 'package:flutter_photobooth/widgets/flash_overlay.dart';
import 'package:flutter_photobooth/widgets/selectable_image.dart';
import 'package:flutter_photobooth/widgets/step_selector.dart';
import 'package:flutter_photobooth/widgets/themed_button.dart';
import 'package:flutter_test/flutter_test.dart';

import 'preview_helper.dart';

// Title previews render at 16:9 (1080p) and iPad; precache both variants.
final _backgrounds = [
  for (final v in AppBackgrounds.solid.variants)
    ResizeImage(AssetImage(v.asset), width: 2560),
];

void main() {
  setUpAll(loadPreviewFonts);

  testWidgets('step 3: decorative_button', (tester) async {
    await renderPreview(
      tester,
      name: 'decorative_button',
      child: Center(
        child: DecorativeButton(label: 'START', onPressed: () {}),
      ),
    );
  });

  testWidgets('step 4: themed_button', (tester) async {
    await renderPreview(
      tester,
      name: 'themed_button',
      screen: const Size(1100, 160),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ThemedButton(label: 'Print Photo', onPressed: () {}),
            const SizedBox(width: 24),
            ThemedButton(
              label: 'Start Over',
              onPressed: () {},
              size: ThemedButtonSize.compact,
            ),
            const SizedBox(width: 24),
            const ThemedButton(
              label: 'Next',
              onPressed: null,
              size: ThemedButtonSize.compact,
            ),
          ],
        ),
      ),
    );
  });

  testWidgets('step 5: badge_label', (tester) async {
    await renderPreview(
      tester,
      name: 'badge_label',
      screen: const Size(1400, 200),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BadgeLabel.counter(taken: 2, total: 4),
            const SizedBox(width: 24),
            BadgeLabel.timer(seconds: 10),
            const SizedBox(width: 24),
            BadgeLabel.timer(seconds: 3),
            const SizedBox(width: 24),
            BadgeLabel.timer(seconds: null),
          ],
        ),
      ),
    );
  });

  testWidgets('step 6: step_selector', (tester) async {
    await renderPreview(
      tester,
      name: 'step_selector',
      screen: const Size(900, 220),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // At min: − disabled.
            StepSelector(
              value: 2,
              min: 2,
              label: 'Number of prints',
              onChanged: (_) {},
            ),
            const SizedBox(width: 40),
            StepSelector(
              value: 6,
              min: 2,
              label: 'Number of prints',
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    );
  });

  testWidgets('step 7: flash_overlay filmstrip', (tester) async {
    // One tile per moment of the flash. Flashes are started in a staggered
    // order so that, at capture time, each tile is at its labelled moment.
    const moments = ['before', '0 ms', '75 ms', '150 ms', '225 ms'];
    final controllers = List.generate(moments.length, (_) => FlashController());

    Widget tile(int i) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FlashOverlay(
            controller: controllers[i],
            child: Container(
              width: 160,
              height: 120,
              color: Colors.blueGrey,
              alignment: Alignment.center,
              child: const Text(
                'camera',
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  color: Colors.white,
                  fontSize: 24,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(moments[i], style: AppText.label),
        ],
      ),
    );

    await renderPreview(
      tester,
      name: 'flash_overlay',
      screen: const Size(1000, 220),
      // Grey backdrop so the white flash is visible against the page.
      child: ColoredBox(
        color: const Color(0xFFDDDDDD),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (var i = 0; i < moments.length; i++) tile(i)],
          ),
        ),
      ),
      beforeCapture: (tester) async {
        // Start the latest moment first: 225 ms, then 150, 75, 0.
        // pump() right after flash() starts that flash's animation clock.
        for (var i = moments.length - 1; i >= 1; i--) {
          controllers[i].flash();
          await tester.pump();
          if (i > 1) await tester.pump(const Duration(milliseconds: 75));
        }
      },
    );
  });

  testWidgets('step 8: selectable_image + frame_swatch', (tester) async {
    // Real camera photos from the Python repo (6000×4000 JPGs).
    const photos = '/Users/chewyan/PROJECTS/py-photobooth/play2';
    // FileImage hangs on the test's fake clock, so read + shrink the photos
    // in real time first and hand the tiles in-memory images.
    final photoA = (await tester.runAsync(
      () => shrunkPhoto('$photos/DSC01105.JPG'),
    ))!;
    final photoB = (await tester.runAsync(
      () => shrunkPhoto('$photos/DSC01136.JPG'),
    ))!;
    // Must match what SelectableImage requests, so precache hits the cache.
    ImageProvider tileImage(ImageProvider p) =>
        ResizeImage(p, width: 600, policy: ResizeImagePolicy.fit);
    const colours = [
      Color(0xFF162D3E),
      Color(0xFF162D3E),
      Color(0xFF82151C),
      Color(0xFF82151C),
      Color(0xFF083F1F),
      Color(0xFF083F1F),
    ];

    await renderPreview(
      tester,
      name: 'selectable_image',
      screen: const Size(760, 480),
      precache: [tileImage(photoA), tileImage(photoB)],
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SelectableImage(image: photoA, selected: false, onTap: () {}),
                const SizedBox(width: 24),
                SelectableImage(image: photoB, selected: true, onTap: () {}),
              ],
            ),
            const SizedBox(height: 24),
            for (final orientation in ['horizontal', 'vertical']) ...[
              Row(
                children: [
                  for (var i = 1; i <= 6; i++) ...[
                    FrameSwatch(
                      // vertical 06 deliberately missing → fallback colour.
                      swatch: orientation == 'vertical' && i == 6
                          ? 'assets/swatches/missing.png'
                          : 'assets/swatches/swatch_${orientation}_0$i.png',
                      fallbackColor: colours[i - 1],
                      selected: i == 2,
                      onTap: () {},
                    ),
                    const SizedBox(width: 20),
                  ],
                  Text(orientation, style: AppText.label),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  });

  testWidgets('step 12: composites from real photos', (tester) async {
    const photos = '/Users/chewyan/PROJECTS/py-photobooth/play2';
    final service = CompositeService();
    late List<ui.Image> shown;
    final timings = <String>[];

    await tester.runAsync(() async {
      final catalog = await TemplateCatalog.load();
      Future<(ui.Image, ui.Image)> build(
        String name,
        FrameTemplate t,
        List<String> files,
      ) async {
        final watch = Stopwatch()..start();
        final composite = await service.compose(t, [
          for (final f in files) '$photos/$f',
        ]);
        final strip = await service.previewStrip(composite);
        final png = await service.encodePng(composite);
        timings.add('$name: ${watch.elapsedMilliseconds} ms');
        // Full-resolution output, exactly what would be printed.
        File('$previewDir/$name.png').writeAsBytesSync(png);
        return (composite, strip);
      }

      final (h, hStrip) = await build(
        'composite_2photos_horizontal_04',
        catalog.forSelectionCount(2)[3],
        ['DSC01105.JPG', 'DSC01136.JPG'],
      );
      final (v, vStrip) = await build(
        'composite_4photos_vertical_05',
        catalog.forSelectionCount(4)[4],
        ['DSC01105.JPG', 'DSC01136.JPG', 'DSC01189.JPG', 'DSC01200.JPG'],
      );
      // Cached decodes: switching frame colour on the selection screen.
      await build(
        'composite_2photos_horizontal_01_cached',
        catalog.forSelectionCount(2)[0],
        ['DSC01105.JPG', 'DSC01136.JPG'],
      );
      shown = [h, hStrip, v, vStrip];
    });
    File('$previewDir/composite_timings.txt')
        .writeAsStringSync(timings.join('\n'));

    Widget labelled(ui.Image image, String text, double height) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RawImage(
          image: image,
          height: height,
          filterQuality: FilterQuality.medium,
        ),
        const SizedBox(height: 6),
        Text(text, style: AppText.label.copyWith(fontSize: 18)),
      ],
    );

    await renderPreview(
      tester,
      name: 'composites',
      screen: const Size(1500, 520),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            labelled(shown[0], '2 photos: print', 300),
            const SizedBox(width: 16),
            labelled(shown[1], 'preview strip', 300),
            const SizedBox(width: 40),
            labelled(shown[2], '4 photos: print', 450),
            const SizedBox(width: 16),
            labelled(shown[3], 'preview strip', 450),
          ],
        ),
      ),
    );
    service.clearCache();
  });

  testWidgets('step 14: fake camera preview + synthetic photos', (
    tester,
  ) async {
    final camera = FakeCameraService(warmUp: Duration.zero);
    late List<MemoryImage> shots;
    await tester.runAsync(() async {
      await camera.start();
      shots = [
        for (var i = 0; i < 2; i++) MemoryImage((await camera.capture()).bytes),
      ];
    });

    Widget labelled(Widget child, String text) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 384, height: 216, child: child),
        const SizedBox(height: 6),
        Text(text, style: AppText.label.copyWith(fontSize: 18)),
      ],
    );

    await renderPreview(
      tester,
      name: 'fake_camera',
      screen: const Size(1300, 300),
      precache: shots,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            labelled(
              Builder(builder: camera.buildPreview),
              'preview (after 2 shots)',
            ),
            const SizedBox(width: 24),
            labelled(Image(image: shots[0]), 'capture 1'),
            const SizedBox(width: 24),
            labelled(Image(image: shots[1]), 'capture 2'),
          ],
        ),
      ),
    );
    camera.dispose();
  });

  // Screen previews go below; new widget/service previews go above this line.

  testWidgets('step 18: title screen at 1080p', (tester) async {
    await renderPreview(
      tester,
      name: 'title_screen_1080p',
      screen: const Size(1920, 1080),
      precache: _backgrounds,
      scale: 0.5,
      child: TitleScreen(onStart: () {}),
    );
  });

  testWidgets('step 18: title screen on iPad', (tester) async {
    await renderPreview(
      tester,
      name: 'title_screen_ipad',
      screen: const Size(1366, 1024),
      precache: _backgrounds,
      scale: 0.5,
      child: TitleScreen(onStart: () {}),
    );
  });
}
