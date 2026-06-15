#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <windowsx.h>

#include <optional>

#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayIconMessage = WM_APP + 1;
constexpr UINT kTrayCommandShow = 1001;
constexpr UINT kTrayCommandExit = 1002;
constexpr UINT kTrayMenuAnchorBottom = 0xFFFF;
constexpr wchar_t kTrayTooltip[] = L"Yunjuan";
constexpr wchar_t kTrayShowLabel[] = L"\u663E\u793A\u4E3B\u7A97\u53E3";
constexpr wchar_t kTrayExitLabel[] = L"\u9000\u51FA\u4E91\u5377";

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    // Each preview sub-window owns a separate Flutter engine, so register the
    // same plugins there before Dart tries to use window and image services.
    auto* flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController*>(controller);
    RegisterPlugins(flutter_view_controller->engine());
  });
  RegisterWindowChannel();
  InitializeTrayIcon();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  if (window_channel_) {
    window_channel_.reset();
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case kTrayIconMessage:
      switch (LOWORD(lparam)) {
        case NIN_SELECT:
        case NIN_KEYSELECT:
        case WM_LBUTTONUP:
        case WM_LBUTTONDBLCLK:
          RestoreFromTray();
          return 0;
        case WM_CONTEXTMENU: {
          POINT anchor = {};
          anchor.x = GET_X_LPARAM(wparam);
          anchor.y = GET_Y_LPARAM(wparam);
          if (anchor.x == -1 && anchor.y == kTrayMenuAnchorBottom) {
            GetCursorPos(&anchor);
          }
          ShowTrayContextMenu(anchor);
          return 0;
        }
        case WM_RBUTTONUP:
        case WM_RBUTTONDOWN: {
          POINT anchor;
          GetCursorPos(&anchor);
          ShowTrayContextMenu(anchor);
          return 0;
        }
      }
      break;

    case WM_COMMAND:
      if (HandleTrayCommand(LOWORD(wparam))) {
        return 0;
      }
      break;

    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::RegisterWindowChannel() {
  auto messenger = flutter_controller_->engine()->messenger();
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "remote_storage/window_controls",
          &flutter::StandardMethodCodec::GetInstance());

  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto& method = call.method_name();
        if (method == "minimize") {
          Minimize();
          result->Success();
          return;
        }
        if (method == "toggleMaximize") {
          MaximizeOrRestore();
          result->Success(flutter::EncodableValue(IsWindowMaximized()));
          return;
        }
        if (method == "close") {
          Close();
          result->Success();
          return;
        }
        if (method == "hideToTray") {
          HideToTray();
          result->Success();
          return;
        }
        if (method == "startDrag") {
          StartDrag();
          result->Success();
          return;
        }
        if (method == "isMaximized") {
          result->Success(flutter::EncodableValue(IsWindowMaximized()));
          return;
        }
        result->NotImplemented();
      });
}

void FlutterWindow::InitializeTrayIcon() {
  tray_icon_data_ = {};
  tray_icon_data_.cbSize = sizeof(NOTIFYICONDATA);
  tray_icon_data_.hWnd = GetHandle();
  tray_icon_data_.uID = kTrayIconId;
  tray_icon_data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon_data_.uCallbackMessage = kTrayIconMessage;
  tray_icon_data_.hIcon =
      LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcsncpy_s(tray_icon_data_.szTip, kTrayTooltip, _TRUNCATE);

  if (Shell_NotifyIcon(NIM_ADD, &tray_icon_data_)) {
    tray_icon_added_ = true;
    tray_icon_data_.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIcon(NIM_SETVERSION, &tray_icon_data_);
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (tray_icon_added_) {
    Shell_NotifyIcon(NIM_DELETE, &tray_icon_data_);
    tray_icon_added_ = false;
  }
}

void FlutterWindow::HideToTray() {
  ShowWindow(GetHandle(), SW_HIDE);
}

void FlutterWindow::RestoreFromTray() {
  const bool maximized = IsWindowMaximized();
  ShowWindow(GetHandle(), maximized ? SW_MAXIMIZE : SW_RESTORE);
  SetForegroundWindow(GetHandle());
}

void FlutterWindow::ShowTrayContextMenu(POINT anchor) {
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }

  AppendMenu(menu, MF_STRING, kTrayCommandShow, kTrayShowLabel);
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenu(menu, MF_STRING, kTrayCommandExit, kTrayExitLabel);

  SetForegroundWindow(GetHandle());
  const UINT clicked = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON, anchor.x, anchor.y,
      0, GetHandle(), nullptr);
  DestroyMenu(menu);

  if (clicked != 0) {
    HandleTrayCommand(clicked);
  }

  // TrackPopupMenu on a notification icon needs a follow-up message so the
  // shell can fully dismiss the temporary menu loop after right-click.
  PostMessage(GetHandle(), WM_NULL, 0, 0);
}

bool FlutterWindow::HandleTrayCommand(UINT command_id) {
  switch (command_id) {
    case kTrayCommandShow:
      RestoreFromTray();
      return true;
    case kTrayCommandExit:
      Close();
      return true;
    default:
      return false;
  }
}
