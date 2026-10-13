#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shellapi.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Must match APPLINK_MSG_ID in the app_links plugin (WM_USER + 2).
constexpr ULONG_PTR kAppLinkMsgId = WM_USER + 2;
constexpr wchar_t kAppLinkPrefix[] = L"stibaliuag-dashboard:";

// When the browser finishes Microsoft sign-in it launches
// `capstone_dashboard.exe stibaliuag-dashboard://login-callback/?code=...`.
// That must reach the window that started the sign-in (it holds the PKCE
// code verifier), not a second app instance. Returns true if the link was
// handed to an already-running copy of this exe.
bool ForwardLinkToRunningInstance() {
  int argc = 0;
  wchar_t **argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) return false;
  std::wstring link = (argc == 2) ? argv[1] : L"";
  ::LocalFree(argv);
  if (link.rfind(kAppLinkPrefix, 0) != 0) return false;

  wchar_t self_path[MAX_PATH];
  if (::GetModuleFileNameW(nullptr, self_path, MAX_PATH) == 0) return false;
  const DWORD self_pid = ::GetCurrentProcessId();

  struct Search {
    const wchar_t *self_path;
    DWORD self_pid;
    HWND found;
  } search{self_path, self_pid, nullptr};

  ::EnumWindows(
      [](HWND hwnd, LPARAM param) -> BOOL {
        auto *s = reinterpret_cast<Search *>(param);
        wchar_t cls[64];
        if (::GetClassNameW(hwnd, cls, 64) == 0 ||
            wcscmp(cls, L"FLUTTER_RUNNER_WIN32_WINDOW") != 0) {
          return TRUE;
        }
        DWORD pid = 0;
        ::GetWindowThreadProcessId(hwnd, &pid);
        if (pid == s->self_pid) return TRUE;
        HANDLE proc = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
        if (proc == nullptr) return TRUE;
        wchar_t path[MAX_PATH];
        DWORD len = MAX_PATH;
        bool same = ::QueryFullProcessImageNameW(proc, 0, path, &len) &&
                    _wcsicmp(path, s->self_path) == 0;
        ::CloseHandle(proc);
        if (same) {
          s->found = hwnd;
          return FALSE;
        }
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&search));

  if (search.found == nullptr) return false;

  // The plugin reads a narrow, NUL-terminated UTF-8 string.
  int size = ::WideCharToMultiByte(CP_UTF8, 0, link.c_str(), -1, nullptr, 0,
                                   nullptr, nullptr);
  if (size <= 0) return false;
  std::string utf8(size, '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, link.c_str(), -1, &utf8[0], size, nullptr,
                        nullptr);

  COPYDATASTRUCT cds = {};
  cds.dwData = kAppLinkMsgId;
  cds.cbData = static_cast<DWORD>(utf8.size());  // includes the NUL
  cds.lpData = &utf8[0];
  ::SendMessageW(search.found, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&cds));

  if (::IsIconic(search.found)) ::ShowWindow(search.found, SW_RESTORE);
  ::SetForegroundWindow(search.found);
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (ForwardLinkToRunningInstance()) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"capstone_dashboard", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
