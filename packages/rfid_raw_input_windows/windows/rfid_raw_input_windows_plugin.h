#ifndef FLUTTER_PLUGIN_RFID_RAW_INPUT_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_RFID_RAW_INPUT_WINDOWS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <windows.h>

#include <memory>
#include <string>

namespace rfid_raw_input_windows {

class RfidRawInputWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  RfidRawInputWindowsPlugin(flutter::PluginRegistrarWindows *registrar);
  virtual ~RfidRawInputWindowsPlugin();

 private:
  std::optional<LRESULT> HandleWindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void RegisterDevice(unsigned short vendor_id, unsigned short product_id);
  void OnRawInput(LPARAM lparam);

  flutter::PluginRegistrarWindows *registrar_;
  int window_proc_id_ = -1;
  unsigned short target_vendor_id_ = 0;
  unsigned short target_product_id_ = 0;
  HANDLE target_device_handle_ = nullptr;
  std::wstring buffer_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
};

}  // namespace rfid_raw_input_windows

#endif
