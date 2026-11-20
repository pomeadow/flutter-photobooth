import 'dart:typed_data';

import 'package:flutter_photobooth/screens/camera_screen.dart';
import 'package:flutter_photobooth/services/camera/camera_service.dart';
import 'package:flutter_photobooth/services/sound_service.dart';
import 'package:flutter_photobooth/widgets/badge_label.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Instant camera; [failNext] makes the next capture throw.
class TestCamera extends CameraService {
  TestCamera() : super(warmUp: Duration.zero);

  int shots = 0;
  bool failNext = false;

  @override
  Future<void> openDevice() async {}

  @override
  Future<void> closeDevice() async {}

  @override
  Future<CapturedPhoto> takePicture() async {
    if (failNext) {
      failNext = false;
      throw Exception('sensor glitch');
    }
    shots++;
    return CapturedPhoto(Uint8List.fromList([shots]), extension: 'jpg');
  }

  @override
  Widget buildPreview(BuildContext context) => const SizedBox.expand();
}

class LogEffect implements SoundEffect {
  LogEffect(this.log);
  final List<String> log;
  String name = '';

  @override
  Future<void> load(String asset) async => name = asset.split('/').last;
  @override
  Future<void> play() async => log.add('$name play');
  @override
  Future<void> stop() async => log.add('$name stop');
  @override
  Future<void> setVolume(double v) async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  late TestCamera camera;
  late SoundService sounds;
  late List<String> soundLog;
  late List<int> saved;
  late int done;
  late int backs;

  /// Starts the camera. Its warm-up is a timer, and widget-test timers only
  /// advance when pumped — awaiting start() without pumping hangs forever.
  /// The warm-up timer is only created once openDevice() completes, so keep
  /// pumping until start() has finished (never `await` it un-pumped).
  Future<void> startCamera(WidgetTester tester) async {
    var started = false;
    camera.start().then((_) => started = true);
    for (var i = 0; i < 20 && !started; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(started, isTrue, reason: 'camera.start() did not finish');
  }

  Future<void> pumpScreen(WidgetTester tester, {bool start = true}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    camera = TestCamera();
    soundLog = [];
    sounds = SoundService(createEffect: () => LogEffect(soundLog));
    await sounds.load();
    saved = [];
    done = 0;
    backs = 0;
    if (start) await startCamera(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: CameraScreen(
          camera: camera,
          sounds: sounds,
          onPhoto: (photo) async => saved.add(photo.bytes.first),
          onBack: () => backs++,
          onDone: () => done++,
        ),
      ),
    );
  }

  Future<void> seconds(WidgetTester tester, double s) =>
      tester.pump(Duration(milliseconds: (s * 1000).round()));

  /// Let a capture finish (flash + 300 ms hold).
  Future<void> settleCapture(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('full flow: 10 s, then 5 s ×3 → 4 photos → onDone', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('Photos: 0 / 4'), findsOneWidget);

    await seconds(tester, 10);
    await settleCapture(tester);
    expect(saved, [1]);
    expect(find.text('Photos: 1 / 4'), findsOneWidget);
    expect(find.text('5'), findsOneWidget, reason: 'next countdown is 5 s');

    for (var i = 0; i < 3; i++) {
      await seconds(tester, 5);
      await settleCapture(tester);
    }
    expect(saved, [1, 2, 3, 4]);
    expect(done, 1);
    expect(camera.shots, 4);
  });

  testWidgets('bells at 4 s left; shutter on capture', (tester) async {
    await pumpScreen(tester);
    await seconds(tester, 5); // ticks 10…5
    expect(soundLog, isEmpty);
    await seconds(tester, 1); // tick 4
    expect(soundLog, ['multi_sleigh_bells.wav play']);

    await seconds(tester, 4);
    await settleCapture(tester);
    expect(soundLog, contains('camera_flash_join.wav play'));
  });

  testWidgets('no countdown until the camera is ready', (tester) async {
    await pumpScreen(tester, start: false);
    expect(find.text('Starting camera…'), findsOneWidget);
    expect(find.byType(BadgeLabel), findsOneWidget, reason: 'counter only');

    await startCamera(tester);
    await tester.pump();
    expect(find.text('10'), findsOneWidget);
    expect(find.text('Starting camera…'), findsNothing);
  });

  testWidgets('failed capture → message and retry after 5 s', (tester) async {
    await pumpScreen(tester);
    camera.failNext = true;
    await seconds(tester, 10);
    await tester.pump();
    expect(find.textContaining("let's try that again"), findsOneWidget);
    expect(saved, isEmpty);
    expect(find.text('5'), findsOneWidget);

    await seconds(tester, 5);
    await settleCapture(tester);
    expect(saved, [1]);
    expect(find.textContaining("let's try"), findsNothing);
  });

  testWidgets('failed save → message and retry', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    camera = TestCamera();
    await startCamera(tester);
    var attempts = 0;
    sounds = SoundService(createEffect: () => LogEffect([]));
    await tester.pumpWidget(
      MaterialApp(
        home: CameraScreen(
          camera: camera,
          sounds: sounds,
          onPhoto: (_) async {
            if (attempts++ == 0) throw Exception('disk full');
          },
          onBack: () {},
          onDone: () {},
        ),
      ),
    );
    await seconds(tester, 10);
    await tester.pump();
    expect(find.textContaining("Couldn't save"), findsOneWidget);
    expect(find.text('Photos: 0 / 4'), findsOneWidget);

    await seconds(tester, 5);
    await settleCapture(tester);
    expect(find.text('Photos: 1 / 4'), findsOneWidget);
  });

  testWidgets('Capture button shoots now and restarts the countdown', (
    tester,
  ) async {
    await pumpScreen(tester);
    await seconds(tester, 2);
    await tester.tap(find.text('Capture'));
    await settleCapture(tester);
    expect(saved, [1]);
    expect(find.text('5'), findsOneWidget);

    // The cancelled 10 s countdown must not fire an extra capture.
    await seconds(tester, 4);
    expect(saved, [1]);
    await seconds(tester, 1);
    await settleCapture(tester);
    expect(saved, [1, 2]);
  });

  testWidgets('camera error stops the countdown and explains', (tester) async {
    await pumpScreen(tester);
    await seconds(tester, 3);
    // ignore: invalid_use_of_protected_member
    camera.reportError('webcam unplugged');
    await tester.pump();
    expect(find.textContaining('Camera problem'), findsOneWidget);

    await seconds(tester, 20);
    expect(saved, isEmpty);
  });

  testWidgets('Back stops everything and calls onBack', (tester) async {
    await pumpScreen(tester);
    await seconds(tester, 3);
    await tester.tap(find.text('Back'));
    await seconds(tester, 20);
    expect(backs, 1);
    expect(saved, isEmpty);
  });
}
