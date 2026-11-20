# CLAUDE.md

This file guides Claude Code when working in this repository.

## Project purpose

`flutter_photobooth` is a **Flutter port of an existing Python/PySide6 photobooth app** at
`/Users/chewyan/PROJECTS/py-photobooth`. The port is in progress, built one file per step with
user approval (see **Port progress & design decisions** below). The Python app is the
**reference implementation**. When behavior is unclear, read the Python source; don't guess.

Theme: a Christmas-themed event photobooth for a kiosk/touchscreen. It captures photos, lets
the guest choose photos and a frame colour, builds a print-ready composite, and sends it to
Canon SELPHY CP1500 printer(s).

## Commands

```bash
flutter pub get
flutter run -d macos          # primary dev target (desktop kiosk); also windows for printing
flutter analyze
flutter test
dart format .
```

Lints: `flutter_lints` via `analysis_options.yaml`, which also excludes `build/` and the
platform folders. **Flutter ≥3.47 (Dart `^3.13.0`) is required**: `material_ui` needs 3.47 and
`printing` 5.15 needs 3.41. Developed on **Flutter 3.50.1 / Dart 3.14**.

**Import Material from `package:material_ui/material_ui.dart`, never
`package:flutter/material.dart`.** Material moved out of the Flutter SDK in 3.47, and the old
import is deprecated. `dart fix --apply` migrates stray imports.

## User flow (from the Python app, v0.1)

1. **Title screen**: full-screen background image with a big "START" button.
   Pressing it creates a new session folder and goes to the camera screen with `photosToTake = 4`.
2. **Camera screen**:
   - Live, horizontally **mirrored** preview. The saved photo is **not** mirrored.
   - Counter label "Photos: N / 4" and a big countdown label.
   - First countdown is **10 s**. Later countdowns are **5 s**.
   - At **4 s remaining**, play `multi-sleigh-bells.wav`.
   - At 0: show "Time's up!", capture a frame, save it, flash white for **300 ms**
     (pause preview updates during the flash), stop the bells, and play `camera-flash_join.wav`.
   - After 4 photos, go to the selection screen. The back button returns to the title screen.
   - The camera starts at app launch and stops on window close. The first **90 frames are skipped**
     to hide the webcam's startup logo.
3. **Selection screen**:
   - Shows the session's photos in a 2×2 grid (4 per page; pagination exists but is hidden).
     Thumbnails are 300×225, aspect-fit.
   - Tapping a photo toggles selection (5 px gold border when selected).
   - Valid selection counts are **2 or 4**.
     - **2 selected** → **horizontal** templates (4 slots, "2 x 2" grid; photos go p1,p2,p1,p2).
     - **4 selected** → **vertical** templates (8 slots, two identical 4-photo strips).
     - Python's rule is `template.num_photos == selected * 2`. This line was backwards in an
       earlier version of this file; it was corrected in step 10.
     - Any other count hides the preview and disables "Next".
   - A row of frame pickers, one per eligible template. The first template is selected by
     default.
     - Python used **40 px plain colour circles**, coloured from the template's pixel at (10,10).
     - **The Flutter port uses 60 px swatch images instead.** See step 8 below.
     - The sampled colour is still used as the fallback.
   - The preview strip (480×640 box) is the **left half** of the full composite.
   - "Start over" goes to the title screen. "Next" goes to the print screen.
4. **Print screen**:
   - Shows the preview strip, a "Number of prints" stepper (starts at 2, min 2, step 2, no max),
     plus **Back**, **Print Photo**, and **Start over** buttons.
   - Print saves `final_composite_<YYYYmmdd_HHMMSS>.png` into the session folder with DPI
     preserved (default 300). It then sends it to the printer with `copies = prints / 2`,
     because each 4×6 sheet holds 2 strips that get cut in half. It shows a "Sent to print" popup.
   - Every press of Print creates a **new** composite file.
5. Returning to the title screen resets the session, camera screen, and selection state.

## Compositing algorithm (must match exactly)

Templates are 300 DPI PNGs in `resources/templates/v0.1/`:
- `Photo Frame Horizontal-0[1-6].png`: **1800×1200**, 4 slots.
- `Photo Frame Vertical-0[1-6].png`: **1200×1800**, 8 slots (two identical 4-photo columns,
  so the sheet is cut into 2 strips).

The type comes from the filename (`horizontal` in the lowercased name gives 4 slots, otherwise 8).
Templates are sorted by path.

Slots are `(x, y, w, h)` in template pixels (`config/load_metadata.py`):

```
Vertical (8):   (50,85,500,333) (50,475,500,333) (50,865,500,333) (50,1255,500,333)
                (650,85,500,333) (650,475,500,333) (650,865,500,333) (650,1255,500,333)
Horizontal (4): (40,40,840,540) (40,620,840,540) (920,40,840,540) (920,620,840,540)
```

For slot `i`, use `photo = selected[i % selected.length]`. Photos are drawn **over** the frame
in their slots, as Python pasted them over the slot pixels. Frame artwork that overlaps a slot
(e.g. the centre snowflake) is covered.

Fit each photo to its slot with cover scaling: `scale = max(slotW/w, slotH/h)`. Resize, then
**center-crop** to exactly `slotW×slotH`. Python used Lanczos to upscale and area interpolation
to downscale. Flutter decodes at reduced size and then draws with `FilterQuality.high`.

Preview strip: the left half (`width ~/ 2`) of the composite. Python first rebuilt the composite
from `photos + photos`, but that is identical to the `i % length` rule, so Flutter reuses the one
composite.

Output is PNG at **300 DPI** (the frames' DPI, 6×4 in). Python used the first photo's DPI, which
is 350 on the DSLR and gives the wrong print size.

An optional overlay (an RGBA PNG alpha-blended over live frames and captures) exists in Python
(`ImageProcessor.apply_overlay`), but it is **unused** (overlay path is empty).

## Sessions and files

- On START, a session folder `session_YYYYmmdd_HHMMSS/` is created under the working dir.
- Each capture is saved as `YYYY-mm-dd HHMMSS.ffffff_image.png` inside it.
- The selection screen lists `*.png` in the session folder, excluding names containing
  `preview_strip` or `composite`.
- The preview is written as `preview_strip_<n>photos.png`. Old previews are deleted on entering
  the selection screen.

## Configuration

`.env` in the Python app:
- `CAMERA_INDEX` (default 0)
- `CAMERA_WIDTH` / `CAMERA_HEIGHT` (default 1920×1080, 30 fps)

The Python repo has `list_cameras.py` to find the index. The Flutter equivalent should be a
config file or settings screen.

## Visual style

| Token | Value |
|---|---|
| Primary (deep red) | `#81151B` (hover `#B82424` / `#A01E1E`, pressed `rgb(100,15,20)`) |
| Accent (gold) | `#C9A961`, used for text, borders, and selected outlines |
| Screen background | `#FFFFFF` + `resources/UI Asset/UI Background (Solid Colour)-01.png` scaled to fill |
| Font | Impact (bold) for buttons and counters; `resources/fonts/DynaPuff-VariableFont_wdth,wght.ttf` is available |

- **DecorativeButton** (START): solid red fill with **concave (inward) 10 px quarter-circle
  corners**. It has an inner gold 3 px outline inset by 5 px following the same shape, plus gold
  Impact 60 pt centered text. Minimum size is 800×120. Build it in Flutter with a `CustomPainter`.
- Counter/timer labels: Impact 64 px bold, gold text on `#81151B`, 5 px gold border, rounded.
  The timer is circular.
- Regular buttons: red bg, gold text, 3 px gold border, radius 10, padding 20×40.
- Stepper: 80×80 red `-`/`+` buttons (radius 10, 32 px white bold) and a 120×80 read-only
  value box (36 px gold bold, 2 px red border).

Assets to copy from the Python repo (`resources/`): `templates/v0.1/*.png`, `UI Asset/*`,
`sounds/*.wav` (`multi-sleigh-bells.wav`, `camera-flash_join.wav`, plus unused beeps),
and `fonts/`. Register them under `flutter: assets:` / `fonts:` in `pubspec.yaml`.

## Printing

The Python app uses the git submodule `python_parallel_print`
(https://github.com/isaacwkz/python_parallel_print). It is **Windows-only** (pywin32). It finds
every printer whose name contains `"Canon SELPHY CP1500"` and distributes jobs across them. It
auto-rotates landscape images to portrait, and printer page size is about 1200×1800. The UI
currently uses `MockPrinter` (it logs only).

In Flutter, put printing behind an interface (e.g. `PrinterService`) with a mock implementation
and a real one, such as `printing` package or a platform channel. Keep the auto-rotate and
copies semantics.

## Suggested Flutter architecture (mirrors Python structure)

| Python | Flutter suggestion |
|---|---|
| `ui/main_window.py` (QStackedWidget, `navigate_to(name)`, `on_enter`/`on_exit` hooks) | Router or simple screen-state enum, with lifecycle via `initState`/`dispose` or a controller |
| `controllers/camera_controller.py` (OpenCV, 30 ms timer, skip 90 frames) | `camera` / `camera_macos` / `camera_windows` plugin wrapped in a `CameraService` |
| `controllers/session_manager.py` | `SessionService` (folder creation, `savePhoto`, template info, reset) |
| `controllers/image_processor.py` | `CompositeService` using `package:image` (run in an isolate; images are large) |
| `config/load_metadata.py` | Template config (slots + colour sampled at pixel 10,10) |
| `components/countdown_timer.py` | `Timer.periodic` countdown: tick(n) … finished |
| `components/flash_overlay.py` | White overlay shown for 300 ms |
| `components/range_selector.py` | Stepper widget (min/step/optional max) |
| `utils/utils.load_sound_effect` | `audioplayers` / `just_audio` |

## Known quirks in the Python reference (don't port these bugs)

- `pyproject.toml` is stale. `requirements.txt` is the real dependency list (PySide6 6.10,
  opencv, pillow, numpy, python-dotenv).
- `CameraScreen._capture_photo` blocks with a nested `QEventLoop` for 100 ms. Use async delays.
- `SessionManager.photo_count` is never incremented.
- The template-colour row compares the path to an int when adding spacing, so it always adds spacing.
- `print_screen._on_print_clicked` references `output_path` even when there is no session folder.

## Port progress & design decisions

Workflow: one file per step, and the user approves each step before the next. The full step list
is in `~/.claude/plans/can-you-add-each-mellow-dewdrop.md`. Keep the original step order; the user
declined pulling the title screen forward.

Every step ends with this checklist:
1. `dart format lib test test_preview`
2. `flutter analyze`
3. `flutter test test --timeout 60s`. The whole suite has been green since step 19 (156 tests at step 22c).
4. **No preview renders or mock-ups any more (user's request, step 19).** Check visible work by
   running the app with `flutter run -d macos`, which always uses the real camera. The existing
   `test_preview/` renders are kept but no longer extended.
5. Update this section with any decision or change from Python.
6. **If the step changes setup, permissions, file locations, assets or commands, update
   `README.md` too.** It's the human-facing setup guide for build machines and event devices.
7. Ask the user to approve.


### Platforms
- Targets are **macOS (dev) + Windows (kiosk) + possibly iPad**.
- **The app has no fake camera**, matching py-photobooth, which only had a `MockPrinter`. The
  fake camera exists **for tests only**, in `test/support/fake_camera.dart` (user's decision,
  step 19).
- Real cameras:
  - `camera` plugin for Windows + iPad.
  - `camera_macos` for macOS.
- Printing goes through the `printing` package (AirPrint on iPad/macOS, spooler on Windows),
  behind a `PrinterService`. `MockPrinterService` is the default until the SELPHY is verified.
- Sessions are stored under `path_provider`'s documents dir, not the working dir, because iPad
  has no working dir.

### Layout
- Every screen renders on a fixed **1920×1080 design canvas** scaled with `FittedBox`
  (`lib/widgets/design_canvas.dart`). Python pixel sizes are used as-is in canvas pixels.

### Assets (step 0)
- `resources/` from the Python repo was copied to `assets/` and renamed to snake_case:
  - `assets/templates/photo_frame_{horizontal,vertical}_0N.png` (identical to `templates/v0.1/`).
  - `assets/ui/background_solid.png`, `background_transparent.png`, `start_button.png`.
  - `assets/sounds/*.wav` (the hyphens became underscores).
  - `assets/fonts/DynaPuff.ttf`.
- Horizontal/vertical detection still goes by filename (`horizontal` → 4 slots).
- Not copied: the design reference images ("Overall Sample", "Colour Code.JPG") and the `.mp3`
  beep (a `.wav` duplicate exists).
- Package dependencies are added only in the step that needs them.

### Theme & fonts (step 1, `lib/theme/app_theme.dart`)
- **Fonts are named only in `AppFonts`.** `display = 'Impact'`, `fallback = ['DynaPuff']`.
  Widgets use `AppText.*` styles and never hard-code a font name.
- Impact is **not bundled** because it's a licensed system font (macOS/Windows). iPad falls back
  to DynaPuff.
- To switch font: change `AppFonts.display`, register the `.ttf` in `pubspec.yaml` if needed,
  then do a full restart.
- Two hover shades are kept deliberately:
  - Regular buttons: `redHover #B82424` / `redPressed #A01E1E`.
  - DecorativeButton: `decorativeHover #A01E1E` / `decorativePressed #640F14`.
- Sizes that differ from Python:
  - Regular button text is **32 px**. Python left it at the Qt default, which is too small on
    1920×1080.
  - The stepper caption is **24 px** (Qt 18 pt ≈ 24 px).
- `AppText` base style sets `decoration: TextDecoration.none`, so text outside a `Material`
  never shows Flutter's yellow debug underline. This was added during step 3.

### Design canvas (step 2, `lib/widgets/design_canvas.dart`)
- `DesignCanvas(background:, child:)` has three layers:
  - A white fill.
  - An optional background image, **cover-fit across the whole screen**.
  - The child in a 1920×1080 box, contain-scaled and centred.
- On non-16:9 screens (iPad 4:3) the bars show the background image, not empty space. Content is
  never cropped.
- **Differs from Python:** Python stretched the 5334×3264 (≈1.63:1) background to the window,
  which distorted it. Flutter uses cover, so the edges crop slightly and nothing distorts.
- The background is decoded at 2560 px wide (`ResizeImage`) to save memory on iPad.
- Background paths: `AppBackgrounds.solid` / `.transparent`. Python used the solid one on the
  title screen only; other screens are plain white.
- Test: `test/widgets/design_canvas_test.dart` checks the child gets exactly 1920×1080 at 1080p
  and at iPad size.


### DecorativeButton (step 3, `lib/widgets/decorative_button.dart`)
- `DecorativeButton(label:, onPressed:, minWidth: 800, minHeight: 120)`.
- Geometry matches the Qt `paintEvent`:
  - The red fill is the rect inset 10 px, with a quarter-circle of radius 10 cut at each corner
    (centred on the corner, so the corner is concave).
  - The gold 3 px outline is the same shape inset 15 px.
  - The outer 10 px margin is transparent.
- The button **hugs its minimum size**: `Center(widthFactor: 1, heightFactor: 1)`. Without that
  it would stretch to fill the parent. Text has horizontal padding only, so the height stays 120.
- States:
  - Fill colour: red → `decorativeHover` on hover → `decorativePressed` while pressed.
  - `onPressed: null` means disabled. It renders at 50 % opacity, with no hover/tap. This is new;
    Python never disabled this button.
- Tests: `test/widgets/decorative_button_test.dart` (tap, 800×120 size, disabled).

### ThemedButton (step 4, `lib/widgets/themed_button.dart`)
- `ThemedButton(label:, onPressed:, size: ThemedButtonSize.regular | .compact)`.
- Built on `TextButton` + `ButtonStyle`, so focus, keyboard and semantics come free.
- Look:
  - Red fill, gold text, 3 px gold border, radius 10.
  - Hover is `redHover`, pressed is `redPressed`.
  - There's no ripple (transparent overlay, `NoSplash`), to match Qt.
- Sizes:
  - `regular` = padding 20×40 (`buttons_css`).
  - `compact` = padding 10×20 (the selection-screen override).
- **Margins aren't part of the button.** Python's `margin: 30px` / `5px` become spacing in each
  screen's layout.
- **Differs from Python:** disabled buttons are **dimmed to 50 %**. In Python, the disabled
  "Next" looked identical to the enabled one, because the stylesheet had no `:disabled` rule.
  Guests couldn't tell why it didn't work.
- Tests: `test/widgets/themed_button_test.dart` (tap, state colours, disabled, compact < regular).

### BadgeLabel (step 5, `lib/widgets/badge_label.dart`)
- `BadgeLabel.counter(taken:, total:)` shows "Photos: N / M". It's a rounded rect (radius 20,
  padding 15), matching `counter_css`.
- `BadgeLabel.timer(seconds:)` is a **circle** for numbers. When `seconds` is null it's a
  **pill** reading "Time's up!".
- All badges have a red fill, gold Impact 64 text, and a 5 px gold border. They hug their
  content instead of filling the parent.
- **Differs from Python:** `timer_css` uses `border-radius: 50%`, but Qt stylesheets don't
  support percentage radii, so the Python timer was actually rectangular. The Flutter timer is
  really round.
- Circle sizing: the private `_Square` render box makes the badge square, with side =
  max(natural width, natural height), and `CircleBorder` draws on that. So "3" and "10" come out
  as identical circles.
- Tests: `test/widgets/badge_label_test.dart`. Preview: `build/preview/badge_label.png`.

### StepSelector (step 6, `lib/widgets/step_selector.dart`)
- `StepSelector(value:, onChanged:, min:, max:, step: 2, label:)` lays out "− [value] +" with an
  optional caption above.
- It's **controlled**: the parent screen owns `value`.
  - Python kept the value inside the widget and never reset it, so the next guest inherited the
    previous guest's print count.
  - **Step 21 must reset prints to 2 on every new session.**
- Look matches `range_selector.py`:
  - 80×80 red −/+ buttons (radius 10, white 32 px).
  - A 120×80 read-only value box (`#F5F5F5` fill, 2 px red border, gold 36 px).
  - 20 px gaps, and the caption in `AppText.label`.
- **Differs from Python:**
  - Values are **clamped** to min..max. Python checked the limit *before* adding the step, so it
    could overshoot (max 5, value 4 → 6) or undershoot.
  - The − / + button is **disabled and dimmed** at its limit. In Python it stayed active and did
    nothing.
- The buttons have semantics labels "Decrease" / "Increase", which the tests use.
- Tests: `test/widgets/step_selector_test.dart`. Preview: `build/preview/step_selector.png`.

### FlashOverlay (step 7, `lib/widgets/flash_overlay.dart`)
- Usage: `FlashOverlay(controller: FlashController(), child: <camera preview>)`. After each
  capture, `await controller.flash()`. `controller.isFlashing` and the `onStart` / `onEnd`
  callbacks replace Python's `flash_started` / `flash_finished` signals.
- The overlay is a white layer **on top of** the preview, wrapped in `IgnorePointer`. Python
  swapped the preview pixmap and paused frame updates; Flutter has no need to pause.
- **Differs from Python (deliberately, for the "Smoothen the animations" item below):**
  - The total is still 300 ms, but it's **150 ms full white + 150 ms fade-out**, where Python
    snapped back instantly.
  - `fadeOut: Duration.zero` restores Python's exact behaviour. `hold` and `fadeOut` are both
    configurable.
- Calling `flash()` while a flash is running returns the same in-progress future, so there's
  never a double flash.
- Tests: `test/widgets/flash_overlay_test.dart`. Preview: `build/preview/flash_overlay.png`, a
  filmstrip at before / 0 / 75 / 150 / 225 ms.
- **Testing gotcha (animations):**
  - An animation's clock starts on the first frame *after* it's triggered, so call
    `tester.pump()` immediately after triggering.
  - An animation only completes when strictly *past* its duration.
  - `onEnd`-style code that runs after `await animation` needs one extra `pump()`.
- `renderPreview(..., beforeCapture: (tester) async {...})` lets a preview trigger and advance
  animations before the snapshot. Afterwards the helper runs `pumpAndSettle()`.

### Assets: frame swatches (step 8)
- The 6 frames come in **3 colour pairs with 2 designs each**. At pixel (10,10):

  | Frames | Colour | Hex |
  |---|---|---|
  | 01/02 | navy | `#162D3E` |
  | 03/04 | red | `#82151C` |
  | 05/06 | green | `#083F1F` |

  Odd numbers have stars and lines; even numbers have snowflakes. Plain colour circles can't
  tell the pairs apart.
- **The user chose designer-provided swatch images:**
  - Files are **per orientation**:
    `assets/swatches/swatch_{horizontal|vertical}_0N.png`, **120×120 px**, square. The circle
    mask is applied in code.
  - The path comes from `FrameTemplate.swatchAsset`, introduced in step 10.
- **Horizontal swatches are real.** The user supplied them in step 10 (they first landed in
  `assets/templates/` and were moved).
  - They include **opaque white corners** from the photo slots. The user was told; this is the
    designer's call.
- **Vertical swatches are still placeholders.** Each is a 200×200 crop at x 200–400,
  y 1595–1795 of `photo_frame_vertical_0N.png` (the starburst/snowflake corner below the last
  photo slot), scaled to 120×120. The designer can overwrite them with the same names.
- Cropping the horizontal frames at their centre was tried and rejected: the crop catches the
  white photo slots and looks like a "+".

### SelectableImage + FrameSwatch (step 8, `lib/widgets/selectable_image.dart`)
- `SelectableImage(image:, selected:, onTap:)`:
  - A 300×225 tile with the photo fitted inside (contain), as in Python.
  - When selected, it gets a 5 px gold border drawn on top, so the photo doesn't shift.
  - It decodes at most 600 px wide (`ResizeImage`), because camera photos can be 6000×4000
    (24 MP).
- `FrameSwatch(swatch:, fallbackColor:, selected:, onTap:, diameter: 60)`:
  - A 60 px circle showing the swatch image.
  - When selected, it gets a 5 px gold ring (as in Python).
  - **If the image is missing or broken, it shows the plain `fallbackColor` circle** (the Python
    look). The sampled colour also shows while the image loads.
- The step 8 helper `FrameSwatch.swatchAssetFor(n)` was **removed in step 10**. Use
  `FrameTemplate.swatchAsset` instead.
- Tests: `test/widgets/selectable_image_test.dart`. Preview: `build/preview/selectable_image.png`
  (real photos from `py-photobooth/play2`, with swatch 06 deliberately missing to show the
  fallback). Comparison render from the decision: `build/preview/swatch_comparison.png`.
- **Preview gotcha:**
  - `FileImage` never finishes loading on the widget-test fake clock, even with `runAsync`
    precache, and the run hangs.
  - Use `await tester.runAsync(() => shrunkPhoto(path))` from `preview_helper.dart`, which
    returns a small `MemoryImage`.
  - Run previews with `flutter test test_preview --timeout 90s`, so a hang fails fast.

### CountdownController (step 9, `lib/services/countdown_controller.dart`)
- `CountdownController(onTick:, onFinished:)` with `start(n)`, `stop()`, `remaining`,
  `isRunning`, `isFinished`. It's also a `ChangeNotifier`, so the timer badge can use a
  `ListenableBuilder`.
- **Same timeline as Python:**
  - `onTick(n)` fires immediately, then `n-1 … 1` once a second, then `onFinished` at *n*
    seconds. There's no tick 0.
  - The camera's bells cue on tick 4, which comes 6 s into the 10 s countdown and 1 s into
    the 5 s ones.
- `remaining`:
  - `n … 1` while running.
  - `0` after finishing; the UI shows "Time's up!" (`BadgeLabel.timer(seconds: null)`).
  - `null` when idle or stopped.
- `start()` while running replaces the countdown. `stop()` never calls `onFinished`, and calling
  it when idle does nothing.
- **Python bugs not ported:**
  - Every `start()` emitted a spurious `cancelled`, because the running flag was set before
    `stop()`.
  - `remaining_seconds` never updated.
  - The unused `started` / `cancelled` signals were dropped.
- Tests: `test/services/countdown_controller_test.dart`. They use `testWidgets` +
  `tester.pump(Duration)` to advance timers instantly, so no `fake_async` dependency is needed.
  There's no preview, since it isn't visual.

### Templates (step 10, `lib/config/templates.dart`)
- `PhotoSlot(x, y, width, height)` uses int frame pixels.
- `FrameLayout` enum:
  - `grid2x2`: horizontal, 1800×1200, 4 slots, **2 photos selected**.
  - `strip2x4`: vertical, 1200×1800, 8 slots, **4 photos selected**.
  - The slot tables are copied verbatim from Python, and a test pins them.
  - `FrameLayout.fromFileName` (the "horizontal" rule) and `forSelectionCount(n)` (null unless
    n is 2 or 4).
- `FrameTemplate`: `asset`, `layout`, `designNumber` (trailing digits), `colour` (pixel 10,10),
  `swatchAsset`.
- `TemplateCatalog.load()`:
  - Lists `assets/templates/*.png` from the `AssetManifest`, sorted by path.
  - **Checks each frame's size against its layout** and throws a clear `StateError` otherwise.
    Python silently mis-composited in that case.
  - `forSelectionCount(n)` returns the frames in path order; the first is the default.
- **Every PNG in `assets/templates/` must be a frame.** Put swatches and other images
  elsewhere, or loading fails. That's how the misplaced swatches were caught.
- Colours are sampled with `dart:ui`'s native decoder, **not the `image` package**. It's faster
  at startup, and no new dependency was needed. `image` is planned for step 12, where
  isolate-based compositing needs it.
- Tests: `test/config/templates_test.dart`:
  - Filename rule, count → layout, the exact slot tables, and slots inside frames.
  - With the real assets: 12 frames, 6 per count, the default, the colours, the swatch paths,
    and that every swatch exists.
- **Stale test assets gotcha:** after moving or renaming assets, `flutter test` can keep serving
  old files from `build/unit_test_assets/`. Delete that folder; don't run `flutter clean`,
  which would also wipe `build/preview/`.

### SessionService (step 11, `lib/services/session_service.dart`)
- Dependencies added: `path_provider`, `path`.
- `SessionService.inDocuments()` puts sessions in
  `<app documents>/photobooth_sessions/session_YYYYmmdd_HHMMSS/`. The constructor also takes
  `root:` and `clock:` for tests.
- **Where photos land** (bundle id `com.occ.photobooth` since step 22b):
  - macOS (sandboxed):
    `~/Library/Containers/com.occ.photobooth/Data/Documents/photobooth_sessions/`
  - Windows: `%USERPROFILE%\Documents\photobooth_sessions\`
  - iPad: the app's Documents folder. To show it in the Files app, set
    `UIFileSharingEnabled` / `LSSupportsOpeningDocumentsInPlace` later.
- API:
  - `createSession()`, `current`, `reset()`.
  - `savePhoto(bytes, extension: 'jpg')`, `listPhotos()`.
  - `savePreviewStrip(png, n)`, `deletePreviewStrips()`, `saveFinalComposite(png)`.
  - `Session.template` holds the chosen `FrameTemplate`.
- File names match Python:
  - `YYYY-mm-dd HHMMSS.ffffff_image.<ext>`
  - `preview_strip_<n>photos.png`
  - `final_composite_YYYYmmdd_HHMMSS.png`
- **Differs from Python:**
  - **Same-second collisions** add a `_2`, `_3`… suffix to folders and files. Python reused
    the folder (`exist_ok=True`), which mixed two guests' photos.
  - **No session → `StateError`.** Python silently saved to the working directory.
  - **Photos are saved in the camera's format**, so `.jpg` by default and not re-encoded to
    PNG. `listPhotos()` accepts `.jpg`, `.jpeg` and `.png`, excluding names containing
    `preview_strip` or `composite`. It's sorted by name, which is chronological; Python's
    listing order wasn't guaranteed.
  - `reset()` keeps the files on disk, as Python did.
- **Open question (not implemented):** sessions accumulate forever (guest photos, disk space).
  Decide on retention/cleanup before an event.
- Tests: `test/services/session_service_test.dart`. They use a temp dir and a fixed clock, and
  cover naming, collisions, listing filter and order, previews, composites, reset, and no-session
  errors.

### CompositeService (step 12, `lib/services/composite_service.dart`)
- **Uses `dart:ui` (native, engine threads), not the `image` package.** No dependency was
  added; the plan had assumed `image` in an isolate.
  - Pure-Dart decoding of 6000×4000 JPEGs would be slow.
  - `ImageDescriptor` + `instantiateCodec(targetWidth:)` shrinks while decoding, never
    upscaling. `drawImageRect` with `FilterQuality.high` does the final fit.
- API:
  - `compose(template, photoPaths)` returns the full `ui.Image`. The caller disposes it.
  - `previewStrip(composite)` returns the left half.
  - `encodePng(image, dpi: 300)` returns PNG bytes with a pHYs chunk.
  - `coverCrop(source, slot)` is Python's crop maths, as a source rect.
  - `withDpi(png, dpi)` inserts or replaces pHYs (with a hand-rolled CRC32).
  - `clearCache()`.
- Draw order: white background, then the frame, then the photos (over the slots).
- **Caches** decoded frames (by asset) and photos (by path + slot size), so switching frame
  colour on the selection screen doesn't re-decode. Call `clearCache()` when a session ends.
- **Differs from Python:**
  - **Always 300 DPI.** Python used the photo's DPI: 350 from the DSLR, so the 6×4 print was
    tagged as 5.1×3.4 in. Python's `cv.imwrite` test outputs even say 72.
  - The preview strip reuses the composite (see the compositing section above).
  - Resampling is Flutter's high-quality filter instead of Lanczos/area. The test checks the
    crop geometry; the visual result was checked against the Python composites in
    `py-photobooth/play/`.
- **Measured with real 24 MP DSLR photos, in the test environment** (CPU rendering, so a real
  device should be faster):
  - 2 photos, horizontal: ~0.9 s.
  - 4 photos, vertical: ~1.2 s.
  - A colour switch with the decodes cached: ~0.55 s, mostly PNG encoding.
  - So the selection screen should show the preview from the `ui.Image` directly and **only
    encode PNG when printing**.
- Tests: `test/services/composite_service_test.dart`, using synthetic solid-colour photos:
  - Slot order for 2 and 4 photos; frame colour outside the slots.
  - Cover-crop band widths; a small photo upscaled edge to edge; `coverCrop` against Python's
    maths.
  - Preview = left half; pHYs = 11811 px/m; no duplicate pHYs; empty list rejected.
- Preview: `build/preview/composites.png` (prints + strips). The full-resolution outputs
  `build/preview/composite_*.png` are 1800×1200 / 1200×1800 at 300 DPI, and
  `composite_timings.txt` holds the timings.

### SoundService (step 13, `lib/services/sound_service.dart`)
- Dependency added: `audioplayers` (^6.7).
- `SoundService.load()` preloads `assets/sounds/multi_sleigh_bells.wav` and
  `camera_flash_join.wav`. Then: `playBells()` (camera tick 4), `stopBells({fade})`,
  `playShutter()`, `dispose()`.
- Audio sits behind the `SoundEffect` interface (`AudioplayersSoundEffect` is the real one).
  Tests inject fakes, so no audio device is needed.
- **Never throws.** Load, play and stop failures are logged with `debugPrint`, and a sound that
  fails to load is skipped. A sound problem must never block a capture.
- **Differs from Python (for the "smoothen sounds" item):** `stopBells()` **fades out over
  250 ms** (10 volume steps) instead of cutting off. `fade: Duration.zero` gives Python's hard
  stop. Calling `playBells()` during a fade cancels it.
- Tests: `test/services/sound_service_test.dart`: asset paths, capture order, the fade, cancel,
  swallowed failures, a failed load being skipped, dispose.

### Build environment (steps 13, 16 and 17)
- The full per-machine setup is written up in **`README.md` → Setup**. Keep it current.
- **No CocoaPods, anywhere.** It can't be installed on the dev Mac: an Intel Mac on macOS 14.4 is
  a "Tier 3" setup for Homebrew, and the Command Line Tools are outdated. **Apple platforms build
  with Swift Package Manager** instead:
  - `flutter config --enable-swift-package-manager` is a per-user global setting, enabled on
    this Mac.
  - `macos/Podfile` and `ios/Podfile` were **deleted**, as were the
    `#include? "Pods/Target Support Files/..."` lines in `macos/Flutter/Flutter-*.xcconfig` and
    `ios/Flutter/{Debug,Release}.xcconfig`. Flutter 3.50 runs CocoaPods while either exists.
    **Don't recreate them, and don't run `pod install`.** `flutter create .` would bring them
    back; delete them again if so.
  - The Xcode projects never had Pods wiring, so `pod deintegrate` isn't needed.
  - Flutter 3.50 reports "All plugins found for macos are Swift Packages".
- **Flutter was upgraded 3.35.4 → 3.50.1 in step 17** (user's decision), for two reasons:
  - `printing` only supports SPM from 5.15.0, which needs Flutter ≥3.41.
  - The published `camera_macos` 0.1.1 needs the `FlutterFramework` SPM package, which only
    newer Flutter generates.
  - Results:
    - The temporary **patched `packages/camera_macos` copy was removed**; we're back on the
      published `camera_macos: ^0.1.1`.
    - Packages were upgraded within their majors, e.g. `camera_avfoundation` 0.11 and
      `path_provider_foundation` 2.6.
    - All 25 Material imports were migrated to `material_ui`.
    - One fragile test was fixed (newer `MaterialApp` adds its own `ColoredBox`es).
    - Previews were re-rendered: 13 of 14 are pixel-identical, and `badge_label` differs only
      in border anti-aliasing (0.03 %).
- **Xcode 15.3 is fine for Flutter 3.50**, which requires 15 and recommends 16. An earlier note
  claiming newer Flutter needs Xcode 16 / macOS 14.5 was **wrong**.
- **Flutter is deprecating Intel Macs** (`flutter doctor` warning on 3.50). A future version will
  need Apple Silicon to build macOS and iOS apps, so this Mac's lifetime as the Apple build
  machine is limited.
- **iPad caveat:** installing on a device running iPadOS 18+ needs Xcode 16 device support; Xcode
  15.3 can't. That's an Xcode limit, independent of Flutter. It isn't tried yet, and there are no
  iOS Simulator runtimes installed.
- **Verified:** `flutter build macos --debug` succeeds on 3.50.1 with all plugins. The app has the
  `device.camera` entitlement and `NSCameraUsageDescription`. SPM links plugins statically.
- Windows apps are still **built on a Windows PC** (Flutter **≥3.47** + Visual Studio "Desktop
  development with C++"). Copy `build/windows/x64/runner/Release`.
### CameraService + FakeCameraService (step 14; the fake moved to `test/support/fake_camera.dart` in step 19)
- `CameraConfig(index: 0, width: 1920, height: 1080)` replaces Python's `.env` camera
  settings. The real services use it from step 15.
- `CameraService` (abstract):
  - `start()` / `stop()` / `dispose()`.
  - `status` is a `ValueListenable<CameraStatus>`: `CameraIdle` → `CameraStarting` →
    `CameraReady`, or `CameraError(message)`.
  - `capture()` returns `CapturedPhoto(bytes, extension)`. `buildPreview(context)` returns the
    preview widget.
  - Subclasses implement `openDevice()`, `closeDevice()`, `takePicture()` and `buildPreview()`.
- **Warm-up is built into the base class.** `CameraReady` comes only after `warmUp` (3 s by
  default), replacing Python's skip-90-frames logic for every implementation.
- **`start()` never throws.** Failures go to `CameraError`. `capture()` throws
  `CameraException` when the camera isn't ready or the capture fails. The camera screen must
  handle that; Python just returned None, and the flow stalled with no restart.
- `stop()` during warm-up means it never reports ready (a generation counter guards this).
- **Not mirrored.** The preview and captures are raw; the camera screen mirrors the preview,
  as Python did.
- `FakeCameraService(photoPaths: [], warmUp: 500ms)`:
  - **Default:** synthetic 1920×1080 PNGs ("Fake photo N" on a gradient, with corner dots to
    show cropping).
  - **With `photoPaths`:** cycles through those files as-is, e.g. real DSLR JPEGs from
    `py-photobooth/play2`. Personal photos are never bundled as assets.
  - The preview is a coloured panel (or the next file photo) with a static "FAKE CAMERA"
    banner. **It's static on purpose:** a ticking clock keeps timers alive and breaks
    `pumpAndSettle`.
  - A missing photo file reports `CameraError` on start.
- Fake camera text uses `AppFonts`. Text with no font family renders as blocks in previews (the
  test font).
- Tests: `test/services/camera_service_test.dart`: warm-up timing, capture-before-ready, open
  and capture failures, stop during warm-up, synthetic photos, path cycling, the missing file,
  the banner. Preview: `build/preview/fake_camera.png`.

### PluginCameraService (step 15, `lib/services/camera/plugin_camera_service.dart`)
- Dependencies added: `camera` (^0.12) **and `camera_windows` (^0.2.6)**. The `camera` plugin
  only includes Android, iOS and web, so **Windows needs `camera_windows` as a direct
  dependency**, or there's no camera on the kiosk.
- Used for **Windows + iPad**. macOS gets its own service in step 16.
- Windows limitations (no focus, exposure, flash, orientation or frame streams) don't matter.
  Only the preview and still capture are used, as in Python.
- **Camera selection** (`selectCamera`):
  - If `CameraConfig.facing` is set and a camera faces that way, use the first match.
  - Otherwise use `CameraConfig.index`, falling back to 0 when it's out of range.
  - `CameraFacing` was added to `CameraConfig` in this step. **iPad should use
    `facing: front`**, because index 0 is usually the back camera. The app shell (step 22)
    sets that.
- **Resolution** (`presetFor(height)`): the plugin only has presets. 1080 → `veryHigh`
  (1920×1080), >1080 → `ultraHigh`, 720 → `high`, 480 → `medium`. `enableAudio: false`.
- **Capture:** the plugin writes a temp file per shot. We read the bytes and **delete the temp
  file** so iPad storage doesn't fill up. `.jpeg` and extension-less files are reported as `jpg`.
- **Errors:**
  - Init failures dispose the controller and become `CameraError`.
  - Device errors after start (e.g. the webcam unplugged) go through the new protected
    `CameraService.reportError()` (added to the step 14 file) and also become `CameraError`.
- **Preview:** black until ready, then `Center(CameraPreview)`. That's contained and centred,
  like Python's KeepAspectRatio, and not mirrored.
- **iOS `Info.plist`:** added `NSCameraUsageDescription` and `NSMicrophoneUsageDescription`.
  Without them iOS kills the app when it opens the camera.
- **Open decision (step 22):** the iPad's `Info.plist` still allows portrait orientations; the UI
  is a 1920×1080 landscape canvas.
- **The plugin's own `CameraException` clashes with ours.** Always
  `import 'package:camera/camera.dart' hide CameraException;`.
- Tests: `test/services/plugin_camera_service_test.dart` (14). They inject `listCameras` /
  `createController` with a `FakeController extends CameraController` that never touches the
  platform. **Not verified on real hardware yet**; Windows and iPad builds can't run here. Check
  on the first Windows build and iPad install.

### MacosCameraService (step 16, `lib/services/camera/macos_camera_service.dart`)
- Dependency added: `camera_macos` (^0.1.1). The official `camera` plugin has no macOS
  support.
- **The camera is started without the plugin's `CameraMacOSView`.** The service calls the
  plugin's `initialize()` itself and shows the preview with `Texture(textureId)`. So the Mac
  camera opens at app launch like the other services, not when a widget mounts.
- **The plugin's own controller always takes TIFF at max resolution, and Flutter's decoder
  can't read TIFF, so compositing would fail.** We use `MethodChannelCameraMacOS` directly
  (imported from `camera_macos/camera_macos_method_channel.dart`, which isn't exported) to call
  `takePicture(format: jpg, resolution:)`.
- Overridden plugin defaults: `isVideoMirrored: false` (the plugin default is true; the service
  is never mirrored), `enableAudio: false`, `pictureFormat: jpg`, `CameraMacOSMode.photo`.
- `MacCameraBackend` is our seam over the plugin. `CameraMacosBackend` is the real one, and
  tests inject a fake.
- Device = `CameraConfig.index` into the plugin's video devices, falling back to 0 when out of
  range. `facing` is ignored, since Macs report no lens direction.
- `resolutionFor(height)`: 1080 → `veryHigh`, >1080 → `ultraHigh`, 720 → `high`,
  540 → `medium`.
- Preview: black until ready, then `Center(AspectRatio(Texture))`, contained.
- **macOS permissions:**
  - `com.apple.security.device.camera` in both `DebugProfile.entitlements` and
    `Release.entitlements`.
  - `NSCameraUsageDescription` and `NSMicrophoneUsageDescription` in
    `macos/Runner/Info.plist`.
  - The plugin README also asks for `device.audio-input`; it was **left out on purpose (least
    privilege)**. If the camera fails to start on macOS, try adding it.
- Tests: `test/services/macos_camera_service_test.dart` (8) with a fake backend. The app builds
  under SPM, but **the real Mac camera hasn't run yet**; that needs a screen (step 19+).

### PrinterService (step 17, `lib/services/printer_service.dart`)
- Dependencies added: `printing` (^5.15.1, the first version with SPM, needs Flutter ≥3.41) and
  `pdf` (^3.13).
- **Getting here required the Flutter 3.35 → 3.50 upgrade** (see Build environment).
  `printing` 5.14 was CocoaPods-only on Apple platforms.
- `PrinterService` (abstract): `printers()`, `printSheet(png, prints:, jobName:)`. Static,
  tested helpers:
  - `copiesFor(prints)` = `max(1, prints ÷ 2)`. Python used `int(prints/2)`: each 4×6 sheet
    holds 2 strips.
  - `distribute(copies, printers, startAt:)` spreads copies round-robin. That's Python's
    parallel printing across several SELPHYs.
  - `pngSize(png)` reads the size from the IHDR, with no decode.
  - `rotateToPortrait(png)`: landscape is rotated **90° counter-clockwise**, like PIL
    `rotate(90, expand=True)`. Portrait is returned untouched. It's done with `dart:ui`, so
    tests check it pixel by pixel.
  - `sheetFormat` = 4×6 in (288×432 pt), zero margin.
  - `buildPdf(portraitPng, pages)` makes one page per copy, with the image filling the page.
    The print APIs have no portable copy count.
- `MockPrinterService` logs with `debugPrint` and records `jobs`. Python's `MockPrinter`.
  **It stays the app default until a real SELPHY is verified.**
- `SystemPrinterService(nameFilter: 'Canon SELPHY CP1500', useDriverSettings: false)`:
  - macOS/Windows: uses every **available** printer whose name contains the filter
    (case-insensitive), sorted by name.
  - One job per printer, **in parallel** (`Future.wait`). The round-robin start carries over
    between guests, so the load balances.
  - **iPad can't list printers.** Call `usePrinters([picked])` after `Printing.pickPrinter`, or
    printing throws `PrinterException`.
  - Errors (no matching printer, cancelled job, not a PNG) become `PrinterException`.
  - Uses `Printing.directPrintPdf` (no dialog), `dynamicLayout: false`, `format: sheetFormat`.
  - `useDriverSettings` maps to `usePrinterSettings` (Windows only). It's **the knob for "the
    photos printed slightly outside the boundaries"**: whether our exact 4×6 page or the
    driver's own paper/margin setup is right must be found on the real SELPHY. Also recheck
    the issue now that sheets are correctly 300 DPI (step 12).
- `PrintBackend` is the seam over `Printing.*`. `PrintingPackageBackend` is the real one, and
  tests inject a fake.
- macOS entitlement `com.apple.security.print` was added to both entitlements files (the
  `printing` README requires it).
- Tests: `test/services/printer_service_test.dart` (14):
  - copies, distribution, PNG header reading, CCW rotation (pixels), PDF page count and
    MediaBox;
  - mock rotation;
  - filter/availability, 6 prints → 3 copies over 2 printers, guest rotation, the driver flag,
    no printer, the iPad `usePrinters`, cancel.
  - The PDF writes `/MediaBox[...]` with no space.
- **Not verified on real printers yet.** Needs the Windows kiosk with the SELPHY driver (and
  AirPrint for Mac/iPad).

### TitleScreen (step 18, `lib/screens/title_screen.dart`)
- `TitleScreen(onStart:)` is a `Scaffold` > `DesignCanvas(background: solid)` > 800×120
  DecorativeButton "START", **bottom-centre, with margins 100/0/100/80** (Python's
  `setContentsMargins`).
- **It only reports the tap.** The app shell (step 22) creates the session and navigates, as
  Python's main window did with `create_session_signal`. `onStart: null` disables START (dimmed),
  e.g. while loading.
- Tests: `test/screens/title_screen_test.dart` (tap, background, position 800×120 at
  x-centre 960 and bottom 1000, disabled). **Run `test/screens` from now on**, alongside the
  other unit test folders.
- Previews: `title_screen_1080p.png` and `title_screen_ipad.png` replace the old `title_mock_*`.
  In `widgets_preview_test.dart`, **screen previews go at the end**, after the marker comment.
- At 16:9 the cover-fit background crops about 47 px top and bottom, which **cuts the church
  logo at the top in half**. The current image is 5334×3264, about 1.63:1. On iPad it's fine.
  - **Decision (user): the designer re-exports the background at 16:9.** For example 3840×2160
    (decoded at 2560 px wide) or 1920×1080, overwriting `assets/ui/background_solid.png`.
  - **No code change.** `DesignCanvas` stays cover-fit and centred.
  - On a 4:3 iPad, a 16:9 image will be cropped ~12.5 % at each side, so **important artwork
    must stay inside the central 75 % of the width**.
  - Pending the new asset.

### Backgrounds per screen shape (step 19, `lib/widgets/design_canvas.dart`)
- The user re-exported the backgrounds at 16:9: `assets/ui/background_{solid,transparent}-1920x1080.png`.
  They're actually **3840×2160**, despite the names. The originals are 5334×3264 (1.63:1).
- `AppBackground([BackgroundVariant(asset, aspectRatio), …])`. `DesignCanvas` picks **the
  variant whose ratio is closest to the screen's** (LayoutBuilder), rather than choosing by
  platform:
  - a 16:9 monitor or the Windows kiosk gets the 16:9 export;
  - a 4:3 iPad gets the original (it crops less there);
  - **a 16:10 MacBook (1.60) also gets the original**, because it's closer to 1.63 than to
    1.78.
- `AppBackgrounds.solid` / `.transparent` are `AppBackground`s now, no longer strings. To add a
  ratio, list another variant.
- Tests are in `design_canvas_test.dart`.

### CameraScreen (step 19, `lib/screens/camera_screen.dart`)
- `CameraScreen(camera:, sounds:, onPhoto:, onBack:, onDone:, photosToTake: 4,
  firstCountdown: 10, nextCountdown: 5, bellsAt: 4, showCaptureButton: true)`.
- Top bar as in Python: Back | counter | timer | Capture, stretched 1:2:2:1, 160 px high.
  Below: the preview, **mirrored with `Transform.flip`**, inside the `FlashOverlay`.
- The timer badge is hidden while idle and shows "Time's up!" at 0.
- On capture: flash, bells fade, shutter, `onPhoto`, counter +1, wait 300 ms for the flash,
  then the next 5 s countdown or `onDone`.
- **Fixes over Python:**
  - The countdown starts **only when the camera is ready**, and restarts if it becomes ready
    again.
  - A failed **capture** shows "Oops — let's try that again" and retries after 5 s. A failed
    **save** (`onPhoto` throws) shows "Couldn't save that one" and retries too. Python stalled.
  - **Capture cancels the running countdown**. Python's could fire an extra photo.
  - A camera error stops the countdown and bells, and shows "Camera problem — please ask for
    help".
  - No blocking event loop.
- A new screen is built for each visit, so `initState`/`dispose` are Python's
  `on_enter`/`on_exit`. Dispose stops the countdown and the bells (no fade).
- **Saving is the shell's job** (`onPhoto`), which keeps the screen free of file IO and testable.
- Tests: `test/screens/camera_screen_test.dart` (8): full flow, bells/shutter, waits for ready,
  capture retry, save retry, the Capture button, camera error, Back.
- **Test-hang gotcha (cost two hung runs):**
  - `CameraService.start()` creates its warm-up timer only after `openDevice()` completes.
    **Never `await camera.start()` in a widget test without pumping.** Use a loop that pumps
    until it finishes (the `startCamera` helper in the test).
  - A stuck fake-async await **also ignores `--timeout`**. Run long suites in the background
    and read the log.

### App shell, early (steps 19/22, `lib/app.dart`, `lib/main.dart`)
- **Built early so the user can run the app now.** Step 22 extends it rather than starting it.
- `main()`: `SessionService.inDocuments()`, `SoundService().load()`, `createCamera()`, then
  `runApp(PhotoboothApp(...))`.
- `createCamera()` **always returns a real camera**:
  - macOS gives `MacosCameraService`;
  - iOS gives `PluginCameraService(facing: front)`;
  - everything else gives `PluginCameraService` (Windows; Android and web via the plugin).
    Unsupported platforms report "No camera found".
  - The `FAKE_CAMERA` switch existed briefly and was **removed in step 19**; the
    `FakeCameraService` is now test-only.
- `PhotoboothApp` uses a screen enum (`title`, `camera`, `selection`, `print`) and takes
  `catalog:` (loaded in `main` with `TemplateCatalog.load()`) and a shared `composer:`
  (`CompositeService`). Step 20 changes:
  - Camera done: `session.listPhotos()`, then the selection screen.
  - Selection's `buildPreview` = `compose` + `previewStrip`; the composite is disposed and the
    strip returned.
  - Next stores the `Selection` and goes to `print`.
  - Back to title also calls `composer.clearCache()`.
  - It starts the camera at launch and stops/disposes it with the app.
  - START creates the session (disabled while doing so), then goes to Camera.
  - Back or Start over calls `session.reset()` and returns to Title.
  - `onPhoto` calls `session.savePhoto(bytes, extension)`.
- No placeholders left. **The full guest flow runs:** Title → Camera → Selection → Print →
  (Back to Selection | Start Over → Title). The app takes `printer:`.
- **Bug found by the smoke test and fixed:** the shell's `unawaited(camera.stop())` followed by
  `dispose()` made `stop()` set a disposed `ValueNotifier` at app exit. `CameraService` now
  ignores status changes after `dispose()` (`_disposed` + `_set`), and `start()` after dispose
  does nothing. A regression test is in `camera_service_test.dart`.
- `test/widget_test.dart` is now the shell smoke test (it opens on START).
- `flutter build macos --debug` ✓.

### SelectionScreen (step 20, `lib/screens/selection_screen.dart`)
- `SelectionScreen(photoPaths:, catalog:, buildPreview:, onNext:, onStartOver:, imageFor:)`
  returns a `Selection(photos, template)` through `onNext`.
- **Layout as in Python:**
  - Left: the "Preview" heading over a 480×640 strip box.
  - Right: the photos as 300×225 `SelectableImage` tiles, 2 per row (a `Wrap`, so any count
    works).
  - Bottom (170 px): the swatch row and "Select 2 or all 4 photos" (32 px) on the left, Start
    Over and Next (compact, stacked) on the right.
- **Rules as in Python:**
  - Photos are kept **in tap order**; slot `i` gets `photos[i % n]`.
  - 2 photos use the horizontal frames and 4 use the vertical ones, with the **first frame by
    default**. The chosen frame is kept while the count stays valid.
  - Any other count clears the frame and preview and disables Next.
  - **Next is only enabled once the preview is ready.**
- **Differences:**
  - The **preview stays in memory** as a `ui.Image` from `buildPreview`. Python wrote
    `preview_strip_<n>photos.png` only to hand it to the print screen.
    `SessionService.savePreviewStrip` / `deletePreviewStrips` are **unused for now**.
  - The print screen re-composes from the `Selection`; the shared `CompositeService` cache keeps
    that fast.
  - While the count is invalid, the swatches are **dimmed and inactive** (Python's were tappable
    with no effect). They show the 2-photo family, as Python did.
  - **A newer tap supersedes an in-flight preview** (request counter), so a stale image never
    flashes. Superseded and old images are disposed.
  - A preview failure shows "Couldn't make the preview" and keeps Next disabled.
- Tests: `test/screens/selection_screen_test.dart` (7). They inject memory thumbnails
  (`imageFor`) and a fake `buildPreview` returning `toImageSync` images, so there's no file IO
  or async engine work in widget tests.

### PrintScreen (step 21, `lib/screens/print_screen.dart`)
- `PrintScreen(buildSheet:, printSheet:, onBack:, onStartOver:)`. The screen only drives the
  UI; the shell builds and prints the sheet.
- **Layout as in Python:**
  - "Your Photo is Ready!" (40 px).
  - A white panel with a 3 px gold top border, holding the strip box (800×640, the **left
    half** of the sheet via `ClipRect`/`OverflowBox`) and `StepSelector` ("Number of prints",
    starts 2, min 2, step 2, no max).
  - Buttons: Back to Selection | Print Photo | Start Over (regular).
- Print → `printSheet(sheet, prints)` → a "Sent to print" dialog with OK (gold-bordered
  `Dialog`). **Every press prints again**, as in Python.
- **Fixes over Python:**
  - The count is **2 for every guest** (screen state; Python kept the last count).
  - **Print is disabled while sending** ("Printing…"), so a double tap doesn't double-print.
  - A printer error shows "Couldn't print — please ask for help". Python's
    `_on_print_clicked` could hit an undefined `output_path`.
  - A sheet build failure shows a message and disables Print.
- **Back to Selection keeps the picks.** `SelectionScreen(initialSelection:)` restores the photos
  and frame and rebuilds the preview, as Python's never-rebuilt screen did.
- `saveAndPrint(...)` (public, in `lib/app.dart`): `composer.encodePng(sheet)` (300 DPI) →
  `session.saveFinalComposite(png)` (new file every press, suffixed if in the same second) →
  `printer.printSheet(png, prints:, jobName: <file name>)`.
- **The app uses `MockPrinterService`** (set in `main.dart`) until a real SELPHY is verified.
- Tests:
  - `test/screens/print_screen_test.dart` (7): layout, count, success dialog, repeat prints,
    disabled while printing, error, sheet failure, buttons.
  - `selection_screen_test.dart` got an `initialSelection` test.
  - **`test/services/print_pipeline_test.dart`** runs the **real** services with no UI: fake
    photos → session → compose → `saveAndPrint` → a 1800×1200 PNG at 300 DPI on disk, plus a
    mock job with 3 copies for 6 prints.

### Kiosk mode + release builds (step 22a, user-requested)
- **`lib/services/kiosk_service.dart`** — `KioskService.enter()` / `exit()`:
  - All platforms keep the screen awake with **`wakelock_plus`** (^1.8; it has SPM support).
  - **macOS/Windows:** `MethodChannel('photobooth/kiosk')` → `setFullScreen(bool)`, handled
    natively.
  - **iOS/Android:** `SystemChrome` immersiveSticky + landscape orientations.
  - Never throws (`_guard` logs).
- **On by default in release builds only:** `KioskService.enabledByDefault` =
  `bool.fromEnvironment('KIOSK', defaultValue: kReleaseMode)`. `main()` calls `enter()` after
  `runApp`. `flutter run` stays windowed; `--dart-define=KIOSK=true|false` overrides.
- **`window_manager` was rejected:** it's CocoaPods-only (no Package.swift), which would break
  the SPM build. Full screen is done natively in the runners instead, a few lines each:
  - `macos/Runner/MainFlutterWindow.swift`: the channel toggles native full screen
    (`toggleFullScreen`, deferred with `DispatchQueue.main.async` so it works at launch). It
    adds `.fullScreenPrimary`. The operator quits with ⌘Q.
  - `windows/runner/flutter_window.{h,cpp}`: the channel switches to a borderless window over
    the whole monitor, and back (Raymond Chen's WS_OVERLAPPEDWINDOW / MONITORINFO approach).
    It saves the style and rect for restoring. The operator exits with Alt+F4.
    **Not compiled yet**; it needs the Windows build PC.
- **iOS `Info.plist`:** landscape-only (iPhone and iPad keys), `UIRequiresFullScreen` = true.
  Use Guided Access for a hard lock.
- Tests: `test/services/kiosk_service_test.dart` (mocked channel, fake wakelock): macOS and
  Windows enter/exit, iOS, failures swallowed, off by default in tests.
- **macOS release build verified:**
  - `flutter build macos --release` gives a **universal binary (x86_64 + arm64)**, ~44 MB.
  - It's **ad-hoc signed (no Team ID)**, so other Macs need a one-time Gatekeeper override
    ("Open Anyway" or `xattr -dr com.apple.quarantine`). Notarization needs a paid account.
  - Zip it with `ditto -c -k --sequesterRsrc --keepParent …` (keeps the signature), giving
    `build/dist/OCC-Photobooth-macOS.zip` (19 MB).
- **Windows deployment needs the VC++ Redistributable (x64)** on the kiosk, plus the whole
  `Release\` folder.
- The README "Event devices" section has the step-by-step deployment per device.
- The app was renamed right after this (22b, below).

### App name "OCC Photobooth" (step 22b, user's choice)
- **Display name "OCC Photobooth"; bundle/app id `com.occ.photobooth`** (chosen by Claude, since
  any unique reverse-DNS id works). The Dart package name stays `flutter_photobooth` (internal;
  renaming would touch every import).
- **macOS:** `macos/Runner/Configs/AppInfo.xcconfig` has `PRODUCT_NAME = OCC Photobooth` (so
  the build is **`OCC Photobooth.app`**, the executable is `OCC Photobooth`), the bundle id, and
  copyright "OCC". RunnerTests ids are in `project.pbxproj`. The space in the name works with
  `flutter build`/`run`; **quote paths**.
- **iOS:** `Info.plist` has `CFBundleDisplayName` / `CFBundleName` = "OCC Photobooth";
  `project.pbxproj` has the bundle ids.
- **Windows:** `BINARY_NAME "occ_photobooth"` (so the exe is **`occ_photobooth.exe`**, no
  space), the window title "OCC Photobooth" in `runner/main.cpp`, and `Runner.rc` version info
  (company "OCC", product "OCC Photobooth").
- `MaterialApp.title` = 'OCC Photobooth'. Android, Linux and web identifiers were left alone
  (not targets).
- **Consequence:** the macOS container moved, so photos now land in
  `~/Library/Containers/com.occ.photobooth/...`. Test sessions from before the rename stay in
  `~/Library/Containers/com.example.flutterPhotobooth/...`.
- Verified: the release build is `OCC Photobooth.app` (`com.occ.photobooth`, universal); the
  debug build works; 150 tests pass. Distributable: `build/dist/OCC-Photobooth-macOS.zip`.

### GifService (step 22c, user-requested; NEW, py-photobooth had no GIF)
- `lib/services/gif_service.dart`: `const GifService().create(photoPaths, options:)` returns GIF
  bytes. `SessionService.saveGif(bytes)` writes `animation_YYYYmmdd_HHMMSS.gif` (never
  overwrites). `listPhotos()` ignores `.gif`.
- **Not wired into the UI yet.** The user asked for a separate service; how guests get the GIF
  (shown on screen, saved only, shared) is still to decide.
- `GifOptions`:
  - `width` 640; height follows the first photo's aspect.
  - `frameDelay` 500 ms, stored in 1/100 s and rounded.
  - `boomerang` false (true plays 1→n then n-1→2).
  - `loop` true.
- **Dependency added: `image` (^4.13, pure Dart, so SPM is unaffected).** Flutter's `dart:ui` can
  decode but **can't encode GIF**. Two stages:
  1. Main isolate, `dart:ui`: shrink-on-decode, then **centre-crop every photo to one frame
     size** (GIF frames must match) with `CompositeService.coverCrop`, giving raw RGBA.
  2. **`Isolate.run`**: `img.GifEncoder` (NeuQuant 256 colours, Floyd–Steinberg dither) via the
     static `encodeGif(...)`, which is pure and testable.
- **`image` GIF gotchas:**
  - `GifEncoder` **always writes the NETSCAPE2.0 loop block**; `repeat: -1` becomes a
    65535-loop count, not "play once". For play-once we **strip the 19-byte block**
    (`withoutLoopExtension`).
  - `decodeGif` reports `frameDuration` in **ms**, while the file stores 1/100 s. The tests
    check both (`rawDelays`).
- Measured on the user's real 4 Mac-camera photos (1280×720): **~1.7 s** to make; ~600 KB normal
  and ~900 KB boomerang (the same time, since only 4 distinct frames are quantised).
- Tests: `test/services/gif_service_test.dart` (6): size/order/timing/loop, boomerang order,
  options (width, speed, play once), mixed photo shapes, empty list, `saveGif` naming and
  listing.

### Pre-existing issue (resolved in step 19)
- The template `test/widget_test.dart` (a broken counter test) was replaced by an app-shell
  smoke test.

| Step | File | Status |
|---|---|---|
| 0 | `pubspec.yaml`, `assets/` | done |
| 1 | `lib/theme/app_theme.dart` | done |
| 2 | `lib/widgets/design_canvas.dart` | done |
| 3 | `lib/widgets/decorative_button.dart` | done |
| 4 | `lib/widgets/themed_button.dart` | done |
| 5 | `lib/widgets/badge_label.dart` | done |
| 6 | `lib/widgets/step_selector.dart` | done |
| 7 | `lib/widgets/flash_overlay.dart` | done |
| 8 | `lib/widgets/selectable_image.dart`, `assets/swatches/` | done |
| 9 | `lib/services/countdown_controller.dart` | done |
| 10 | `lib/config/templates.dart` (+ swatches per orientation) | done |
| 11 | `lib/services/session_service.dart` | done |
| 12 | `lib/services/composite_service.dart` | done |
| 13 | `lib/services/sound_service.dart` | done (macOS build ✓ via SPM) |
| 14 | `lib/services/camera/camera_service.dart` | done |
| 15 | `lib/services/camera/plugin_camera_service.dart` | done (needs real Windows/iPad check) |
| 16 | `lib/services/camera/macos_camera_service.dart` | done (builds ✓ on published plugin; real-camera run needs a screen, step 19+) |
| 17 | `lib/services/printer_service.dart` (+ Flutter 3.50 upgrade) | done (needs real SELPHY check) |
| 18 | `lib/screens/title_screen.dart` | done |
| 19 | `lib/screens/camera_screen.dart` (+ background variants, early app shell) | done |
| 20 | `lib/screens/selection_screen.dart` (+ fake camera moved to tests) | done |
| 21 | `lib/screens/print_screen.dart` | done |
| 22 | App shell finishing (`lib/app.dart`) — see list below | next |


**Step 22 candidates.** These are open items collected in earlier steps; the user decides which
to do:
- **Printer choice:** switch `MockPrinterService` → `SystemPrinterService` (setting or build
  flag). The iPad needs a one-time `Printing.pickPrinter` → `usePrinters`. There's also the
  `useDriverSettings` margin knob.
- **Camera settings:** the equivalent of Python's `.env` (`CameraConfig` index and height).
- ~~Kiosk mode~~ **done (22a)**. Optional extra: hide the cursor on touch kiosks.
- **iPad:** ~~landscape lock~~ done (22a). The iPad build is still untried, and iPadOS 18+
  devices need Xcode 16.
- ~~App identity~~ **done (22b): "OCC Photobooth", `com.occ.photobooth`.**
- **Camera recovery:** a way to restart the camera after "Camera problem" (now only Back).
- **Session retention:** photos accumulate forever. Decide on cleanup or privacy.
- **GIF in the guest flow:** `GifService` exists (22c). Decide when it's made (e.g. after the
  camera, in the background), and whether guests see or share it.
- **Verify on real hardware:** the Mac camera (first `flutter run`), the Windows camera and
  SELPHY, and the iPad.

# To be resolved

- The photos being printed are slightly outside of the boundaries (something to do with print margin?)
- Adding hand gestures to capture
- Improving sharpness of the photo
- Smoothen the animations/ sounds
