/*
 * ocr_hotkey.h - Win32 system-wide hotkey support for Eiffel
 *
 * Registers a global hotkey that fires even when another application has
 * focus, and CONSUMES the keystroke so it never reaches that application.
 *
 * Design note: the hotkey is registered against a real message-only window
 * (HWND_MESSAGE) with its own WndProc, NOT against RegisterHotKey(NULL,...).
 * Vision2 runs a GetMessage(NULL) loop on the same thread; a thread-queue
 * hotkey message would be retrieved by that loop and then silently dropped
 * by DispatchMessage (msg.hwnd == NULL dispatches nowhere). With a real
 * HWND, whichever loop retrieves the message routes it to soh_wndproc, so
 * the press is counted regardless of which pump wins the race.
 *
 * Following Eric Bezault's recommended pattern: implementations in .h file,
 * called from Eiffel inline C with use directive.
 *
 * Copyright (c) 2026 Larry Rix - MIT License
 */

#ifndef OCR_HOTKEY_H
#define OCR_HOTKEY_H

#if defined(_WIN32) || defined(EIF_WINDOWS)

#include <windows.h>
#include <string.h>

#define SOH_HOTKEY_ID   0xB001
#define SOH_CLASS_NAME  "SimpleOcrCaptureHotkeyWnd"

static volatile LONG soh_press_count = 0;
static HWND          soh_hwnd        = NULL;
static int           soh_registered  = 0;

static LRESULT CALLBACK soh_wndproc (HWND h, UINT m, WPARAM w, LPARAM l)
{
    if (m == WM_HOTKEY && (int) w == SOH_HOTKEY_ID) {
        InterlockedIncrement (&soh_press_count);
        return 0;
    }
    return DefWindowProcA (h, m, w, l);
}

/* Create the message-only window. Returns 1 on success, 0 on failure. */
static int soh_init (void)
{
    WNDCLASSA wc;
    HINSTANCE hinst;

    if (soh_hwnd != NULL) return 1;

    hinst = GetModuleHandleA (NULL);

    memset (&wc, 0, sizeof (wc));
    wc.lpfnWndProc   = soh_wndproc;
    wc.hInstance     = hinst;
    wc.lpszClassName = SOH_CLASS_NAME;

    /* Ignore failure: the class may already be registered from a prior call. */
    RegisterClassA (&wc);

    soh_hwnd = CreateWindowExA (0, SOH_CLASS_NAME, "", 0,
                                0, 0, 0, 0,
                                HWND_MESSAGE, NULL, hinst, NULL);

    return soh_hwnd != NULL ? 1 : 0;
}

/*
 * Register the hotkey. Modifiers are the Win32 MOD_* flags
 * (ALT=1, CONTROL=2, SHIFT=4, WIN=8); vk is a virtual key code.
 * Returns 1 on success, 0 on failure (combo already owned by another app).
 */
static int soh_register (unsigned int mods, unsigned int vk)
{
    if (!soh_init ()) return 0;

    if (soh_registered) {
        UnregisterHotKey (soh_hwnd, SOH_HOTKEY_ID);
        soh_registered = 0;
    }

    /* MOD_NOREPEAT (0x4000) stops auto-repeat from queueing a burst of
       captures when the key is held down. */
    if (RegisterHotKey (soh_hwnd, SOH_HOTKEY_ID, mods | 0x4000, vk)) {
        soh_registered = 1;
        return 1;
    }
    return 0;
}

static void soh_unregister (void)
{
    if (soh_hwnd != NULL && soh_registered) {
        UnregisterHotKey (soh_hwnd, SOH_HOTKEY_ID);
        soh_registered = 0;
    }
}

static int soh_is_registered (void)
{
    return soh_registered;
}

/*
 * Drain pending messages for our window, then atomically read and reset the
 * press count. Safe to call from a GUI timer tick. Returns the number of
 * presses since the last call.
 */
static int soh_take_presses (void)
{
    MSG msg;

    if (soh_hwnd != NULL) {
        while (PeekMessageA (&msg, soh_hwnd, 0, 0, PM_REMOVE)) {
            TranslateMessage (&msg);
            DispatchMessageA (&msg);
        }
    }
    return (int) InterlockedExchange ((LONG *) &soh_press_count, 0);
}

static void soh_cleanup (void)
{
    soh_unregister ();
    if (soh_hwnd != NULL) {
        DestroyWindow (soh_hwnd);
        soh_hwnd = NULL;
    }
}

#else
/* ============ NON-WINDOWS STUBS ============ */
static int  soh_register (unsigned int mods, unsigned int vk) { (void) mods; (void) vk; return 0; }
static void soh_unregister (void) {}
static int  soh_is_registered (void) { return 0; }
static int  soh_take_presses (void) { return 0; }
static void soh_cleanup (void) {}
#endif

#endif /* OCR_HOTKEY_H */
