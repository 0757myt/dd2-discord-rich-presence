// DiscordPresence.dll - REFramework plugin for Dragon's Dogma 2.
//
// Talks to the Discord client over its local IPC pipe (\\.\pipe\discord-ipc-N).
// What to show is decided by reframework/autorun/DiscordPresence.lua, which writes
// reframework/data/DiscordPresence/presence.json:
//     { "activity": { ...Discord activity... }, "client_id": "...", "updated": <unix time> }
// This plugin only forwards that activity (adding the "elapsed" timer from the game's start time).
// Discord removes the status by itself when the game process exits and the pipe closes.
//
// Plain C with only Windows and C runtime calls: no C++ runtime, a single export, and the worker
// thread starts when REFramework initializes the plugin, not while the DLL is being loaded.

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define POLL_MS 1000
#define MIN_UPDATE_MS 5000   // Discord allows ~5 activity updates per 20 s
#define RECONNECT_MS 10000
#define STALE_SEC 30         // presence.json older than this = Lua side not running

static HMODULE g_module;
static wchar_t g_presencePath[MAX_PATH];
static FILE* g_log;
static volatile LONG g_started;

static void log_line(const char* fmt, ...) {
    if (!g_log) return;
    SYSTEMTIME t;
    GetLocalTime(&t);
    fprintf(g_log, "%02d:%02d:%02d  ", t.wHour, t.wMinute, t.wSecond);
    va_list args;
    va_start(args, fmt);
    vfprintf(g_log, fmt, args);
    va_end(args);
    fputc('\n', g_log);
    fflush(g_log);
}

// ---------------------------------------------------------------- growable string

typedef struct { char* p; size_t n, cap; } Buf;

static bool buf_reserve(Buf* b, size_t extra) {
    if (b->n + extra + 1 <= b->cap) return true;
    size_t cap = b->cap ? b->cap : 256;
    while (cap < b->n + extra + 1) cap *= 2;
    char* p = (char*)realloc(b->p, cap);
    if (!p) return false;
    b->p = p;
    b->cap = cap;
    return true;
}

static void buf_add(Buf* b, const char* s, size_t len) {
    if (!buf_reserve(b, len)) return;
    memcpy(b->p + b->n, s, len);
    b->n += len;
    b->p[b->n] = '\0';
}

static void buf_str(Buf* b, const char* s) { buf_add(b, s, strlen(s)); }

static void buf_fmt(Buf* b, const char* fmt, ...) {
    char tmp[64];
    va_list args;
    va_start(args, fmt);
    int k = vsnprintf(tmp, sizeof(tmp), fmt, args);
    va_end(args);
    if (k > 0) buf_add(b, tmp, (size_t)k);
}

static void buf_set(Buf* b, const char* s, size_t len) { b->n = 0; buf_add(b, s, len); if (!len && b->p) b->p[0] = '\0'; }
static bool buf_eq(const Buf* b, const char* s, size_t len) { return b->n == len && (len == 0 || memcmp(b->p, s, len) == 0); }

// ---------------------------------------------------------------- tiny JSON helpers
// Enough for the flat file written by the Lua script: finds a top-level key and returns
// its raw value text (a quoted string, object, array or bare number).

static size_t skip_ws(const char* s, size_t n, size_t i) {
    while (i < n && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r' || s[i] == '\n')) ++i;
    return i;
}

// i points at '"'; returns index just past the closing quote
static size_t skip_string(const char* s, size_t n, size_t i) {
    for (++i; i < n; ++i) {
        if (s[i] == '\\') ++i;
        else if (s[i] == '"') return i + 1;
    }
    return n;
}

static size_t skip_value(const char* s, size_t n, size_t i) {
    if (i >= n) return i;
    if (s[i] == '"') return skip_string(s, n, i);
    if (s[i] == '{' || s[i] == '[') {
        int depth = 0;
        while (i < n) {
            char c = s[i];
            if (c == '"') { i = skip_string(s, n, i); continue; }
            if (c == '{' || c == '[') ++depth;
            else if ((c == '}' || c == ']') && --depth == 0) return i + 1;
            ++i;
        }
        return i;
    }
    while (i < n && s[i] != ',' && s[i] != '}' && s[i] != ']' && s[i] != ' ' && s[i] != '\r' && s[i] != '\n') ++i;
    return i;
}

static bool top_level_value(const char* s, size_t n, const char* key, size_t* start, size_t* end) {
    size_t keyLen = strlen(key);
    size_t i = skip_ws(s, n, 0);
    if (i >= n || s[i] != '{') return false;
    ++i;
    for (;;) {
        i = skip_ws(s, n, i);
        if (i >= n || s[i] != '"') return false;
        size_t keyEnd = skip_string(s, n, i);
        bool match = keyEnd - i - 2 == keyLen && memcmp(s + i + 1, key, keyLen) == 0;
        i = skip_ws(s, n, keyEnd);
        if (i >= n || s[i] != ':') return false;
        i = skip_ws(s, n, i + 1);
        size_t valEnd = skip_value(s, n, i);
        if (match) { *start = i; *end = valEnd; return true; }
        i = skip_ws(s, n, valEnd);
        if (i >= n || s[i] != ',') return false;
        ++i;
    }
}

static bool read_file(const wchar_t* path, Buf* out) {
    HANDLE h = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                           NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return false;
    buf_set(out, "", 0);
    char chunk[4096];
    DWORD got = 0;
    while (ReadFile(h, chunk, sizeof(chunk), &got, NULL) && got > 0) buf_add(out, chunk, got);
    CloseHandle(h);
    return out->n > 0;
}

// ---------------------------------------------------------------- Discord IPC

enum { OP_HANDSHAKE = 0, OP_FRAME = 1, OP_CLOSE = 2 };

typedef struct { HANDLE pipe; char clientId[32]; unsigned nonce; } Ipc;

static bool ipc_connected(const Ipc* c) { return c->pipe != INVALID_HANDLE_VALUE; }

static void ipc_close(Ipc* c) {
    if (ipc_connected(c)) CloseHandle(c->pipe);
    c->pipe = INVALID_HANDLE_VALUE;
    c->clientId[0] = '\0';
}

static bool ipc_send(Ipc* c, uint32_t op, const Buf* json) {
    Buf frame = { 0 };
    uint32_t header[2] = { op, (uint32_t)json->n };
    buf_add(&frame, (const char*)header, sizeof(header));
    buf_add(&frame, json->p, json->n);
    DWORD written = 0;
    bool ok = frame.n == sizeof(header) + json->n &&
              WriteFile(c->pipe, frame.p, (DWORD)frame.n, &written, NULL) && written == frame.n;
    free(frame.p);
    if (!ok) ipc_close(c);
    return ok;
}

static bool ipc_read_exact(Ipc* c, void* dst, DWORD size) {
    DWORD total = 0;
    while (total < size) {
        DWORD got = 0;
        if (!ReadFile(c->pipe, (char*)dst + total, size - total, &got, NULL) || got == 0) {
            ipc_close(c);
            return false;
        }
        total += got;
    }
    return true;
}

// Polls with PeekNamedPipe so a silent Discord never blocks the thread forever.
static bool ipc_wait_frame(Ipc* c, uint32_t* op, Buf* data, DWORD timeoutMs) {
    DWORD start = GetTickCount();
    while (ipc_connected(c)) {
        DWORD avail = 0;
        if (!PeekNamedPipe(c->pipe, NULL, 0, NULL, &avail, NULL)) { ipc_close(c); return false; }
        if (avail >= 8) {
            uint32_t header[2];
            if (!ipc_read_exact(c, header, 8)) return false;
            *op = header[0];
            buf_set(data, "", 0);
            if (header[1] == 0) return true;
            if (header[1] > (1u << 20) || !buf_reserve(data, header[1])) { ipc_close(c); return false; }
            if (!ipc_read_exact(c, data->p, header[1])) return false;
            data->n = header[1];
            data->p[data->n] = '\0';
            return true;
        }
        if (GetTickCount() - start > timeoutMs) return false;
        Sleep(20);
    }
    return false;
}

static bool ipc_connect(Ipc* c, const char* clientId) {
    ipc_close(c);
    for (int n = 0; n < 10 && !ipc_connected(c); ++n) {
        wchar_t name[64];
        swprintf(name, 64, L"\\\\.\\pipe\\discord-ipc-%d", n);
        c->pipe = CreateFileW(name, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
    }
    if (!ipc_connected(c)) return false;

    Buf msg = { 0 }, reply = { 0 };
    buf_str(&msg, "{\"v\":1,\"client_id\":\"");
    buf_str(&msg, clientId);
    buf_str(&msg, "\"}");
    uint32_t op = 0;
    bool ok = ipc_send(c, OP_HANDSHAKE, &msg) && ipc_wait_frame(c, &op, &reply, 5000) &&
              op == OP_FRAME && reply.p && strstr(reply.p, "\"READY\"");
    if (!ok) {
        log_line("Discord rejected the handshake (wrong client_id?): %s", reply.p ? reply.p : "");
        ipc_close(c);
    } else {
        strncpy(c->clientId, clientId, sizeof(c->clientId) - 1);
        c->clientId[sizeof(c->clientId) - 1] = '\0';
    }
    free(msg.p);
    free(reply.p);
    return ok;
}

// activity == NULL clears the status
static bool ipc_set_activity(Ipc* c, const Buf* activity) {
    Buf msg = { 0 }, reply = { 0 };
    buf_fmt(&msg, "{\"cmd\":\"SET_ACTIVITY\",\"args\":{\"pid\":%lu", (unsigned long)GetCurrentProcessId());
    if (activity) { buf_str(&msg, ",\"activity\":"); buf_add(&msg, activity->p, activity->n); }
    buf_fmt(&msg, "},\"nonce\":\"%u\"}", ++c->nonce);
    uint32_t op = 0;
    if (ipc_send(c, OP_FRAME, &msg) && ipc_wait_frame(c, &op, &reply, 3000)) {
        if (op == OP_CLOSE) { log_line("Discord closed the connection: %s", reply.p ? reply.p : ""); ipc_close(c); }
        else if (reply.p && strstr(reply.p, "\"evt\":\"ERROR\"")) log_line("Discord error: %s", reply.p);
        else log_line(activity ? "Status updated" : "Status cleared");
    }
    free(msg.p);
    free(reply.p);
    return ipc_connected(c);
}

// ---------------------------------------------------------------- worker

static long long process_start_unix(void) {
    FILETIME created, exited, kernel, user;
    if (!GetProcessTimes(GetCurrentProcess(), &created, &exited, &kernel, &user)) return (long long)time(NULL);
    ULARGE_INTEGER t;
    t.LowPart = created.dwLowDateTime;
    t.HighPart = created.dwHighDateTime;
    return (long long)((t.QuadPart - 116444736000000000ULL) / 10000000ULL);
}

// Activity with "timestamps":{"start":...} inserted as its first field.
static void with_timestamps(Buf* out, const char* activity, size_t n, long long start) {
    buf_set(out, "", 0);
    const char* brace = memchr(activity, '{', n);
    if (!brace) { buf_add(out, activity, n); return; }
    size_t after = (size_t)(brace - activity) + 1;
    buf_add(out, activity, after);
    buf_fmt(out, "\"timestamps\":{\"start\":%lld}", start);
    size_t next = skip_ws(activity, n, after);
    if (!(next < n && activity[next] == '}')) buf_str(out, ",");
    buf_add(out, activity + after, n - after);
}

static DWORD WINAPI worker(LPVOID unused) {
    (void)unused;
    Ipc ipc = { INVALID_HANDLE_VALUE, "", 0 };
    const long long gameStart = process_start_unix();
    Buf file = { 0 }, lastSent = { 0 }, payload = { 0 };
    bool haveSent = false, loggedWaiting = false;
    DWORD lastSendTick = 0, nextConnectTick = 0;

    log_line("Plugin loaded, watching %ls", g_presencePath);

    for (;;) {
        Sleep(POLL_MS);

        char clientId[32] = "";
        const char* activity = NULL;
        size_t activityLen = 0;
        bool fresh = false;
        size_t a, b;
        if (read_file(g_presencePath, &file) &&
            top_level_value(file.p, file.n, "client_id", &a, &b) && b - a >= 2 && b - a - 2 < sizeof(clientId)) {
            memcpy(clientId, file.p + a + 1, b - a - 2);
            clientId[b - a - 2] = '\0';
            if (top_level_value(file.p, file.n, "updated", &a, &b)) {
                long long age = (long long)time(NULL) - atoll(file.p + a);
                fresh = age >= -5 && age <= STALE_SEC;
            }
            if (top_level_value(file.p, file.n, "activity", &a, &b) && b > a && file.p[a] == '{') {
                activity = file.p + a;
                activityLen = b - a;
            }
        }

        if (!fresh || !clientId[0]) {
            if (!loggedWaiting) { log_line("Waiting for DiscordPresence.lua data..."); loggedWaiting = true; }
            if (ipc_connected(&ipc) && haveSent && lastSent.n > 0) {
                ipc_set_activity(&ipc, NULL);
                buf_set(&lastSent, "", 0);
            }
            continue;
        }
        loggedWaiting = false;

        if (!ipc_connected(&ipc) || strcmp(ipc.clientId, clientId) != 0) {
            if ((LONG)(GetTickCount() - nextConnectTick) < 0) continue;
            if (!ipc_connect(&ipc, clientId)) {
                nextConnectTick = GetTickCount() + RECONNECT_MS;
                continue;
            }
            log_line("Connected to Discord (client_id %s)", clientId);
            haveSent = false;
        }

        if (haveSent && buf_eq(&lastSent, activity, activityLen)) continue;
        if (haveSent && GetTickCount() - lastSendTick < MIN_UPDATE_MS) continue;

        bool ok;
        if (activity) {
            with_timestamps(&payload, activity, activityLen, gameStart);
            ok = ipc_set_activity(&ipc, &payload);
        } else {
            ok = ipc_set_activity(&ipc, NULL);
        }
        if (ok) {
            buf_set(&lastSent, activity ? activity : "", activityLen);
            haveSent = true;
            lastSendTick = GetTickCount();
        } else {
            log_line("Lost connection to Discord, will retry");
            nextConnectTick = GetTickCount() + RECONNECT_MS;
        }
    }
}

static void init_paths(void) {
    wchar_t dir[MAX_PATH];
    if (!GetModuleFileNameW(g_module, dir, MAX_PATH)) return;
    for (int up = 0; up < 2; ++up) {                     // ...\reframework\plugins\x.dll -> ...\reframework
        wchar_t* slash = wcsrchr(dir, L'\\');
        if (slash) *slash = L'\0';
    }
    wchar_t dataDir[MAX_PATH];
    swprintf(dataDir, MAX_PATH, L"%ls\\data", dir);
    CreateDirectoryW(dataDir, NULL);
    swprintf(dataDir, MAX_PATH, L"%ls\\data\\DiscordPresence", dir);
    CreateDirectoryW(dataDir, NULL);
    swprintf(g_presencePath, MAX_PATH, L"%ls\\presence.json", dataDir);
    wchar_t logPath[MAX_PATH];
    swprintf(logPath, MAX_PATH, L"%ls\\plugin.log", dataDir);
    g_log = _wfopen(logPath, L"w");
}

// Called by REFramework once its plugin loader is ready.
__declspec(dllexport) bool reframework_plugin_initialize(const void* param) {
    (void)param;
    if (InterlockedCompareExchange(&g_started, 1, 0) != 0) return true;
    // The worker lives for the whole process, so the DLL must never be unloaded.
    HMODULE pinned = NULL;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                       (LPCWSTR)(void*)&reframework_plugin_initialize, &pinned);
    init_paths();
    HANDLE t = CreateThread(NULL, 0, worker, NULL, 0, NULL);
    if (t) CloseHandle(t);
    return true;
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved) {
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        g_module = inst;
        DisableThreadLibraryCalls(inst);
    }
    return TRUE;
}
