import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Kiosk mode: full screen, screen never sleeps, landscape on iPad.
///
/// - macOS / Windows: asks the native window (see `macos/Runner/
///   MainFlutterWindow.swift`, `windows/runner/flutter_window.cpp`) to go
///   full screen over the `photobooth/kiosk` channel. The operator can still
///   quit with ⌘Q / Alt+F4.
/// - iPad: hides the status bar (immersive) and locks to landscape. For a
///   hard lock, use iPadOS Guided Access.
/// - All: keeps the screen awake (`wakelock_plus`).
///
/// Never throws — a kiosk problem must not stop the booth.
class KioskService {
  KioskService({
    this.channel = defaultChannel,
    Future<void> Function(bool awake)? setAwake,
    TargetPlatform? platform,
  }) : _setAwake = setAwake ?? _wakelock,
       _platform = platform ?? defaultTargetPlatform;

  static const MethodChannel defaultChannel = MethodChannel('photobooth/kiosk');

  /// Kiosk on in release builds (what's installed on event devices), off in
  /// debug (`flutter run`). Override: `--dart-define=KIOSK=true|false`.
  static const bool enabledByDefault = bool.fromEnvironment(
    'KIOSK',
    defaultValue: kReleaseMode,
  );

  /// Window channel (native side in the macOS/Windows runners).
  final MethodChannel channel;
  final Future<void> Function(bool awake) _setAwake;
  final TargetPlatform _platform;

  static Future<void> _wakelock(bool awake) =>
      WakelockPlus.toggle(enable: awake);

  bool get _desktop =>
      _platform == TargetPlatform.macOS || _platform == TargetPlatform.windows;

  bool get _mobile =>
      _platform == TargetPlatform.iOS || _platform == TargetPlatform.android;

  Future<void> enter() async {
    await _guard('keep awake', () => _setAwake(true));
    if (_desktop) {
      await _guard(
        'full screen',
        () => channel.invokeMethod<void>('setFullScreen', true),
      );
    } else if (_mobile) {
      await _guard('immersive', () async {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      });
    }
  }

  Future<void> exit() async {
    await _guard('allow sleep', () => _setAwake(false));
    if (_desktop) {
      await _guard(
        'leave full screen',
        () => channel.invokeMethod<void>('setFullScreen', false),
      );
    } else if (_mobile) {
      await _guard('leave immersive', () async {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        await SystemChrome.setPreferredOrientations(const []);
      });
    }
  }

  static Future<void> _guard(
    String what,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      debugPrint('KioskService: $what failed: $error');
    }
  }
}
