#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <shellapi.h>

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
  void RegisterWindowChannel();
  void InitializeTrayIcon();
  void RemoveTrayIcon();
  void HideToTray();
  void RestoreFromTray();
  void ShowTrayContextMenu(POINT anchor);
  bool HandleTrayCommand(UINT command_id);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // The window-control channel keeps the Flutter chrome lightweight while the
  // native host still owns window state transitions.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  // The Windows tray icon keeps the app accessible after hiding the window.
  NOTIFYICONDATA tray_icon_data_{};
  bool tray_icon_added_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
