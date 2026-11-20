// Rico helper: global hotkeys, foreground-app reporting, and taskbar hiding for Rico.
// Talks to the Godot app over stdout, one line per event.
//   HOTKEY chat | HOTKEY voice | HOTKEY toggle
//   FG <window title>
// Usage: rico_helper.exe <parent_pid>
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <dwmapi.h>

static DWORD g_parent_pid = 0;
static HANDLE g_parent = NULL;
static wchar_t g_last_title[512] = L"";
static HWND g_rico = NULL;

static void emit_utf8(const char *prefix, const wchar_t *w) {
    char buf[2048];
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, buf, sizeof(buf) - 1, NULL, NULL);
    if (n <= 0) buf[0] = 0;
    for (char *p = buf; *p; ++p) if (*p == '\n' || *p == '\r') *p = ' ';
    printf("%s%s\n", prefix, buf);
    fflush(stdout);
}

static BOOL CALLBACK hide_from_taskbar(HWND hwnd, LPARAM lp) {
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid != g_parent_pid || !IsWindowVisible(hwnd)) return TRUE;
    // Only the main (owner-less) window: settings windows stay on the taskbar.
    if (GetWindow(hwnd, GW_OWNER) != NULL) return TRUE;
    wchar_t title[256];
    GetWindowTextW(hwnd, title, 256);
    if (wcscmp(title, L"Rico") != 0) return TRUE;
    g_rico = hwnd;
    LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    if (!(ex & WS_EX_TOOLWINDOW)) {
        ShowWindow(hwnd, SW_HIDE);
        SetWindowLongPtrW(hwnd, GWL_EXSTYLE, (ex | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW);
        ShowWindow(hwnd, SW_SHOWNOACTIVATE);
        printf("TASKBAR hidden\n");
        fflush(stdout);
    }
    return TRUE;
}

static HWND g_last_fg = NULL;
static RECT g_last_rect = {0, 0, 0, 0};

// FGRECT <l> <t> <r> <b> <exe>   (or FGRECT none) for the window Rico should dodge
static void report_rect(HWND fg, DWORD pid) {
    char line[700];
    wchar_t cls[64] = L"";
    GetClassNameW(fg, cls, 64);
    if (IsIconic(fg) || !wcscmp(cls, L"Progman") || !wcscmp(cls, L"WorkerW") || !wcscmp(cls, L"Shell_TrayWnd")) {
        if (g_last_fg != NULL) { printf("FGRECT none\n"); fflush(stdout); }
        g_last_fg = NULL;
        return;
    }
    RECT r;
    if (FAILED(DwmGetWindowAttribute(fg, DWMWA_EXTENDED_FRAME_BOUNDS, &r, sizeof(r)))) GetWindowRect(fg, &r);
    if (fg == g_last_fg && !memcmp(&r, &g_last_rect, sizeof(r))) return;
    g_last_fg = fg;
    g_last_rect = r;
    wchar_t exe[MAX_PATH] = L"unknown";
    HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (h) {
        DWORD n = MAX_PATH;
        if (QueryFullProcessImageNameW(h, 0, exe, &n)) {
            wchar_t *slash = wcsrchr(exe, L'\\');
            if (slash) memmove(exe, slash + 1, (wcslen(slash + 1) + 1) * sizeof(wchar_t));
        }
        CloseHandle(h);
    }
    snprintf(line, sizeof(line), "FGRECT %ld %ld %ld %ld ", r.left, r.top, r.right, r.bottom);
    emit_utf8(line, exe);
}

static void report_foreground(void) {
    HWND fg = GetForegroundWindow();
    if (!fg) return;
    DWORD pid = 0;
    GetWindowThreadProcessId(fg, &pid);
    if (pid == g_parent_pid) return;
    report_rect(fg, pid);
    wchar_t title[512];
    if (GetWindowTextW(fg, title, 512) <= 0) return;
    if (wcscmp(title, g_last_title) == 0) return;
    wcscpy(g_last_title, title);
    emit_utf8("FG ", title);
}

int main(int argc, char **argv) {
    if (argc > 1) g_parent_pid = (DWORD)strtoul(argv[1], NULL, 10);
    if (g_parent_pid) g_parent = OpenProcess(SYNCHRONIZE, FALSE, g_parent_pid);
    // Match Godot's per-monitor DPI awareness so window rects are in real pixels.
    typedef BOOL (WINAPI *SetCtx)(HANDLE);
    SetCtx set_ctx = (SetCtx)GetProcAddress(GetModuleHandleW(L"user32.dll"), "SetProcessDpiAwarenessContext");
    if (set_ctx) set_ctx((HANDLE)-4); else SetProcessDPIAware();

    struct { int id; UINT mods; UINT vk; const char *name; } keys[] = {
        {1, MOD_CONTROL | MOD_SHIFT, VK_SPACE, "chat"},
        {2, MOD_CONTROL | MOD_ALT, VK_SPACE, "voice"},
        {3, MOD_CONTROL | MOD_ALT, 'R', "toggle"},
        {4, MOD_ALT, VK_SPACE, "search"},
    };
    for (int i = 0; i < 4; ++i) {
        if (!RegisterHotKey(NULL, keys[i].id, keys[i].mods | 0x4000 /*MOD_NOREPEAT*/, keys[i].vk)) {
            printf("HOTKEYFAIL %s\n", keys[i].name);
            fflush(stdout);
        }
    }
    printf("READY\n");
    fflush(stdout);

    SetTimer(NULL, 0, 400, NULL);
    int ticks = 0;
    MSG msg;
    while (GetMessageW(&msg, NULL, 0, 0) > 0) {
        if (msg.message == WM_HOTKEY) {
            for (int i = 0; i < 4; ++i) if ((int)msg.wParam == keys[i].id) {
                if (keys[i].id != 3) {
                    if (!g_rico) EnumWindows(hide_from_taskbar, 0);
                    AllowSetForegroundWindow(g_parent_pid);
                    if (g_rico) SetForegroundWindow(g_rico);
                }
                printf("HOTKEY %s\n", keys[i].name);
                fflush(stdout);
            }
        } else if (msg.message == WM_TIMER) {
            ++ticks;
            if (g_parent && WaitForSingleObject(g_parent, 0) == WAIT_OBJECT_0) break;
            if (ticks <= 25 || ticks % 12 == 0) EnumWindows(hide_from_taskbar, 0);
            report_foreground();
        }
        DispatchMessageW(&msg);
    }
    return 0;
}
