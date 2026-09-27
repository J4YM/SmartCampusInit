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

  // Lets a non-kiosk Dart entrypoint (lib/main.dart,
  // lib/main_it_technician.dart) ask this window to drop the kiosk
  // lockdown every window starts in — see
  // Win32Window::DisableKioskLockdown's own doc comment. Set up in
  // OnCreate(), once flutter_controller_'s engine exists.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_lockdown_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
