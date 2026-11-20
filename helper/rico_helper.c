// Rico helper: global hotkeys, foreground-app reporting, and taskbar hiding for Rico.
// Talks to the Godot app over stdout, one line per event.
//   HOTKEY chat | HOTKEY voice | HOTKEY toggle
//   FG <window title>
// Usage: rico_helper.exe <parent_pid>
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>

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

static void report_foreground(void) {
    HWND fg = GetForegroundWindow();
    if (!fg) return;
    DWORD pid = 0;
    GetWindowThreadProcessId(fg, &pid);
    if (pid == g_parent_pid) return;
    wchar_t title[512];
    if (GetWindowTextW(fg, title, 512) <= 0) return;
    if (wcscmp(title, g_last_title) == 0) return;
    wcscpy(g_last_title, title);
    emit_utf8("FG ", title);
}

int main(int argc, char **argv) {
    if (argc > 1) g_parent_pid = (DWORD)strtoul(argv[1], NULL, 10);
    if (g_parent_pid) g_parent = OpenProcess(SYNCHRONIZE, FALSE, g_parent_pid);

    struct { int id; UINT mods; UINT vk; const char *name; } keys[] = {
        {1, MOD_CONTROL | MOD_SHIFT, VK_SPACE, "chat"},
        {2, MOD_CONTROL | MOD_ALT, VK_SPACE, "voice"},
        {3, MOD_CONTROL | MOD_ALT, 'R', "toggle"},
    };
    for (int i = 0; i < 3; ++i) {
        if (!RegisterHotKey(NULL, keys[i].id, keys[i].mods | 0x4000 /*MOD_NOREPEAT*/, keys[i].vk)) {
            printf("HOTKEYFAIL %s\n", keys[i].name);
        }
    }
    printf("READY\n");
    fflush(stdout);

    SetTimer(NULL, 0, 1000, NULL);
    int ticks = 0;
    MSG msg;
    while (GetMessageW(&msg, NULL, 0, 0) > 0) {
        if (msg.message == WM_HOTKEY) {
            for (int i = 0; i < 3; ++i) if ((int)msg.wParam == keys[i].id) {
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
            if (ticks <= 10 || ticks % 5 == 0) EnumWindows(hide_from_taskbar, 0);
            report_foreground();
        }
        DispatchMessageW(&msg);
    }
    return 0;
}
