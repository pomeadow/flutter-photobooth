# Flutter Photobooth

A Christmas-themed event photobooth for touchscreens.
1. A guest presses START.
2. A countdown takes 4 photos.
3. The guest picks 2 or 4 of them and a frame.
4. A 6×4 in print-ready sheet is sent to a Canon SELPHY CP1500.

This is a Flutter port of the Python/PySide6 app `py-photobooth`. Targets: **macOS**
(development), **Windows** (event kiosk), and **iPad**.

> **Status:** in progress. Widgets, frame config, sessions, compositing and sounds are done;
> the camera, printing and screens are still being built. `CLAUDE.md` tracks the step list and
> every design decision.

---

## Setup

There are two kinds of machine:
- **Build machines** compile the app. They need Flutter and the platform toolchain.
- **Event devices** only run the finished app. They need no developer tools.

| You want to… | You need |
|---|---|
| Build or run the **macOS** app | [A Mac build machine](#mac-build-machine-macos--ipad) |
| Build or install the **iPad** app | [A Mac build machine](#mac-build-machine-macos--ipad) (Apple only allows iOS builds on a Mac) |
| Build the **Windows** app | [A Windows build machine](#windows-build-machine) (a Mac can't build Windows apps) |
| Run the app at an event | [Event devices](#event-devices-run-only) |

### Mac build machine (macOS + iPad)

1. **Flutter 3.47 or newer** (developed on 3.50): follow
   https://docs.flutter.dev/get-started/install/macos.
   - **Intel Macs work today, but Flutter is phasing them out**; a future version will need an
     Apple Silicon Mac to build.
2. **Xcode,** from the App Store. Then run, once:
   ```bash
   sudo xcodebuild -runFirstLaunch
   ```
3. **Turn on Swift Package Manager.** This project builds the plugins' native code (audio, file
   paths, camera) with SPM, which is built into Xcode. **CocoaPods is not used or needed.** It's
   one command, per user, once:
   ```bash
   flutter config --enable-swift-package-manager
   ```
   The project has no `Podfile` (and no Pods includes in the `.xcconfig` files) on purpose.
   Don't run `pod install`.
4. Check everything with the command below.
   - The *Flutter* and *Xcode* lines matter. Xcode may still say "CocoaPods not installed";
     ignore that, it isn't used.
   - Android can be ignored.
   ```bash
   flutter doctor
   ```
5. **iPad only.** Sign in with an Apple ID in Xcode → Settings → Accounts.
   - A free Apple ID can install on your own iPad, but the install **expires after 7 days**, so
     reinstall before each event.
   - A paid Apple Developer account removes the expiry and allows TestFlight.
6. **Optional:** to test the iPad layout without an iPad, install an iOS Simulator runtime in
   Xcode → Settings → Platforms (several GB).

### Windows build machine

1. **Flutter 3.47 or newer** (developed on 3.50): follow
   https://docs.flutter.dev/get-started/install/windows.
2. **Visual Studio 2022** (not VS Code), with the **"Desktop development with C++"** workload.
3. **Git.**
4. Check with `flutter doctor`. The *Visual Studio* line must be ✓.

There's no CocoaPods on Windows; plugins build through Visual Studio automatically.

### Every build machine: get the project running

```bash
flutter pub get          # download packages
flutter analyze          # should say "No issues found!"
flutter run -d macos     # or: -d windows, or an iPad device id from `flutter devices`
```

The app always uses the real camera. If none is found, the camera screen says so.

**The full guest flow works:**
1. **Title**
2. **Camera:** countdown, 4 photos, flash, sounds.
3. **Selection:** pick 2 or 4 photos and a frame, with a live preview.
4. **Print:** the guest's strip, then Print Photo.
5. **Share:** the guest's **animated GIF** plays, next to a QR code for their photos. The GIF is
   made from the guest's photos in the background after the camera and saved as
   `animation_*.gif`.

Photos land in the session folder (see below).

### Event devices (run only)

None of these need Flutter, Xcode or Visual Studio. **Release builds start in kiosk mode:**
- **Full screen.**
- **The screen never sleeps.**
- **Landscape on iPad.**

`flutter run` (debug) stays windowed. Override either way with `--dart-define=KIOSK=true|false`.

| Device | How the operator exits kiosk mode |
|---|---|
| Mac | **⌘Q** (or move the mouse to the top edge to show the menu bar) |
| Windows | **Alt+F4** |
| iPad | Swipe up / Home. For a locked kiosk, use **Guided Access** (Settings → Accessibility) |

#### Mac (any Mac: Intel or Apple Silicon, one universal app)

1. **Build it** on the Mac build machine:
   ```bash
   flutter build macos --release
   ditto -c -k --sequesterRsrc --keepParent \
     "build/macos/Build/Products/Release/flutter_photobooth.app" build/dist/Flutter-Photobooth-macOS.zip
   ```
   Use `ditto`, not Finder's "Compress"; it keeps the app's signature intact.
2. **Copy** `Flutter-Photobooth-macOS.zip` to the other Mac (USB stick, AirDrop…), unzip it, and
   move **`flutter_photobooth.app`** to **Applications**.
3. **The first launch is blocked by Gatekeeper.** The app is only ad-hoc signed (no Apple
   Developer ID), so macOS says it "can't be opened". To allow it, either:
   - double-click it once, then go to **System Settings → Privacy & Security → "Open Anyway"**;
     or
   - in Terminal: `xattr -dr com.apple.quarantine "/Applications/flutter_photobooth.app"`.

   You only do this once per Mac. To avoid it entirely you'd need a paid Apple Developer
   account (Developer ID signing + notarization).
4. **On first run**, allow the **camera** prompt. To print for real, add the SELPHY under
   System Settings → Printers.
5. Photos are saved in
   `~/Library/Containers/com.example.flutterPhotobooth/Data/Documents/photobooth_sessions/`.

#### Windows kiosk

1. **Build it on a Windows PC** (see Windows build machine above). A Mac can't build Windows
   apps:
   ```bat
   flutter build windows --release
   ```
2. **Copy the whole `build\windows\x64\runner\Release\` folder** to the kiosk, e.g. to
   `C:\Photobooth\`. The `.exe` needs the DLLs and the `data\` folder next to it.
3. **Install the Microsoft Visual C++ Redistributable (x64)** on the kiosk, once. It's the free
   "vc_redist.x64.exe" from Microsoft. Without it the app won't start ("VCRUNTIME140.dll was not
   found").
4. Run **`flutter_photobooth.exe`**. Allow camera access (Settings → Privacy & security → Camera →
   "Let desktop apps access your camera").
5. **Optional, to start automatically:** put a shortcut to the `.exe` in the Startup folder
   (Win+R → `shell:startup`).
6. Install the SELPHY CP1500 driver (see Printer notes). Photos are saved in
   `Documents\photobooth_sessions\`.

#### iPad

Verified on an **iPadOS 26** iPad, built with Xcode 16.x.

1. **Use Xcode 16 or newer.** The camera plugin doesn't compile with Xcode 15
   (`AVCaptureSession has no member 'wasInterruptedNotification'`). With several Xcodes installed,
   check and switch:
   ```bash
   xcode-select -p && xcodebuild -version
   sudo xcode-select --switch /Applications/<Xcode 16>.app/Contents/Developer
   ```
   If you build from Xcode's ▶ button, open the project in that same Xcode.
2. **On the iPad, once:** connect by cable, unlock, tap **Trust**. Then **Settings → Privacy &
   Security → Developer Mode** → on → restart → unlock → **Turn On**.
3. **Signing, once:** open `ios/Runner.xcworkspace` → blue **Runner** project → **TARGETS:
   Runner** → **Signing & Capabilities** (All) → **Automatically manage signing** → choose your
   **Team** (a free Apple ID shows as "Personal Team").
4. **Install a release build** (`flutter devices` shows the iPad's id; `-d iPad` also works):
   ```bash
   rm -rf build/ios/iphoneos          # see "Stale debug build" below
   flutter run --release -d iPad --dart-define=DRIVE_SERVER=… --dart-define=DRIVE_API_KEY=…
   ```
   The first time, trust your developer profile on the iPad: **Settings → General → VPN & Device
   Management**. Then the app also opens from the home screen.
   - **Debug mode doesn't work on iPadOS 26 from Xcode 16**: the app installs, but stops with
     `ptrace(PT_TRACE_ME): Operation not permitted` / "Cannot create a FlutterEngine instance in
     debug mode", because Xcode 16 can't attach its debugger to iPadOS 26. Use `--release`
     (or `--profile`). Debug and hot reload on the iPad need Xcode 26 (macOS 15.6+).
   - **Stale debug build:** `flutter run --release` installed the leftover *debug* app from
     `build/ios/iphoneos/` (same error as above) instead of the new one in
     `build/ios/Release-iphoneos/`. Deleting `build/ios/iphoneos` fixes it (`flutter clean` also
     works). Or install the release app directly:
     `xcrun devicectl device install app --device <ipad-id> build/ios/Release-iphoneos/Runner.app`.
   - A free Apple ID's install **expires after 7 days**: reinstall before each event. A paid
     Apple Developer account gives 1-year installs and TestFlight.
   - `DRIVE_SERVER` must be reachable from the iPad: the Render URL or the Mac's network IP, not
     `localhost`.
5. Allow the camera and local-network prompts. The app is landscape-only and full screen.
6. **At events, use Guided Access** to lock the iPad into the app: Settings → Accessibility →
   Guided Access → on (set a passcode); open the app and **triple-click the top (or Home)
   button** → Start. Triple-click again and enter the passcode to leave.

**Camera notes**
- **Windows:** any webcam Windows sees works. Close other apps that use the camera (Teams,
  Zoom, the Camera app); only one app can hold it at a time.
- **Mac:** uses the built-in camera (or the first external one, depending on the configured
  index). If the camera was refused, re-enable it in System Settings → Privacy & Security →
  Camera.
- **iPad:** uses the **front** camera, facing the guests. The permission prompt appears the first
  time; if it was declined, re-enable it in Settings → Privacy & Security → Camera.

**Printing: a separate print server (not part of this app)**

The app doesn't talk to printers. Your separate printer code (`python_parallel_print`, which
shares copies round-robin across all connected Canon SELPHY CP1500s and rotates sheets to
portrait) runs as a small **print server**. The app sends it each finished sheet over the
network. One print PC can serve every booth device, or it can run on the same machine.

- **Contract** the print server must implement:
  ```
  POST http://<print-pc>:8765/print?copies=<sheets>&name=<job name>
  Content-Type: image/png
  <body: the 300-DPI sheet PNG, as composed — 1800×1200 or 1200×1800, not rotated>

  → reply 2xx (optional text body)  = accepted
  → anything else (text body)        = error, shown to the guest as "Couldn't print"
  ```
  `copies` is the number of **sheets**. The guest chooses strips, and each 4×6 sheet holds 2
  (cut in half), so `copies = prints ÷ 2`. The sheet is also saved as
  `final_composite_*.png` in the session folder before sending.
- **Turning it on:** builds use a **mock printer** (logs only) unless built with:
  ```bash
  flutter build windows --release --dart-define=PRINTER=network --dart-define=PRINT_SERVER=http://192.168.1.50:8765
  # same machine as the print server: PRINT_SERVER defaults to http://localhost:8765
  ```
- **Network permissions** are already set up: macOS has outgoing network, and iPad has
  local-network HTTP. The first time on iPad, allow the "find devices on your local network"
  prompt.
- **On the print PC:** install the Canon driver and print a Windows test page first. In the
  driver's preferences choose Postcard size (4×6 in / 100×148 mm) and **borderless**. Load
  Postcard paper and ink.

---

## Where photos are saved

Each guest gets a `session_YYYYmmdd_HHMMSS/` folder holding their photos, every printed sheet
(`final_composite_*.png`, 300 DPI) and the animated `animation_*.gif` of the guest's photos.

| Platform | Folder |
|---|---|
| macOS | `~/Library/Containers/com.example.flutterPhotobooth/Data/Documents/photobooth_sessions/` |
| Windows | `Documents\photobooth_sessions\` |
| iPad | The app's Documents folder |

Folders are never deleted automatically. Clear them out between events if disk space or guest
privacy matters.

---

## Assets (for designers)

| Folder | Contents | Rules |
|---|---|---|
| `assets/templates/` | Print frames | **Only frames go here.** Name them `photo_frame_horizontal_0N.png` (1800×1200) or `photo_frame_vertical_0N.png` (1200×1800), at 300 DPI. Any other PNG here, or a frame of the wrong size, stops the app loading frames. |
| `assets/swatches/` | Frame-picker circles | `swatch_horizontal_0N.png` / `swatch_vertical_0N.png`, **120×120**, square (the app masks them to a circle). The number matches the frame's. A missing swatch falls back to the frame's colour. |
| `assets/ui/` | Screen backgrounds, buttons | **Backgrounds: 16:9**, ideally 3840×2160 (1920×1080 minimum). Screens fill without distortion, so on a 4:3 iPad about 12.5 % is cropped from each side: keep logos and key artwork inside the **central 75 % of the width**. *(The current `background_solid.png` is 1.63:1 and cuts the top logo on 16:9 screens; a 16:9 re-export is pending.)* |
| `assets/sounds/` | Bells and shutter `.wav` | |
| `assets/fonts/` | DynaPuff (fallback font) | Impact is used from the system on macOS and Windows. |

To replace an image, overwrite the file with the same name, then fully restart the app.

---

## Development

```bash
dart format lib test test_preview
flutter analyze
flutter test test --timeout 60s   # all tests
```

- Tests use a fake camera (`test/support/fake_camera.dart`); the app itself doesn't.
- **Assets look stale in tests after renaming or moving files?** Delete `build/unit_test_assets/`.
  Don't run `flutter clean`, which also deletes the preview renders.
- **macOS or iOS build says "CocoaPods not installed"?**
  - SPM isn't switched on (see [Mac build machine](#mac-build-machine-macos--ipad), step 3), or
  - a `Podfile` came back (e.g. after `flutter create .`). Delete `macos/Podfile` /
    `ios/Podfile`.
- **Build still asks for CocoaPods although no Podfile exists?** Check that
  `macos/Flutter/Flutter-*.xcconfig` and `ios/Flutter/{Debug,Release}.xcconfig` don't contain
  `#include? "Pods/..."` lines. Delete those lines if they do.
- **Build says "FlutterFramework doesn't exist"?** Flutter is too old. Upgrade to 3.47+.
