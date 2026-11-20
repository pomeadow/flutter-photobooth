import 'dart:typed_data';

import 'package:camera_macos/camera_macos.dart';
// Not exported by camera_macos, but needed: only the method-channel class
// lets takePicture() choose the format. The plugin's own controller always
// asks for TIFF, which Flutter's image decoder can't read.
import 'package:camera_macos/camera_macos_method_channel.dart';
import 'package:material_ui/material_ui.dart';

import 'camera_service.dart';

/// What [MacosCameraService] needs from the `camera_macos` plugin — a thin
/// seam so tests don't touch the platform.
abstract class MacCameraBackend {
  /// Video devices in system order (what [CameraConfig.index] indexes).
  Future<List<String>> listVideoDeviceIds();

  /// Starts [deviceId]; returns the preview texture id and frame size.
  Future<({int textureId, Size size})> start(
    String deviceId,
    PictureResolution resolution,
  );

  Future<Uint8List> takeJpeg(PictureResolution resolution);

  Future<void> destroy();
}

class CameraMacosBackend implements MacCameraBackend {
  final MethodChannelCameraMacOS _plugin = MethodChannelCameraMacOS();

  @override
  Future<List<String>> listVideoDeviceIds() async {
    final devices = await _plugin.listDevices(
      deviceType: CameraMacOSDeviceType.video,
    );
    return [for (final d in devices) d.deviceId];
  }

  @override
  Future<({int textureId, Size size})> start(
    String deviceId,
    PictureResolution resolution,
  ) async {
    final args = await _plugin.initialize(
      deviceId: deviceId,
      cameraMacOSMode: CameraMacOSMode.photo,
      enableAudio: false,
      pictureFormat: PictureFormat.jpg,
      resolution: resolution,
      // Plugin default is true. The service is never mirrored — the camera
      // screen mirrors the preview itself.
      isVideoMirrored: false,
    );
    final textureId = args?.textureId;
    if (args == null || textureId == null) {
      throw CameraException('Camera did not provide a preview');
    }
    return (textureId: textureId, size: args.size);
  }

  @override
  Future<Uint8List> takeJpeg(PictureResolution resolution) async {
    final file = await _plugin.takePicture(
      format: PictureFormat.jpg,
      resolution: resolution,
    );
    final bytes = file?.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw CameraException('Camera returned no image');
    }
    return bytes;
  }

  @override
  Future<void> destroy() async {
    await _plugin.destroy();
  }
}

/// Real camera on **macOS** via `camera_macos` (the official `camera`
/// plugin has no macOS support).
///
/// Starts the camera directly through the plugin (no `CameraMacOSView`), so
/// it opens at app launch like the other camera services, and shows the
/// preview with Flutter's [Texture].
///
/// Only [CameraConfig.index] selects the device; Macs report no lens
/// direction, so [CameraConfig.facing] is ignored.
class MacosCameraService extends CameraService {
  MacosCameraService({
    this.config = const CameraConfig(),
    super.warmUp,
    MacCameraBackend? backend,
  }) : _backend = backend ?? CameraMacosBackend();

  final CameraConfig config;
  final MacCameraBackend _backend;

  int? _textureId;
  Size? _size;

  /// Plugin resolution for a configured height: 1080 → veryHigh
  /// (1920×1080), >1080 → ultraHigh, 720 → high, 540 → medium, else low.
  static PictureResolution resolutionFor(int height) {
    if (height > 1080) return PictureResolution.ultraHigh;
    if (height > 720) return PictureResolution.veryHigh;
    if (height > 540) return PictureResolution.high;
    if (height > 480) return PictureResolution.medium;
    return PictureResolution.low;
  }

  PictureResolution get _resolution => resolutionFor(config.height);

  @override
  Future<void> openDevice() async {
    final ids = await _backend.listVideoDeviceIds();
    if (ids.isEmpty) throw CameraException('No camera found');
    final index = config.index;
    final id = ids[index >= 0 && index < ids.length ? index : 0];
    final started = await _backend.start(id, _resolution);
    _textureId = started.textureId;
    _size = started.size;
  }

  @override
  Future<void> closeDevice() async {
    if (_textureId == null) return;
    _textureId = null;
    _size = null;
    await _backend.destroy();
  }

  @override
  Future<CapturedPhoto> takePicture() async =>
      CapturedPhoto(await _backend.takeJpeg(_resolution), extension: 'jpg');

  @override
  Widget buildPreview(BuildContext context) {
    final textureId = _textureId;
    final size = _size;
    return ColoredBox(
      color: Colors.black,
      child: textureId == null || size == null || size.isEmpty
          ? const SizedBox.expand()
          // Contained and centred, like Python's KeepAspectRatio.
          : Center(
              child: AspectRatio(
                aspectRatio: size.width / size.height,
                child: Texture(textureId: textureId),
              ),
            ),
    );
  }

  @override
  void dispose() {
    closeDevice();
    super.dispose();
  }
}
