import 'package:flutter_photobooth/services/countdown_controller.dart';
import 'package:flutter_test/flutter_test.dart';

// testWidgets runs in a fake-async zone: tester.pump(duration) advances
// Timer.periodic without real waiting.
void main() {
  late List<Object> events;
  late CountdownController countdown;

  void setUpCountdown() {
    events = [];
    countdown = CountdownController(
      onTick: events.add,
      onFinished: () => events.add('finished'),
    );
  }

  Future<void> seconds(WidgetTester tester, int n) =>
      tester.pump(Duration(seconds: n));

  testWidgets('Python timeline: n immediately, n-1…1, finished at n s', (
    tester,
  ) async {
    setUpCountdown();
    countdown.start(5);
    expect(events, [5], reason: 'first tick is immediate');
    expect(countdown.remaining, 5);
    expect(countdown.isRunning, isTrue);

    await seconds(tester, 4);
    expect(events, [5, 4, 3, 2, 1]);
    expect(countdown.remaining, 1);

    await seconds(tester, 1);
    expect(events, [5, 4, 3, 2, 1, 'finished'], reason: 'no tick 0');
    expect(countdown.remaining, 0);
    expect(countdown.isFinished, isTrue);
    expect(countdown.isRunning, isFalse);

    await seconds(tester, 3);
    expect(events.length, 6, reason: 'nothing after finishing');
    countdown.dispose();
  });

  testWidgets('camera flow: 10 s, then 5 s, bells cue on tick 4', (
    tester,
  ) async {
    setUpCountdown();
    countdown.start(10);
    await seconds(tester, 6);
    expect(events.last, 4, reason: 'tick 4 arrives 6 s into a 10 s count');

    await seconds(tester, 4);
    expect(events.last, 'finished');

    events.clear();
    countdown.start(5);
    await seconds(tester, 1);
    expect(events, [5, 4], reason: 'tick 4 arrives 1 s into a 5 s count');
    await seconds(tester, 4);
    expect(events.last, 'finished');
    countdown.dispose();
  });

  testWidgets('stop cancels without finishing', (tester) async {
    setUpCountdown();
    countdown.start(5);
    await seconds(tester, 2);
    countdown.stop();
    expect(countdown.remaining, isNull);
    expect(countdown.isRunning, isFalse);

    await seconds(tester, 10);
    expect(events, [5, 4, 3]);
    countdown.dispose();
  });

  testWidgets('restart replaces the running countdown', (tester) async {
    setUpCountdown();
    countdown.start(10);
    await seconds(tester, 3);
    countdown.start(5);
    await seconds(tester, 5);
    expect(events, [10, 9, 8, 7, 5, 4, 3, 2, 1, 'finished']);
    countdown.dispose();
  });

  testWidgets('notifies listeners on every change', (tester) async {
    setUpCountdown();
    var notifications = 0;
    countdown.addListener(() => notifications++);

    countdown.start(3); // 3
    await seconds(tester, 3); // 2, 1, finished(0)
    expect(notifications, 4);

    countdown.stop(); // finished → idle
    expect(notifications, 5);
    countdown.stop(); // already idle: no-op
    expect(notifications, 5);
    countdown.dispose();
  });
}
