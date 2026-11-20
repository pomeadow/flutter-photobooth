import 'dart:io';

import 'package:camera/camera.dart' hide CameraException;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_photobooth/services/camera/camera_service.dart';
import 'package:flutter_photobooth/services/camera/plugin_camera_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const back = CameraDescription(
  name: 'back',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);
const front = CameraDescription(
  name: 'front',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 270,
);
const usb = CameraDescription(
  name: 'usb',
  lensDirection: CameraLensDirection.external,
  sensorOrientation: 0,
);

/// CameraController that never touches the platform.
class FakeController extends CameraController {
  FakeController(super.description, super.preset, {required this.shotPath});

  final String shotPath;
  bool disposed = false;
  bool failInit = false;

  @override
  Future<void> initialize() async {
    if (failInit) throw Exception('device busy');
    value = value.copyWith(
      isInitialized: true,
      previewSize: const Size(1920, 1080),
    );
  }

  @override
  Future<XFile> takePicture() async => XFile(shotPath);

  @override
  // ignore: must_call_super
  Future<void> dispose() async => disposed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('selectCamera', () {
    const cameras = [back, front, usb];

    test('index picks the device (Python CAMERA_INDEX)', () {
      expect(
        PluginCameraService.selectCamera(cameras, const CameraConfig(index: 2)),
        usb,
      );
    });

    test('out-of-range index falls back to camera 0', () {
      expect(
        PluginCameraService.selectCamera(cameras, const CameraConfig(index: 9)),
        back,
      );
    });

    test('facing front wins over index (iPad booth)', () {
      expect(
        PluginCameraService.selectCamera(
          cameras,
          const CameraConfig(facing: CameraFacing.front),
        ),
        front,
      );
    });

    test('facing requested but absent → index', () {
      expect(
        PluginCameraService.selectCamera(const [
          usb,
        ], const CameraConfig(facing: CameraFacing.front)),
        usb,
      );
    });

    test('no cameras → CameraException', () {
      expect(
        () => PluginCameraService.selectCamera(const [], const CameraConfig()),
        throwsA(isA<CameraException>()),
      );
    });
  });

  test('presetFor maps heights to the smallest sufficient preset', () {
    expect(PluginCameraService.presetFor(2160), ResolutionPreset.ultraHigh);
    expect(PluginCameraService.presetFor(1080), ResolutionPreset.veryHigh);
    expect(PluginCameraService.presetFor(720), ResolutionPreset.high);
    expect(PluginCameraService.presetFor(480), ResolutionPreset.medium);
    expect(PluginCameraService.presetFor(240), ResolutionPreset.low);
  });

  group('with a fake controller', () {
    late Directory tmp;
    late List<FakeController> controllers;
    late PluginCameraService camera;

    PluginCameraService build({
      List<CameraDescription> cameras = const [back, front],
      CameraConfig config = const CameraConfig(),
      bool failInit = false,
      String shot = 'shot.jpg',
    }) {
      controllers = [];
      return PluginCameraService(
        config: config,
        warmUp: Duration.zero,
        listCameras: () async => cameras,
        createController: (d, preset) {
          final c = FakeController(d, preset, shotPath: p.join(tmp.path, shot))
            ..failInit = failInit;
          controllers.add(c);
          return c;
        },
      );
    }

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('plugin_cam_');
    });
    tearDown(() => tmp.delete(recursive: true));

    test('starts with the configured camera at the 1080p preset', () async {
      camera = build(config: const CameraConfig(facing: CameraFacing.front));
      await camera.start();
      expect(camera.isReady, isTrue);
      expect(camera.camera, front);
      expect(
        controllers.single.mediaSettings.resolutionPreset,
        ResolutionPreset.veryHigh,
      );
      camera.dispose();
    });

    test('capture returns the bytes and deletes the temp file', () async {
      camera = build();
      final shot = File(p.join(tmp.path, 'shot.jpg'))
        ..writeAsBytesSync([7, 8, 9]);
      await camera.start();

      final photo = await camera.capture();
      expect(photo.bytes, [7, 8, 9]);
      expect(photo.extension, 'jpg');
      expect(shot.existsSync(), isFalse, reason: 'temp file cleaned up');
      camera.dispose();
    });

    test('.jpeg temp files are reported as jpg', () async {
      camera = build(shot: 'shot.JPEG');
      File(p.join(tmp.path, 'shot.JPEG')).writeAsBytesSync([1]);
      await camera.start();
      expect((await camera.capture()).extension, 'jpg');
      camera.dispose();
    });

    test('init failure → CameraError and the controller is released', () async {
      camera = build(failInit: true);
      await camera.start();
      expect(camera.status.value, isA<CameraError>());
      expect(controllers.single.disposed, isTrue);
      camera.dispose();
    });

    test('no cameras → CameraError("No camera found")', () async {
      camera = build(cameras: const []);
      await camera.start();
      final status = camera.status.value;
      expect(status, isA<CameraError>());
      expect((status as CameraError).message, contains('No camera found'));
      camera.dispose();
    });

    test('device error after start (unplugged) → CameraError', () async {
      camera = build();
      await camera.start();
      final c = controllers.single;
      c.value = c.value.copyWith(errorDescription: 'device disconnected');
      final status = camera.status.value;
      expect(status, isA<CameraError>());
      expect((status as CameraError).message, 'device disconnected');
      camera.dispose();
    });

    test('stop disposes the controller', () async {
      camera = build();
      await camera.start();
      await camera.stop();
      expect(controllers.single.disposed, isTrue);
      expect(camera.status.value, isA<CameraIdle>());
      camera.dispose();
    });

    testWidgets('preview is black until started', (tester) async {
      camera = build();
      await tester.pumpWidget(
        MaterialApp(home: Builder(builder: camera.buildPreview)),
      );
      // MaterialApp adds its own ColoredBoxes, so look for the black one.
      expect(
        find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == Colors.black,
        ),
        findsOneWidget,
      );
      camera.dispose();
    });
  });
}
