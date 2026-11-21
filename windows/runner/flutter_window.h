#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Kiosk mode (lib/services/kiosk_service.dart): "setFullScreen" (bool).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      kiosk_channel_;
  void SetFullScreen(bool full_screen);
  void SetCursorHidden(bool hidden);
  bool is_full_screen_ = false;
  bool cursor_hidden_ = false;
  LONG saved_style_ = 0;
  RECT saved_rect_ = {};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
