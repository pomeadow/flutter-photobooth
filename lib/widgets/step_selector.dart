import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// "− [value] +" stepper with an optional caption above — "Number of prints".
///
/// Port of py-photobooth `components/range_selector.py`, as a *controlled*
/// widget: the parent owns [value] and updates it from [onChanged], so it can
/// be reset per session.
///
/// Values are clamped to [min]..[max] (Python could overshoot by a step).
/// The − / + button is disabled at the respective limit. [max] null = no limit.
class StepSelector extends StatelessWidget {
  const StepSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max,
    this.step = 2,
    this.label,
  }) : assert(step > 0),
       assert(max == null || max >= min);

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int? max;
  final int step;

  /// Caption above the controls, e.g. "Number of prints".
  final String? label;

  bool get _canDecrement => value > min;
  bool get _canIncrement => max == null || value < max!;

  int _clamp(int v) {
    if (v < min) return min;
    if (max != null && v > max!) return max!;
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          symbol: '−',
          semanticLabel: 'Decrease',
          onPressed: _canDecrement
              ? () => onChanged(_clamp(value - step))
              : null,
        ),
        const SizedBox(width: 20),
        _ValueBox(value: value),
        const SizedBox(width: 20),
        _StepButton(
          symbol: '+',
          semanticLabel: 'Increase',
          onPressed: _canIncrement
              ? () => onChanged(_clamp(value + step))
              : null,
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(label!, style: AppText.label),
            ),
          controls,
        ],
      ),
    );
  }
}

/// 80×80 red button with a white − or +.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.symbol,
    required this.semanticLabel,
    required this.onPressed,
  });

  final String symbol;
  final String semanticLabel;
  final VoidCallback? onPressed;

  static final ButtonStyle _style = ButtonStyle(
    fixedSize: const WidgetStatePropertyAll(Size(80, 80)),
    minimumSize: const WidgetStatePropertyAll(Size(80, 80)),
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return AppColors.red.withValues(alpha: 0.4);
      }
      if (states.contains(WidgetState.pressed)) return AppColors.redPressed;
      if (states.contains(WidgetState.hovered)) return AppColors.redHover;
      return AppColors.red;
    }),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? Colors.white.withValues(alpha: 0.6)
          : Colors.white,
    ),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    ),
    textStyle: WidgetStatePropertyAll(AppText.stepperButton),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    splashFactory: NoSplash.splashFactory,
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      excludeSemantics: true,
      child: TextButton(
        onPressed: onPressed,
        style: _style,
        child: Text(symbol),
      ),
    );
  }
}

/// 120×80 read-only value display (Python's disabled QLineEdit).
class _ValueBox extends StatelessWidget {
  const _ValueBox({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 80,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.disabledFill,
        border: Border.all(color: AppColors.red, width: 2),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Text('$value', style: AppText.stepperValue),
    );
  }
}
