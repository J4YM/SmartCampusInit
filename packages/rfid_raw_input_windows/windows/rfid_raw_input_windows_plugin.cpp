#include "rfid_raw_input_windows_plugin.h"

#include <flutter/standard_method_codec.h>
#include <flutter/event_stream_handler_functions.h>

#include <variant>
#include <vector>

namespace rfid_raw_input_windows {

using flutter::EncodableMap;
using flutter::EncodableValue;

namespace {

// Parses the 4 hex digits following "VID_" and "PID_" out of a raw input
// keyboard's device interface path (RIDI_DEVICENAME), e.g.
// "\\?\HID#VID_08FF&PID_0009#7&27a4f0a0&0&0000#{...}". Returns false if
// either segment isn't present or doesn't parse as hex — e.g. non-USB
// keyboards (PS/2, ACPI) have no VID_/PID_ segment at all.
bool ParseVendorProductId(const std::wstring &device_name,
                           unsigned short *vendor_id,
                           unsigned short *product_id) {
  auto vid_pos = device_name.find(L"VID_");
  auto pid_pos = device_name.find(L"PID_");
  if (vid_pos == std::wstring::npos || pid_pos == std::wstring::npos) {
    return false;
  }
  if (vid_pos + 8 > device_name.size() || pid_pos + 8 > device_name.size()) {
    return false;
  }
  try {
    *vendor_id = static_cast<unsigned short>(
        std::stoul(device_name.substr(vid_pos + 4, 4), nullptr, 16));
    *product_id = static_cast<unsigned short>(
        std::stoul(device_name.substr(pid_pos + 4, 4), nullptr, 16));
  } catch (...) {
    return false;
  }
  return true;
}

}  // namespace

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
  // vendor/product id matches. A USB HID keyboard-wedge reader enumerates
  // as RIM_TYPEKEYBOARD (not RIM_TYPEHID — that's for non-keyboard/mouse
  // HID collections), and RIDI_DEVICEINFO's keyboard union arm carries no
  // vendor/product id at all. Instead, query RIDI_DEVICENAME for the
  // device's interface path (e.g. "\\?\HID#VID_08FF&PID_0009#...") and
  // parse the ids out of that.
  UINT device_count = 0;
  GetRawInputDeviceList(nullptr, &device_count, sizeof(RAWINPUTDEVICELIST));
  if (device_count == 0) return;

  std::vector<RAWINPUTDEVICELIST> devices(device_count);
  GetRawInputDeviceList(devices.data(), &device_count, sizeof(RAWINPUTDEVICELIST));

  for (const auto &device : devices) {
    if (device.dwType != RIM_TYPEKEYBOARD) continue;

    // Two-call pattern: first with a null buffer to get the required
    // size (in characters), then with an allocated buffer for the data.
    UINT name_size = 0;
    GetRawInputDeviceInfoW(device.hDevice, RIDI_DEVICENAME, nullptr, &name_size);
    if (name_size == 0) continue;

    std::vector<wchar_t> name_buffer(name_size);
    UINT chars_written = GetRawInputDeviceInfoW(
        device.hDevice, RIDI_DEVICENAME, name_buffer.data(), &name_size);
    if (chars_written == 0 || chars_written == static_cast<UINT>(-1)) {
      continue;
    }

    std::wstring device_name(name_buffer.data());
    unsigned short device_vendor_id = 0;
    unsigned short device_product_id = 0;
    if (!ParseVendorProductId(device_name, &device_vendor_id, &device_product_id)) {
      continue;
    }
    if (device_vendor_id == vendor_id && device_product_id == product_id) {
      target_device_handle_ = device.hDevice;
      break;
    }
  }

  if (target_device_handle_ == nullptr) return;

  auto *view = registrar_->GetView();
  if (view == nullptr) return;

  // RIDEV_INPUTSINK requires hwndTarget to be a top-level window; the
  // Flutter view's own HWND is a *child* of it, and
  // RegisterTopLevelWindowProcDelegate (which HandleWindowProc is wired
  // through) only ever receives messages sent to the top-level window. So
  // resolve up to the actual top-level ancestor before registering.
  HWND top_level_hwnd = GetAncestor(view->GetNativeWindow(), GA_ROOT);

  // RIDEV_INPUTSINK: receive this device's input even when our window
  // doesn't have foreground focus — the whole point of this plugin.
  RAWINPUTDEVICE rid;
  rid.usUsagePage = 0x01;  // Generic Desktop
  rid.usUsage = 0x06;      // Keyboard
  rid.dwFlags = RIDEV_INPUTSINK;
  rid.hwndTarget = top_level_hwnd;
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
  const bool is_break = (kb.Flags & RI_KEY_BREAK) != 0;

  // Track this device's own Shift state from its raw key-down/key-up
  // events before decoding. RFID UIDs in this project are uppercase hex
  // pairs joined by ':' (e.g. "A3:F1:0B:9C" — see
  // supabase/populating/populate_mock_data.sql and record_rfid_tap's
  // exact-match lookup), both of which require Shift on a US layout,
  // so ToUnicode needs an accurate Shift state to decode them correctly.
  // We maintain this ourselves rather than using GetKeyboardState because
  // that reflects the foreground window's keyboard state, which this
  // device may not be driving at all when it lacks OS focus. Raw Input
  // reports Shift key events with either the generic VK_SHIFT or the
  // side-specific VK_LSHIFT/VK_RSHIFT depending on the device, so handle
  // all three.
  if (kb.VKey == VK_SHIFT || kb.VKey == VK_LSHIFT || kb.VKey == VK_RSHIFT) {
    const BYTE state = is_break ? 0 : 0x80;
    keyboard_state_[VK_SHIFT] = state;
    if (kb.VKey == VK_LSHIFT) keyboard_state_[VK_LSHIFT] = state;
    if (kb.VKey == VK_RSHIFT) keyboard_state_[VK_RSHIFT] = state;
  }

  if (is_break) return;  // key-up; only act on key-down for buffering

  WCHAR decoded[4] = {0};
  int result = ToUnicode(kb.VKey, kb.MakeCode, keyboard_state_, decoded, 4, 0);

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
