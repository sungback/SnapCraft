#include "flutter_window.h"

#include <atlimage.h>
#include <dwmapi.h>
#include <windows.h>
#include <ole2.h>
#include <shellapi.h>
#include <shlobj.h>

#include <algorithm>
#include <cstring>
#include <cwctype>
#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

#ifndef DWMWA_EXTENDED_FRAME_BOUNDS
#define DWMWA_EXTENDED_FRAME_BOUNDS 9
#endif

#ifndef DWMWA_CLOAKED
#define DWMWA_CLOAKED 14
#endif

namespace {

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int size_needed = MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  if (size_needed <= 0) return std::wstring();
  std::wstring result(size_needed, 0);
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      &result[0], size_needed);
  return result;
}

std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) return std::string();
  int size_needed = WideCharToMultiByte(
      CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()), nullptr, 0,
      nullptr, nullptr);
  if (size_needed <= 0) return std::string();
  std::string result(size_needed, 0);
  WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                      &result[0], size_needed, nullptr, nullptr);
  return result;
}

std::optional<std::string> GetClipboardFirstFilePath() {
  if (!IsClipboardFormatAvailable(CF_HDROP)) {
    return std::nullopt;
  }
  if (!OpenClipboard(nullptr)) {
    return std::nullopt;
  }
  std::optional<std::string> result;
  HANDLE hdrop = GetClipboardData(CF_HDROP);
  if (hdrop != nullptr) {
    UINT count = DragQueryFileW(reinterpret_cast<HDROP>(hdrop), 0xFFFFFFFF,
                                nullptr, 0);
    if (count > 0) {
      UINT len = DragQueryFileW(reinterpret_cast<HDROP>(hdrop), 0, nullptr, 0);
      if (len > 0) {
        std::wstring buf(len + 1, L'\0');
        DragQueryFileW(reinterpret_cast<HDROP>(hdrop), 0, &buf[0], len + 1);
        buf.resize(len);
        result = WideToUtf8(buf);
      }
    }
  }
  CloseClipboard();
  return result;
}

HGLOBAL CreateDibFromPngBytes(const std::vector<uint8_t>& png_bytes) {
  if (png_bytes.empty()) return nullptr;

  HGLOBAL h_png = GlobalAlloc(GMEM_MOVEABLE, png_bytes.size());
  if (!h_png) return nullptr;
  void* png_ptr = GlobalLock(h_png);
  if (!png_ptr) {
    GlobalFree(h_png);
    return nullptr;
  }
  std::memcpy(png_ptr, png_bytes.data(), png_bytes.size());
  GlobalUnlock(h_png);

  IStream* stream = nullptr;
  if (FAILED(CreateStreamOnHGlobal(h_png, TRUE, &stream)) || !stream) {
    GlobalFree(h_png);
    return nullptr;
  }

  CImage image;
  HRESULT hr = image.Load(stream);
  stream->Release();
  if (FAILED(hr) || image.IsNull()) {
    return nullptr;
  }

  const int w = image.GetWidth();
  const int h = image.GetHeight();
  if (w <= 0 || h <= 0) {
    return nullptr;
  }

  const size_t pixel_bytes =
      static_cast<size_t>(w) * static_cast<size_t>(h) * 4;
  HGLOBAL h_dib =
      GlobalAlloc(GMEM_MOVEABLE, sizeof(BITMAPINFOHEADER) + pixel_bytes);
  if (!h_dib) return nullptr;

  auto* dib_ptr = static_cast<uint8_t*>(GlobalLock(h_dib));
  if (!dib_ptr) {
    GlobalFree(h_dib);
    return nullptr;
  }

  BITMAPINFO bi{};
  bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bi.bmiHeader.biWidth = w;
  bi.bmiHeader.biHeight = h;
  bi.bmiHeader.biPlanes = 1;
  bi.bmiHeader.biBitCount = 32;
  bi.bmiHeader.biCompression = BI_RGB;
  bi.bmiHeader.biSizeImage = static_cast<DWORD>(pixel_bytes);

  std::memcpy(dib_ptr, &bi.bmiHeader, sizeof(BITMAPINFOHEADER));
  HDC hdc = GetDC(nullptr);
  int rows = GetDIBits(hdc, static_cast<HBITMAP>(image), 0,
                       static_cast<UINT>(h), dib_ptr + sizeof(BITMAPINFOHEADER),
                       &bi, DIB_RGB_COLORS);
  ReleaseDC(nullptr, hdc);
  GlobalUnlock(h_dib);

  if (rows == 0) {
    GlobalFree(h_dib);
    return nullptr;
  }
  return h_dib;
}

bool CopyPngAndFileToClipboard(HWND owner,
                               const std::vector<uint8_t>& png_bytes,
                               const std::wstring& file_path) {
  HGLOBAL h_dib = CreateDibFromPngBytes(png_bytes);

  HGLOBAL h_png = nullptr;
  if (!png_bytes.empty()) {
    h_png = GlobalAlloc(GMEM_MOVEABLE, png_bytes.size());
    if (h_png) {
      void* dst = GlobalLock(h_png);
      if (dst) {
        std::memcpy(dst, png_bytes.data(), png_bytes.size());
        GlobalUnlock(h_png);
      } else {
        GlobalFree(h_png);
        h_png = nullptr;
      }
    }
  }

  HGLOBAL h_drop = nullptr;
  if (!file_path.empty()) {
    const size_t drop_size =
        sizeof(DROPFILES) + (file_path.size() + 2) * sizeof(wchar_t);
    h_drop = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, drop_size);
    if (h_drop) {
      auto* df = static_cast<DROPFILES*>(GlobalLock(h_drop));
      if (df) {
        df->pFiles = sizeof(DROPFILES);
        df->fWide = TRUE;
        wchar_t* dst = reinterpret_cast<wchar_t*>(
            reinterpret_cast<uint8_t*>(df) + sizeof(DROPFILES));
        std::memcpy(dst, file_path.c_str(), file_path.size() * sizeof(wchar_t));
        GlobalUnlock(h_drop);
      } else {
        GlobalFree(h_drop);
        h_drop = nullptr;
      }
    }
  }

  HGLOBAL h_text = nullptr;
  if (!file_path.empty()) {
    const size_t text_bytes = (file_path.size() + 1) * sizeof(wchar_t);
    h_text = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, text_bytes);
    if (h_text) {
      void* dst = GlobalLock(h_text);
      if (dst) {
        std::memcpy(dst, file_path.c_str(), file_path.size() * sizeof(wchar_t));
        GlobalUnlock(h_text);
      } else {
        GlobalFree(h_text);
        h_text = nullptr;
      }
    }
  }

  if (!OpenClipboard(owner)) {
    if (h_dib) GlobalFree(h_dib);
    if (h_png) GlobalFree(h_png);
    if (h_drop) GlobalFree(h_drop);
    if (h_text) GlobalFree(h_text);
    return false;
  }

  EmptyClipboard();
  bool any_image = false;

  const UINT png_format = RegisterClipboardFormatW(L"PNG");
  if (png_format != 0 && h_png) {
    if (SetClipboardData(png_format, h_png) != nullptr) {
      any_image = true;
    } else {
      GlobalFree(h_png);
    }
  } else if (h_png) {
    GlobalFree(h_png);
  }

  if (h_dib) {
    if (SetClipboardData(CF_DIB, h_dib) != nullptr) {
      any_image = true;
    } else {
      GlobalFree(h_dib);
    }
  }

  if (h_drop) {
    if (SetClipboardData(CF_HDROP, h_drop) == nullptr) {
      GlobalFree(h_drop);
    }
  }

  if (h_text) {
    if (SetClipboardData(CF_UNICODETEXT, h_text) == nullptr) {
      GlobalFree(h_text);
    }
  }

  CloseClipboard();
  return any_image;
}

bool GetVisibleWindowBounds(HWND hwnd, RECT* out_rect) {
  if (SUCCEEDED(DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS,
                                      out_rect, sizeof(RECT)))) {
    return true;
  }
  return GetWindowRect(hwnd, out_rect) != FALSE;
}

struct EnumSearchContext {
  POINT pt;
  HWND ignore_app;
  HWND ignore_overlay;
  HWND ignore_highlight;
  HWND found_hwnd;
};

BOOL CALLBACK EnumWindowsAtPointProc(HWND hwnd, LPARAM lparam) {
  auto* ctx = reinterpret_cast<EnumSearchContext*>(lparam);
  if (hwnd == ctx->ignore_app || hwnd == ctx->ignore_overlay ||
      hwnd == ctx->ignore_highlight) {
    return TRUE;
  }
  if (!IsWindowVisible(hwnd) || IsIconic(hwnd)) {
    return TRUE;
  }

  DWORD cloaked = 0;
  if (SUCCEEDED(DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &cloaked,
                                      sizeof(cloaked))) &&
      cloaked != 0) {
    return TRUE;
  }

  LONG ex_style = GetWindowLongW(hwnd, GWL_EXSTYLE);
  if ((ex_style & WS_EX_TRANSPARENT) != 0) {
    return TRUE;
  }

  wchar_t class_name[64] = {0};
  if (GetClassNameW(hwnd, class_name, 63) > 0) {
    if (wcscmp(class_name, L"Progman") == 0 ||
        wcscmp(class_name, L"WorkerW") == 0 ||
        wcscmp(class_name, L"Shell_TrayWnd") == 0 ||
        wcscmp(class_name, L"Shell_SecondaryTrayWnd") == 0) {
      return TRUE;
    }
  }

  RECT bounds{};
  if (!GetVisibleWindowBounds(hwnd, &bounds)) {
    return TRUE;
  }
  if (bounds.right - bounds.left < 20 || bounds.bottom - bounds.top < 20) {
    return TRUE;
  }

  if (PtInRect(&bounds, ctx->pt)) {
    ctx->found_hwnd = hwnd;
    return FALSE;  // Stop enumeration; found topmost window in Z-order
  }
  return TRUE;
}

HWND FindTopWindowAtPoint(POINT pt, HWND ignore_app, HWND ignore_overlay,
                          HWND ignore_highlight) {
  EnumSearchContext ctx{};
  ctx.pt = pt;
  ctx.ignore_app = ignore_app;
  ctx.ignore_overlay = ignore_overlay;
  ctx.ignore_highlight = ignore_highlight;
  ctx.found_hwnd = nullptr;
  EnumWindows(EnumWindowsAtPointProc, reinterpret_cast<LPARAM>(&ctx));
  return ctx.found_hwnd;
}

struct WindowPickerState {
  HWND app_hwnd = nullptr;
  HWND overlay_hwnd = nullptr;
  HWND highlight_hwnd = nullptr;
  HWND hovered_hwnd = nullptr;
  HWND selected_hwnd = nullptr;
  bool done = false;
};

WindowPickerState g_picker_state;

void UpdateHoveredHighlight(POINT pt) {
  HWND target = FindTopWindowAtPoint(
      pt, g_picker_state.app_hwnd, g_picker_state.overlay_hwnd,
      g_picker_state.highlight_hwnd);
  if (target == g_picker_state.hovered_hwnd) {
    return;
  }
  g_picker_state.hovered_hwnd = target;

  if (target != nullptr && g_picker_state.highlight_hwnd != nullptr) {
    RECT rect{};
    if (GetVisibleWindowBounds(target, &rect)) {
      int w = rect.right - rect.left;
      int h = rect.bottom - rect.top;
      SetWindowPos(g_picker_state.highlight_hwnd, HWND_TOPMOST, rect.left,
                   rect.top, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW);
      InvalidateRect(g_picker_state.highlight_hwnd, nullptr, TRUE);
      UpdateWindow(g_picker_state.highlight_hwnd);
      return;
    }
  }

  if (g_picker_state.highlight_hwnd != nullptr) {
    ShowWindow(g_picker_state.highlight_hwnd, SW_HIDE);
  }
}

LRESULT CALLBACK HighlightWndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                  LPARAM lparam) {
  if (msg == WM_PAINT) {
    PAINTSTRUCT ps{};
    HDC hdc = BeginPaint(hwnd, &ps);
    RECT rc{};
    GetClientRect(hwnd, &rc);

    // Fill interior with color-key black (transparent)
    HBRUSH bg_brush = CreateSolidBrush(RGB(0, 0, 0));
    FillRect(hdc, &rc, bg_brush);
    DeleteObject(bg_brush);

    // Draw a 4px bright blue highlight border (#3B82F6)
    HBRUSH border_brush = CreateSolidBrush(RGB(59, 130, 246));
    const int thickness = 4;
    RECT top_rc = {rc.left, rc.top, rc.right, rc.top + thickness};
    RECT bottom_rc = {rc.left, rc.bottom - thickness, rc.right, rc.bottom};
    RECT left_rc = {rc.left, rc.top, rc.left + thickness, rc.bottom};
    RECT right_rc = {rc.right - thickness, rc.top, rc.right, rc.bottom};
    FillRect(hdc, &top_rc, border_brush);
    FillRect(hdc, &bottom_rc, border_brush);
    FillRect(hdc, &left_rc, border_brush);
    FillRect(hdc, &right_rc, border_brush);
    DeleteObject(border_brush);

    EndPaint(hwnd, &ps);
    return 0;
  }
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

LRESULT CALLBACK OverlayWndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                LPARAM lparam) {
  switch (msg) {
    case WM_SETCURSOR:
      SetCursor(LoadCursor(nullptr, IDC_CROSS));
      return TRUE;
    case WM_MOUSEMOVE: {
      POINT pt{};
      GetCursorPos(&pt);
      UpdateHoveredHighlight(pt);
      return 0;
    }
    case WM_LBUTTONDOWN: {
      POINT pt{};
      GetCursorPos(&pt);
      g_picker_state.selected_hwnd = FindTopWindowAtPoint(
          pt, g_picker_state.app_hwnd, g_picker_state.overlay_hwnd,
          g_picker_state.highlight_hwnd);
      g_picker_state.done = true;
      return 0;
    }
    case WM_RBUTTONDOWN:
      g_picker_state.selected_hwnd = nullptr;
      g_picker_state.done = true;
      return 0;
    case WM_KEYDOWN:
      if (wparam == VK_ESCAPE) {
        g_picker_state.selected_hwnd = nullptr;
        g_picker_state.done = true;
      }
      return 0;
  }
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

HWND SelectWindowInteractively(HWND app_hwnd) {
  HINSTANCE hinst = GetModuleHandle(nullptr);

  static bool classes_registered = false;
  if (!classes_registered) {
    WNDCLASSEXW overlay_cls{};
    overlay_cls.cbSize = sizeof(WNDCLASSEXW);
    overlay_cls.lpfnWndProc = OverlayWndProc;
    overlay_cls.hInstance = hinst;
    overlay_cls.hCursor = LoadCursor(nullptr, IDC_CROSS);
    overlay_cls.lpszClassName = L"SnapCraftWindowPickerOverlay";
    RegisterClassExW(&overlay_cls);

    WNDCLASSEXW highlight_cls{};
    highlight_cls.cbSize = sizeof(WNDCLASSEXW);
    highlight_cls.lpfnWndProc = HighlightWndProc;
    highlight_cls.hInstance = hinst;
    highlight_cls.lpszClassName = L"SnapCraftWindowPickerHighlight";
    RegisterClassExW(&highlight_cls);

    classes_registered = true;
  }

  g_picker_state = WindowPickerState{};
  g_picker_state.app_hwnd = app_hwnd;

  int vx = GetSystemMetrics(SM_XVIRTUALSCREEN);
  int vy = GetSystemMetrics(SM_YVIRTUALSCREEN);
  int vw = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  int vh = GetSystemMetrics(SM_CYVIRTUALSCREEN);

  HWND highlight_hwnd = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED | WS_EX_TRANSPARENT |
          WS_EX_NOACTIVATE,
      L"SnapCraftWindowPickerHighlight", L"", WS_POPUP, 0, 0, 0, 0, nullptr,
      nullptr, hinst, nullptr);
  SetLayeredWindowAttributes(highlight_hwnd, RGB(0, 0, 0), 235,
                             LWA_COLORKEY | LWA_ALPHA);
  g_picker_state.highlight_hwnd = highlight_hwnd;

  HWND overlay_hwnd = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED,
      L"SnapCraftWindowPickerOverlay", L"", WS_POPUP | WS_VISIBLE, vx, vy, vw,
      vh, nullptr, nullptr, hinst, nullptr);
  SetLayeredWindowAttributes(overlay_hwnd, 0, 1, LWA_ALPHA);
  g_picker_state.overlay_hwnd = overlay_hwnd;

  SetForegroundWindow(overlay_hwnd);
  SetFocus(overlay_hwnd);

  POINT init_pt{};
  GetCursorPos(&init_pt);
  UpdateHoveredHighlight(init_pt);

  MSG msg{};
  while (!g_picker_state.done && GetMessageW(&msg, nullptr, 0, 0)) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }

  if (highlight_hwnd) {
    ShowWindow(highlight_hwnd, SW_HIDE);
    DestroyWindow(highlight_hwnd);
  }
  if (overlay_hwnd) {
    ShowWindow(overlay_hwnd, SW_HIDE);
    DestroyWindow(overlay_hwnd);
  }
  DwmFlush();

  return g_picker_state.selected_hwnd;
}

bool CaptureSelectedWindowToPng(HWND target_hwnd,
                                const std::wstring& output_path) {
  if (target_hwnd == nullptr || !IsWindow(target_hwnd)) {
    return false;
  }

  // Bring the selected window to the very front so no other window overlaps it.
  LONG orig_ex_style = GetWindowLongW(target_hwnd, GWL_EXSTYLE);
  bool was_topmost = (orig_ex_style & WS_EX_TOPMOST) != 0;

  HWND fg_hwnd = GetForegroundWindow();
  DWORD fg_thread =
      fg_hwnd ? GetWindowThreadProcessId(fg_hwnd, nullptr) : 0;
  DWORD cur_thread = GetCurrentThreadId();
  if (fg_thread != 0 && fg_thread != cur_thread) {
    AttachThreadInput(cur_thread, fg_thread, TRUE);
  }
  BringWindowToTop(target_hwnd);
  SetForegroundWindow(target_hwnd);
  if (fg_thread != 0 && fg_thread != cur_thread) {
    AttachThreadInput(cur_thread, fg_thread, FALSE);
  }

  SetWindowPos(target_hwnd, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  UpdateWindow(target_hwnd);
  DwmFlush();
  Sleep(100);

  RECT ext_rect{};
  if (!GetVisibleWindowBounds(target_hwnd, &ext_rect)) {
    if (!was_topmost) {
      SetWindowPos(target_hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }
    return false;
  }

  // Clamp capture rectangle to virtual screen bounds
  int vx = GetSystemMetrics(SM_XVIRTUALSCREEN);
  int vy = GetSystemMetrics(SM_YVIRTUALSCREEN);
  int vw = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  int vh = GetSystemMetrics(SM_CYVIRTUALSCREEN);

  int left = std::max<int>(ext_rect.left, vx);
  int top = std::max<int>(ext_rect.top, vy);
  int right = std::min<int>(ext_rect.right, vx + vw);
  int bottom = std::min<int>(ext_rect.bottom, vy + vh);
  int width = right - left;
  int height = bottom - top;

  if (width <= 4 || height <= 4) {
    if (!was_topmost) {
      SetWindowPos(target_hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }
    return false;
  }

  HDC hdc_screen = GetDC(nullptr);
  HDC hdc_mem = CreateCompatibleDC(hdc_screen);
  HBITMAP hbitmap = CreateCompatibleBitmap(hdc_screen, width, height);
  HGDIOBJ old_obj = SelectObject(hdc_mem, hbitmap);

  BitBlt(hdc_mem, 0, 0, width, height, hdc_screen, left, top,
         SRCCOPY | CAPTUREBLT);

  SelectObject(hdc_mem, old_obj);
  DeleteDC(hdc_mem);
  ReleaseDC(nullptr, hdc_screen);

  if (!was_topmost) {
    SetWindowPos(target_hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  }

  CImage image;
  image.Attach(hbitmap);
  HRESULT hr = image.Save(output_path.c_str(), Gdiplus::ImageFormatPNG);
  image.Detach();
  DeleteObject(hbitmap);

  return SUCCEEDED(hr);
}

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

  capture_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "snap_craft/windows_capture",
          &flutter::StandardMethodCodec::GetInstance());

  capture_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "startRegionCapture") {
          auto result_code = reinterpret_cast<INT_PTR>(ShellExecuteW(
              nullptr, L"open", L"ms-screenclip://?clippingMode=Rectangle",
              nullptr, nullptr, SW_SHOWNORMAL));
          if (result_code <= 32) {
            result->Error("CAPTURE_LAUNCH_FAILED", "Unable to start Windows screen clipping");
          } else {
            result->Success();
          }
        } else if (call.method_name() == "regionCaptureState") {
          HWND foreground = GetForegroundWindow();
          DWORD process_id = 0;
          GetWindowThreadProcessId(foreground, &process_id);
          HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
          wchar_t name[MAX_PATH] = {};
          DWORD length = MAX_PATH;
          bool active = false;
          if (process) {
            if (QueryFullProcessImageNameW(process, 0, name, &length)) {
              std::wstring path(name, length);
              std::transform(path.begin(), path.end(), path.begin(),
                             [](wchar_t c) { return std::towlower(c); });
              active = path.find(L"screenclippinghost.exe") != std::wstring::npos ||
                       path.find(L"snippingtool.exe") != std::wstring::npos;
            }
            CloseHandle(process);
          }
          flutter::EncodableMap state;
          state[flutter::EncodableValue("active")] = flutter::EncodableValue(active);
          state[flutter::EncodableValue("image")] = flutter::EncodableValue(IsClipboardFormatAvailable(CF_BITMAP) != FALSE);
          result->Success(flutter::EncodableValue(state));
        } else if (call.method_name() == "captureWindow") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (!args) {
            result->Error("INVALID_ARGS", "Expected map arguments");
            return;
          }
          auto it = args->find(flutter::EncodableValue("path"));
          if (it == args->end() || !std::holds_alternative<std::string>(it->second)) {
            result->Error("INVALID_ARGS", "Missing path argument");
            return;
          }
          std::string path_utf8 = std::get<std::string>(it->second);
          std::wstring path_wide = Utf8ToWide(path_utf8);

          HWND selected = SelectWindowInteractively(GetHandle());
          if (selected == nullptr) {
            result->Success(flutter::EncodableValue(false));
            return;
          }
          bool ok = CaptureSelectedWindowToPng(selected, path_wide);
          result->Success(flutter::EncodableValue(ok));
        } else {
          result->NotImplemented();
        }
      });

  clipboard_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "snap_craft/clipboard",
          &flutter::StandardMethodCodec::GetInstance());

  clipboard_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "currentFilePath") {
          auto path = GetClipboardFirstFilePath();
          if (path.has_value()) {
            result->Success(flutter::EncodableValue(*path));
          } else {
            result->Success();
          }
        } else if (call.method_name() == "copyImageAndFile") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (!args) {
            result->Error("INVALID_ARGS", "Missing map arguments");
            return;
          }
          auto bytes_it = args->find(flutter::EncodableValue("bytes"));
          auto path_it = args->find(flutter::EncodableValue("path"));
          if (bytes_it == args->end() ||
              path_it == args->end() ||
              !std::holds_alternative<std::vector<uint8_t>>(bytes_it->second) ||
              !std::holds_alternative<std::string>(path_it->second)) {
            result->Error("INVALID_ARGS", "Missing bytes or path");
            return;
          }
          const auto& png_bytes =
              std::get<std::vector<uint8_t>>(bytes_it->second);
          const auto& path_utf8 = std::get<std::string>(path_it->second);
          const bool ok = CopyPngAndFileToClipboard(
              GetHandle(), png_bytes, Utf8ToWide(path_utf8));
          result->Success(flutter::EncodableValue(ok));
        } else {
          result->NotImplemented();
        }
      });

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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
