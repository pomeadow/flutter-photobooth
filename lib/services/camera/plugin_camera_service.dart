import 'dart:io';

// Hide the plugin's CameraException: ours (camera_service.dart) is the one
// the app uses.
import 'package:camera/camera.dart' hide CameraException;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'camera_service.dart';

typedef ListCameras = Future<List<CameraDescription>> Function();
typedef CreateController = CameraController Function(
  CameraDescription camera,
  ResolutionPreset preset,
);

/// Real camera via Flutter's `camera` plugin — **Windows** (through
/// `camera_windows`, which must be a direct dependency: `camera` doesn't
/// include Windows) and **iPad** (`camera_avfoundation`).
///
/// Port of py-photobooth `controllers/camera_controller.py` (OpenCV).
/// Windows limitations (no focus/exposure/flash/orientation/frame streams)
/// don't matter: the photobooth only needs preview + still capture.
class PluginCameraService extends CameraService {
  PluginCameraService({
    this.config = const CameraConfig(),
    super.warmUp,
    ListCameras? listCameras,
    CreateController? createController,
  }) : _listCameras = listCameras ?? availableCameras,
       _createController = createController ?? _defaultController;

  final CameraConfig config;
  final ListCameras _listCameras;
  final CreateController _createController;
  CameraController? _controller;

  static CameraController _defaultController(
    CameraDescription camera,
    ResolutionPreset preset,
  ) => CameraController(camera, preset, enableAudio: false);

  /// The device chosen when the camera started (null before that).
  CameraDescription? get camera => _controller?.description;

  /// Picks the camera: first one facing [CameraConfig.facing] if requested
  /// and present, else [CameraConfig.index] (out of range → 0).
  static CameraDescription selectCamera(
    List<CameraDescription> cameras,
    CameraConfig config,
  ) {
    if (cameras.isEmpty) throw CameraException('No camera found');
    final wanted = switch (config.facing) {
      CameraFacing.front => CameraLensDirection.front,
      CameraFacing.back => CameraLensDirection.back,
      CameraFacing.any => null,
    };
    if (wanted != null) {
      for (final c in cameras) {
        if (c.lensDirection == wanted) return c;
      }
    }
    final index = config.index;
    return cameras[index >= 0 && index < cameras.length ? index : 0];
  }

  /// The plugin works in presets, not exact sizes. Smallest preset that
  /// reaches [height]: 2160 → ultraHigh, 1080 → veryHigh (1920×1080),
  /// 720 → high, 480 → medium, else low.
  static ResolutionPreset presetFor(int height) {
    if (height > 1080) return ResolutionPreset.ultraHigh;
    if (height > 720) return ResolutionPreset.veryHigh;
    if (height > 480) return ResolutionPreset.high;
    if (height > 288) return ResolutionPreset.medium;
    return ResolutionPreset.low;
  }

  @override
  Future<void> openDevice() async {
    final description = selectCamera(await _listCameras(), config);
    final controller = _createController(description, presetFor(config.height));
    try {
      await controller.initialize();
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
    controller.addListener(_onControllerChanged);
    _controller = controller;
  }

  void _onControllerChanged() {
    final value = _controller?.value;
    if (value != null && value.hasError) {
      reportError(value.errorDescription ?? 'Camera error');
    }
  }

  @override
  Future<void> closeDevice() async {
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_onControllerChanged);
    await controller?.dispose();
  }

  @override
  Future<CapturedPhoto> takePicture() async {
    final controller = _controller;
    if (controller == null) throw CameraException('Camera is not open');

    final file = await controller.takePicture();
    final bytes = await file.readAsBytes();
    // The plugin writes each shot to a temp file; delete it so repeated
    // sessions don't slowly fill the device (iPad storage especially).
    try {
      await File(file.path).delete();
    } catch (error) {
      debugPrint('PluginCameraService: could not delete ${file.path}: $error');
    }

    var ext = p.extension(file.name.isNotEmpty ? file.name : file.path);
    ext = ext.replaceFirst('.', '').toLowerCase();
    return CapturedPhoto(
      bytes,
      extension: switch (ext) {
        '' || 'jpeg' => 'jpg',
        _ => ext,
      },
    );
  }

  @override
  Widget buildPreview(BuildContext context) {
    final controller = _controller;
    return ColoredBox(
      color: Colors.black,
      child: controller == null || !controller.value.isInitialized
          ? const SizedBox.expand()
          // CameraPreview sizes itself with AspectRatio → contained and
          // centred, like Python's KeepAspectRatio.
          : Center(child: CameraPreview(controller)),
    );
  }

  @override
  void dispose() {
    closeDevice();
    super.dispose();
  }
}
