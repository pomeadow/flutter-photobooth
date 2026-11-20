import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerKioskChannel(flutterViewController)

    super.awakeFromNib()
  }

  /// Kiosk mode (lib/services/kiosk_service.dart): "setFullScreen" (Bool)
  /// switches native macOS full screen on/off. The menu bar and Dock hide
  /// automatically; the operator can still quit with Cmd+Q.
  private func registerKioskChannel(_ controller: FlutterViewController) {
    collectionBehavior.insert(.fullScreenPrimary)
    let channel = FlutterMethodChannel(
      name: "photobooth/kiosk",
      binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "setFullScreen":
        let wanted = (call.arguments as? Bool) ?? false
        let isFull = self.styleMask.contains(.fullScreen)
        if wanted != isFull {
          // Defer so the window is on screen before toggling at launch.
          DispatchQueue.main.async { self.toggleFullScreen(nil) }
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
