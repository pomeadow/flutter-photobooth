import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/drive_upload_service.dart';
import '../theme/app_theme.dart';
import '../widgets/design_canvas.dart';
import '../widgets/themed_button.dart';

/// Shown after Print Photo (NEW, py-photobooth had a "Sent to print" popup):
/// the print status, the guest's GIF and a QR code to their Drive folder.
///
/// - [printed] false → "Couldn't print" note; the guest still gets the GIF
///   and QR.
/// - Done (or [idleTimeout] without a tap) → [onDone], so the next guest
///   isn't left looking at the last guest's QR code. Any tap restarts the
///   countdown.
class ShareScreen extends StatefulWidget {
  const ShareScreen({
    super.key,
    required this.printed,
    required this.onDone,
    this.gif,
    this.driveFolder,
    this.idleTimeout = const Duration(seconds: 60),
  });

  /// Whether the print job was sent.
  final bool printed;
  final VoidCallback onDone;

  /// The guest's animated GIF. Null result = it couldn't be made (panel
  /// hidden); no future = feature off.
  final Future<Uint8List?>? gif;

  /// Link to the guest's session folder on Drive, shown as a QR code. Null
  /// result = upload/folder failed (panel hidden); no future = feature off.
  final Future<DriveFolder?>? driveFolder;

  final Duration idleTimeout;

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  Timer? _idle;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _restartIdle();
  }

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  void _restartIdle() {
    _idle?.cancel();
    _idle = Timer(widget.idleTimeout, _finish);
  }

  /// Once only: Done and the timeout can't both fire [onDone].
  void _finish() {
    if (_done) return;
    _done = true;
    _idle?.cancel();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _restartIdle(),
      child: Scaffold(
        body: DesignCanvas(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(60, 30, 60, 40),
            child: Column(
              children: [
                Text(
                  widget.printed
                      ? 'Sent to print!'
                      : "Couldn't print — please ask for help",
                  style: AppText.heading.copyWith(
                    fontSize: 40,
                    color: widget.printed ? null : AppColors.red,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(child: _panel()),
                const SizedBox(height: 30),
                ThemedButton(label: 'Done', onPressed: _finish),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
          if (widget.gif case final gif?) _gifPanel(gif),
          if (widget.gif != null && widget.driveFolder != null)
            const SizedBox(width: 80),
          if (widget.driveFolder case final folder?) _qrPanel(folder),
        ],
      ),
    );
  }

  /// "Your GIF": spinner while it's being made, then the looping animation
  /// (Flutter plays animated GIFs natively). Hidden if it couldn't be made.
  Widget _gifPanel(Future<Uint8List?> gif) {
    return FutureBuilder<Uint8List?>(
      future: gif,
      builder: (context, snapshot) {
        final done = snapshot.connectionState == ConnectionState.done;
        final bytes = snapshot.data;
        if (done && bytes == null) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Your GIF', style: AppText.heading),
            const SizedBox(height: 12),
            Container(
              width: 800,
              height: 450,
              decoration: BoxDecoration(
                color: AppColors.disabledFill,
                border: Border.all(color: AppColors.gold, width: 3),
              ),
              child: bytes == null
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.gold),
                    )
                  : Image.memory(
                      bytes,
                      key: const ValueKey('guest-gif'),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                    ),
            ),
          ],
        );
      },
    );
  }

  /// "Scan for your photos": spinner until the Drive folder is ready, then a
  /// QR code linking to it. Hidden if the folder couldn't be made.
  Widget _qrPanel(Future<DriveFolder?> folder) {
    return FutureBuilder<DriveFolder?>(
      future: folder,
      builder: (context, snapshot) {
        final done = snapshot.connectionState == ConnectionState.done;
        final ready = snapshot.data;
        if (done && ready == null) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Scan for your photos', style: AppText.heading),
            const SizedBox(height: 12),
            Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.gold, width: 3),
              ),
              alignment: Alignment.center,
              child: ready == null
                  ? const CircularProgressIndicator(color: AppColors.gold)
                  : QrImageView(
                      key: const ValueKey('drive-qr'),
                      data: ready.url.toString(),
                      size: 330,
                      backgroundColor: Colors.white,
                    ),
            ),
          ],
        );
      },
    );
  }
}
