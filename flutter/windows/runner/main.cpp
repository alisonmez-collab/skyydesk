#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <tchar.h>
#include <uni_links_desktop/uni_links_desktop_plugin.h>
#include <windows.h>

#include <algorithm>
#include <iostream>

#include "win32_desktop.h"
#include "flutter_window.h"
#include "utils.h"

typedef char** (*FUNC_CORE_MAIN)(int*);
typedef void (*FUNC_FREE_ARGS)( char**, int);
typedef int (*FUNC_GET_APP_NAME)(wchar_t*, int);
typedef int (*FUNC_IS_DISABLE_INSTALLATION)();
/// Note: `--server`, `--service` are already handled in [core_main.rs].
const std::vector<std::string> parameters_white_list = {"--install", "--cm"};

const wchar_t* getWindowClassName();

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command)
{
  // Cekirdek kutuphanenin adi Cargo.toml'daki [lib] name ile ayni olmak
  // ZORUNDA. Ikisi ayrisirsa uygulama hic acilmaz ve derleme bunu yakalamaz:
  // ad burada bir metin, derleyici dogrulayamiyor. 15.08.2026'da tam bu oldu --
  // kutuphane libskyydesk.dll olarak yeniden adlandirildi, burasi eski adi
  // aramaya devam etti; paketlenen surum "Failed to load librustdesk.dll"
  // deyip cikiyordu. Kurulum da bu yuzden hic tamamlanmiyordu.
  HINSTANCE hInstance = LoadLibraryA("libskyydesk.dll");
  if (!hInstance)
  {
    std::cout << "Failed to load libskyydesk.dll." << std::endl;
    return EXIT_FAILURE;
  }
  FUNC_CORE_MAIN core_main =
      (FUNC_CORE_MAIN)GetProcAddress(hInstance, "rustdesk_core_main_args");
  if (!core_main)
  {
    std::cout << "Failed to get the core entry point." << std::endl;
    return EXIT_FAILURE;
  }
  FUNC_FREE_ARGS free_c_args =
      (FUNC_FREE_ARGS)GetProcAddress(hInstance, "free_c_args");
  if (!free_c_args)
  {
    std::cout << "Failed to get free_c_args." << std::endl;
    return EXIT_FAILURE;
  }
  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  // Remove possible trailing whitespace from command line arguments
  for (auto& argument : command_line_arguments) {
    argument.erase(argument.find_last_not_of(" \n\r\t"));
  }

  int args_len = 0;
  char** c_args = core_main(&args_len);
  if (!c_args)
  {
    std::string args_str = "";
    for (const auto& argument : command_line_arguments) {
      args_str += (argument + " ");
    }
    // std::cout << "RustDesk [" << args_str << "], core returns false, exiting without launching Flutter app." << std::endl;
    return EXIT_SUCCESS;
  }
  std::vector<std::string> rust_args(c_args, c_args + args_len);
  free_c_args(c_args, args_len);
  FUNC_IS_DISABLE_INSTALLATION is_disable_installation_fn =
      (FUNC_IS_DISABLE_INSTALLATION)GetProcAddress(hInstance, "rustdesk_is_disable_installation");
  bool is_disable_installation =
      is_disable_installation_fn && is_disable_installation_fn() != 0;
  const auto installParam = std::string("--install");
  // Flutter reads the original process command line, not only rust_args, so
  // remove the `--install` injected by the portable wrapper here as well. This
  // also lets `no-install.exe` continue as a portable app when installation is
  // disabled. See: https://github.com/rustdesk/rustdesk-server-pro/issues/991#issuecomment-4978376890
  if (is_disable_installation) {
    command_line_arguments.erase(
        std::remove(command_line_arguments.begin(),
                    command_line_arguments.end(),
                    installParam),
        command_line_arguments.end());
  }

  std::wstring app_name = L"SkyDesk";
  FUNC_GET_APP_NAME get_app_name_fn = (FUNC_GET_APP_NAME)GetProcAddress(hInstance, "get_rustdesk_app_name");
  if (get_app_name_fn) {
    wchar_t app_name_buffer[512] = {0};
    if (get_app_name_fn(app_name_buffer, 512) == 0) {
      app_name = std::wstring(app_name_buffer);
    }
  }

  // Uri links dispatch
  //
  // Yalnizca GORUNUR bir ana pencereye defer et. Kurulu makinede arka planda
  // --server ve --tray surecleri de ayni pencere sinifi + basligiyla GIZLI
  // pencere tutuyor; eski kod FindWindowW ile ilk eslesen (cogu zaman o gizli
  // server penceresi) uzerinde ShowWindow yapip cikiyor, ama gizli pencere
  // gorunmedigi icin uygulama kurulunca/kisayoldan tiklaninca HIC acilmiyordu.
  // Gorunur bir eslesme yoksa (sadece server/tray varsa) defer etmeyip yeni
  // ana pencere aciyoruz. (20.08.2026, sahada tespit.)
  HWND hwnd = NULL;
  {
    HWND h = ::FindWindowExW(NULL, NULL, getWindowClassName(), app_name.c_str());
    while (h != NULL) {
      if (::IsWindowVisible(h)) {
        hwnd = h;
        break;
      }
      h = ::FindWindowExW(NULL, h, getWindowClassName(), app_name.c_str());
    }
  }
  if (hwnd != NULL) {
    // Allow multiple flutter instances when being executed by parameters
    // contained in whitelists.
    bool allow_multiple_instances = false;
    for (auto& whitelist_param : parameters_white_list) {
      allow_multiple_instances =
          allow_multiple_instances ||
          std::find(command_line_arguments.begin(),
                    command_line_arguments.end(),
                    whitelist_param) != command_line_arguments.end();
    }
    if (!allow_multiple_instances) {
      if (!command_line_arguments.empty()) {
        // Dispatch command line arguments
        DispatchToUniLinksDesktop(hwnd);
      } else {
        // Not called with arguments, or just open the app shortcut on desktop.
        // So we just show the main window instead.
        ::ShowWindow(hwnd, SW_NORMAL);
        ::SetForegroundWindow(hwnd);
      }
      return EXIT_FAILURE;
    }
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent())
  {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  // connection manager hide icon from taskbar
  bool is_cm_page = false;
  auto cmParam = std::string("--cm");
  if (!command_line_arguments.empty() && command_line_arguments.front().compare(0, cmParam.size(), cmParam.c_str()) == 0) {
    is_cm_page = true;
  }
  bool is_install_page = false;
  if (!command_line_arguments.empty() && command_line_arguments.front().compare(0, installParam.size(), installParam.c_str()) == 0) {
    is_install_page = true;
  }

  command_line_arguments.insert(command_line_arguments.end(), rust_args.begin(), rust_args.end());
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);

  // Get primary monitor's work area.
  Win32Window::Point workarea_origin(0, 0);
  Win32Window::Size workarea_size(0, 0);

  Win32Desktop::GetWorkArea(workarea_origin, workarea_size);

  // Compute window bounds for default main window position: (10, 10) x(800, 600)
  Win32Window::Point relative_origin(10, 10);

  Win32Window::Point origin(workarea_origin.x + relative_origin.x, workarea_origin.y + relative_origin.y);
  Win32Window::Size size(800u, 600u);

  // Fit the window to the monitor's work area.
  Win32Desktop::FitToWorkArea(origin, size);

  std::wstring window_title;
  if (is_cm_page) {
    window_title = app_name + L" - Connection Manager";
  } else if (is_install_page) {
    window_title = app_name + L" - Install";
  } else {
    window_title = app_name;
  }
  if (!window.CreateAndShow(window_title, origin, size, !is_cm_page)) {
      return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0))
  {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
