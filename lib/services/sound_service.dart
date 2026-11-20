import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// One preloaded sound. Abstracted so tests (and machines without audio)
/// don't need a real audio device.
abstract class SoundEffect {
  Future<void> load(String asset);

  /// Plays from the start (restarting if already playing).
  Future<void> play();
  Future<void> stop();
  Future<void> setVolume(double volume);
  Future<void> dispose();
}

/// [SoundEffect] backed by the `audioplayers` package.
class AudioplayersSoundEffect implements SoundEffect {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> load(String asset) async {
    // Keep the source after finishing so it can be replayed instantly.
    await _player.setReleaseMode(ReleaseMode.stop);
    // AssetSource paths are relative to `assets/`.
    await _player.setSource(
      AssetSource(asset.replaceFirst(RegExp('^assets/'), '')),
    );
  }

  @override
  Future<void> play() async {
    await _player.stop(); // rewind if mid-play
    await _player.resume();
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> dispose() => _player.dispose();
}

/// The photobooth's sound effects.
///
/// Port of py-photobooth `ui/camera_screen.py` sound handling:
/// - [playBells] at countdown tick 4 (`multi-sleigh-bells.wav`)
/// - on capture: [stopBells], then [playShutter] (`camera-flash_join.wav`)
///
/// Every call swallows and logs errors: a sound problem must never stop a
/// guest's photos being taken.
class SoundService {
  SoundService({SoundEffect Function()? createEffect})
    : _create = createEffect ?? AudioplayersSoundEffect.new;

  static const bellsAsset = 'assets/sounds/multi_sleigh_bells.wav';
  static const shutterAsset = 'assets/sounds/camera_flash_join.wav';

  /// Default bells fade-out when stopped at capture. Python stopped
  /// instantly; pass `fade: Duration.zero` for that.
  static const defaultBellsFade = Duration(milliseconds: 250);

  final SoundEffect Function() _create;
  SoundEffect? _bells;
  SoundEffect? _shutter;
  int _fadeGeneration = 0;

  /// Preloads both sounds. Call once at startup.
  Future<void> load() async {
    _bells = await _loaded(bellsAsset);
    _shutter = await _loaded(shutterAsset);
  }

  Future<void> playBells() async {
    final bells = _bells;
    if (bells == null) return;
    _fadeGeneration++; // cancel any fade in progress
    await _guard('play bells', () async {
      await bells.setVolume(1);
      await bells.play();
    });
  }

  /// Stops the bells, fading out over [fade] (in ~10 steps).
  Future<void> stopBells({Duration fade = defaultBellsFade}) async {
    final bells = _bells;
    if (bells == null) return;
    final generation = ++_fadeGeneration;
    await _guard('stop bells', () async {
      const steps = 10;
      if (fade > Duration.zero) {
        for (var i = steps - 1; i >= 0; i--) {
          await Future<void>.delayed(fade ~/ steps);
          if (generation != _fadeGeneration) return; // bells restarted
          await bells.setVolume(i / steps);
        }
      }
      await bells.stop();
      await bells.setVolume(1);
    });
  }

  Future<void> playShutter() async {
    final shutter = _shutter;
    if (shutter == null) return;
    await _guard('play shutter', shutter.play);
  }

  Future<void> dispose() async {
    _fadeGeneration++;
    for (final effect in [_bells, _shutter]) {
      if (effect != null) await _guard('dispose', effect.dispose);
    }
    _bells = _shutter = null;
  }

  Future<SoundEffect?> _loaded(String asset) async {
    final effect = _create();
    try {
      await effect.load(asset);
      return effect;
    } catch (error) {
      debugPrint('SoundService: could not load $asset: $error');
      await _guard('dispose', effect.dispose);
      return null;
    }
  }

  static Future<void> _guard(
    String what,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      debugPrint('SoundService: $what failed: $error');
    }
  }
}
