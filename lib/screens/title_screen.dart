import 'package:material_ui/material_ui.dart';

import '../widgets/decorative_button.dart';
import '../widgets/design_canvas.dart';

/// First screen: full-screen background with a big START button.
///
/// Port of py-photobooth `ui/title_screen.py`. The screen only reports the
/// tap via [onStart]; creating the session and navigating to the camera is
/// the app shell's job (Python's main window handled `create_session_signal`).
class TitleScreen extends StatelessWidget {
  const TitleScreen({super.key, required this.onStart});

  /// Called when START is tapped. Null disables the button (e.g. while the
  /// app is still loading).
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DesignCanvas(
        background: AppBackgrounds.solid,
        child: Padding(
          // Python: setContentsMargins(100, 0, 100, 80), bottom-centre.
          padding: const EdgeInsets.fromLTRB(100, 0, 100, 80),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: DecorativeButton(label: 'START', onPressed: onStart),
          ),
        ),
      ),
    );
  }
}
