import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_theme.dart';

enum BadgeShape {
  /// `counter_css`: radius 20, padding 15. Used for "Photos: N / 4".
  rounded,

  /// `timer_css` for numbers: a perfect circle, diameter = max(w, h) of the
  /// padded text.
  circle,

  /// `timer_css` for longer text ("Time's up!"): rounded-end pill.
  pill,
}

/// Gold-on-red label with a 5 px gold border — the camera screen's photo
/// counter and countdown timer.
///
/// Port of py-photobooth `ui/styles.py` `counter_css` / `timer_css`.
class BadgeLabel extends StatelessWidget {
  const BadgeLabel(this.text, {super.key, this.shape = BadgeShape.rounded});

  /// Photo counter, e.g. `BadgeLabel.counter(taken: 1, total: 4)`.
  const BadgeLabel.counter({super.key, required int taken, required int total})
    : text = 'Photos: $taken / $total',
      shape = BadgeShape.rounded;

  /// Countdown timer: a circle showing [seconds], or a "Time's up!" pill when
  /// null.
  BadgeLabel.timer({super.key, required int? seconds})
    : text = seconds?.toString() ?? "Time's up!",
      shape = seconds == null ? BadgeShape.pill : BadgeShape.circle;

  final String text;
  final BadgeShape shape;

  static const _border = BorderSide(color: AppColors.gold, width: 5);

  EdgeInsets get _padding => switch (shape) {
    BadgeShape.rounded => const EdgeInsets.all(15),
    BadgeShape.circle => const EdgeInsets.all(10),
    // Extra side padding keeps text clear of the rounded ends.
    BadgeShape.pill => const EdgeInsets.symmetric(vertical: 10, horizontal: 30),
  };

  ShapeBorder get _shape => switch (shape) {
    BadgeShape.rounded => const RoundedRectangleBorder(
      side: _border,
      borderRadius: BorderRadius.all(Radius.circular(20)),
    ),
    BadgeShape.circle => const CircleBorder(side: _border),
    BadgeShape.pill => const StadiumBorder(side: _border),
  };

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: _padding,
      decoration: ShapeDecoration(color: AppColors.red, shape: _shape),
      // Factors of 1 → hug the text rather than expanding to fill the parent.
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(text, style: AppText.counter, textAlign: TextAlign.center),
      ),
    );

    return shape == BadgeShape.circle ? _Square(child: badge) : badge;
  }
}

/// Lays its child out as a square whose side is the larger of the child's
/// natural width and height. Used to turn a [CircleBorder] badge into a
/// perfect circle regardless of the text's aspect ratio.
class _Square extends SingleChildRenderObjectWidget {
  const _Square({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSquare();
}

class _RenderSquare extends RenderProxyBox {
  Size _squareFor(Size natural, BoxConstraints constraints) {
    final side = math.max(natural.width, natural.height);
    return constraints.constrain(Size.square(side));
  }

  @override
  void performLayout() {
    final child = this.child!;
    child.layout(constraints.loosen(), parentUsesSize: true);
    child.layout(
      BoxConstraints.tight(_squareFor(child.size, constraints)),
      parentUsesSize: true,
    );
    size = child.size;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _squareFor(child!.getDryLayout(constraints.loosen()), constraints);
}
