import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_photobooth/services/kiosk_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;
  late List<bool> awake;

  KioskService kiosk(TargetPlatform platform, {bool channelFails = false}) {
    calls = [];
    awake = [];
    messenger.setMockMethodCallHandler(KioskService.defaultChannel, (
      call,
    ) async {
      calls.add('${call.method}(${call.arguments})');
      if (channelFails) throw PlatformException(code: 'boom');
      return null;
    });
    return KioskService(
      platform: platform,
      setAwake: (on) async => awake.add(on),
    );
  }

  tearDown(
    () => messenger.setMockMethodCallHandler(KioskService.defaultChannel, null),
  );

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    test('$platform: enter = awake + full screen; exit reverses', () async {
      final k = kiosk(platform);
      await k.enter();
      expect(calls, ['setFullScreen(true)']);
      expect(awake, [true]);

      await k.exit();
      expect(calls.last, 'setFullScreen(false)');
      expect(awake.last, isFalse);
    });
  }

  test('iOS: awake, no window channel call (uses SystemChrome)', () async {
    final k = kiosk(TargetPlatform.iOS);
    await k.enter();
    expect(awake, [true]);
    expect(calls, isEmpty);
  });

  test('channel failure is swallowed (never stops the booth)', () async {
    final k = kiosk(TargetPlatform.windows, channelFails: true);
    await expectLater(k.enter(), completes);
    expect(awake, [true]);
  });

  test('wakelock failure is swallowed too', () async {
    final k = KioskService(
      platform: TargetPlatform.macOS,
      setAwake: (_) async => throw Exception('no wakelock'),
    );
    messenger.setMockMethodCallHandler(
      KioskService.defaultChannel,
      (_) async => null,
    );
    await expectLater(k.enter(), completes);
  });

  test('kiosk is off in debug/test builds by default', () {
    expect(KioskService.enabledByDefault, kReleaseMode);
  });
}
