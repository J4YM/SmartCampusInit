#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// A class abstraction for a high DPI-aware Win32 Window. Intended to be
// inherited from by classes that wish to specialize with custom
// rendering and input handling
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // Creates a win32 window with |title| that is positioned and sized using
  // |origin| and |size|. New windows are created on the default monitor. Window
  // sizes are specified to the OS in physical pixels, hence to ensure a
  // consistent size this function will scale the inputted width and height as
  // as appropriate for the default monitor. The window is invisible until
  // |Show| is called. Returns true if the window was created successfully.
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // Show the current window. Returns true if the window was successfully shown.
  bool Show();

  // Release OS resources associated with window.
  void Destroy();

  // Inserts |content| into the window tree.
  void SetChildContent(HWND content);

  // Returns the backing Window handle to enable clients to set icon and other
  // window properties. Returns nullptr if the window has been destroyed.
  HWND GetHandle();

  // If true, closing this window will quit the application.
  void SetQuitOnClose(bool quit_on_close);

  // Return a RECT representing the bounds of the current client area.
  RECT GetClientArea();

  // Reverses EnterFullscreenKioskMode: restores normal window chrome
  // (title bar, close/minimize/maximize buttons, resizable border) at
  // this window's originally requested position/size, and lets WM_CLOSE/
  // WM_SYSCOMMAND behave normally again. Called from a platform channel
  // (see flutter_window.cpp) by every non-kiosk Dart entrypoint
  // (lib/main.dart, lib/main_it_technician.dart) right after startup —
  // lib/main_kiosk.dart never calls it, so the kiosk build keeps today's
  // locked-down behavior unchanged. A brief flash of the fullscreen,
  // chrome-less kiosk window before this call lands is expected: native
  // window creation (and EnterFullscreenKioskMode with it) always happens
  // before the Dart entrypoint that would ask to skip it ever runs.
  void DisableKioskLockdown();

 protected:
  // Processes and route salient window messages for mouse handling,
  // size change and DPI. Delegates handling of these to member overloads that
  // inheriting classes can handle.
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // Strips the title bar/borders/system menu, resizes to fill the monitor,
  // and registers the Ctrl+Shift+Alt+Q exit hotkey — see win32_window.cpp
  // for why this applies unconditionally to every window this runner
  // creates.
  void EnterFullscreenKioskMode(HWND window);

  // Called when CreateAndShow is called, allowing subclass window-related
  // setup. Subclasses should return false if setup fails.
  virtual bool OnCreate();

  // Called when Destroy is called.
  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  // OS callback called by message pump. Handles the WM_NCCREATE message which
  // is passed when the non-client area is being created and enables automatic
  // non-client DPI scaling so that the non-client area automatically
  // responds to changes in DPI. All other messages are handled by
  // MessageHandler.
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // Retrieves a class instance pointer for |window|
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // Update the window frame's theme to match the system theme.
  static void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;

  // True from creation until DisableKioskLockdown() is called (if ever).
  // Gates the WM_CLOSE/WM_SYSCOMMAND blocking in MessageHandler — see
  // DisableKioskLockdown's own doc comment.
  bool kiosk_lockdown_active_ = true;

  // The position/size originally requested in Create(), scaled for the
  // monitor's DPI — restored by DisableKioskLockdown() once
  // EnterFullscreenKioskMode has resized the window to fill the monitor.
  int restore_origin_x_ = 0;
  int restore_origin_y_ = 0;
  int restore_width_ = 0;
  int restore_height_ = 0;

  // window handle for top level window.
  HWND window_handle_ = nullptr;

  // window handle for hosted content.
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
