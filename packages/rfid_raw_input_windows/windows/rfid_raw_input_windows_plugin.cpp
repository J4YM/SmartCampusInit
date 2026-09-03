#include "rfid_raw_input_windows_plugin.h"

#include <flutter/standard_method_codec.h>
#include <flutter/event_stream_handler_functions.h>

namespace rfid_raw_input_windows {

using flutter::EncodableMap;
using flutter::EncodableValue;

// static
void RfidRawInputWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto plugin = std::make_unique<RfidRawInputWindowsPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

RfidRawInputWindowsPlugin::RfidRawInputWindowsPlugin(
    flutter::PluginRegistrarWindows *registrar)
    : registrar_(registrar) {
  auto method_channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "rfid_raw_input_windows/methods",
      &flutter::StandardMethodCodec::GetInstance());
  method_channel->SetMethodCallHandler(
      [this](const auto &call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  auto event_channel = std::make_unique<flutter::EventChannel<EncodableValue>>(
      registrar->messenger(), "rfid_raw_input_windows/events",
      &flutter::StandardMethodCodec::GetInstance());
  auto handler = std::make_unique<
      flutter::StreamHandlerFunctions<EncodableValue>>(
      [this](const EncodableValue *arguments,
             std::unique_ptr<flutter::EventSink<EncodableValue>> &&events)
          -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        event_sink_ = std::move(events);
        if (auto *map = std::get_if<EncodableMap>(arguments)) {
          auto vid = map->find(EncodableValue("vendorId"));
          auto pid = map->find(EncodableValue("productId"));
          if (vid != map->end() && pid != map->end()) {
            RegisterDevice(
                static_cast<unsigned short>(std::get<int>(vid->second)),
                static_cast<unsigned short>(std::get<int>(pid->second)));
          }
        }
        return nullptr;
      },
      [this](const EncodableValue *arguments)
          -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        event_sink_ = nullptr;
        return nullptr;
      });
  event_channel->SetStreamHandler(std::move(handler));

  window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowProc(hwnd, message, wparam, lparam);
      });
}

RfidRawInputWindowsPlugin::~RfidRawInputWindowsPlugin() {
  if (window_proc_id_ != -1) {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
  }
}

void RfidRawInputWindowsPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue> &call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (call.method_name() == "deviceFound") {
    const auto *map = std::get_if<EncodableMap>(call.arguments());
    if (!map) {
      result->Error("bad_args", "Expected a map with vendorId/productId");
      return;
    }
    auto vid = map->find(EncodableValue("vendorId"));
    auto pid = map->find(EncodableValue("productId"));
    if (vid == map->end() || pid == map->end()) {
      result->Error("bad_args", "Missing vendorId/productId");
      return;
    }
    RegisterDevice(
        static_cast<unsigned short>(std::get<int>(vid->second)),
        static_cast<unsigned short>(std::get<int>(pid->second)));
    result->Success(EncodableValue(target_device_handle_ != nullptr));
    return;
  }
  result->NotImplemented();
}

void RfidRawInputWindowsPlugin::RegisterDevice(unsigned short vendor_id,
                                                unsigned short product_id) {
  target_vendor_id_ = vendor_id;
  target_product_id_ = product_id;
  target_device_handle_ = nullptr;

  // Enumerate connected raw input devices and find the one whose HID
  // vendor/product id matches. RIDI_DEVICEINFO gives us that without
  // needing a separate SetupAPI pass.
  UINT device_count = 0;
  GetRawInputDeviceList(nullptr, &device_count, sizeof(RAWINPUTDEVICELIST));
  if (device_count == 0) return;

  std::vector<RAWINPUTDEVICELIST> devices(device_count);
  GetRawInputDeviceList(devices.data(), &device_count, sizeof(RAWINPUTDEVICELIST));

  for (const auto &device : devices) {
    if (device.dwType != RIM_TYPEHID) continue;

    RID_DEVICE_INFO info;
    info.cbSize = sizeof(RID_DEVICE_INFO);
    UINT size = sizeof(RID_DEVICE_INFO);
    if (GetRawInputDeviceInfoW(device.hDevice, RIDI_DEVICEINFO, &info, &size) <= 0) {
      continue;
    }
    if (info.hid.dwVendorId == vendor_id && info.hid.dwProductId == product_id) {
      target_device_handle_ = device.hDevice;
      break;
    }
  }

  if (target_device_handle_ == nullptr) return;

  // RIDEV_INPUTSINK: receive this device's input even when our window
  // doesn't have foreground focus — the whole point of this plugin.
  RAWINPUTDEVICE rid;
  rid.usUsagePage = 0x01;  // Generic Desktop
  rid.usUsage = 0x06;      // Keyboard
  rid.dwFlags = RIDEV_INPUTSINK;
  rid.hwndTarget = registrar_->GetView()->GetNativeWindow();
  RegisterRawInputDevices(&rid, 1, sizeof(RAWINPUTDEVICE));
}

std::optional<LRESULT> RfidRawInputWindowsPlugin::HandleWindowProc(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_INPUT) {
    OnRawInput(lparam);
  }
  return std::nullopt;
}

void RfidRawInputWindowsPlugin::OnRawInput(LPARAM lparam) {
  if (target_device_handle_ == nullptr) return;

  UINT size = 0;
  GetRawInputData(reinterpret_cast<HRAWINPUT>(lparam), RID_INPUT, nullptr, &size,
                   sizeof(RAWINPUTHEADER));
  if (size == 0) return;

  std::vector<BYTE> buffer(size);
  if (GetRawInputData(reinterpret_cast<HRAWINPUT>(lparam), RID_INPUT, buffer.data(),
                       &size, sizeof(RAWINPUTHEADER)) != size) {
    return;
  }

  auto *raw = reinterpret_cast<RAWINPUT *>(buffer.data());
  if (raw->header.dwType != RIM_TYPEKEYBOARD) return;
  // Ignore input from any device other than our registered reader — this
  // is what makes the capture independent of window focus AND of the
  // kiosk's own reader's taps.
  if (raw->header.hDevice != target_device_handle_) return;

  const RAWKEYBOARD &kb = raw->data.keyboard;
  if (kb.Flags & RI_KEY_BREAK) return;  // key-up; only act on key-down

  BYTE keyboard_state[256] = {0};
  WCHAR decoded[4] = {0};
  int result = ToUnicode(kb.VKey, kb.MakeCode, keyboard_state, decoded, 4, 0);

  if (kb.VKey == VK_RETURN) {
    if (!buffer_.empty() && event_sink_) {
      // Narrow the wide buffer — RFID UIDs are ASCII digits/letters, so a
      // direct narrow is safe here (no non-ASCII characters expected).
      std::string uid(buffer_.begin(), buffer_.end());
      event_sink_->Success(EncodableValue(uid));
    }
    buffer_.clear();
    return;
  }

  if (result == 1) {
    buffer_ += decoded[0];
  }
}

}  // namespace rfid_raw_input_windows
