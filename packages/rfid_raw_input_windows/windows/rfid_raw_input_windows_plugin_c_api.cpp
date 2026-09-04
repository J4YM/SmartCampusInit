#include "include/rfid_raw_input_windows/rfid_raw_input_windows_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "rfid_raw_input_windows_plugin.h"

void RfidRawInputWindowsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  rfid_raw_input_windows::RfidRawInputWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
