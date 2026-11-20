import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_photobooth/services/camera/camera_service.dart';

import '../support/fake_camera.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A CameraService whose device can be made to fail.
class _FlakyCamera extends CameraService {
  _FlakyCamera({this.failOpen = false, this.failCapture = false})
    : super(warmUp: const Duration(seconds: 3));

  final bool failOpen;
  final bool failCapture;
  int closes = 0;

  @override
  Future<void> openDevice() async {
    if (failOpen) throw Exception('no camera');
  }

  @override
  Future<void> closeDevice() async => closes++;

  @override
  Future<CapturedPhoto> takePicture() async {
    if (failCapture) throw Exception('sensor error');
    return CapturedPhoto(Uint8List(1), extension: 'jpg');
  }

  @override
  Widget buildPreview(BuildContext context) => const SizedBox.expand();
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CameraService lifecycle', () {
    testWidgets('starting → ready only after the warm-up', (tester) async {
      final camera = _FlakyCamera();
      final starting = camera.start();
      await tester.pump();
      expect(camera.status.value, isA<CameraStarting>());

      await tester.pump(const Duration(milliseconds: 2900));
      expect(camera.isReady, isFalse, reason: 'still hiding startup logo');

      await tester.pump(const Duration(milliseconds: 200));
      await starting;
      expect(camera.status.value, isA<CameraReady>());
      camera.dispose();
    });

    testWidgets('capture before ready throws CameraException', (tester) async {
      final camera = _FlakyCamera();
      expect(camera.capture, throwsA(isA<CameraException>()));
      camera.dispose();
    });

    testWidgets('open failure is reported as CameraError, not thrown', (
      tester,
    ) async {
      final camera = _FlakyCamera(failOpen: true);
      await camera.start();
      final status = camera.status.value;
      expect(status, isA<CameraError>());
      expect((status as CameraError).message, contains('no camera'));
      camera.dispose();
    });

    testWidgets('capture failure becomes a CameraException', (tester) async {
      final camera = _FlakyCamera(failCapture: true);
      final starting = camera.start();
      await tester.pump(const Duration(seconds: 4));
      await starting;
      await expectLater(camera.capture(), throwsA(isA<CameraException>()));
      camera.dispose();
    });

    testWidgets('stop during warm-up never reports ready', (tester) async {
      final camera = _FlakyCamera();
      final starting = camera.start();
      await tester.pump(const Duration(seconds: 1));
      await camera.stop();
      await tester.pump(const Duration(seconds: 5));
      await starting;
      expect(camera.status.value, isA<CameraIdle>());
      expect(camera.closes, 1);
      camera.dispose();
    });
  });

  test(
    'stop() finishing after dispose() does not throw (app shutdown)',
    () async {
      final camera = FakeCameraService(warmUp: Duration.zero);
      await camera.start();
      final stopping = camera.stop(); // app shell: unawaited stop, then dispose
      camera.dispose();
      await expectLater(stopping, completes);
      await camera.start(); // no-op after dispose
    },
  );

  group('FakeCameraService', () {
    test('synthetic photos: 1920×1080 PNGs, different each time', () async {
      final camera = FakeCameraService(warmUp: Duration.zero);
      await camera.start();
      final a = await camera.capture();
      final b = await camera.capture();

      expect(a.extension, 'png');
      final image = await _decode(a.bytes);
      expect([image.width, image.height], [1920, 1080]);
      expect(a.bytes, isNot(equals(b.bytes)));
      expect(camera.taken, 2);
      camera.dispose();
    });

    test('with photoPaths: cycles through the files as-is', () async {
      final dir = await Directory.systemTemp.createTemp('fake_cam_');
      final one = File(p.join(dir.path, 'one.JPG'))..writeAsBytesSync([1]);
      final two = File(p.join(dir.path, 'two.png'))..writeAsBytesSync([2]);
      final camera = FakeCameraService(
        photoPaths: [one.path, two.path],
        warmUp: Duration.zero,
      );
      await camera.start();

      final shots = [for (var i = 0; i < 3; i++) await camera.capture()];
      expect(shots.map((s) => s.bytes.first), [1, 2, 1]);
      expect(shots.map((s) => s.extension), ['jpg', 'png', 'jpg']);
      camera.dispose();
      await dir.delete(recursive: true);
    });

    test('missing photo file → CameraError on start', () async {
      final camera = FakeCameraService(
        photoPaths: ['/nope/missing.jpg'],
        warmUp: Duration.zero,
      );
      await camera.start();
      expect(camera.status.value, isA<CameraError>());
      camera.dispose();
    });

    testWidgets('preview shows the FAKE CAMERA banner', (tester) async {
      final camera = FakeCameraService(warmUp: Duration.zero);
      await tester.pumpWidget(
        MaterialApp(home: Builder(builder: camera.buildPreview)),
      );
      expect(find.text('FAKE CAMERA'), findsOneWidget);
      camera.dispose();
    });
  });
}
