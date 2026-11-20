import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// One image file of a background, with the aspect ratio it was made for.
class BackgroundVariant {
  const BackgroundVariant(this.asset, this.aspectRatio);

  final String asset;

  /// width ÷ height of the image.
  final double aspectRatio;
}

/// A background available in several aspect ratios. [DesignCanvas] shows the
/// variant whose ratio is closest to the screen's, so each device gets the
/// least-cropped image: 16:9 on monitors / the Windows kiosk, the wider-than-
/// 4:3 original on iPad.
class AppBackground {
  /// [variants] must not be empty.
  const AppBackground(this.variants);

  final List<BackgroundVariant> variants;

  /// The variant best matching a screen of [aspectRatio] (width ÷ height).
  BackgroundVariant forAspectRatio(double aspectRatio) {
    var best = variants.first;
    for (final v in variants) {
      if ((v.aspectRatio - aspectRatio).abs() <
          (best.aspectRatio - aspectRatio).abs()) {
        best = v;
      }
    }
    return best;
  }
}

/// Backgrounds available to screens. To add a ratio, export the image,
/// add it under `assets/ui/` and list it here.
class AppBackgrounds {
  AppBackgrounds._();

  static const AppBackground solid = AppBackground([
    BackgroundVariant('assets/ui/background_solid-1920x1080.png', 16 / 9),
    BackgroundVariant('assets/ui/background_solid.png', 5334 / 3264),
  ]);

  static const AppBackground transparent = AppBackground([
    BackgroundVariant('assets/ui/background_transparent-1920x1080.png', 16 / 9),
    BackgroundVariant('assets/ui/background_transparent.png', 5334 / 3264),
  ]);
}

/// Fixed 1920×1080 design surface, scaled uniformly to fit any screen.
///
/// Children are laid out in *design pixels*, so sizes from the Python app
/// (800×120 START button, 480×640 preview, …) can be used as-is and look the
/// same on a 1080p kiosk, a laptop, or an iPad.
///
/// Layers (bottom → top):
/// 1. Plain [AppColors.background] fill over the whole screen.
/// 2. Optional [background] image — the variant closest to the screen's
///    aspect ratio — cover-fit over the **whole screen** (not just the
///    canvas), so letterbox bars on non-16:9 screens (e.g. iPad 4:3) show the
///    image instead of empty space.
/// 3. The [child], centred and scaled to fit (contain) — never cropped.
class DesignCanvas extends StatelessWidget {
  const DesignCanvas({super.key, required this.child, this.background});

  static const double width = 1920;
  static const double height = 1080;
  static const Size size = Size(width, height);

  /// Background, e.g. [AppBackgrounds.solid].
  final AppBackground? background;

  /// Content laid out in a [width]×[height] box.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (background case final background?)
            LayoutBuilder(
              builder: (context, constraints) {
                final ratio = constraints.biggest.aspectRatio;
                final variant = background.forAspectRatio(
                  ratio.isFinite && ratio > 0 ? ratio : 16 / 9,
                );
                return Image(
                  // Sources are ~4K; decode smaller to save memory (iPad).
                  image: ResizeImage(AssetImage(variant.asset), width: 2560),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                );
              },
            ),
          Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(width: width, height: height, child: child),
            ),
          ),
        ],
      ),
    );
  }
}
