/*
 * ocr_http.h - Minimal HTTP POST for Eiffel, built on WinHTTP.
 *
 * Why not simple_http / curl_http_client: that path resolves libcurl.dll at
 * runtime, and libcurl.dll ships only inside EiffelStudio's studio\spec\win64\bin,
 * which is not on PATH. A finalized binary therefore fails with a bare
 * "cURL issue" even though the request never left the process. Shipping it in an
 * installer would mean redistributing libcurl plus its transitive dependencies.
 *
 * WinHTTP is part of every supported Windows, needs no redistributable, and is
 * linked here via #pragma comment so the ECF needs no external_library entry.
 *
 * Following Eric Bezault's recommended pattern: implementations in .h file,
 * called from Eiffel inline C with use directive.
 *
 * Copyright (c) 2026 Larry Rix - MIT License
 */

#ifndef OCR_HTTP_H
#define OCR_HTTP_H

#if defined(_WIN32) || defined(EIF_WINDOWS)

#include <windows.h>
#include <stdlib.h>
#include <string.h>

#pragma comment(lib, "winhttp.lib")

/*
 * <winhttp.h> is deliberately NOT included, and the entry points used here are
 * declared directly instead.
 *
 * The Eiffel C build hard-codes -D_WIN32_WINNT=0x0500 (Windows 2000) and
 * -DWIN32_LEAN_AND_MEAN on the cl command line. winhttp.h declares
 * WINHTTP_CONNECTION_INFO with SOCKADDR_STORAGE members, but <ws2def.h>
 * compiles that type out below _WIN32_WINNT 0x0501, so the header fails with:
 *
 *     winhttp.h(383): error C2061: syntax error: identifier 'SOCKADDR_STORAGE'
 *
 * Raising the version inside this file does not help, because the Winsock
 * headers have already been processed at 0x0500 earlier in the generated
 * translation unit, and include guards stop them being reconsidered. The fix
 * would otherwise have to be a project-wide compiler flag.
 *
 * Declaring the eight functions we call keeps the fix local, and makes the
 * build independent of which Windows SDK is installed on the machine doing
 * the building - worth having for an installer-distributed product. The
 * symbols still come from winhttp.lib, so the ABI is the real one.
 */
typedef LPVOID          HINTERNET;
typedef WORD            INTERNET_PORT;

#define WINHTTP_ACCESS_TYPE_NO_PROXY    1
#define WINHTTP_QUERY_STATUS_CODE       19
#define WINHTTP_QUERY_FLAG_NUMBER       0x20000000

/* Sentinels winhttp.h would normally supply; all of them are simply NULL. */
#define WINHTTP_NO_PROXY_NAME           NULL
#define WINHTTP_NO_PROXY_BYPASS         NULL
#define WINHTTP_NO_REFERER              NULL
#define WINHTTP_DEFAULT_ACCEPT_TYPES    NULL
#define WINHTTP_HEADER_NAME_BY_INDEX    NULL
#define WINHTTP_NO_HEADER_INDEX         NULL

HINTERNET WINAPI WinHttpOpen (LPCWSTR, DWORD, LPCWSTR, LPCWSTR, DWORD);
HINTERNET WINAPI WinHttpConnect (HINTERNET, LPCWSTR, INTERNET_PORT, DWORD);
HINTERNET WINAPI WinHttpOpenRequest (HINTERNET, LPCWSTR, LPCWSTR, LPCWSTR, LPCWSTR, LPCWSTR *, DWORD);
BOOL      WINAPI WinHttpSetTimeouts (HINTERNET, int, int, int, int);
BOOL      WINAPI WinHttpSendRequest (HINTERNET, LPCWSTR, DWORD, LPVOID, DWORD, DWORD, DWORD_PTR);
BOOL      WINAPI WinHttpReceiveResponse (HINTERNET, LPVOID);
BOOL      WINAPI WinHttpQueryHeaders (HINTERNET, DWORD, LPCWSTR, LPVOID, LPDWORD, LPDWORD);
BOOL      WINAPI WinHttpQueryDataAvailable (HINTERNET, LPDWORD);
BOOL      WINAPI WinHttpReadData (HINTERNET, LPVOID, DWORD, LPDWORD);
BOOL      WINAPI WinHttpCloseHandle (HINTERNET);

static int ohttp_last_status = 0;
static int ohttp_last_winerr = 0;

/* UTF-8 -> wide. Caller frees with free(). NULL on failure. */
static wchar_t *ohttp_widen (const char *s)
{
    int   n;
    wchar_t *w;

    if (s == NULL) return NULL;
    n = MultiByteToWideChar (CP_UTF8, 0, s, -1, NULL, 0);
    if (n <= 0) return NULL;
    w = (wchar_t *) malloc (sizeof (wchar_t) * (size_t) n);
    if (w == NULL) return NULL;
    if (MultiByteToWideChar (CP_UTF8, 0, s, -1, w, n) <= 0) {
        free (w);
        return NULL;
    }
    return w;
}

/*
 * POST a_body to http://a_host:a_port/a_path with Content-Type application/json.
 *
 * Returns a malloc'd, NUL-terminated buffer holding the response body, or NULL
 * on failure. *a_out_len receives the body length in bytes. The HTTP status and
 * the Win32 error code are available via ohttp_status() / ohttp_winerr().
 *
 * The response is read in a loop because WinHttpQueryDataAvailable reports only
 * what is buffered right now, not the whole body; a single read would silently
 * truncate a large OCR reply.
 */
static char *ohttp_request (const char *a_verb, const char *a_host, int a_port,
                            const char *a_path, const char *a_body, int a_body_len,
                            int a_timeout_ms, int *a_out_len)
{
    HINTERNET hSession = NULL, hConnect = NULL, hRequest = NULL;
    wchar_t  *wHost = NULL, *wPath = NULL, *wVerb = NULL;
    char     *buffer = NULL, *grown = NULL;
    DWORD     total = 0, avail = 0, read = 0, cap = 0;
    DWORD     status = 0, statusLen = sizeof (DWORD);
    BOOL      ok = FALSE;

    ohttp_last_status = 0;
    ohttp_last_winerr = 0;
    if (a_out_len != NULL) *a_out_len = 0;

    wHost = ohttp_widen (a_host);
    wPath = ohttp_widen (a_path);
    wVerb = ohttp_widen (a_verb);
    if (wHost == NULL || wPath == NULL || wVerb == NULL) goto cleanup;

    hSession = WinHttpOpen (L"simple_ocr_capture/1.0",
                            WINHTTP_ACCESS_TYPE_NO_PROXY,
                            WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (hSession == NULL) goto cleanup;

    /* resolve, connect, send, receive - all generous: a cold model load on the
       far end can take 45s+, and the caller passes the OCR timeout through. */
    WinHttpSetTimeouts (hSession, 10000, 10000, a_timeout_ms, a_timeout_ms);

    hConnect = WinHttpConnect (hSession, wHost, (INTERNET_PORT) a_port, 0);
    if (hConnect == NULL) goto cleanup;

    hRequest = WinHttpOpenRequest (hConnect, wVerb, wPath, NULL,
                                   WINHTTP_NO_REFERER,
                                   WINHTTP_DEFAULT_ACCEPT_TYPES, 0);
    if (hRequest == NULL) goto cleanup;

    ok = WinHttpSendRequest (hRequest,
                             L"Content-Type: application/json\r\n", (DWORD) -1L,
                             (LPVOID) a_body, (DWORD) a_body_len,
                             (DWORD) a_body_len, 0);
    if (!ok) goto cleanup;

    ok = WinHttpReceiveResponse (hRequest, NULL);
    if (!ok) goto cleanup;

    if (WinHttpQueryHeaders (hRequest,
                             WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                             WINHTTP_HEADER_NAME_BY_INDEX, &status, &statusLen,
                             WINHTTP_NO_HEADER_INDEX)) {
        ohttp_last_status = (int) status;
    }

    cap = 65536;
    buffer = (char *) malloc (cap);
    if (buffer == NULL) goto cleanup;

    for (;;) {
        avail = 0;
        if (!WinHttpQueryDataAvailable (hRequest, &avail)) goto cleanup;
        if (avail == 0) break;

        if (total + avail + 1 > cap) {
            while (total + avail + 1 > cap) cap *= 2;
            grown = (char *) realloc (buffer, cap);
            if (grown == NULL) goto cleanup;
            buffer = grown;
        }

        read = 0;
        if (!WinHttpReadData (hRequest, buffer + total, avail, &read)) goto cleanup;
        if (read == 0) break;
        total += read;
    }

    buffer[total] = '\0';
    if (a_out_len != NULL) *a_out_len = (int) total;

    if (hRequest) WinHttpCloseHandle (hRequest);
    if (hConnect) WinHttpCloseHandle (hConnect);
    if (hSession) WinHttpCloseHandle (hSession);
    free (wHost);
    free (wPath);
    free (wVerb);
    return buffer;

cleanup:
    ohttp_last_winerr = (int) GetLastError ();
    if (buffer)   free (buffer);
    if (hRequest) WinHttpCloseHandle (hRequest);
    if (hConnect) WinHttpCloseHandle (hConnect);
    if (hSession) WinHttpCloseHandle (hSession);
    if (wHost)    free (wHost);
    if (wPath)    free (wPath);
    if (wVerb)    free (wVerb);
    return NULL;
}

/* Convenience wrappers so callers do not repeat the verb literal. */
static char *ohttp_post_json (const char *a_host, int a_port, const char *a_path,
                              const char *a_body, int a_body_len,
                              int a_timeout_ms, int *a_out_len)
{
    return ohttp_request ("POST", a_host, a_port, a_path,
                          a_body, a_body_len, a_timeout_ms, a_out_len);
}

static char *ohttp_get (const char *a_host, int a_port, const char *a_path,
                        int a_timeout_ms, int *a_out_len)
{
    return ohttp_request ("GET", a_host, a_port, a_path,
                          NULL, 0, a_timeout_ms, a_out_len);
}

static int  ohttp_status (void) { return ohttp_last_status; }
static int  ohttp_winerr (void) { return ohttp_last_winerr; }
static void ohttp_free (char *p) { if (p) free (p); }

#else
/* ============ NON-WINDOWS STUBS ============ */
static char *ohttp_post_json (const char *a_host, int a_port, const char *a_path,
                              const char *a_body, int a_body_len,
                              int a_timeout_ms, int *a_out_len)
{
    (void) a_host; (void) a_port; (void) a_path;
    (void) a_body; (void) a_body_len; (void) a_timeout_ms;
    if (a_out_len) *a_out_len = 0;
    return NULL;
}
static char *ohttp_get (const char *a_host, int a_port, const char *a_path,
                        int a_timeout_ms, int *a_out_len)
{
    (void) a_host; (void) a_port; (void) a_path; (void) a_timeout_ms;
    if (a_out_len) *a_out_len = 0;
    return NULL;
}
static int  ohttp_status (void) { return 0; }
static int  ohttp_winerr (void) { return 0; }
static void ohttp_free (char *p) { (void) p; }
#endif

#endif /* OCR_HTTP_H */
