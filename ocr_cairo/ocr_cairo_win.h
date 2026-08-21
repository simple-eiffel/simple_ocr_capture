/* ocr_cairo_win.h - pure Win32 window scaffolding for the M3 cairo face.
   Same pattern proven by simple_cairo's spike_gui: RegisterClass +
   CreateWindowExW + a blocking message pump, input forwarded to Eiffel
   through a small event queue. Single-window by design.

   The system-wide hotkey needs nothing here: OCR_HOTKEY owns a
   message-only window and is POLLED (taken_presses) from the timer tick,
   exactly as the classic GUI polls it. */

#ifndef OCR_CAIRO_WIN_H
#define OCR_CAIRO_WIN_H

#include <windows.h>
#pragma comment(lib, "shell32.lib")

/* Event queue: [type, a, b, c] per slot.
   type 0 none | 2 lbutton_down(x,y) | 6 expose | 7 timer_tick */
#define OCW_QCAP 512
static HWND s_ocw_hwnd = 0;
static int  s_ocw_q[OCW_QCAP][4];
static int  s_ocw_qhead = 0, s_ocw_qtail = 0;

static void ocw_push(int t, int a, int b, int c) {
    int next = (s_ocw_qtail + 1) % OCW_QCAP;
    if (next == s_ocw_qhead) return;
    s_ocw_q[s_ocw_qtail][0] = t;
    s_ocw_q[s_ocw_qtail][1] = a;
    s_ocw_q[s_ocw_qtail][2] = b;
    s_ocw_q[s_ocw_qtail][3] = c;
    s_ocw_qtail = next;
}

static LRESULT CALLBACK ocw_wndproc(HWND h, UINT m, WPARAM w, LPARAM l) {
    switch (m) {
        case WM_LBUTTONDOWN:
            ocw_push(2, (int)(short)LOWORD(l), (int)(short)HIWORD(l), 0);
            return 0;
        case WM_TIMER:
            ocw_push(7, 0, 0, 0);
            return 0;
        case WM_PAINT: {
            PAINTSTRUCT ps;
            BeginPaint(h, &ps);
            EndPaint(h, &ps);
            ocw_push(6, 0, 0, 0);
            return 0;
        }
        case WM_ERASEBKGND:
            return 1;
        case WM_DESTROY:
            KillTimer(h, 1);
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProcW(h, m, w, l);
}

static void* ocw_create_window(const wchar_t* title, int cw, int ch) {
    WNDCLASSW wc;
    RECT r;
    HWND h;
    SetProcessDPIAware();
    ZeroMemory(&wc, sizeof(wc));
    wc.lpfnWndProc = ocw_wndproc;
    wc.hInstance = GetModuleHandleW(0);
    wc.hCursor = LoadCursorW(0, (LPCWSTR)IDC_ARROW);
    wc.lpszClassName = L"OcrCairoWindow";
    RegisterClassW(&wc);
    r.left = 0; r.top = 0; r.right = cw; r.bottom = ch;
    AdjustWindowRect(&r, WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX, FALSE);
    h = CreateWindowExW(0, L"OcrCairoWindow", title,
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
        CW_USEDEFAULT, CW_USEDEFAULT,
        r.right - r.left, r.bottom - r.top, 0, 0, GetModuleHandleW(0), 0);
    s_ocw_hwnd = h;
    if (h) {
        ShowWindow(h, SW_SHOW);
        UpdateWindow(h);
        SetTimer(h, 1, 500, 0); /* the product's own poll cadence family */
    }
    return (void*)h;
}

static int ocw_pump(void) {
    MSG m;
    BOOL r = GetMessageW(&m, 0, 0, 0);
    if (r <= 0) return 0;
    TranslateMessage(&m);
    DispatchMessageW(&m);
    return 1;
}

static int ocw_next_event(int* out4) {
    if (s_ocw_qhead == s_ocw_qtail) return 0;
    out4[0] = s_ocw_q[s_ocw_qhead][0];
    out4[1] = s_ocw_q[s_ocw_qhead][1];
    out4[2] = s_ocw_q[s_ocw_qhead][2];
    out4[3] = s_ocw_q[s_ocw_qhead][3];
    s_ocw_qhead = (s_ocw_qhead + 1) % OCW_QCAP;
    return out4[0];
}

static void* ocw_get_dc(void)         { return s_ocw_hwnd ? (void*)GetDC(s_ocw_hwnd) : 0; }
static void  ocw_release_dc(void* dc) { if (s_ocw_hwnd && dc) ReleaseDC(s_ocw_hwnd, (HDC)dc); }

static double ocw_now_ms(void) {
    LARGE_INTEGER f, c;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&c);
    return (double)c.QuadPart * 1000.0 / (double)f.QuadPart;
}

/* Open a file with its associated application (the product's text file). */
static int ocw_shell_open(const wchar_t* path) {
    return (int)(INT_PTR)ShellExecuteW(0, L"open", path, 0, 0, SW_SHOWNORMAL) > 32 ? 1 : 0;
}

#endif /* OCR_CAIRO_WIN_H */
