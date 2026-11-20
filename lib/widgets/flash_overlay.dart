import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Triggers a [FlashOverlay]. Create one per screen, pass it to the overlay,
/// then `await controller.flash()` after each capture.
class FlashController extends ChangeNotifier {
  _FlashOverlayState? _overlay;

  /// True while the white flash is visible.
  bool get isFlashing => _overlay?._isFlashing ?? false;

  /// Shows the flash. Completes when it has fully disappeared. Calling again
  /// while a flash is running returns the same in-progress flash.
  Future<void> flash() => _overlay?._flash() ?? Future.value();

  void _notify() => notifyListeners();
}

/// White camera flash drawn over [child] (the camera preview).
///
/// Port of py-photobooth `components/flash_overlay.py`. Python swapped the
/// preview for solid white for 300 ms and paused frame updates; here the
/// overlay simply covers the preview, so no pausing is needed.
///
/// Timeline: full white for [hold], then fade to clear over [fadeOut].
/// Default 150 + 150 = Python's 300 ms total. Use `fadeOut: Duration.zero`
/// for Python's exact instant on/off.
class FlashOverlay extends StatefulWidget {
  const FlashOverlay({
    super.key,
    required this.controller,
    required this.child,
    this.hold = const Duration(milliseconds: 150),
    this.fadeOut = const Duration(milliseconds: 150),
    this.onStart,
    this.onEnd,
  });

  final FlashController controller;
  final Widget child;
  final Duration hold;
  final Duration fadeOut;

  /// Python's `flash_started` / `flash_finished` signals.
  final VoidCallback? onStart;
  final VoidCallback? onEnd;

  @override
  State<FlashOverlay> createState() => _FlashOverlayState();
}

class _FlashOverlayState extends State<FlashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this);
  late Animation<double> _opacity;
  Future<void>? _running;

  bool get _isFlashing => _running != null;

  @override
  void initState() {
    super.initState();
    _configure();
    _attach(widget.controller);
  }

  @override
  void didUpdateWidget(FlashOverlay old) {
    super.didUpdateWidget(old);
    if (old.hold != widget.hold || old.fadeOut != widget.fadeOut) _configure();
    if (old.controller != widget.controller) {
      _detach(old.controller);
      _attach(widget.controller);
    }
  }

  void _configure() {
    final total = widget.hold + widget.fadeOut;
    _anim.duration = total;
    final holdWeight = widget.hold.inMicroseconds.toDouble();
    final fadeWeight = widget.fadeOut.inMicroseconds.toDouble();
    _opacity = TweenSequence<double>([
      if (holdWeight > 0)
        TweenSequenceItem(tween: ConstantTween(1), weight: holdWeight),
      if (fadeWeight > 0)
        TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: fadeWeight),
    ]).animate(_anim);
  }

  void _attach(FlashController c) => c._overlay = this;

  void _detach(FlashController c) {
    if (c._overlay == this) c._overlay = null;
  }

  Future<void> _flash() => _running ??= _run();

  Future<void> _run() async {
    widget.onStart?.call();
    widget.controller._notify();
    try {
      await _anim.forward(from: 0).orCancel;
    } on TickerCanceled {
      // Disposed mid-flash — nothing more to do.
    } finally {
      _running = null;
      if (mounted) {
        _anim.value = 0;
        widget.onEnd?.call();
        widget.controller._notify();
      }
    }
  }

  @override
  void dispose() {
    _detach(widget.controller);
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, _) {
                // Nothing to draw when idle.
                if (!_anim.isAnimating) return const SizedBox.shrink();
                return ColoredBox(
                  color: AppColors.flash.withValues(alpha: _opacity.value),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
