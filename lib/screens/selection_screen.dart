import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../config/templates.dart';
import '../theme/app_theme.dart';
import '../widgets/design_canvas.dart';
import '../widgets/selectable_image.dart';
import '../widgets/themed_button.dart';

/// What the guest chose: photos in tap order and the frame.
class Selection {
  const Selection({required this.photos, required this.template});

  /// Paths in the order tapped — slot `i` gets `photos[i % length]`.
  final List<String> photos;
  final FrameTemplate template;
}

/// Builds the preview strip (left half of the composite) for a selection.
/// The caller owns the returned image.
typedef PreviewBuilder = Future<ui.Image> Function(
  FrameTemplate template,
  List<String> photos,
);

/// Pick 2 or 4 photos and a frame; shows a live preview strip.
///
/// Port of py-photobooth `ui/selection_screen.py`:
/// - photos in a grid of 300×225 tiles, tap to toggle (gold border);
/// - 2 selected → horizontal frames, 4 → vertical; first frame by default;
/// - frame swatches + "Select 2 or all 4 photos";
/// - preview strip 480×640; Next only when a preview is ready.
///
/// Differences: the preview stays in memory (Python wrote
/// `preview_strip_*.png` only to hand it to the print screen); swatches are
/// dimmed while the count isn't 2 or 4; a newer tap supersedes a preview
/// still being built.
class SelectionScreen extends StatefulWidget {
  const SelectionScreen({
    super.key,
    required this.photoPaths,
    required this.catalog,
    required this.buildPreview,
    required this.onNext,
    required this.onStartOver,
    this.imageFor,
    this.initialSelection,
  });

  /// This session's photos, oldest first.
  final List<String> photoPaths;
  final TemplateCatalog catalog;
  final PreviewBuilder buildPreview;
  final ValueChanged<Selection> onNext;
  final VoidCallback onStartOver;

  /// Thumbnail provider per path (tests inject memory images).
  final ImageProvider Function(String path)? imageFor;

  /// Restores the guest's picks when coming back from the print screen
  /// (Python's selection screen kept them because it was never rebuilt).
  final Selection? initialSelection;

  @override
  State<SelectionScreen> createState() => _SelectionScreenState();
}

class _SelectionScreenState extends State<SelectionScreen> {
  final List<String> _selected = [];
  FrameTemplate? _template;
  ui.Image? _preview;
  bool _building = false;
  bool _failed = false;
  int _request = 0;

  List<FrameTemplate> get _frames =>
      widget.catalog.forSelectionCount(_selected.length);

  /// Frames shown in the swatch row: the current count's family, or the
  /// 2-photo family (dimmed) while the count is invalid — as Python did.
  List<FrameTemplate> get _swatchFrames {
    final frames = _frames;
    return frames.isNotEmpty ? frames : widget.catalog.forSelectionCount(2);
  }

  bool get _valid => _frames.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSelection;
    if (initial != null) {
      _selected.addAll(initial.photos.where(widget.photoPaths.contains));
      if (_frames.contains(initial.template)) _template = initial.template;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshPreview();
      });
    }
  }

  @override
  void dispose() {
    _request++;
    _preview?.dispose();
    super.dispose();
  }

  void _togglePhoto(String path) {
    setState(() {
      if (!_selected.remove(path)) _selected.add(path);
      final frames = _frames;
      if (frames.isEmpty) {
        _template = null;
      } else if (_template == null || !frames.contains(_template)) {
        _template = frames.first; // default frame for this count
      }
    });
    _refreshPreview();
  }

  void _chooseFrame(FrameTemplate template) {
    if (!_valid || template == _template) return;
    setState(() => _template = template);
    _refreshPreview();
  }

  Future<void> _refreshPreview() async {
    final request = ++_request;
    final template = _template;
    _setPreview(null);
    if (template == null) {
      setState(() {
        _building = false;
        _failed = false;
      });
      return;
    }
    setState(() {
      _building = true;
      _failed = false;
    });
    try {
      final image = await widget.buildPreview(template, List.of(_selected));
      if (!mounted || request != _request) {
        image.dispose(); // superseded by a newer tap
        return;
      }
      setState(() {
        _setPreview(image);
        _building = false;
      });
    } catch (error) {
      debugPrint('SelectionScreen: preview failed: $error');
      if (!mounted || request != _request) return;
      setState(() {
        _building = false;
        _failed = true;
      });
    }
  }

  void _setPreview(ui.Image? image) {
    _preview?.dispose();
    _preview = image;
  }

  void _next() {
    final template = _template;
    if (template == null || _preview == null) return;
    widget.onNext(Selection(photos: List.of(_selected), template: template));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DesignCanvas(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(60, 40, 60, 30),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _previewPanel(),
                    const SizedBox(width: 100),
                    _photoGrid(),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(height: 170, child: _bottomBar()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewPanel() {
    final preview = _preview;
    final Widget content;
    if (preview != null) {
      content = RawImage(
        image: preview,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
    } else if (_building) {
      content = const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    } else {
      content = Center(
        child: Text(
          _failed ? "Couldn't make the preview" : 'Pick your photos',
          textAlign: TextAlign.center,
          style: AppText.label.copyWith(color: Colors.black38),
        ),
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Preview', style: AppText.heading),
        const SizedBox(height: 10),
        SizedBox(width: 480, height: 640, child: content),
      ],
    );
  }

  Widget _photoGrid() {
    final imageFor = widget.imageFor ?? (path) => FileImage(File(path));
    return SizedBox(
      width: 300 * 2 + 30,
      child: Wrap(
        spacing: 30,
        runSpacing: 30,
        children: [
          for (final path in widget.photoPaths)
            SelectableImage(
              key: ValueKey(path),
              image: imageFor(path),
              selected: _selected.contains(path),
              onTap: () => _togglePhoto(path),
            ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final frames = _swatchFrames;
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Opacity(
                opacity: _valid ? 1 : 0.4,
                child: IgnorePointer(
                  ignoring: !_valid,
                  child: Wrap(
                    spacing: 20,
                    children: [
                      for (final t in frames)
                        FrameSwatch(
                          key: ValueKey(t.asset),
                          swatch: t.swatchAsset,
                          fallbackColor: t.colour,
                          selected: _valid && t == _template,
                          onTap: () => _chooseFrame(t),
                          semanticLabel: 'Frame ${t.designNumber}',
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select 2 or all 4 photos',
                style: AppText.heading.copyWith(fontSize: 32),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ThemedButton(
                label: 'Start Over',
                size: ThemedButtonSize.compact,
                onPressed: widget.onStartOver,
              ),
              const SizedBox(height: 14),
              ThemedButton(
                label: 'Next',
                size: ThemedButtonSize.compact,
                onPressed: _preview != null && !_building ? _next : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
