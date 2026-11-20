import 'package:flutter_photobooth/services/sound_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records calls instead of playing audio.
class FakeEffect implements SoundEffect {
  FakeEffect(this.log, {this.failOn = const {}});

  final List<String> log;
  final Set<String> failOn;
  String asset = '';
  double volume = 1;

  void _record(String call) {
    log.add('${asset.split('/').last}:$call');
    if (failOn.contains(call)) throw Exception('boom: $call');
  }

  @override
  Future<void> load(String a) async {
    asset = a;
    _record('load');
  }

  @override
  Future<void> play() async => _record('play');

  @override
  Future<void> stop() async => _record('stop');

  @override
  Future<void> setVolume(double v) async => volume = v;

  @override
  Future<void> dispose() async => _record('dispose');
}

void main() {
  late List<String> log;
  late List<FakeEffect> effects;
  late SoundService sounds;

  Future<void> setUpSounds({Set<String> failOn = const {}}) async {
    log = [];
    effects = [];
    sounds = SoundService(
      createEffect: () {
        final e = FakeEffect(log, failOn: failOn);
        effects.add(e);
        return e;
      },
    );
    await sounds.load();
  }

  FakeEffect bells() => effects[0];

  test('preloads bells and shutter from the copied assets', () async {
    await setUpSounds();
    expect(effects.map((e) => e.asset), [
      'assets/sounds/multi_sleigh_bells.wav',
      'assets/sounds/camera_flash_join.wav',
    ]);
  });

  test('capture sequence: bells, then stop bells, then shutter', () async {
    await setUpSounds();
    log.clear();
    await sounds.playBells();
    await sounds.stopBells(fade: Duration.zero);
    await sounds.playShutter();
    expect(log, [
      'multi_sleigh_bells.wav:play',
      'multi_sleigh_bells.wav:stop',
      'camera_flash_join.wav:play',
    ]);
  });

  testWidgets('stopBells fades volume down before stopping', (tester) async {
    await setUpSounds();
    await sounds.playBells();
    log.clear();

    final stopping = sounds.stopBells();
    await tester.pump(const Duration(milliseconds: 125));
    expect(bells().volume, inExclusiveRange(0.2, 0.8), reason: 'mid-fade');
    expect(log, isEmpty, reason: 'not stopped yet');

    await tester.pump(const Duration(milliseconds: 200));
    await stopping;
    expect(log, ['multi_sleigh_bells.wav:stop']);
    expect(bells().volume, 1, reason: 'reset for next play');
  });

  testWidgets('playing bells again cancels a fade in progress', (tester) async {
    await setUpSounds();
    await sounds.playBells();
    log.clear();

    final stopping = sounds.stopBells();
    await tester.pump(const Duration(milliseconds: 100));
    await sounds.playBells();
    await tester.pump(const Duration(milliseconds: 300));
    await stopping;

    expect(log, ['multi_sleigh_bells.wav:play'], reason: 'never stopped');
    expect(bells().volume, 1);
  });

  test('audio failures are swallowed, never thrown', () async {
    await setUpSounds(failOn: {'play', 'stop'});
    await expectLater(sounds.playBells(), completes);
    await expectLater(sounds.stopBells(fade: Duration.zero), completes);
    await expectLater(sounds.playShutter(), completes);
  });

  test(
    'a sound that fails to load is skipped; the other still works',
    () async {
      log = [];
      var created = 0;
      sounds = SoundService(
        createEffect: () =>
            FakeEffect(log, failOn: {if (created++ == 0) 'load'}),
      );
      await sounds.load();
      log.clear();

      await sounds.playBells(); // bells failed to load → no-op
      await sounds.playShutter();
      expect(log, ['camera_flash_join.wav:play']);
    },
  );

  test('dispose releases both sounds', () async {
    await setUpSounds();
    log.clear();
    await sounds.dispose();
    expect(log, [
      'multi_sleigh_bells.wav:dispose',
      'camera_flash_join.wav:dispose',
    ]);
    await expectLater(sounds.playShutter(), completes);
  });
}
