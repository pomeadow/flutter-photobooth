// Smoke test for the app shell (replaces the template counter test).
import 'dart:io';

import 'package:flutter_photobooth/app.dart';
import 'package:flutter_photobooth/config/templates.dart';
import 'package:flutter_photobooth/services/composite_service.dart';
import 'package:flutter_photobooth/services/printer_service.dart';

import 'support/fake_camera.dart';

import 'package:flutter_photobooth/services/session_service.dart';
import 'package:flutter_photobooth/services/sound_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'screens/camera_screen_test.dart' show LogEffect;

void main() {
  testWidgets('app opens on the title screen', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final sounds = SoundService(createEffect: () => LogEffect([]));
    await sounds.load();
    await tester.pumpWidget(
      PhotoboothApp(
        camera: FakeCameraService(warmUp: Duration.zero),
        session: SessionService(root: Directory.systemTemp),
        sounds: sounds,
        catalog: TemplateCatalog([]),
        composer: CompositeService(),
        printer: MockPrinterService(),
      ),
    );
    expect(find.text('START'), findsOneWidget);
    // Let the camera warm-up timer run before the test ends.
    await tester.pump(const Duration(milliseconds: 50));
  });

  test('debug/test builds use the mock printer (no SELPHY needed)', () {
    expect(printerChoice, 'mock');
    expect(createPrinter(), isA<MockPrinterService>());
  });
}
