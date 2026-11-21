import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../widgets/design_canvas.dart';
import '../widgets/step_selector.dart';
import '../widgets/themed_button.dart';

/// Shows the guest's strip, lets them choose how many strips to print, and
/// prints.
///
/// Port of py-photobooth `ui/print_screen.py`:
/// - "Your Photo is Ready!", preview strip + "Number of prints" stepper
///   (starts 2, min 2, step 2, no max);
/// - Back to Selection / Print Photo / Start Over;
/// - "Sent to print" popup with OK — unless [onPrinted] is given: then the
///   app shell moves on to the share screen (GIF + QR), even if printing
///   failed.
///
/// The screen only drives the UI: [buildSheet] makes the full print sheet
/// and [printSheet] saves + prints it (the app shell does both). With the
/// popup, every Print press prints again, as in Python; with [onPrinted],
/// there's one print per visit to this screen.
///
/// Fixes: the print count starts at 2 for every guest (Python kept the last
/// guest's count); Print is disabled while a job is being sent; errors show
/// a message (or go to [onPrinted]) instead of crashing.
class PrintScreen extends StatefulWidget {
  const PrintScreen({
    super.key,
    required this.buildSheet,
    required this.printSheet,
    required this.onBack,
    required this.onStartOver,
    this.onPrinted,
  });

  /// Builds the full composite. The screen owns and disposes the image.
  final Future<ui.Image> Function() buildSheet;

  /// Saves and prints [sheet] for [prints] strips. Throw to report failure.
  final Future<void> Function(ui.Image sheet, int prints) printSheet;

  /// Back to Selection.
  final VoidCallback onBack;
  final VoidCallback onStartOver;

  /// After Print: `true` = sent to the printer, `false` = it failed. Null =
  /// stay here and show the "Sent to print" popup (no GIF or QR to share).
  final void Function(bool printed)? onPrinted;

  @override
  State<PrintScreen> createState() => _PrintScreenState();
}

class _PrintScreenState extends State<PrintScreen> {
  ui.Image? _sheet;
  bool _failed = false;
  bool _printing = false;
  int _prints = 2;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sheet?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final sheet = await widget.buildSheet();
      if (!mounted) {
        sheet.dispose();
        return;
      }
      setState(() => _sheet = sheet);
    } catch (error) {
      debugPrint('PrintScreen: building the sheet failed: $error');
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _print() async {
    final sheet = _sheet;
    if (sheet == null || _printing) return;
    setState(() => _printing = true);
    var printed = true;
    try {
      await widget.printSheet(sheet, _prints);
    } catch (error) {
      debugPrint('PrintScreen: printing failed: $error');
      printed = false;
    }
    if (!mounted) return;
    setState(() => _printing = false);
    if (widget.onPrinted case final onPrinted?) return onPrinted(printed);
    await _showMessage(
      printed ? 'Sent to print' : "Couldn't print — please ask for help",
    );
  }

  Future<void> _showMessage(String message) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: AppColors.gold, width: 3),
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.button.copyWith(color: AppColors.red),
            ),
            const SizedBox(height: 30),
            ThemedButton(
              label: 'OK',
              size: ThemedButtonSize.compact,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DesignCanvas(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(60, 30, 60, 40),
          child: Column(
            children: [
              Text(
                'Your Photo is Ready!',
                style: AppText.heading.copyWith(fontSize: 40),
              ),
              const SizedBox(height: 20),
              Expanded(child: _panel()),
              const SizedBox(height: 30),
              _buttons(),
            ],
          ),
        ),
      ),
    );
  }

  /// Python: white panel with a 3 px gold top border; strip + stepper.
  Widget _panel() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.gold, width: 3)),
      ),
      padding: const EdgeInsets.only(top: 30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 480×640 fits both strip shapes (half of 1800×1200 = 900×1200
          // → 480×640; half of 1200×1800 = 600×1800 → 213×640).
          SizedBox(width: 480, height: 640, child: _strip()),
          const SizedBox(width: 60),
          StepSelector(
            value: _prints,
            min: 2,
            step: 2,
            label: 'Number of prints',
            onChanged: (value) => setState(() => _prints = value),
          ),
        ],
      ),
    );
  }

  /// Left half of the sheet — one guest strip, as it looks after cutting.
  Widget _strip() {
    final sheet = _sheet;
    if (sheet == null) {
      return Center(
        child: _failed
            ? Text(
                "Couldn't make your photo — please go back and try again",
                textAlign: TextAlign.center,
                style: AppText.label.copyWith(color: Colors.black45),
              )
            : const CircularProgressIndicator(color: AppColors.gold),
      );
    }
    return FittedBox(
      child: SizedBox(
        width: sheet.width / 2,
        height: sheet.height.toDouble(),
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            maxWidth: sheet.width.toDouble(),
            child: RawImage(
              image: sheet,
              width: sheet.width.toDouble(),
              height: sheet.height.toDouble(),
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buttons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ThemedButton(label: 'Back to Selection', onPressed: widget.onBack),
        const SizedBox(width: 20),
        ThemedButton(
          label: _printing ? 'Printing…' : 'Print Photo',
          onPressed: _sheet != null && !_printing ? _print : null,
        ),
        const SizedBox(width: 20),
        ThemedButton(label: 'Start Over', onPressed: widget.onStartOver),
      ],
    );
  }
}
