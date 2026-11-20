import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../services/camera/camera_service.dart';
import '../services/countdown_controller.dart';
import '../services/sound_service.dart';
import '../theme/app_theme.dart';
import '../widgets/badge_label.dart';
import '../widgets/design_canvas.dart';
import '../widgets/flash_overlay.dart';
import '../widgets/themed_button.dart';

/// Live mirrored preview, countdown, and automatic capture of
/// [photosToTake] photos.
///
/// Port of py-photobooth `ui/camera_screen.py`:
/// - first countdown [firstCountdown] (10 s), then [nextCountdown] (5 s)
/// - sleigh bells at [bellsAt] (4) seconds left
/// - at zero: capture, flash, stop bells, shutter, save; after the last photo
///   → [onDone]
///
/// Fixes over Python:
/// - the countdown waits until the camera is ready;
/// - a failed capture or save shows a message and retries (Python stalled);
/// - Capture cancels the running countdown (Python could take an extra
///   photo);
/// - no blocking event loop — async delays only.
///
/// A new [CameraScreen] is built for each visit, so `initState`/`dispose` are
/// Python's `on_enter`/`on_exit`.
class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.camera,
    required this.sounds,
    required this.onPhoto,
    required this.onBack,
    required this.onDone,
    this.photosToTake = 4,
    this.firstCountdown = 10,
    this.nextCountdown = 5,
    this.bellsAt = 4,
    this.showCaptureButton = true,
  });

  final CameraService camera;
  final SoundService sounds;

  /// Saves a captured photo (the app shell writes it to the session).
  /// Throwing makes the screen retry that photo.
  final Future<void> Function(CapturedPhoto photo) onPhoto;
  final VoidCallback onBack;

  /// All [photosToTake] photos are saved.
  final VoidCallback onDone;

  final int photosToTake;
  final int firstCountdown;
  final int nextCountdown;
  final int bellsAt;

  /// Python showed a "Capture" button to shoot without waiting.
  final bool showCaptureButton;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late final CountdownController _countdown = CountdownController(
    onTick: (remaining) {
      if (remaining == widget.bellsAt) unawaited(widget.sounds.playBells());
    },
    onFinished: _capture,
  );
  final FlashController _flash = FlashController();

  int _taken = 0;
  bool _capturing = false;
  bool _done = false;
  String? _notice;

  CameraService get _camera => widget.camera;

  @override
  void initState() {
    super.initState();
    _camera.status.addListener(_onCameraStatus);
    _onCameraStatus();
  }

  @override
  void dispose() {
    _camera.status.removeListener(_onCameraStatus);
    _countdown.dispose();
    _flash.dispose();
    unawaited(widget.sounds.stopBells(fade: Duration.zero));
    super.dispose();
  }

  void _onCameraStatus() {
    if (!mounted || _done) return;
    final status = _camera.status.value;
    if (status is CameraReady) {
      if (!_countdown.isRunning && !_capturing) _startCountdown();
    } else if (status is CameraError) {
      _countdown.stop();
      unawaited(widget.sounds.stopBells(fade: Duration.zero));
    }
    setState(() {});
  }

  void _startCountdown() {
    _countdown.start(
      _taken == 0 ? widget.firstCountdown : widget.nextCountdown,
    );
  }

  /// Manual Capture button: shoot now, cancelling the countdown.
  void _captureNow() {
    if (_capturing || !_camera.isReady) return;
    _countdown.stop();
    _capture();
  }

  Future<void> _capture() async {
    if (_capturing || _done || !mounted) return;
    setState(() {
      _capturing = true;
      _notice = null;
    });
    try {
      final CapturedPhoto photo;
      try {
        photo = await _camera.capture();
      } on CameraException {
        _retry("Oops — let's try that again");
        return;
      }

      unawaited(_flash.flash());
      unawaited(widget.sounds.stopBells());
      unawaited(widget.sounds.playShutter());

      try {
        await widget.onPhoto(photo);
      } catch (error) {
        debugPrint('CameraScreen: saving photo failed: $error');
        _retry("Couldn't save that one — let's try again");
        return;
      }
      if (!mounted) return;
      setState(() => _taken++);

      // Let the flash finish before moving on.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      if (_taken >= widget.photosToTake) {
        _done = true;
        widget.onDone();
      } else {
        _startCountdown();
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _retry(String message) {
    if (!mounted) return;
    unawaited(widget.sounds.stopBells(fade: Duration.zero));
    setState(() => _notice = message);
    if (_camera.isReady) _countdown.start(widget.nextCountdown);
  }

  void _back() {
    _countdown.stop();
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    final status = _camera.status.value;
    return Scaffold(
      body: DesignCanvas(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            children: [
              SizedBox(height: 160, child: _topBar(status)),
              const SizedBox(height: 20),
              Expanded(child: _preview(context, status)),
            ],
          ),
        ),
      ),
    );
  }

  /// Python: Back (1) | counter (2) | timer (2) | Capture (1).
  Widget _topBar(CameraStatus status) {
    return Row(
      children: [
        Expanded(
          child: Center(
            child: ThemedButton(label: 'Back', onPressed: _back),
          ),
        ),
        Expanded(
          flex: 2,
          child: Center(
            child: BadgeLabel.counter(
              taken: _taken,
              total: widget.photosToTake,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Center(
            child: ListenableBuilder(
              listenable: _countdown,
              builder: (context, _) {
                final remaining = _countdown.remaining;
                if (remaining == null) return const SizedBox.shrink();
                return BadgeLabel.timer(
                  seconds: remaining == 0 ? null : remaining,
                );
              },
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: widget.showCaptureButton
                ? ThemedButton(
                    label: 'Capture',
                    onPressed: status is CameraReady && !_capturing
                        ? _captureNow
                        : null,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _preview(BuildContext context, CameraStatus status) {
    return Stack(
      fit: StackFit.expand,
      children: [
        FlashOverlay(
          controller: _flash,
          // Mirrored like Python's preview; saved photos are not mirrored.
          child: Transform.flip(
            flipX: true,
            child: _camera.buildPreview(context),
          ),
        ),
        if (_message(status) case final message?)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.9),
                borderRadius: const BorderRadius.all(Radius.circular(20)),
                border: Border.all(color: AppColors.gold, width: 3),
              ),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: AppText.button,
              ),
            ),
          ),
      ],
    );
  }

  String? _message(CameraStatus status) => switch (status) {
    CameraIdle() || CameraStarting() => 'Starting camera…',
    CameraError(:final message) =>
      'Camera problem — please ask for help\n($message)',
    CameraReady() => _notice,
  };
}
