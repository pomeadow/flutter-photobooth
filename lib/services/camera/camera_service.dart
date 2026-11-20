import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Which way the camera should face. On an iPad, camera 0 is usually the
/// back camera — a photobooth wants [front] (facing the guests).
enum CameraFacing { any, front, back }

/// Camera settings — py-photobooth's `.env` (`CAMERA_INDEX`, `CAMERA_WIDTH`,
/// `CAMERA_HEIGHT`), plus [facing]. Used by the real camera services.
class CameraConfig {
  const CameraConfig({
    this.index = 0,
    this.width = 1920,
    this.height = 1080,
    this.facing = CameraFacing.any,
  });

  /// Device index, used when [facing] is [CameraFacing.any] or no camera
  /// faces the requested way. Out of range → camera 0.
  final int index;
  final int width;
  final int height;
  final CameraFacing facing;
}

sealed class CameraStatus {
  const CameraStatus();
}

class CameraIdle extends CameraStatus {
  const CameraIdle();
}

/// Opening the device, then warming up (hiding the startup logo).
class CameraStarting extends CameraStatus {
  const CameraStarting();
}

class CameraReady extends CameraStatus {
  const CameraReady();
}

class CameraError extends CameraStatus {
  const CameraError(this.message);
  final String message;
}

class CameraException implements Exception {
  CameraException(this.message);
  final String message;

  @override
  String toString() => 'CameraException: $message';
}

/// A captured photo, exactly as the camera produced it (not mirrored).
class CapturedPhoto {
  const CapturedPhoto(this.bytes, {required this.extension});

  final Uint8List bytes;

  /// File extension matching [bytes], e.g. `jpg` or `png`.
  final String extension;
}

/// The photobooth camera. Port of py-photobooth
/// `controllers/camera_controller.py`.
///
/// - [start] once at app launch; [stop] on shutdown (Python never stopped
///   between guests).
/// - [status] becomes [CameraReady] only after [warmUp] — Python skipped the
///   first 90 frames (~3 s at 30 fps) to hide the webcam's startup logo.
/// - [buildPreview] and [capture] are **not mirrored**; the camera screen
///   mirrors the preview, as Python did.
abstract class CameraService {
  CameraService({this.warmUp = const Duration(seconds: 3)});

  /// Delay after the device opens before reporting ready.
  final Duration warmUp;

  final ValueNotifier<CameraStatus> _status = ValueNotifier(const CameraIdle());

  ValueListenable<CameraStatus> get status => _status;
  bool get isReady => _status.value is CameraReady;

  int _generation = 0;
  bool _disposed = false;

  /// Status changes are ignored after [dispose] (e.g. a stop() still
  /// finishing during app shutdown).
  void _set(CameraStatus status) {
    if (!_disposed) _status.value = status;
  }

  /// Opens the device, waits [warmUp], then reports ready. Errors are
  /// reported through [status], never thrown. Safe to call when started.
  Future<void> start() async {
    if (_disposed || _status.value is CameraStarting || isReady) return;
    final generation = ++_generation;
    _set(const CameraStarting());
    try {
      await openDevice();
      await Future<void>.delayed(warmUp);
      if (generation == _generation) _set(const CameraReady());
    } catch (error) {
      if (generation == _generation) _set(CameraError('$error'));
    }
  }

  Future<void> stop() async {
    _generation++;
    try {
      await closeDevice();
    } finally {
      _set(const CameraIdle());
    }
  }

  /// Takes a photo. Throws [CameraException] if not ready or it fails.
  Future<CapturedPhoto> capture() async {
    if (!isReady) throw CameraException('Camera is not ready');
    try {
      return await takePicture();
    } on CameraException {
      rethrow;
    } catch (error) {
      throw CameraException('$error');
    }
  }

  /// Live preview filling its parent (not mirrored).
  Widget buildPreview(BuildContext context);

  /// For subclasses: the device failed after starting (e.g. webcam
  /// unplugged). Moves [status] to [CameraError].
  @protected
  void reportError(String message) {
    _generation++;
    _set(CameraError(message));
  }

  @protected
  Future<void> openDevice();

  @protected
  Future<void> closeDevice();

  @protected
  Future<CapturedPhoto> takePicture();

  @mustCallSuper
  void dispose() {
    _generation++;
    _disposed = true;
    _status.dispose();
  }
}
