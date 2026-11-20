import 'dart:typed_data';

import 'package:camera_macos/camera_macos.dart' show PictureResolution;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_photobooth/services/camera/camera_service.dart';
import 'package:flutter_photobooth/services/camera/macos_camera_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBackend implements MacCameraBackend {
  FakeBackend({this.ids = const ['facetime', 'usb'], this.failStart = false});

  final List<String> ids;
  final bool failStart;
  final List<String> calls = [];

  @override
  Future<List<String>> listVideoDeviceIds() async => ids;

  @override
  Future<({int textureId, Size size})> start(
    String deviceId,
    PictureResolution resolution,
  ) async {
    calls.add('start $deviceId ${resolution.name}');
    if (failStart) throw Exception('camera in use');
    return (textureId: 42, size: const Size(1920, 1080));
  }

  @override
  Future<Uint8List> takeJpeg(PictureResolution resolution) async {
    calls.add('take ${resolution.name}');
    return Uint8List.fromList([0xFF, 0xD8]);
  }

  @override
  Future<void> destroy() async => calls.add('destroy');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MacosCameraService build(FakeBackend backend, {int index = 0}) =>
      MacosCameraService(
        config: CameraConfig(index: index),
        warmUp: Duration.zero,
        backend: backend,
      );

  test('resolutionFor maps heights like the other camera service', () {
    expect(MacosCameraService.resolutionFor(2160), PictureResolution.ultraHigh);
    expect(MacosCameraService.resolutionFor(1080), PictureResolution.veryHigh);
    expect(MacosCameraService.resolutionFor(720), PictureResolution.high);
    expect(MacosCameraService.resolutionFor(540), PictureResolution.medium);
    expect(MacosCameraService.resolutionFor(480), PictureResolution.low);
  });

  test('starts the indexed device at 1080p', () async {
    final backend = FakeBackend();
    final camera = build(backend, index: 1);
    await camera.start();
    expect(camera.isReady, isTrue);
    expect(backend.calls, ['start usb veryHigh']);
    camera.dispose();
  });

  test('out-of-range index falls back to camera 0', () async {
    final backend = FakeBackend();
    final camera = build(backend, index: 5);
    await camera.start();
    expect(backend.calls, ['start facetime veryHigh']);
    camera.dispose();
  });

  test('capture asks for JPEG and reports jpg', () async {
    final backend = FakeBackend();
    final camera = build(backend);
    await camera.start();
    final photo = await camera.capture();
    expect(photo.extension, 'jpg');
    expect(photo.bytes, [0xFF, 0xD8]);
    expect(backend.calls.last, 'take veryHigh');
    camera.dispose();
  });

  test('no cameras → CameraError', () async {
    final camera = build(FakeBackend(ids: const []));
    await camera.start();
    expect(camera.status.value, isA<CameraError>());
    camera.dispose();
  });

  test('start failure (camera in use) → CameraError', () async {
    final camera = build(FakeBackend(failStart: true));
    await camera.start();
    final status = camera.status.value;
    expect(status, isA<CameraError>());
    expect((status as CameraError).message, contains('camera in use'));
    camera.dispose();
  });

  test('stop destroys once; stopping again is a no-op', () async {
    final backend = FakeBackend();
    final camera = build(backend);
    await camera.start();
    await camera.stop();
    await camera.stop();
    expect(backend.calls.where((c) => c == 'destroy'), hasLength(1));
    camera.dispose();
  });

  testWidgets('preview: black before start, texture after', (tester) async {
    final camera = build(FakeBackend());
    Widget app() => MaterialApp(home: Builder(builder: camera.buildPreview));

    await tester.pumpWidget(app());
    expect(find.byType(Texture), findsNothing);

    await tester.runAsync(camera.start);
    await tester.pumpWidget(app());
    expect(tester.widget<Texture>(find.byType(Texture)).textureId, 42);
    expect(
      tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
      closeTo(16 / 9, 0.001),
    );
    camera.dispose();
  });
}
