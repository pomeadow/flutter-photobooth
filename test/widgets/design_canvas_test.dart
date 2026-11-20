import 'package:material_ui/material_ui.dart';
import 'package:flutter_photobooth/widgets/design_canvas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final screen in const [Size(1920, 1080), Size(1366, 1024)]) {
    testWidgets('child always gets 1920×1080 design pixels on $screen', (
      tester,
    ) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const key = Key('content');
      await tester.pumpWidget(
        const MaterialApp(
          home: DesignCanvas(child: SizedBox.expand(key: key)),
        ),
      );

      expect(tester.getSize(find.byKey(key)), DesignCanvas.size);
    });
  }

  group('background variant by screen shape', () {
    const bg = AppBackgrounds.solid;

    test('16:9 screens get the 16:9 export', () {
      expect(bg.forAspectRatio(1920 / 1080).aspectRatio, closeTo(16 / 9, 1e-9));
      // A 16:10 MacBook (1.60) is closer to the 1.63 original, which crops
      // less there (only a sliver at the sides, logo intact).
      expect(bg.forAspectRatio(1.6).asset, 'assets/ui/background_solid.png');
    });

    test('4:3 iPad gets the original 1.63:1 image', () {
      expect(
        bg.forAspectRatio(1366 / 1024).asset,
        'assets/ui/background_solid.png',
      );
    });

    for (final (screen, expected) in const [
      (Size(1920, 1080), 'assets/ui/background_solid-1920x1080.png'),
      (Size(1366, 1024), 'assets/ui/background_solid.png'),
    ]) {
      testWidgets('DesignCanvas shows $expected on $screen', (tester) async {
        tester.view.physicalSize = screen;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          const MaterialApp(
            home: DesignCanvas(background: bg, child: SizedBox()),
          ),
        );
        final image = tester.widget<Image>(find.byType(Image)).image;
        expect(
          ((image as ResizeImage).imageProvider as AssetImage).assetName,
          expected,
        );
      });
    }
  });
}
