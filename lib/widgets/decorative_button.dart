import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Big red/gold button with concave (inward-curving) corners — used for START.
///
/// Port of py-photobooth `components/decorative_button.py`:
/// - Red fill: the widget rect inset by [_outerInset], with a quarter-circle of
///   radius [_cornerRadius] cut out of each corner (centred on the corner).
/// - Gold outline: the same shape inset a further [_outlineMargin], 3 px wide.
/// - Fill colour: red → [AppColors.decorativeHover] on hover →
///   [AppColors.decorativePressed] while pressed.
///
/// Pass `onPressed: null` to disable (drawn at half opacity, no interaction).
class DecorativeButton extends StatefulWidget {
  const DecorativeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.minWidth = 800,
    this.minHeight = 120,
  });

  final String label;
  final VoidCallback? onPressed;
  final double minWidth;
  final double minHeight;

  @override
  State<DecorativeButton> createState() => _DecorativeButtonState();
}

class _DecorativeButtonState extends State<DecorativeButton> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  Color get _fill {
    if (_pressed) return AppColors.decorativePressed;
    if (_hovered) return AppColors.decorativeHover;
    return AppColors.red;
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final button = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: widget.minWidth,
        minHeight: widget.minHeight,
      ),
      child: CustomPaint(
        painter: _ConcaveButtonPainter(fill: _fill),
        // widthFactor/heightFactor 1 → hug content (min 800×120) instead of
        // expanding to fill the parent, like the Qt button.
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Padding(
            // Keep text clear of the outline.
            // Horizontal only: vertical padding would push the height past
            // 120 (Qt draws the text centred with no padding).
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(widget.label, style: AppText.decorativeButton),
          ),
        ),
      ),
    );

    if (!_enabled) return Opacity(opacity: 0.5, child: button);

    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: widget.onPressed,
          child: button,
        ),
      ),
    );
  }
}

const double _cornerRadius = 10;
const double _outerInset = 10;
const double _outlineMargin = 5;
const double _outlineWidth = 3;

class _ConcaveButtonPainter extends CustomPainter {
  _ConcaveButtonPainter({required this.fill});

  final Color fill;

  /// Rectangle whose four corners are replaced by inward quarter-circle arcs
  /// of [radius], each centred on the original corner.
  static Path _concaveRect(Rect r, double radius) {
    final arc = Radius.circular(radius);
    return Path()
      ..moveTo(r.left + radius, r.top)
      ..lineTo(r.right - radius, r.top)
      ..arcToPoint(
        Offset(r.right, r.top + radius),
        radius: arc,
        clockwise: false,
      )
      ..lineTo(r.right, r.bottom - radius)
      ..arcToPoint(
        Offset(r.right - radius, r.bottom),
        radius: arc,
        clockwise: false,
      )
      ..lineTo(r.left + radius, r.bottom)
      ..arcToPoint(
        Offset(r.left, r.bottom - radius),
        radius: arc,
        clockwise: false,
      )
      ..lineTo(r.left, r.top + radius)
      ..arcToPoint(
        Offset(r.left + radius, r.top),
        radius: arc,
        clockwise: false,
      )
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;

    final outer = _concaveRect(bounds.deflate(_outerInset), _cornerRadius);
    canvas.drawPath(outer, Paint()..color = fill);

    final inner = _concaveRect(
      bounds.deflate(_outerInset + _outlineMargin),
      _cornerRadius,
    );
    canvas.drawPath(
      inner,
      Paint()
        ..color = AppColors.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = _outlineWidth,
    );
  }

  @override
  bool shouldRepaint(_ConcaveButtonPainter old) => old.fill != fill;
}
