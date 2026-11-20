import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Padding presets from py-photobooth.
enum ThemedButtonSize {
  /// `ui/styles.py buttons_css`: padding 20px 40px.
  regular(EdgeInsets.symmetric(vertical: 20, horizontal: 40)),

  /// Selection screen override: padding 10px 20px.
  compact(EdgeInsets.symmetric(vertical: 10, horizontal: 20));

  const ThemedButtonSize(this.padding);
  final EdgeInsets padding;
}

/// Regular red/gold button: Back, Next, Print Photo, Start Over, OK.
///
/// Port of `ui/styles.py buttons_css`: red fill, gold text, 3 px gold border,
/// radius 10, hover/pressed shades. Margins are *not* included — the parent
/// layout handles spacing.
///
/// Pass `onPressed: null` to disable (dimmed to 50 %).
class ThemedButton extends StatelessWidget {
  const ThemedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = ThemedButtonSize.regular,
  });

  final String label;
  final VoidCallback? onPressed;
  final ThemedButtonSize size;

  static Color _dim(Color c) => c.withValues(alpha: 0.5);

  static final ButtonStyle _style = ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return _dim(AppColors.red);
      if (states.contains(WidgetState.pressed)) return AppColors.redPressed;
      if (states.contains(WidgetState.hovered)) return AppColors.redHover;
      return AppColors.red;
    }),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? _dim(AppColors.gold)
          : AppColors.gold,
    ),
    side: WidgetStateProperty.resolveWith(
      (states) => BorderSide(
        color: states.contains(WidgetState.disabled)
            ? _dim(AppColors.gold)
            : AppColors.gold,
        width: 3,
      ),
    ),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    ),
    textStyle: WidgetStatePropertyAll(AppText.button),
    // Qt has no ripple — colour change only.
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    splashFactory: NoSplash.splashFactory,
    elevation: const WidgetStatePropertyAll(0),
    mouseCursor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: _style.copyWith(padding: WidgetStatePropertyAll(size.padding)),
      child: Text(label),
    );
  }
}
