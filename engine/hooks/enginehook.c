// EaW engine hook for Statecraft, built as POWRPROF.dll (the game loads it from its own folder).
// Passes CallNtPowerInformation through to the Windows DLL and adds what the mod needs from the engine.
// No game file is modified. If StarWarsG.exe is not the expected build, nothing is patched.
#include <windows.h>
#include <math.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <wchar.h>
#include <ctype.h>
#include "MinHook.h"
#include <emmintrin.h>

typedef void lua_State;
typedef int (*lua_CFunction)(lua_State *);
typedef struct { const char *name; lua_CFunction func; } luaL_reg;

// Engine functions (StarWarsG.exe FoC 1.121.859328, x64), offsets from the module base.
#define RVA_LUAOPEN_TABLE   0x7d1110
#define RVA_PUSHNUMBER      0x7b9520
#define RVA_CHECKNUMBER     0x7ce220
#define RVA_OPENLIB         0x7ce7a0
#define RVA_GETTOP          0x7b8ef0
#define RVA_SETTOP          0x7b9ab0
#define RVA_PUSHSTRING      0x7b9540
#define RVA_PUSHCCLOSURE    0x7b9340
#define RVA_SETTABLE        0x7b9a60
#define LUA_GLOBALSINDEX    (-10001)

static const struct { DWORD rva; unsigned char bytes[8]; } SIGNATURES[] = {
    {RVA_LUAOPEN_TABLE, {0x48,0x83,0xec,0x28,0x45,0x33,0xc9,0x4c}},
    {RVA_PUSHNUMBER,    {0x48,0x8b,0x41,0x10,0xf2,0x0f,0x11,0x48}},
    {RVA_CHECKNUMBER,   {0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83}},
    {RVA_OPENLIB,       {0x48,0x89,0x5c,0x24,0x10,0x48,0x89,0x6c}},
    {RVA_GETTOP,        {0x48,0x8b,0x41,0x10,0x48,0x2b,0x41,0x18}},
    {RVA_SETTOP,        {0x85,0xd2,0x78,0x3f,0x4c,0x63,0xc2,0x48}},
    {RVA_PUSHSTRING,    {0x48,0x89,0x6c,0x24,0x18,0x56,0x48,0x83}},
    {RVA_PUSHCCLOSURE,  {0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x74}},
    {RVA_SETTABLE,      {0x40,0x53,0x48,0x83,0xec,0x20,0x48,0x8b}},
};

static void   (*lua_pushnumber)(lua_State *, double);
static double (*luaL_checknumber)(lua_State *, int);
static void   (*luaL_openlib)(lua_State *, const char *, const luaL_reg *, int);
static int    (*lua_gettop)(lua_State *);
static void   (*lua_settop)(lua_State *, int);
static void   (*lua_pushstring)(lua_State *, const char *);
static void   (*lua_pushcclosure)(lua_State *, lua_CFunction, int);
static void   (*lua_settable)(lua_State *, int);
static int    (*orig_luaopen_table)(lua_State *);

static char log_path[MAX_PATH];
static void log_line(const char *text) {
    if (!log_path[0]) return;
    FILE *f = fopen(log_path, "a");
    if (f) { fputs(text, f); fputs("\n", f); fclose(f); }
}

// --- Mod check: the gameplay changes apply only when the mod is loaded (MODPATH or a STEAMMOD folder holding
// its main script). Without it the game plays exactly as without the hook.
#define MOD_MARKER "\\Data\\Scripts\\Library\\eawx-plugins\\diplomacy\\Diplomacy.lua"
static int mod_loaded = -1;
static char mod_folder[MAX_PATH];                // the first mod folder in the launch options that holds it

static int marker_in(const char *folder) {
    char path[MAX_PATH * 2];
    snprintf(path, sizeof path, "%s%s", folder, MOD_MARKER);
    return GetFileAttributesA(path) != INVALID_FILE_ATTRIBUTES;
}

static int diplomacy_loaded(void) {
    if (mod_loaded >= 0) return mod_loaded;
    mod_loaded = 0;
    char game[MAX_PATH];                         // ...\Star Wars Empire at War\corruption
    DWORD n = GetModuleFileNameA(NULL, game, MAX_PATH);
    char *slash = n ? strrchr(game, '\\') : NULL;
    if (!slash) return 0;
    *slash = 0;
    const char *cmd = GetCommandLineA();
    for (const char *at = cmd; *at; at++) {
        int modpath = _strnicmp(at, "MODPATH=", 8) == 0, steammod = _strnicmp(at, "STEAMMOD=", 9) == 0;
        if (!modpath && !steammod) continue;
        if (at != cmd && at[-1] != ' ' && at[-1] != '\t' && at[-1] != '"') continue;
        at += modpath ? 8 : 9;
        int quoted = *at == '"';
        if (quoted) at++;
        char value[MAX_PATH] = "";
        int len = 0;
        while (*at && len < MAX_PATH - 1 && (quoted ? *at != '"' : (*at != ' ' && *at != '\t'))) value[len++] = *at++;
        value[len] = 0;
        if (!*at) at--;
        char folder[MAX_PATH * 2];
        if (modpath)
            snprintf(folder, sizeof folder, strchr(value, ':') ? "%s" : "%s\\%s", strchr(value, ':') ? value : game,
                     value);
        else                                     // steamapps\common\<game>\corruption -> steamapps\workshop\content\32470
            snprintf(folder, sizeof folder, "%s\\..\\..\\..\\workshop\\content\\32470\\%s", game, value);
        if (marker_in(folder)) {
            if (!mod_loaded && !GetFullPathNameA(folder, MAX_PATH, mod_folder, NULL)) mod_folder[0] = 0;
            mod_loaded = 1;
        }
    }
    log_line(mod_loaded ? "MOD: loaded (the hook's game changes are on)"
                        : "MOD: not loaded (the hook changes nothing in how the game plays)");
    return mod_loaded;
}

#include "rebuild.c"

// --- Crash report for access violations in the Lua core (0x7b0000-0x7d0000): closure, script, line, stack.
static unsigned char *crash_base;
static int crash_reports;
// Lua busy outside any script (a save, a load, a garbage collection). The frame tick never enters Lua then.
static volatile int lua_busy;
static DWORD lua_busy_since;                    // when it began (an error unwinding past a hook could leave it set:
static void busy_enter(void) { if (lua_busy++ == 0) lua_busy_since = GetTickCount(); }   // stale after 30 s)
static void busy_leave(void) { if (lua_busy > 0) lua_busy--; }
static int busy_now(void) {
    if (lua_busy > 0 && GetTickCount() - lua_busy_since > 30000) lua_busy = 0;
    return lua_busy > 0;
}

static int readable(const void *p, size_t n) {
    MEMORY_BASIC_INFORMATION m;
    if (!p || !VirtualQuery(p, &m, sizeof m) || m.State != MEM_COMMIT || (m.Protect & (PAGE_NOACCESS | PAGE_GUARD))) return 0;
    return (const unsigned char *)p + n <= (const unsigned char *)m.BaseAddress + m.RegionSize;
}
// --- Error messages from a broken call frame -----------------------------------------------------------------
// lua_getinfo (0x7ba6b0) can crash on a frame whose function slot is invalid. A fault in its option loop fills the
// option as for a C function and resumes at the next option (0x7ba955), so the script still gets its error.
#define RVA_GETINFO_LOOP    0x7ba710    // first instruction of the option loop
#define RVA_GETINFO_NEXT    0x7ba955    // mov ecx,[rsp+68h]: next option
#define RVA_GETINFO_EMPTY   0x7ff8a8    // "" (namewhat when there is no name)
#define RVA_GETINFO_CSRC    0x8fd060    // "=[C]"
#define RVA_GETINFO_CWHAT   0x879944    // "C"
static void test_log(const char *line);
static int getinfo_guard_ok, getinfo_recoveries;
static int getinfo_recover(CONTEXT *c, unsigned long long rva) {
    if (!getinfo_guard_ok || rva < RVA_GETINFO_LOOP || rva >= RVA_GETINFO_NEXT) return 0;
    unsigned char *ar = (unsigned char *)c->Rbp;            // lua_Debug
    const char *option = (const char *)c->R13;
    if (!readable(ar, 0x70) || !readable(option, 1)) return 0;
    switch (*option) {
    case 'n': *(void **)(ar + 0x08) = NULL; *(void **)(ar + 0x10) = crash_base + RVA_GETINFO_EMPTY; break;
    case 'l': *(int *)(ar + 0x28) = -1; break;
    case 'u': *(int *)(ar + 0x2c) = 0; break;
    case 'S':
        *(void **)(ar + 0x20) = crash_base + RVA_GETINFO_CSRC;
        *(void **)(ar + 0x18) = crash_base + RVA_GETINFO_CWHAT;
        *(int *)(ar + 0x30) = -1;
        memcpy(ar + 0x34, "[C]", 4);
        break;
    default: return 0;
    }
    if (getinfo_recoveries++ < 20) {
        char line[200];
        snprintf(line, sizeof line, "LUA GETINFO: broken call frame, option '%c' at +0x%llx skipped (the script gets "
                 "its error without a function name)", *option, rva);
        log_line(line);
        test_log(line);
    }
    c->Rip = (unsigned long long)crash_base + RVA_GETINFO_NEXT;
    return 1;
}

// The files the hook writes next to itself. The players' copy names them after the mod.
#ifdef RELEASE_BUILD
#define FILE_LOG          "Statecraft_Engine.log"
#define FILE_SCRIPT_LOG   "Statecraft_Scripts.log"
#define FILE_CRASH_LOG    "Statecraft_Crash_Engine.log"
#define FILE_CRASH_SCRIPT "Statecraft_Crash_Scripts.log"
#define FILE_CRASH_DUMP   "Statecraft_Crash.dmp"
#define FILE_SWITCH(name) "Statecraft_" name ".txt"
#else
#define FILE_LOG          "EngineHook.log"
#define FILE_SCRIPT_LOG   "EngineTest.log"
#define FILE_CRASH_LOG    "EngineCrash_Hook.log"
#define FILE_CRASH_SCRIPT "EngineCrash_Test.log"
#define FILE_CRASH_DUMP   "EngineCrash.dmp"
#define FILE_SWITCH(name) "EngineHook_" name ".txt"
#endif

// --- Crash records -----------------------------------------------------------------------------------------
// On the first fatal fault of a session both logs are copied and a minidump is written next to the DLL.
#define STATUS_HEAP_CORRUPTION_CODE 0xC0000374
static char test_log_path[MAX_PATH];
static FILE *test_log_file;
typedef BOOL (WINAPI *minidump_fn)(HANDLE, DWORD, HANDLE, int, void *, void *, void *);
#pragma pack(push, 4)        // MINIDUMP_EXCEPTION_INFORMATION is packed (the pointer at +4): unpacked, the dump failed
typedef struct { DWORD thread; EXCEPTION_POINTERS *pointers; BOOL client; } DumpException;
#pragma pack(pop)
static volatile LONG crash_saved;
static void sibling_path(char *out, const char *name) {
    strcpy(out, log_path);
    char *slash = strrchr(out, '\\');
    strcpy(slash ? slash + 1 : out, name);
}
static void save_crash(EXCEPTION_POINTERS *e) {
    if (!log_path[0] || InterlockedExchange(&crash_saved, 1)) return;
    char line[160], path[MAX_PATH];
    snprintf(line, sizeof line, "CRASH 0x%08lx at StarWarsG+0x%llx (address 0x%llx): logs and " FILE_CRASH_DUMP " saved",
             e->ExceptionRecord->ExceptionCode,
             (unsigned long long)e->ContextRecord->Rip - (unsigned long long)crash_base,
             e->ExceptionRecord->NumberParameters > 1 ? (unsigned long long)e->ExceptionRecord->ExceptionInformation[1] : 0ULL);
    log_line(line);
    test_log(line);
    if (test_log_file) fflush(test_log_file);
    sibling_path(path, FILE_CRASH_LOG);
    CopyFileA(log_path, path, FALSE);
    sibling_path(path, FILE_CRASH_SCRIPT);
    CopyFileA(test_log_path, path, FALSE);
    HMODULE dbghelp = LoadLibraryA("dbghelp.dll");
    minidump_fn write_dump = dbghelp ? (minidump_fn)GetProcAddress(dbghelp, "MiniDumpWriteDump") : NULL;
    if (!write_dump) return;
    sibling_path(path, FILE_CRASH_DUMP);
    HANDLE file = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return;
    DumpException info = {GetCurrentThreadId(), e, FALSE};
    // data segments | unloaded modules | indirectly referenced memory (the objects the stacks point at) | thread
    // info (the whole heap took too long: Windows ended the game before the dump was complete)
    if (!write_dump(GetCurrentProcess(), GetCurrentProcessId(), file, 0x1 | 0x20 | 0x40 | 0x1000, &info, NULL, NULL)) {
        snprintf(line, sizeof line, "CRASH dump failed (error %lu)", GetLastError());
        log_line(line);
    }
    CloseHandle(file);
}
static int in_game_code(unsigned long long rip) {
    if (!crash_base) return 0;
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(crash_base + ((IMAGE_DOS_HEADER *)crash_base)->e_lfanew);
    return rip >= (unsigned long long)crash_base && rip < (unsigned long long)crash_base + nt->OptionalHeader.SizeOfImage;
}

static LONG CALLBACK crash_report(EXCEPTION_POINTERS *e) {
    DWORD code = e->ExceptionRecord->ExceptionCode;
    if (code == STATUS_HEAP_CORRUPTION_CODE && crash_base) {
        save_crash(e);
        return EXCEPTION_CONTINUE_SEARCH;
    }
    if (code != EXCEPTION_ACCESS_VIOLATION || !crash_base)
        return EXCEPTION_CONTINUE_SEARCH;
    CONTEXT *c = e->ContextRecord;
    unsigned long long rva = c->Rip - (unsigned long long)crash_base;
    if (rva < 0x7b0000 || rva >= 0x7d0000) {
        if (in_game_code(c->Rip)) save_crash(e);
        return EXCEPTION_CONTINUE_SEARCH;
    }
    if (getinfo_recover(c, rva)) return EXCEPTION_CONTINUE_EXECUTION;
    save_crash(e);
    if (crash_reports >= 3) return EXCEPTION_CONTINUE_SEARCH;
    crash_reports++;
    char line[600];
    snprintf(line, sizeof line, "CRASH in Lua core at +0x%llx (address 0x%llx): rbx %llx r10 %llx r11 %llx rdx %llx",
             rva, (unsigned long long)e->ExceptionRecord->ExceptionInformation[1],
             c->Rbx, c->R10, c->R11, c->Rdx);
    log_line(line);
    unsigned char *cl = (unsigned char *)c->Rbx;
    if (rva >= 0x7bd850 && rva < 0x7bd9d0 && readable(cl, 0x30)) {
        int slot = readable((void *)c->R11, 8) ? (int)((c->R11 - (c->Rbx + 0x30)) / 8) : -1;
        unsigned char *proto = *(unsigned char **)(cl + 0x28);
        int line_defined = readable(proto, 0x68) ? *(int *)(proto + 0x60) : -1;
        unsigned char *source = readable(proto, 0x48) ? *(unsigned char **)(proto + 0x40) : NULL;
        char name[120] = "?";
        if (readable(source, 0x18 + 100)) {
            const char *t = (const char *)source + 0x18;
            int i = 0;
            while (i < 100 && t[i] >= 32 && t[i] < 127) { name[i] = t[i]; i++; }
            name[i] = 0;
        }
        snprintf(line, sizeof line, "CRASH closure: C %d, %d upvalues, bad upvalue %d, function at line %d of %s",
                 cl[10], cl[11], slot, line_defined, name);
        log_line(line);
        if (slot >= 0 && slot < cl[11]) {     // the other upvalues' values: type and pointer
            for (int i = 0; i < cl[11] && i < 12; i++) {
                unsigned char *uv = *(unsigned char **)(cl + 0x30 + 8 * i);
                if (readable(uv, 0x28))
                    snprintf(line, sizeof line, "  upvalue %d: type %d value %llx", i, *(int *)(uv + 0x18),
                             *(unsigned long long *)(uv + 0x20));
                else
                    snprintf(line, sizeof line, "  upvalue %d: unreadable %p", i, (void *)uv);
                log_line(line);
            }
        }
    }
    char *p = line;
    p += snprintf(p, 80, "CRASH stack:");
    unsigned long long *sp = (unsigned long long *)c->Rsp;
    for (int i = 0, n = 0; i < 4000 && n < 24 && readable(sp + i, 8); i++) {
        unsigned long long v = sp[i];
        if (v > (unsigned long long)crash_base + 0x1000 && v < (unsigned long long)crash_base + 0x800000) {
            p += snprintf(p, line + sizeof line - p, " %llx", v - (unsigned long long)crash_base);
            n++;
        }
    }
    log_line(line);
    return EXCEPTION_CONTINUE_SEARCH;
}

// --- Saved games keep the scripts' upvalues ------------------------------------------------------------
// The engine saves a Lua function without its upvalues (0x7c15c0), so loaded functions point at garbage. Before
// each save the upvalues go into a hidden global table; after each load they are restored and the table removed.
#define RVA_SAVE_STATE      0x7b8d20    // (L, writer, data, object callback, flag)
#define RVA_LOAD_STATE      0x7c5020    // (L, reader, data, name, object callback, flag)
#define RVA_NEWTABLE        0x7b9140
#define RVA_PUSHVALUE       0x7b9600
#define RVA_RAWGET          0x7b9720
#define RVA_RAWGETI         0x7b9770
#define RVA_RAWSET          0x7b97c0
#define RVA_NEXT            0x7b9220
#define RVA_REALLOC         0x7bf7e0    // luaM_realloc(L, block, old size, new size)
#define RVA_LINK            0x7bca30    // luaC_link(L, object, type)
#define UPVALUE_STASH       "__saved_upvalues"
// --- Room on a Lua stack ------------------------------------------------------------------------------------
// Values pushed from outside a Lua call need free stack slots: lua_checkstack (0x7b8bc0) grows the stack first.
#define RVA_CHECKSTACK      0x7b8bc0    // lua_checkstack(L, extra slots) -> 0 if it cannot grow
#define LUA_STACK_LAST(L)   (*(unsigned char **)((unsigned char *)(L) + 0x60))
static int (*lua_checkstack_fn)(lua_State *, int);
static int room_for(lua_State *L, int slots, const char *where) {
    if (!L) return 0;
    long long free_slots = (LUA_STACK_LAST(L) - *(unsigned char **)((unsigned char *)L + 0x10)) / 16;
    if (free_slots < slots) {
        static int reported;
        if (reported++ < 20) {
            char line[160];
            snprintf(line, sizeof line, "LUA STACK: only %lld free slots for %s (needs %d): grown first", free_slots,
                     where, slots);
            log_line(line);
            test_log(line);
        }
    }
    return lua_checkstack_fn ? lua_checkstack_fn(L, slots) : 1;
}
// Layouts: lua_State +0x10 top, +0x18 base, +0x20 global state, +0xa0 globals; global state +0x10 object list,
// +0x70 GC threshold, +0x74 in use; function +0x0a C flag, +0x0b upvalue count, +0x30 upvalues; upvalue +0x10
// value pointer, +0x18 closed value. A TObject is 16 bytes.
typedef struct { int type; int pad; void *value; } lua_value;
static int  (*orig_save_state)(lua_State *, void *, void *, void *, int);
static void (*orig_load_state)(lua_State *, void *, void *, void *, void *, int);
static void (*lua_newtable_fn)(lua_State *);
static void (*lua_pushvalue_fn)(lua_State *, int);
static void (*lua_rawget_fn)(lua_State *, int);
static void (*lua_rawgeti_fn)(lua_State *, int, int);
static void (*lua_rawset_fn)(lua_State *, int);
static int  (*lua_next_fn)(lua_State *, int);
static void *(*lua_realloc_fn)(lua_State *, void *, size_t, size_t);
static void (*lua_link_fn)(lua_State *, void *, int);

#define LUA_TOP(L)      (*(lua_value **)((unsigned char *)(L) + 0x10))
#define LUA_GLOBAL(L)   (*(unsigned char **)((unsigned char *)(L) + 0x20))
static void push_value(lua_State *L, const lua_value *v) { *LUA_TOP(L) = *v; LUA_TOP(L)++; }
static void push_globals(lua_State *L) { push_value(L, (lua_value *)((unsigned char *)L + 0xa0)); }
static void push_nil(lua_State *L) { lua_value v = {0, 0, NULL}; push_value(L, &v); }
static lua_value *value_at(lua_State *L, int index) {
    return (lua_value *)(*(unsigned char **)((unsigned char *)L + 0x18) + 16 * (index - 1));
}
static int int_at(lua_State *L, int index) {
    lua_value *v = value_at(L, index);
    double d;
    memcpy(&d, &v->value, sizeof d);
    return v->type == 3 ? (int)d : 0;
}

// pointer -> number (1, 2, ...): an open-addressing table that grows
typedef struct { void **keys; int *values; int size, count; } ptr_map;
static int map_get(ptr_map *m, void *key, int add) {
    if (add && (m->count + 1) * 2 > m->size) {
        int size = m->size ? m->size * 2 : 1024;
        ptr_map bigger = {calloc(size, sizeof(void *)), calloc(size, sizeof(int)), size, m->count};
        for (int i = 0; i < m->size; i++) {
            if (!m->keys[i]) continue;
            size_t h = ((size_t)m->keys[i] >> 4) & (size - 1);
            while (bigger.keys[h]) h = (h + 1) & (size - 1);
            bigger.keys[h] = m->keys[i];
            bigger.values[h] = m->values[i];
        }
        free(m->keys);
        free(m->values);
        *m = bigger;
    }
    if (!m->size) return 0;
    size_t h = ((size_t)key >> 4) & (m->size - 1);
    while (m->keys[h]) {
        if (m->keys[h] == key) return m->values[h];
        h = (h + 1) & (m->size - 1);
    }
    if (!add) return 0;
    m->keys[h] = key;
    m->values[h] = ++m->count;
    return m->count;
}
static void map_free(ptr_map *m) { free(m->keys); free(m->values); memset(m, 0, sizeof *m); }

static int is_lua_function(const unsigned char *o) { return o[8] == 6 && o[10] == 0 && o[11] > 0; }
static int proto_id(const unsigned char *function) { return *(int *)(*(unsigned char **)(function + 0x18) + 100); }
static unsigned char **upvalue_slot(unsigned char *function, int i) { return (unsigned char **)(function + 0x30 + 8 * i); }

// Loaded functions are matched by prototype number, or by the table field holding them when a prototype has
// closures with different upvalues.
// globals[UPVALUE_STASH] = {[1] = {box -> value}, [2] = {prototype -> {boxes}}, [3] = {table, key, {boxes}, ...}}
typedef struct { unsigned char *first; int ambiguous; } proto_info;
static void push_boxes(lua_State *L, unsigned char *function, ptr_map *boxes) {
    lua_newtable_fn(L);
    int t = lua_gettop(L);
    for (int i = 0; i < function[11]; i++) {
        lua_pushnumber(L, i + 1);
        lua_pushnumber(L, map_get(boxes, *upvalue_slot(function, i), 0));
        lua_rawset_fn(L, t);
    }
}

static void stash_upvalues(lua_State *L) {
    if (!room_for(L, 24, "the save")) return;
    unsigned char *g = LUA_GLOBAL(L);
    unsigned int threshold = *(unsigned int *)(g + 0x70);
    *(unsigned int *)(g + 0x70) = 0xffffffff;          // no collection while the object list is walked
    unsigned char *objects = *(unsigned char **)(g + 0x10);   // (new tables go in front: never walked)
    int top = lua_gettop(L);
    push_globals(L);                                    // top+1
    lua_pushstring(L, UPVALUE_STASH);                   // top+2
    lua_newtable_fn(L);                                 // top+3 the stash
    lua_newtable_fn(L);                                 // top+4 box values
    lua_newtable_fn(L);                                 // top+5 by prototype
    lua_newtable_fn(L);                                 // top+6 by table field
    ptr_map boxes = {0}, protos = {0};
    int proto_count = 0, proto_size = 0, records = 0;
    proto_info *info = NULL;
    for (unsigned char *o = objects; o; o = *(unsigned char **)o) {
        if (!is_lua_function(o)) continue;
        for (int i = 0; i < o[11]; i++) {
            unsigned char *up = *upvalue_slot(o, i);
            if (!up || map_get(&boxes, up, 0)) continue;
            lua_pushnumber(L, map_get(&boxes, up, 1));
            push_value(L, *(lua_value **)(up + 0x10));
            lua_rawset_fn(L, top + 4);
        }
        unsigned char *proto = *(unsigned char **)(o + 0x18);
        int n = map_get(&protos, proto, 0);
        if (!n) {
            n = map_get(&protos, proto, 1);
            if (n > proto_size) {
                proto_size = proto_size ? proto_size * 2 : 1024;
                info = realloc(info, proto_size * sizeof *info);
            }
            info[n - 1].first = o;
            info[n - 1].ambiguous = 0;
            proto_count = n;
        } else if (!info[n - 1].ambiguous) {
            for (int i = 0; i < o[11]; i++)
                if (*upvalue_slot(o, i) != *upvalue_slot(info[n - 1].first, i)) info[n - 1].ambiguous = 1;
        }
    }
    int ambiguous = 0;
    for (int n = 0; n < proto_count; n++) {
        if (info[n].ambiguous) { ambiguous++; continue; }
        lua_pushnumber(L, proto_id(info[n].first));
        push_boxes(L, info[n].first, &boxes);
        lua_rawset_fn(L, top + 5);
    }
    if (ambiguous) {                // the table fields holding functions of those prototypes
        for (unsigned char *o = objects; ; o = *(unsigned char **)o) {
            lua_value t = {5, 0, o};
            if (o && o[8] != 5) continue;
            if (o) push_value(L, &t);
            else lua_pushvalue_fn(L, top + 4);           // last: the box values themselves
            int ti = lua_gettop(L);
            push_nil(L);
            while (lua_next_fn(L, ti)) {                 // key at ti+1, value at ti+2
                lua_value *v = value_at(L, ti + 2);
                unsigned char *f = v->type == 6 ? v->value : NULL;
                if (f && is_lua_function(f) && info[map_get(&protos, *(unsigned char **)(f + 0x18), 0) - 1].ambiguous) {
                    lua_pushnumber(L, ++records);
                    lua_pushvalue_fn(L, ti);
                    lua_rawset_fn(L, top + 6);
                    lua_pushnumber(L, ++records);
                    lua_pushvalue_fn(L, ti + 1);
                    lua_rawset_fn(L, top + 6);
                    lua_pushnumber(L, ++records);
                    push_boxes(L, f, &boxes);
                    lua_rawset_fn(L, top + 6);
                }
                lua_settop(L, ti + 1);
            }
            lua_settop(L, ti - 1);
            if (!o) break;
        }
    }
    for (int k = 1; k <= 3; k++) {
        lua_pushnumber(L, k);
        lua_pushvalue_fn(L, top + 3 + k);
        lua_rawset_fn(L, top + 3);
    }
    lua_settop(L, top + 3);
    lua_rawset_fn(L, top + 1);                          // globals[UPVALUE_STASH] = the stash
    lua_settop(L, top);
    free(info);
    map_free(&protos);
    map_free(&boxes);
    *(unsigned int *)(g + 0x70) = threshold;
}

static void drop_stash(lua_State *L) {
    if (!room_for(L, 8, "the save")) return;
    int top = lua_gettop(L);
    push_globals(L);
    lua_pushstring(L, UPVALUE_STASH);
    push_nil(L);
    lua_rawset_fn(L, top + 1);
    lua_settop(L, top);
}

static unsigned char *new_upvalue(lua_State *L, const lua_value *v) {
    unsigned char *up = lua_realloc_fn(L, NULL, 0, 0x28);
    *(lua_value *)(up + 0x18) = *v;
    *(void **)(up + 0x10) = up + 0x18;
    lua_link_fn(L, up, 10);
    return up;
}

// gives `function` the upvalues listed (box numbers) in the table at `list`; box values at `values`
typedef struct { unsigned char **made; int size; } upvalue_cache;
static void give_upvalues(lua_State *L, unsigned char *function, int list, int values, upvalue_cache *c) {
    int top = lua_gettop(L);
    for (int i = 0; i < function[11]; i++) {
        lua_rawgeti_fn(L, list, i + 1);
        int box = int_at(L, top + 1);
        lua_settop(L, top);
        if (box <= 0) continue;
        if (box >= c->size) {
            int size = box * 2;
            unsigned char **more = realloc(c->made, size * sizeof *more);
            if (!more) continue;
            memset(more + c->size, 0, (size - c->size) * sizeof *more);
            c->made = more;
            c->size = size;
        }
        if (!c->made[box]) {
            lua_rawgeti_fn(L, values, box);
            c->made[box] = new_upvalue(L, value_at(L, top + 1));
            lua_settop(L, top);
        }
        *upvalue_slot(function, i) = c->made[box];
    }
}

static void restore_upvalues(lua_State *L) {
    if (!room_for(L, 24, "the load")) return;
    unsigned char *g = LUA_GLOBAL(L);
    int top = lua_gettop(L);
    push_globals(L);                                    // top+1
    lua_pushstring(L, UPVALUE_STASH);
    lua_rawget_fn(L, top + 1);                          // top+2 the stash
    ptr_map done = {0};
    upvalue_cache cache = {NULL, 0};
    int restored = 0, emptied = 0, stashed = value_at(L, top + 2)->type == 5;
    if (stashed) {
        lua_rawgeti_fn(L, top + 2, 1);                  // top+3 box values
        lua_rawgeti_fn(L, top + 2, 2);                  // top+4 by prototype
        lua_rawgeti_fn(L, top + 2, 3);                  // top+5 by table field
        for (int k = 1; ; k += 3) {
            lua_rawgeti_fn(L, top + 5, k);              // top+6 table
            if (value_at(L, top + 6)->type != 5) break;
            lua_rawgeti_fn(L, top + 5, k + 1);          // top+7 key
            lua_rawget_fn(L, top + 6);                  // top+7 the function now
            lua_rawgeti_fn(L, top + 5, k + 2);          // top+8 its box numbers
            lua_value *v = value_at(L, top + 7);
            unsigned char *f = v->type == 6 ? v->value : NULL;
            if (f && is_lua_function(f) && value_at(L, top + 8)->type == 5 && !map_get(&done, f, 0)) {
                give_upvalues(L, f, top + 8, top + 3, &cache);
                map_get(&done, f, 1);
                restored++;
            }
            lua_settop(L, top + 5);
        }
        lua_settop(L, top + 5);
        for (unsigned char *o = *(unsigned char **)(g + 0x10); o; o = *(unsigned char **)o) {
            if (!is_lua_function(o) || map_get(&done, o, 0)) continue;
            lua_rawgeti_fn(L, top + 4, proto_id(o));    // top+6 its box numbers
            if (value_at(L, top + 6)->type == 5) {
                give_upvalues(L, o, top + 6, top + 3, &cache);
                map_get(&done, o, 1);
                restored++;
            }
            lua_settop(L, top + 5);
        }
    }
    lua_settop(L, top);
    free(cache.made);
    // functions the save had no upvalues for (an older save): empty upvalues instead of garbage. Only slots
    // that point at no live upvalue (functions an earlier load of this script already restored are whole).
    ptr_map live = {0};
    for (unsigned char *o = *(unsigned char **)(g + 0x10); o; o = *(unsigned char **)o)
        if (o[8] == 10) map_get(&live, o, 1);
    for (unsigned char *o = *(unsigned char **)((unsigned char *)L + 0xb0); o; o = *(unsigned char **)o)
        map_get(&live, o, 1);                           // open upvalues
    lua_value nil = {0, 0, NULL};
    for (unsigned char *o = *(unsigned char **)(g + 0x10); o; o = *(unsigned char **)o) {
        if (!is_lua_function(o) || map_get(&done, o, 0)) continue;
        int bad = 0;
        for (int i = 0; i < o[11]; i++) {
            if (map_get(&live, *upvalue_slot(o, i), 0)) continue;
            *upvalue_slot(o, i) = new_upvalue(L, &nil);
            bad = 1;
        }
        emptied += bad;
    }
    map_free(&live);
    map_free(&done);
    drop_stash(L);
    if (!restored && !emptied) return;
    char line[160];
    snprintf(line, sizeof line, "SAVE LOAD: upvalues of %d functions restored, %d without saved upvalues (emptied)",
             restored, emptied);
    log_line(line);
}

static void reattach_gui(lua_State *L);       // (with Engine_Gui_Listen below)
static void set_global_value(lua_State *L, const char *name, const char *text, double number);
#define GUI_LISTEN_GLOBAL   "__gui_listen"
#define GUI_TICK_GLOBAL     "__gui_tick"

static double now_ms(void);
static int hooked_save_state(lua_State *L, void *writer, void *data, void *callback, int flag) {
    double t0 = now_ms();
    busy_enter();
    stash_upvalues(L);
    int result = orig_save_state(L, writer, data, callback, flag);
    drop_stash(L);
    busy_leave();
    double ms = now_ms() - t0;
    if (ms >= 300) {
        char line[96];
        snprintf(line, sizeof line, "SLOW: script save %.0f ms (state %p)", ms, (void *)L);
        test_log(line);
    }
    return result;
}

static void hooked_load_state(lua_State *L, void *reader, void *data, void *name, void *callback, int flag) {
    busy_enter();
    unsigned char *g = LUA_GLOBAL(L);
    unsigned int threshold = *(unsigned int *)(g + 0x70);
    *(unsigned int *)(g + 0x70) = 0xffffffff;          // no collection until the functions are whole again
    orig_load_state(L, reader, data, name, callback, flag);
    if (*(unsigned int *)(g + 0x70) != 0xffffffff) threshold = *(unsigned int *)(g + 0x70);
    *(unsigned int *)(g + 0x70) = 0xffffffff;
    restore_upvalues(L);
    *(unsigned int *)(g + 0x70) = threshold;
    reattach_gui(L);
    busy_leave();
}

// The garbage collector (0x7bc850, L): busy while it runs (it calls the scripts' handles' __gc).
#define RVA_LUA_GC          0x7bc850
static long long (*orig_lua_gc)(void *, void *, void *, void *);
static int profile_on;                         // (the profiler, below)
static double now_ms(void);
static double gc_ms;                           // collection time since the last profile dump
static unsigned long gc_count;
static long long hooked_lua_gc(void *a, void *b, void *c, void *d) {
    double t0 = now_ms();
    busy_enter();
    long long result = orig_lua_gc(a, b, c, d);
    busy_leave();
    if (!profile_on) {
        double ms = now_ms() - t0;
        if (ms >= 300) {
            char line[96];
            snprintf(line, sizeof line, "SLOW: script collection %.0f ms (state %p)", ms, a);
            test_log(line);
        }
    }
    if (profile_on) {
        double ms = now_ms() - t0;
        gc_ms += ms;
        gc_count++;
        if (ms >= 50) {
            unsigned char *g = a ? LUA_GLOBAL((lua_State *)a) : NULL;
            char line[160];
            snprintf(line, sizeof line, "GC %.0f ms (state %p, %u KB in use after)", ms, a,
                     g ? *(unsigned int *)(g + 0x74) / 1024 : 0);
            test_log(line);
        }
    }
    return result;
}

// --- A script state's call frame --------------------------------------------------------------------------
// The current frame (L+0x58) must lie in the frame array (L+0x80 .. L+0x78). If it doesn't, the frame whose base
// is L+0x18 is used instead, and the fix is logged.
#define RVA_GC_TRAVERSE     0x7bd9d0    // (collector state, L): marks a thread, then shrinks its arrays
#define RVA_REALLOC_CI      0x7bc180    // (L, entries)
#define RVA_REALLOC_STACK   0x7bc220    // (L, slots)
#define LUA_CI(L)           (*(unsigned char **)((unsigned char *)(L) + 0x58))
#define LUA_BASE_CI(L)      (*(unsigned char **)((unsigned char *)(L) + 0x80))
#define LUA_END_CI(L)       (*(unsigned char **)((unsigned char *)(L) + 0x78))
#define LUA_CI_SIZE         0x30
static void check_frame(void *L, const char *where) {
    if (!L) return;
    unsigned char *ci = LUA_CI(L), *first = LUA_BASE_CI(L), *end = LUA_END_CI(L);
    if (!first || (ci >= first && ci <= end)) return;
    int entries = *(unsigned short *)((unsigned char *)L + 0x88);
    unsigned char *found = first;
    if (end == first + (long long)entries * LUA_CI_SIZE) {
        void *base = *(void **)((unsigned char *)L + 0x18);
        for (int i = 0; i < entries; i++) {
            if (*(void **)(first + i * LUA_CI_SIZE) == base) {
                found = first + i * LUA_CI_SIZE;
                break;
            }
        }
    }
    static int reported;
    if (reported++ < 20) {
        char line[200];
        snprintf(line, sizeof line, "LUA FRAME repaired (%s): state %p frame %p, array %p, %d entries, now frame %d",
                 where, L, (void *)ci, (void *)first, entries, (int)((found - first) / LUA_CI_SIZE));
        test_log(line);
        log_line(line);
    }
    LUA_CI(L) = found;
}
static void (*orig_gc_traverse)(void *, void *);
static void hooked_gc_traverse(void *collector, void *L) {
    check_frame(L, "collection");
    orig_gc_traverse(collector, L);
}
static void (*orig_realloc_ci)(void *, int);
static void hooked_realloc_ci(void *L, int entries) {
    check_frame(L, "before the frames move");
    orig_realloc_ci(L, entries);
    check_frame(L, "after the frames moved");
}
static void (*orig_realloc_stack)(void *, int);
static void hooked_realloc_stack(void *L, int slots) {
    check_frame(L, "before the stack moves");
    orig_realloc_stack(L, slots);
}

// --- Lua 5.0 lmathlib against the engine's API ----------------------------------------------
#define ONE(name, fn) static int math_##name(lua_State *L) { lua_pushnumber(L, fn(luaL_checknumber(L, 1))); return 1; }
ONE(abs, fabs) ONE(sin, sin) ONE(cos, cos) ONE(tan, tan) ONE(asin, asin) ONE(acos, acos) ONE(atan, atan)
ONE(ceil, ceil) ONE(floor, floor) ONE(sqrt, sqrt) ONE(log, log) ONE(log10, log10) ONE(exp, exp)
static int math_atan2(lua_State *L) { lua_pushnumber(L, atan2(luaL_checknumber(L, 1), luaL_checknumber(L, 2))); return 1; }
static int math_mod(lua_State *L) { lua_pushnumber(L, fmod(luaL_checknumber(L, 1), luaL_checknumber(L, 2))); return 1; }
static int math_pow(lua_State *L) { lua_pushnumber(L, pow(luaL_checknumber(L, 1), luaL_checknumber(L, 2))); return 1; }
static int math_deg(lua_State *L) { lua_pushnumber(L, luaL_checknumber(L, 1) * (180.0 / 3.14159265358979323846)); return 1; }
static int math_rad(lua_State *L) { lua_pushnumber(L, luaL_checknumber(L, 1) * (3.14159265358979323846 / 180.0)); return 1; }
static int math_frexp(lua_State *L) { int e; lua_pushnumber(L, frexp(luaL_checknumber(L, 1), &e)); lua_pushnumber(L, e); return 2; }
static int math_ldexp(lua_State *L) { lua_pushnumber(L, ldexp(luaL_checknumber(L, 1), (int)luaL_checknumber(L, 2))); return 1; }
static int math_min(lua_State *L) {
    int n = lua_gettop(L), i; double m = luaL_checknumber(L, 1);
    for (i = 2; i <= n; i++) { double v = luaL_checknumber(L, i); if (v < m) m = v; }
    lua_pushnumber(L, m); return 1;
}
static int math_max(lua_State *L) {
    int n = lua_gettop(L), i; double m = luaL_checknumber(L, 1);
    for (i = 2; i <= n; i++) { double v = luaL_checknumber(L, i); if (v > m) m = v; }
    lua_pushnumber(L, m); return 1;
}
static int math_random(lua_State *L) {    // as Lua 5.0: random() in [0,1), random(m) in [1,m], random(m,n)
    double r = (double)(rand() % RAND_MAX) / (double)RAND_MAX;
    int n = lua_gettop(L);
    if (n == 0) { lua_pushnumber(L, r); return 1; }
    double lo = 1, hi = luaL_checknumber(L, 1);
    if (n >= 2) { lo = hi; hi = luaL_checknumber(L, 2); }
    if (hi < lo) hi = lo;
    lua_pushnumber(L, floor(r * (hi - lo + 1)) + lo); return 1;
}
static int math_randomseed(lua_State *L) { srand((unsigned)(long long)luaL_checknumber(L, 1)); return 0; }

static const luaL_reg MATHLIB[] = {
    {"abs", math_abs}, {"sin", math_sin}, {"cos", math_cos}, {"tan", math_tan}, {"asin", math_asin},
    {"acos", math_acos}, {"atan", math_atan}, {"atan2", math_atan2}, {"ceil", math_ceil},
    {"floor", math_floor}, {"mod", math_mod}, {"frexp", math_frexp}, {"ldexp", math_ldexp},
    {"sqrt", math_sqrt}, {"min", math_min}, {"max", math_max}, {"log", math_log},
    {"log10", math_log10}, {"exp", math_exp}, {"deg", math_deg}, {"rad", math_rad},
    {"pow", math_pow}, {"random", math_random}, {"randomseed", math_randomseed}, {NULL, NULL}
};

static volatile LONG states_patched = 0;
static int lua_engine_log(lua_State *L);   // defined with the test log below
static int lua_engine_set_text(lua_State *L);   // defined with the text overrides below
static int lua_engine_set_object_text(lua_State *L);

static int lua_rebellion_prompt(lua_State *L);
static int lua_battle_planet(lua_State *L);
static int lua_spied(lua_State *L);
static int lua_envoy_slots(lua_State *L);
static int lua_envoy_worlds(lua_State *L);
static int lua_envoy_posted(lua_State *L);
static int lua_envoy_recalls(lua_State *L);
static int lua_set_build_limit(lua_State *L);
static int lua_lane_colors(lua_State *L);
static int lua_layout_open(lua_State *L);
static int lua_layout_pick(lua_State *L);
static int lua_layout_select(lua_State *L);
static int lua_hardpoint_at(lua_State *L);
static int lua_hardpoint_build(lua_State *L);
static int lua_hardpoint_remove(lua_State *L);
static int hp_pad_click(int x, int y, int left);
static int lua_planet_flash(lua_State *L);
static int lua_planet_info(lua_State *L);
static int lua_gui_pressed(lua_State *L);
static int lua_cursor(lua_State *L);
static int lua_gui_visible(lua_State *L);
static int lua_trade_lanes(lua_State *L);
static int lua_lanes_refresh(lua_State *L);
static int lua_safe_path(lua_State *L);
static int lua_faction_colour(lua_State *L);
static void note_battle_planet(unsigned char *planet);
static int lua_battle_serial(lua_State *L);
static char zoomed_planet[64];     // (defined with the zoom hooks below)
static void remember_main_state(lua_State *L);
static int lua_set_human_planets(lua_State *L);
static int lua_gui_listen(lua_State *L);
static int lua_screen_text(lua_State *L);
static int lua_screen_size(lua_State *L);
static int lua_mouse(lua_State *L);
static int lua_gui_tick(lua_State *L);
static int lua_ticks(lua_State *L);
static int lua_play_sound(lua_State *L);
static int lua_stop_sound(lua_State *L);
static int lua_sound_playing(lua_State *L);
static int lua_wheel_capture(lua_State *L);
static int lua_escape_capture(lua_State *L);
static int lua_escape_pressed(lua_State *L);
static int lua_income_rows(lua_State *L);
static int lua_planet_income_off(lua_State *L);
static int lua_movie_rect(lua_State *L);
static int lua_planet_income_real(lua_State *L);
static int lua_taxes(lua_State *L);
static int lua_shown_income(lua_State *L);
static int lua_glued_text(lua_State *L);
static int glued_text_on;
static int lua_selected_planet(lua_State *L);
static int lua_zoomed_planet(lua_State *L);
static int lua_spawn_between(lua_State *L);
static int lua_fleet_sample(lua_State *L);
static int lua_inbound(lua_State *L);
static int lua_inbound_arrive(lua_State *L);
static int lua_inbound_settle(lua_State *L);
static int lua_border_lanes(lua_State *L);
static int lua_border_bonds(lua_State *L);
static int lua_inbound_retreat(lua_State *L);
static int lua_autoresolve_own(lua_State *L);
static int lua_autoresolve_take(lua_State *L);
static int lua_battle_continue(lua_State *L);
static int lua_human_retreated(lua_State *L);
static int lua_retreats(lua_State *L);
static void retreat_reset(void);
static int lua_victory_test(lua_State *L);
static int lua_declare_win(lua_State *L);
static int lua_autoresolve_finish(lua_State *L);
static int lua_battle_end_check(lua_State *L);
static int lua_battle_lane(lua_State *L);
static int lua_rotate(lua_State *L);
static int lua_route_lanes(lua_State *L);
static int lua_battle_hold(lua_State *L);
static int lua_spawn_facing(lua_State *L);
static int lua_battle_allies(lua_State *L);
static int lua_pool_types(lua_State *L);
static void battle_hold_reset(void);
static void note_inbound(unsigned char *planet, int attacker, int defender);
static int inbound_count;
static int human_retreated;          // (the human's retreat is complete: hooked_retreat_done)
static int battle_attacker = -1, battle_defender = -1;   // (the two sides of the human's last battle)
static int inbound_unsettled;        // a battle's inbound list not yet settled (Engine_Inbound_Settle) after it
#ifndef RELEASE_BUILD
static int lua_fleets(lua_State *L);
static int lua_peek(lua_State *L);
#endif
static int lua_pause(lua_State *L);

static int lua_start_hold(lua_State *L);       // (the start hold, below)
static void start_hold_tick(void);

static int hooked_luaopen_table(lua_State *L) {
    int result = orig_luaopen_table(L);
    int top = lua_gettop(L);
    luaL_openlib(L, "math", MATHLIB, 0);
    lua_pushstring(L, "pi");   lua_pushnumber(L, 3.14159265358979323846); lua_settable(L, -3);
    lua_pushstring(L, "huge"); lua_pushnumber(L, HUGE_VAL);               lua_settable(L, -3);
    lua_pushstring(L, "__pow"); lua_pushcclosure(L, math_pow, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Log"); lua_pushcclosure(L, lua_engine_log, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Set_Text"); lua_pushcclosure(L, lua_engine_set_text, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Set_Object_Text"); lua_pushcclosure(L, lua_engine_set_object_text, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Set_Human_Planets"); lua_pushcclosure(L, lua_set_human_planets, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Gui_Listen"); lua_pushcclosure(L, lua_gui_listen, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Screen_Size"); lua_pushcclosure(L, lua_screen_size, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Mouse"); lua_pushcclosure(L, lua_mouse, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Gui_Tick"); lua_pushcclosure(L, lua_gui_tick, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Ticks"); lua_pushcclosure(L, lua_ticks, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Pause"); lua_pushcclosure(L, lua_pause, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Start_Hold"); lua_pushcclosure(L, lua_start_hold, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Play_Sound"); lua_pushcclosure(L, lua_play_sound, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Stop_Sound"); lua_pushcclosure(L, lua_stop_sound, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Sound_Playing"); lua_pushcclosure(L, lua_sound_playing, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Wheel_Capture"); lua_pushcclosure(L, lua_wheel_capture, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Escape_Capture"); lua_pushcclosure(L, lua_escape_capture, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Escape_Pressed"); lua_pushcclosure(L, lua_escape_pressed, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Income_Rows"); lua_pushcclosure(L, lua_income_rows, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Movie_Rect"); lua_pushcclosure(L, lua_movie_rect, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Planet_Income_Off"); lua_pushcclosure(L, lua_planet_income_off, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Planet_Income_Real"); lua_pushcclosure(L, lua_planet_income_real, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Taxes"); lua_pushcclosure(L, lua_taxes, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Shown_Income"); lua_pushcclosure(L, lua_shown_income, 0); lua_settable(L, LUA_GLOBALSINDEX);
    if (glued_text_on) { lua_pushstring(L, "Engine_Glued_Text"); lua_pushcclosure(L, lua_glued_text, 0); lua_settable(L, LUA_GLOBALSINDEX); }
    lua_pushstring(L, "Engine_Selected_Planet"); lua_pushcclosure(L, lua_selected_planet, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Zoomed_Planet"); lua_pushcclosure(L, lua_zoomed_planet, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Spawn_Between"); lua_pushcclosure(L, lua_spawn_between, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Fleet_Sample"); lua_pushcclosure(L, lua_fleet_sample, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Inbound"); lua_pushcclosure(L, lua_inbound, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Inbound_Arrive"); lua_pushcclosure(L, lua_inbound_arrive, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Inbound_Settle"); lua_pushcclosure(L, lua_inbound_settle, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Border_Lanes"); lua_pushcclosure(L, lua_border_lanes, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Border_Bonds"); lua_pushcclosure(L, lua_border_bonds, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Inbound_Retreat"); lua_pushcclosure(L, lua_inbound_retreat, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Autoresolve_Own"); lua_pushcclosure(L, lua_autoresolve_own, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Autoresolve_Take"); lua_pushcclosure(L, lua_autoresolve_take, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Battle_Continue"); lua_pushcclosure(L, lua_battle_continue, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Human_Retreated"); lua_pushcclosure(L, lua_human_retreated, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Retreats"); lua_pushcclosure(L, lua_retreats, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Victory_Test"); lua_pushcclosure(L, lua_victory_test, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Declare_Win"); lua_pushcclosure(L, lua_declare_win, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Autoresolve_Finish"); lua_pushcclosure(L, lua_autoresolve_finish, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Battle_End_Check"); lua_pushcclosure(L, lua_battle_end_check, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Battle_Lane"); lua_pushcclosure(L, lua_battle_lane, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Rotate"); lua_pushcclosure(L, lua_rotate, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Route_Lanes"); lua_pushcclosure(L, lua_route_lanes, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Battle_Hold"); lua_pushcclosure(L, lua_battle_hold, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Spawn_Facing"); lua_pushcclosure(L, lua_spawn_facing, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Battle_Allies"); lua_pushcclosure(L, lua_battle_allies, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Pool_Types"); lua_pushcclosure(L, lua_pool_types, 0); lua_settable(L, LUA_GLOBALSINDEX);
#ifndef RELEASE_BUILD
    lua_pushstring(L, "Engine_Fleets"); lua_pushcclosure(L, lua_fleets, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Peek"); lua_pushcclosure(L, lua_peek, 0); lua_settable(L, LUA_GLOBALSINDEX);
#endif
    lua_pushstring(L, "Engine_Screen_Text"); lua_pushcclosure(L, lua_screen_text, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Battle_Planet"); lua_pushcclosure(L, lua_battle_planet, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Battle_Serial"); lua_pushcclosure(L, lua_battle_serial, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Spied"); lua_pushcclosure(L, lua_spied, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Envoy_Slots"); lua_pushcclosure(L, lua_envoy_slots, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Envoy_Worlds"); lua_pushcclosure(L, lua_envoy_worlds, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Envoy_Posted"); lua_pushcclosure(L, lua_envoy_posted, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Envoy_Recalls"); lua_pushcclosure(L, lua_envoy_recalls, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Set_Build_Limit"); lua_pushcclosure(L, lua_set_build_limit, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Lane_Colors"); lua_pushcclosure(L, lua_lane_colors, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Layout_Open"); lua_pushcclosure(L, lua_layout_open, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Layout_Pick"); lua_pushcclosure(L, lua_layout_pick, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Layout_Select"); lua_pushcclosure(L, lua_layout_select, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Hardpoint_At"); lua_pushcclosure(L, lua_hardpoint_at, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Hardpoint_Build"); lua_pushcclosure(L, lua_hardpoint_build, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Hardpoint_Remove"); lua_pushcclosure(L, lua_hardpoint_remove, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Planet_Flash"); lua_pushcclosure(L, lua_planet_flash, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Planet_Info"); lua_pushcclosure(L, lua_planet_info, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Gui_Pressed"); lua_pushcclosure(L, lua_gui_pressed, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Cursor"); lua_pushcclosure(L, lua_cursor, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Gui_Visible"); lua_pushcclosure(L, lua_gui_visible, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Trade_Lanes"); lua_pushcclosure(L, lua_trade_lanes, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Lanes_Refresh"); lua_pushcclosure(L, lua_lanes_refresh, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Safe_Path"); lua_pushcclosure(L, lua_safe_path, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Faction_Colour"); lua_pushcclosure(L, lua_faction_colour, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_pushstring(L, "Engine_Rebellion_Prompt"); lua_pushcclosure(L, lua_rebellion_prompt, 0); lua_settable(L, LUA_GLOBALSINDEX);
    lua_settop(L, top);
    remember_main_state(L);
    if (InterlockedIncrement(&states_patched) == 1) {
        log_line("first Lua state: math library added");
    }
    return result;
}

// --- Diagnostics: the engine's debug prints (compiled out in the retail build) -----------------
#define RVA_DEBUG_PRINT     0x025760    // printf-style, body is just `ret` in retail
#define RVA_DECLARE_VICTORY 0x343b90    // logs "VICTORY - Victory type %d, player ID %d ..."
static void (*orig_debug_print)(const char *, ...);
static unsigned long long (*orig_declare_victory)(void *, int *);
static unsigned char *module_base;

static int interesting(const char *s) {
    static const char *KEYS[] = {"VICTORY", "DEFEAT", "defeat", "WINNER", "winner", "rror", "ERROR", "Lua", "LUA",
                                 "lua", "SCRIPT", "Script", "script", "Fail", "fail", "FAIL", "assert", "ASSERT",
                                 "nil value", "stack", "DIPLOMACY"};
    for (size_t i = 0; i < sizeof(KEYS) / sizeof(KEYS[0]); i++) if (strstr(s, KEYS[i])) return 1;
    return 0;
}
static void hooked_debug_print(const char *fmt, ...) {
    char buf[1024];
    va_list ap; va_start(ap, fmt); vsnprintf(buf, sizeof buf, fmt, ap); va_end(ap);
    if (interesting(buf)) { log_line(buf); }
}
// Players: list at +0xa16fd0; Get_Local_Player(list), Get_Player_By_ID(list, id). A player's diplomatic
// table is at player+0x370 (int per player ID: 1 = enemy, 0 = ally); its ID is at player+0x4c.
#define RVA_PLAYER_LIST     0xa16fd0
#define RVA_LOCAL_PLAYER    0x294a40
#define RVA_PLAYER_BY_ID    0x294bc0
static unsigned char *(*get_local_player)(void *);
static unsigned char *(*get_player_by_id)(void *, int);

// Planet-control victories (types 0 and 1) are refused for an AI not at war with the human: the engine counts a
// treaty partner's planets as its own, so a ceasefire or alliance would end the campaign.
static const char *player_name(int id);
static void test_log(const char *line);
// The human's world count, reported by the Diplomacy script (-1: not known yet). An AI wins only once it is 0.
static volatile int human_planets = -1;

static int refuse_victory(const int *event) {
    if ((event[0] != 0 && event[0] != 1) || !get_local_player || !diplomacy_loaded()) return 0;
    unsigned char *list = module_base + RVA_PLAYER_LIST;
    unsigned char *local = get_local_player(list);
    unsigned char *winner = get_player_by_id(list, event[1]);
    if (!local || !winner || winner == local) return 0;
    if (human_planets > 0) return 1;
    int *relations = *(int **)(local + 0x370);
    return relations && relations[event[1]] != 1;
}

static unsigned long long hooked_declare_victory(void *self, int *event) {
    static unsigned long refusals = 0;
    static DWORD last_refusal_log = 0;
    if (refuse_victory(event)) {
        refusals++;
        DWORD now = GetTickCount();
        if (refusals == 1 || now - last_refusal_log >= 10000) {
            last_refusal_log = now;
            char msg[200];
            snprintf(msg, sizeof msg, "refused victory type %d for player %d %s (the human holds %d worlds), %lu refusals",
                     event[0], event[1], player_name(event[1]), human_planets, refusals);
            log_line(msg);
            test_log(msg);
        }
        return 0;
    }
    char buf[256];
    snprintf(buf, sizeof buf, "DECLARE VICTORY event: %d %d %d %d %d %d, called from +0x%llx", event[0], event[1],
             event[2], event[3], event[4], event[5],
             (unsigned long long)((unsigned char *)__builtin_return_address(0) - module_base));
    log_line(buf);
    return orig_declare_victory(self, event);
}

// Lua's _ALERT (script error reporter): the retail engine drops the message; log it first.
#define RVA_LUA_ALERT       0x246940
#define RVA_TOSTRING        0x7b9cc0
static int (*orig_lua_alert)(lua_State *);
static const char *(*lua_tostring_fn)(lua_State *, int);
static int hooked_lua_alert(lua_State *L) {
    int n = lua_gettop(L);
    for (int i = 1; i <= n; i++) {
        const char *s = lua_tostring_fn(L, i);
        if (s) {
            char buf[1100];
            snprintf(buf, sizeof buf, "LUA ERROR: %.1000s", s);
            log_line(buf);
        }
    }
    return orig_lua_alert(L);
}

// --- Test log (EngineTest.log, cleared at every game start) -----------------------------------
// Kept open and buffered; flushed every LOG_FLUSH_MS, on the frame tick, on script errors and on a crash.
#define LOG_FLUSH_MS 250
static DWORD test_log_flushed;
static int test_log_dirty;
static void test_log_flush(void) {
    if (test_log_file && test_log_dirty) { fflush(test_log_file); test_log_dirty = 0; test_log_flushed = GetTickCount(); }
}
static void test_log(const char *text) {
    if (!test_log_path[0]) return;
    if (!test_log_file) {
        test_log_file = fopen(test_log_path, "a");
        if (test_log_file) setvbuf(test_log_file, NULL, _IOFBF, 1 << 16);
    }
    if (!test_log_file) return;
    DWORD now = GetTickCount();
    fprintf(test_log_file, "%10lu  %s\n", now, text);
    test_log_dirty = 1;
    if (now - test_log_flushed >= LOG_FLUSH_MS) test_log_flush();
}
// Engine_Log(text): lets scripts write to EngineTest.log.
static int lua_engine_log(lua_State *L) {
    const char *s = lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    if (s) test_log(s);
    return 0;
}

// lua_resume (runs one step of a script thread). A failed step leaves the thread dead and the
// retail engine reports nothing; log the error (Lua prefixes it with file:line).
#define RVA_RESUME          0x7bc310
// Scripts running right now: the frame tick never enters Lua while one is (a second call into the same state
// corrupts it).
static volatile int script_depth;
static int script_depth_tracked;            // both hooks below installed
static int (*orig_lua_resume)(lua_State *, int, void *);

// Thread watch: each thread's call stack and last run time, written every 5 s.
#define RVA_GETSTACK        0x7bb5c0
#define RVA_GETINFO         0x7bb3a0
typedef struct { int event; const char *name, *namewhat, *what, *source; int currentline, nups, linedefined;
                 char short_src[60]; int i_ci; } lua_Debug;   // Lua 5.0 layout (i_ci at 0x70, as in the engine)
static int (*lua_getstack_fn)(lua_State *, int, lua_Debug *);
static int (*lua_getinfo_fn)(lua_State *, const char *, lua_Debug *);
#define MAX_THREADS 512
static struct { lua_State *L; DWORD last_run; unsigned long runs; char where[400]; } threads[MAX_THREADS];
static DWORD last_dump;
// Diagnostics: off unless EngineHook_diag.txt sits next to the DLL (not in the release build).
static int thread_watch_on = 0;

static void describe_stack(lua_State *L, char *out, size_t size) {
    lua_Debug ar;
    size_t used = 0;
    out[0] = 0;
    for (int level = 0; level < 8 && lua_getstack_fn(L, level, &ar); level++) {
        memset(&ar.name, 0, offsetof(lua_Debug, i_ci) - offsetof(lua_Debug, name));   // keep i_ci from getstack
        if (!lua_getinfo_fn(L, "Sln", &ar)) break;
        int n = snprintf(out + used, size - used, "%s%s:%d(%s)", level ? " < " : "", ar.short_src, ar.currentline,
                         ar.name ? ar.name : "?");
        if (n < 0 || (size_t)n >= size - used) break;
        used += n;
    }
    if (!out[0]) snprintf(out, size, "(no Lua frames: finished or waiting in the engine)");
}

// Profiler (EngineHook_profile.txt next to the DLL): time per named script call and thread step, and the slowest
// call in each stall. Off, it costs one flag test.
#define PROFILE_DUMP_MS 10000
#define STALL_MS 250
static double qpc_scale;
static double now_ms(void) {
    LARGE_INTEGER t;
    if (qpc_scale == 0) { LARGE_INTEGER f; QueryPerformanceFrequency(&f); qpc_scale = 1000.0 / (double)f.QuadPart; }
    QueryPerformanceCounter(&t);
    return (double)t.QuadPart * qpc_scale;
}
#define MAX_PROF 160
static struct { char src[64]; double total, max; unsigned long count; } prof_steps[MAX_PROF];
static double slowest_ms;                    // the slowest single call since the last pumped message
static char slowest[140];
static void note_slow(const char *what, const char *src, double ms) {
    if (ms > slowest_ms) { slowest_ms = ms; snprintf(slowest, sizeof slowest, "%s (%s) %.0f ms", what, src, ms); }
}
static void prof_step(const char *src, double ms) {
    int slot = -1;
    for (int i = 0; i < MAX_PROF; i++) {
        if (prof_steps[i].src[0] && strcmp(prof_steps[i].src, src) == 0) { slot = i; break; }
        if (slot < 0 && !prof_steps[i].src[0]) slot = i;
    }
    if (slot < 0) slot = MAX_PROF - 1;
    if (!prof_steps[slot].src[0] || strcmp(prof_steps[slot].src, src) != 0) {
        snprintf(prof_steps[slot].src, sizeof prof_steps[slot].src, "%s", src);
        prof_steps[slot].total = prof_steps[slot].max = 0;
        prof_steps[slot].count = 0;
    }
    prof_steps[slot].total += ms;
    prof_steps[slot].count++;
    if (ms > prof_steps[slot].max) prof_steps[slot].max = ms;
}

// Lua sampling while profiling: a count hook (0x7bb640) records the running function every LUA_SAMPLE instructions.
#define RVA_SETHOOK         0x7bb640
#define LUA_SAMPLE          1000
#define LUA_HOOK_FIELD      0x98            // lua_State.hook (as lua_sethook writes it)
static int (*lua_sethook_fn)(lua_State *, void (*)(lua_State *, lua_Debug *), int, int);
#define MAX_LUAFN 512
static struct { char key[72]; unsigned long hits; } luafn[MAX_LUAFN];
// The last lines each script state ran (one per sample), logged when the state is closed: a script that dies
// without an error message still shows where it was.
#define TRAIL_LEN 8
static struct { void *g; char at[TRAIL_LEN][72]; int next; } trails[8];
static void trail_add(void *g, const char *file, int line) {
    int slot = -1;
    for (int i = 0; i < 8; i++) if (trails[i].g == g) { slot = i; break; }
    if (slot < 0) {
        static int rr;
        for (int i = 0; i < 8 && slot < 0; i++) if (!trails[i].g) slot = i;
        if (slot < 0) slot = rr++ & 7;
        memset(&trails[slot], 0, sizeof trails[slot]);
        trails[slot].g = g;
    }
    snprintf(trails[slot].at[trails[slot].next], 72, "%s:%d", file, line);
    trails[slot].next = (trails[slot].next + 1) % TRAIL_LEN;
}
static void trail_dump(void *g) {
    for (int i = 0; i < 8; i++) if (trails[i].g == g) {
        char line[160];
        for (int n = 0; n < TRAIL_LEN; n++) {
            const char *at = trails[i].at[(trails[i].next + n) % TRAIL_LEN];
            if (!at[0]) continue;
            snprintf(line, sizeof line, "TRAIL %s", at);
            test_log(line);
        }
        trails[i].g = NULL;
    }
}
// The engine's script error report (0x248190). The retail game prints nothing and stops the script silently,
// so the error is logged with the script's last lines.
#define RVA_SCRIPT_ERROR    0x248190
static lua_State *running_thread;   // the script thread being resumed (its stack names the line that stopped it)
static void (*orig_script_error)(void *, const char *, void *, void *);
static void hooked_script_error(void *script, const char *fmt, void *a, void *b) {
    char line[700];
    int used = snprintf(line, sizeof line, "SCRIPT STOPPED BY THE ENGINE: %.400s", fmt ? fmt : "?");
    if (fmt && strstr(fmt, "%s") && a && !IsBadStringPtrA((const char *)a, 200))
        snprintf(line + used, sizeof line - used, " [%.200s]", (const char *)a);
    else if (fmt && strstr(fmt, "%d"))
        snprintf(line + used, sizeof line - used, " [%lld]", (long long)a);
    test_log(line);
    lua_State *L = script ? *(lua_State **)((unsigned char *)script + 0x58) : NULL;
    if (L && lua_getstack_fn && lua_getinfo_fn) {
        char where[600];
        describe_stack(running_thread ? running_thread : L, where, sizeof where);
        snprintf(line, sizeof line, "  at %s", where);
        test_log(line);
    }
    if (L) {
        void *g = *(void **)((unsigned char *)L + 0x20);
        for (int i = 0; i < 8; i++) if (trails[i].g == g)
            for (int n = 0; n < TRAIL_LEN; n++) {
                const char *at = trails[i].at[(trails[i].next + n) % TRAIL_LEN];
                if (at[0]) { snprintf(line, sizeof line, "  last ran %s", at); test_log(line); }
            }
    }
    test_log_flush();
    orig_script_error(script, fmt, a, b);
}
static void lua_count_hook(lua_State *L, lua_Debug *ar) {
    if (!lua_getinfo_fn) return;
    memset(&ar->name, 0, offsetof(lua_Debug, i_ci) - offsetof(lua_Debug, name));
    if (!lua_getinfo_fn(L, "Sl", ar)) return;
    const char *file = strrchr(ar->short_src, '/');
    file = file ? file + 1 : ar->short_src;
    trail_add(*(void **)((unsigned char *)L + 0x20 /* lua_State.l_G */), file, ar->currentline);
    char key[72];
    snprintf(key, sizeof key, "%s:%d", file, ar->linedefined);
    DWORD h = 2166136261u;
    for (const char *s = key; *s; s++) h = (h ^ (unsigned char)*s) * 16777619u;
    for (int n = 0; n < 32; n++, h++) {
        int i = h & (MAX_LUAFN - 1);
        if (!luafn[i].key[0]) { memcpy(luafn[i].key, key, sizeof key); luafn[i].hits = 1; return; }
        if (strcmp(luafn[i].key, key) == 0) { luafn[i].hits++; return; }
    }
}
static void lua_profile_state(lua_State *L) {
    if (lua_sethook_fn && L && !*(void **)((unsigned char *)L + LUA_HOOK_FIELD))
        lua_sethook_fn(L, lua_count_hook, 8 /* LUA_MASKCOUNT */, LUA_SAMPLE);
}
static void lua_profile_dump(void) {
    char line[160];
    unsigned long total = 0;
    for (int i = 0; i < MAX_LUAFN; i++) total += luafn[i].hits;
    if (!total) return;
    snprintf(line, sizeof line, "LUA %lu samples (one per %d instructions)", total, LUA_SAMPLE);
    test_log(line);
    for (int n = 0; n < 20; n++) {
        int best = -1;
        for (int i = 0; i < MAX_LUAFN; i++) if (luafn[i].hits && (best < 0 || luafn[i].hits > luafn[best].hits)) best = i;
        if (best < 0 || luafn[best].hits * 100 < total) break;
        snprintf(line, sizeof line, "LUA %5.1f%% %s", 100.0 * luafn[best].hits / total, luafn[best].key);
        test_log(line);
        luafn[best].hits = 0;
    }
    memset(luafn, 0, sizeof luafn);
}

// Named calls into scripts (engine -> Lua function by name, e.g. Story_Mode_Service): per script and
// function, how often and when last called. Dumped with the threads.
#define RVA_CALL_BY_NAME    0x2437c0
static void *(*orig_call_by_name)(void *, void *, const char *, void *, long long, long long, long long);
#define MAX_CALLS 256
static struct { void *script; char name[48]; DWORD last; unsigned long count; char src[64]; double total, max; }
    calls[MAX_CALLS];
// The file a script's global function comes from (the script object keeps its Lua state at +0x58).
static void script_source(void *script, const char *name, char *out, size_t size) {
    snprintf(out, size, "?");
    lua_State *L = script ? *(lua_State **)((unsigned char *)script + 0x58) : NULL;
    if (!L || !lua_getinfo_fn || !lua_rawget_fn || !lua_pushstring || !lua_settop || !lua_gettop) return;
    if (!room_for(L, 3, "the profiler")) return;
    int top = lua_gettop(L);
    lua_pushstring(L, name);
    lua_rawget_fn(L, LUA_GLOBALSINDEX);
    lua_value *v = *(lua_value **)((unsigned char *)L + 0x10) - 1;
    if (v->type == 6) {                          // a function: lua_getinfo(">S") reads and pops it
        lua_Debug ar;
        memset(&ar, 0, sizeof ar);
        if (lua_getinfo_fn(L, ">S", &ar)) snprintf(out, size, "%s", ar.short_src);
    }
    lua_settop(L, top);
}
static void *hooked_call_by_name(void *script, void *out, const char *name, void *args, long long flag, long long x6,
                                 long long x7) {
    int slot = -1;
    if (name && (thread_watch_on || profile_on)) {
        DWORD now = GetTickCount();
        for (int i = 0; i < MAX_CALLS; i++) {
            if (calls[i].script == script && strncmp(calls[i].name, name, sizeof calls[i].name - 1) == 0) { slot = i; break; }
            if (slot < 0 && !calls[i].script) slot = i;
        }
        if (slot >= 0 && calls[slot].script && calls[slot].script != script) slot = -1;
        if (slot < 0) {                       // full: reuse the entry called least recently
            slot = 0;
            for (int i = 1; i < MAX_CALLS; i++) if (calls[i].last < calls[slot].last) slot = i;
            calls[slot].script = NULL;
            calls[slot].count = 0;
        }
        if (!calls[slot].script) {
            calls[slot].script = script;
            memset(calls[slot].name, 0, sizeof calls[slot].name);
            strncpy(calls[slot].name, name, sizeof calls[slot].name - 1);
            calls[slot].total = calls[slot].max = 0;
            if (profile_on) script_source(script, name, calls[slot].src, sizeof calls[slot].src);
            else calls[slot].src[0] = 0;
        }
        calls[slot].last = now;
        calls[slot].count++;
    }
    if (profile_on && script) lua_profile_state(*(lua_State **)((unsigned char *)script + 0x58));
    double t0 = profile_on ? now_ms() : 0;
    script_depth++;
    void *result = orig_call_by_name(script, out, name, args, flag, x6, x7);
    script_depth--;
    if (profile_on && slot >= 0) {
        double ms = now_ms() - t0;
        calls[slot].total += ms;
        if (ms > calls[slot].max) calls[slot].max = ms;
        note_slow(calls[slot].name, calls[slot].src, ms);
    }
    return result;
}

// Sampling profiler: a thread samples the main thread's stack about every millisecond using the exe's unwind data
// (.pdata) and reports the engine functions it spends time in.
static DWORD main_thread_id;
static unsigned char *img_base;
static size_t img_size;
static RUNTIME_FUNCTION *pdata;
static DWORD pdata_count;
#define SAMPLE_SLOTS 16384
static struct { DWORD rva; unsigned long self, incl; } samples[SAMPLE_SLOTS];
static unsigned long sample_total, sample_outside;
static CRITICAL_SECTION sample_lock;
#define PATH_SLOTS 8192
static struct { DWORD f[5]; unsigned long n; } paths[PATH_SLOTS];
static void path_add(const DWORD *frames, int count) {
    DWORD key[5] = {0, 0, 0, 0, 0};
    for (int i = 0; i < 5 && i < count; i++) key[i] = frames[i];
    DWORD h = 2166136261u;
    for (int i = 0; i < 5; i++) h = (h ^ key[i]) * 16777619u;
    for (int n = 0; n < 64; n++, h++) {
        DWORD i = h & (PATH_SLOTS - 1);
        if (paths[i].n == 0) { memcpy(paths[i].f, key, sizeof key); paths[i].n = 1; return; }
        if (memcmp(paths[i].f, key, sizeof key) == 0) { paths[i].n++; return; }
    }
}

static RUNTIME_FUNCTION *find_function(DWORD rva) {
    DWORD lo = 0, hi = pdata_count;
    while (lo < hi) {
        DWORD mid = (lo + hi) / 2;
        if (rva < pdata[mid].BeginAddress) hi = mid;
        else if (rva >= pdata[mid].EndAddress) lo = mid + 1;
        else {
            return &pdata[mid];
        }
    }
    return NULL;
}
static int in_image(DWORD64 a) { return a >= (DWORD64)img_base && a < (DWORD64)img_base + img_size; }
static int looks_like_return(DWORD64 a) {     // the instruction before it is a call
    unsigned char *p = (unsigned char *)a;
    return in_image(a - 7) && (p[-5] == 0xE8 || (p[-6] == 0xFF && p[-5] == 0x15) || (p[-2] == 0xFF && (p[-1] & 0xF0) == 0xD0)
                               || (p[-3] == 0xFF && (p[-2] & 0x38) == 0x10));
}
static void sample_add(DWORD fn, int self) {
    DWORD i = (fn * 2654435761u) & (SAMPLE_SLOTS - 1);
    for (int n = 0; n < 64; n++, i = (i + 1) & (SAMPLE_SLOTS - 1)) {
        if (samples[i].rva == fn || samples[i].rva == 0) {
            samples[i].rva = fn;
            samples[i].incl++;
            if (self) samples[i].self++;
            return;
        }
    }
}
// A walk can meet a stack the main thread is in the middle of changing: a fault inside it ends that one sample (the
// guard below jumps back), never the game.
static DWORD sampler_tid;
static volatile int sampler_walking;
static void *sampler_jump[5];
static LONG CALLBACK sampler_guard(EXCEPTION_POINTERS *e) {
    if (sampler_walking && GetCurrentThreadId() == sampler_tid
        && e->ExceptionRecord->ExceptionCode == EXCEPTION_ACCESS_VIOLATION) {
        sampler_walking = 0;
        __builtin_longjmp(sampler_jump, 1);
    }
    return EXCEPTION_CONTINUE_SEARCH;
}
static DWORD WINAPI sampler_thread(void *unused) {
    (void)unused;
    HANDLE h = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, FALSE, main_thread_id);
    if (!h) return 0;
    for (;;) {
        Sleep(1);
        DWORD frames[48];
        int count = 0, outside = 0;
        CONTEXT c;
        memset(&c, 0, sizeof c);
        c.ContextFlags = CONTEXT_CONTROL | CONTEXT_INTEGER;
        if (SuspendThread(h) == (DWORD)-1) break;
        sampler_walking = 1;
        if (__builtin_setjmp(sampler_jump)) {           // a fault during the walk: this sample is dropped
            count = 0;
            outside = 0;
        } else if (GetThreadContext(h, &c)) {
            MEMORY_BASIC_INFORMATION stack;              // the walk stays inside the main thread's stack
            DWORD64 lo = 0, hi = 0;
            if (VirtualQuery((void *)c.Rsp, &stack, sizeof stack)) {
                lo = (DWORD64)stack.AllocationBase;
                hi = (DWORD64)stack.BaseAddress + stack.RegionSize;
            }
            if (!in_image(c.Rip)) {                 // in a system DLL: from the first return into the game
                outside = 1;
                MEMORY_BASIC_INFORMATION mbi;
                if (VirtualQuery((void *)c.Rsp, &mbi, sizeof mbi)) {
                    DWORD64 end = (DWORD64)mbi.BaseAddress + mbi.RegionSize;
                    for (DWORD64 s = c.Rsp; s + 8 <= end && s < c.Rsp + 0x8000; s += 8) {
                        DWORD64 v = *(DWORD64 *)s;
                        if (in_image(v) && looks_like_return(v)) { c.Rip = v; c.Rsp = s + 8; break; }
                    }
                }
            }
            for (int depth = 0; depth < 48 && in_image(c.Rip) && c.Rsp >= lo && c.Rsp + 64 <= hi && !(c.Rsp & 7); depth++) {
                RUNTIME_FUNCTION *f = find_function((DWORD)(c.Rip - (DWORD64)img_base));
                if (f) {
                    frames[count++] = f->BeginAddress;
                    void *handler_data;
                    DWORD64 establisher;
                    RtlVirtualUnwind(0, (DWORD64)img_base, c.Rip, f, &c, &handler_data, &establisher, NULL);
                } else {                               // a leaf without unwind data: its return address is on top
                    if (!readable((void *)c.Rsp, 8)) break;
                    c.Rip = *(DWORD64 *)c.Rsp;
                    c.Rsp += 8;
                }
            }
        }
        sampler_walking = 0;
        ResumeThread(h);
        EnterCriticalSection(&sample_lock);
        sample_total++;
        if (outside) sample_outside++;
        for (int i = 0; i < count; i++) {
            int seen = 0;
            for (int j = 0; j < i; j++) if (frames[j] == frames[i]) seen = 1;
            if (!seen) sample_add(frames[i], i == 0);
        }
        if (count) path_add(frames, count);
        LeaveCriticalSection(&sample_lock);
    }
    CloseHandle(h);
    return 0;
}
static void start_sampler(void) {
    IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)GetModuleHandleA(NULL);
    IMAGE_NT_HEADERS64 *nt = (IMAGE_NT_HEADERS64 *)((unsigned char *)dos + dos->e_lfanew);
    IMAGE_DATA_DIRECTORY *ex = &nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXCEPTION];
    img_base = (unsigned char *)dos;
    img_size = nt->OptionalHeader.SizeOfImage;
    if (!ex->VirtualAddress || !ex->Size) return;
    pdata = (RUNTIME_FUNCTION *)(img_base + ex->VirtualAddress);
    pdata_count = ex->Size / sizeof(RUNTIME_FUNCTION);
    InitializeCriticalSection(&sample_lock);
    main_thread_id = GetCurrentThreadId();
    AddVectoredExceptionHandler(1, sampler_guard);
    HANDLE th = CreateThread(NULL, 0, sampler_thread, NULL, 0, &sampler_tid);
    if (th) CloseHandle(th);
}
static void sample_dump(void) {
    if (!pdata) return;
    char line[200];
    EnterCriticalSection(&sample_lock);
    unsigned long total = sample_total;
    if (total == 0) { LeaveCriticalSection(&sample_lock); return; }
    snprintf(line, sizeof line, "SAMPLES %lu (%lu started outside the game's code)", total, sample_outside);
    test_log(line);
    for (int pass = 0; pass < 2; pass++) {
        for (int n = 0; n < (pass ? 15 : 30); n++) {
            int best = -1;
            for (int i = 0; i < SAMPLE_SLOTS; i++) {
                unsigned long v = pass ? samples[i].self : samples[i].incl;
                if (samples[i].rva && v && (best < 0 || v > (pass ? samples[best].self : samples[best].incl))) best = i;
            }
            if (best < 0) break;
            unsigned long v = pass ? samples[best].self : samples[best].incl;
            if (v * 100 < total) break;                  // under 1%: not worth listing
            snprintf(line, sizeof line, "SAMPLE %s 0x%06lx %5.1f%%", pass ? "self" : "incl", (unsigned long)samples[best].rva,
                     100.0 * v / total);
            test_log(line);
            if (pass) samples[best].self = 0; else samples[best].incl = 0;
        }
    }
    for (int n = 0; n < 12; n++) {                  // the busiest call paths (innermost first)
        int best = -1;
        for (int i = 0; i < PATH_SLOTS; i++) if (paths[i].n && (best < 0 || paths[i].n > paths[best].n)) best = i;
        if (best < 0 || paths[best].n * 50 < total) break;
        snprintf(line, sizeof line, "PATH %5.1f%% 0x%06lx < 0x%06lx < 0x%06lx < 0x%06lx < 0x%06lx", 100.0 * paths[best].n / total,
                 (unsigned long)paths[best].f[0], (unsigned long)paths[best].f[1], (unsigned long)paths[best].f[2],
                 (unsigned long)paths[best].f[3], (unsigned long)paths[best].f[4]);
        test_log(line);
        paths[best].n = 0;
    }
    memset(paths, 0, sizeof paths);
    memset(samples, 0, sizeof samples);
    sample_total = sample_outside = 0;
    LeaveCriticalSection(&sample_lock);
}

// --- Loose-file index: the engine probes every mod folder for every file, nearly always in vain. Each Data folder
// is listed once; reads of files it doesn't have fail at once. Writes, folders and other paths go to Windows as
// before. EngineHook_noindex.txt next to the DLL turns this off.
static int file_index_on;
#define MAX_ROOTS 24
static struct { char prefix[MAX_PATH]; char **set; DWORD cap, count; int ok; } roots[MAX_ROOTS];
static int root_count;
static CRITICAL_SECTION index_lock;
static unsigned long index_refused;              // opens answered from the index (nothing there)

static DWORD path_hash(const char *s) {
    DWORD h = 2166136261u;
    while (*s) h = (h ^ (unsigned char)*s++) * 16777619u;
    return h;
}
static void set_add(int r, const char *rel) {
    if (roots[r].count * 2 >= roots[r].cap) {    // grow (and rehash) at half full
        DWORD cap = roots[r].cap ? roots[r].cap * 2 : 8192;
        char **set = calloc(cap, sizeof *set);
        if (!set) { roots[r].ok = 0; return; }
        for (DWORD i = 0; i < roots[r].cap; i++) {
            char *s = roots[r].set[i];
            if (!s) continue;
            DWORD h = path_hash(s) & (cap - 1);
            while (set[h]) h = (h + 1) & (cap - 1);
            set[h] = s;
        }
        free(roots[r].set);
        roots[r].set = set;
        roots[r].cap = cap;
    }
    DWORD h = path_hash(rel) & (roots[r].cap - 1);
    while (roots[r].set[h]) {
        if (strcmp(roots[r].set[h], rel) == 0) return;
        h = (h + 1) & (roots[r].cap - 1);
    }
    roots[r].set[h] = _strdup(rel);
    roots[r].count++;
}
static int set_has(int r, const char *rel) {
    if (!roots[r].cap) return 0;
    DWORD h = path_hash(rel) & (roots[r].cap - 1);
    while (roots[r].set[h]) {
        if (strcmp(roots[r].set[h], rel) == 0) return 1;
        h = (h + 1) & (roots[r].cap - 1);
    }
    return 0;
}
// Lists every file under root r's folder (relative paths, lower case). Returns 0 if a folder could not be read.
static int list_folder(int r, char *rel, size_t rel_len) {
    char pattern[MAX_PATH * 2];
    snprintf(pattern, sizeof pattern, "%s%s*", roots[r].prefix, rel);
    WIN32_FIND_DATAA fd;
    HANDLE h = FindFirstFileExA(pattern, FindExInfoBasic, &fd, FindExSearchNameMatch, NULL, 2 /* large fetch */);
    if (h == INVALID_HANDLE_VALUE) return GetLastError() == ERROR_FILE_NOT_FOUND || GetLastError() == ERROR_PATH_NOT_FOUND;
    int ok = 1;
    do {
        if (!strcmp(fd.cFileName, ".") || !strcmp(fd.cFileName, "..")) continue;
        size_t n = strlen(fd.cFileName);
        if (rel_len + n + 2 >= MAX_PATH) { ok = 0; continue; }
        memcpy(rel + rel_len, fd.cFileName, n + 1);
        for (size_t i = rel_len; i < rel_len + n; i++) rel[i] = (char)tolower((unsigned char)rel[i]);
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
            rel[rel_len + n] = '\\';
            rel[rel_len + n + 1] = 0;
            ok &= list_folder(r, rel, rel_len + n + 1);
        } else {
            set_add(r, rel);
        }
        rel[rel_len] = 0;
    } while (FindNextFileA(h, &fd));
    FindClose(h);
    return ok;
}
// 1: the file is surely not there (answer at once); 0: ask Windows.
static int surely_missing(LPCSTR name, DWORD access, DWORD how, DWORD flags) {
    if (!file_index_on || !name || how != OPEN_EXISTING || (flags & FILE_FLAG_BACKUP_SEMANTICS)
        || (access & (GENERIC_WRITE | GENERIC_ALL | FILE_WRITE_DATA | FILE_APPEND_DATA | DELETE | WRITE_DAC | WRITE_OWNER)))
        return 0;
    char path[MAX_PATH], full[MAX_PATH * 2];
    if (!(name[0] && name[1] == ':') && name[0] != '\\' && name[0] != '/') {   // relative: from the game's folder
        DWORD cwd = GetCurrentDirectoryA(MAX_PATH, full);
        if (!cwd || cwd >= MAX_PATH) return 0;
        snprintf(full + cwd, sizeof full - cwd, "\\%s", name);
        name = full;
    }
    size_t n = 0;
    for (const char *s = name; *s; s++) {           // lower case, '/' -> '\', no doubled separators
        char ch = *s == '/' ? '\\' : (char)tolower((unsigned char)*s);
        if (ch == '\\' && n && path[n - 1] == '\\') continue;
        if (n + 1 >= sizeof path) return 0;
        path[n++] = ch;
    }
    path[n] = 0;
    if (n < 4 || path[1] != ':' || path[2] != '\\' || strstr(path, "..") || strchr(path + 2, ':')) return 0;
    char *data = strstr(path, "\\data\\");
    if (!data || !data[6]) return 0;
    size_t plen = (size_t)(data - path) + 6;
    char *rel = path + plen;
    int missing = 0;
    EnterCriticalSection(&index_lock);
    int r = -1;
    for (int i = 0; i < root_count; i++)
        if (strlen(roots[i].prefix) == plen && strncmp(roots[i].prefix, path, plen) == 0) { r = i; break; }
    if (r < 0 && root_count < MAX_ROOTS) {
        r = root_count++;
        memcpy(roots[r].prefix, path, plen);
        roots[r].prefix[plen] = 0;
        char buf[MAX_PATH] = "";
        roots[r].ok = 1;
        roots[r].ok = list_folder(r, buf, 0) && roots[r].ok;
        char line[MAX_PATH + 80];
        snprintf(line, sizeof line, "file index: %lu files in %s%s", (unsigned long)roots[r].count, roots[r].prefix,
                 roots[r].ok ? "" : " (not complete: not used)");
        log_line(line);
    }
    if (r >= 0 && roots[r].ok && !set_has(r, rel)) { missing = 1; index_refused++; }
    LeaveCriticalSection(&index_lock);
    return missing;
}

// File opens while profiling: how many, how many found nothing, the time they took, and the slowest ones.
static HANDLE (WINAPI *orig_create_file)(LPCSTR, DWORD, DWORD, LPSECURITY_ATTRIBUTES, DWORD, DWORD, HANDLE);
static unsigned long file_opens, file_misses;
static double file_ms, file_miss_ms;
static struct { double ms; char path[160]; } slow_files[6];
static HANDLE WINAPI hooked_create_file(LPCSTR name, DWORD access, DWORD share, LPSECURITY_ATTRIBUTES sa, DWORD how,
                                       DWORD flags, HANDLE tmpl) {
    if (surely_missing(name, access, how, flags)) {
        if (profile_on && GetFileAttributesA(name) != INVALID_FILE_ATTRIBUTES) {   // check the index (profiling)
            static int wrong;
            if (wrong++ < 50) {
                char line[MAX_PATH + 40];
                snprintf(line, sizeof line, "INDEX WRONG (file exists): %s", name);
                log_line(line);
            }
        }
        SetLastError(ERROR_FILE_NOT_FOUND);
        return INVALID_HANDLE_VALUE;
    }
    if (!profile_on) return orig_create_file(name, access, share, sa, how, flags, tmpl);
    double t0 = now_ms();
    HANDLE h = orig_create_file(name, access, share, sa, how, flags, tmpl);
    double ms = now_ms() - t0;
    if (GetCurrentThreadId() == main_thread_id) {
        DWORD err = GetLastError();
        file_opens++;
        file_ms += ms;
        if (h == INVALID_HANDLE_VALUE) { file_misses++; file_miss_ms += ms; }
        int slot = 0;
        for (int i = 1; i < 6; i++) if (slow_files[i].ms < slow_files[slot].ms) slot = i;
        if (ms > slow_files[slot].ms) {
            slow_files[slot].ms = ms;
            snprintf(slow_files[slot].path, sizeof slow_files[slot].path, "%s%s", h == INVALID_HANDLE_VALUE ? "(none) " : "",
                     name ? name : "?");
        }
        SetLastError(err);
    }
    return h;
}
static void file_dump(void) {
    if (!orig_create_file || (!file_opens && !index_refused)) return;
    char line[260];
    snprintf(line, sizeof line, "FILES %lu opened in %.0f ms; %lu not found (%.0f ms); %lu answered by the index",
             file_opens, file_ms, file_misses, file_miss_ms, index_refused);
    index_refused = 0;
    test_log(line);
    for (int i = 0; i < 6; i++) {
        if (slow_files[i].ms >= 5) {
            snprintf(line, sizeof line, "FILE %.0f ms %s", slow_files[i].ms, slow_files[i].path);
            test_log(line);
        }
        slow_files[i].ms = 0;
    }
    file_opens = file_misses = 0;
    file_ms = file_miss_ms = 0;
}

// --- AI map rebuilds at most every REBUILD_GAP_MS: each world changing hands rebuilds every AI planner's distance
// tables (0x4e4670), which stalls a large map's start. Further changes within the gap are batched into one rebuild.
// EngineHook_nodefer.txt next to the DLL turns this off.
#define RVA_GALAXY_UPDATE   0x3a6b80
#define RVA_REBUILD_PLANNERS 0x4e4670
#define REBUILD_GAP_MS      2000
static int defer_rebuild_on = 1;
static void (*orig_galaxy_update)(long long *, unsigned int, char);
static void (*orig_rebuild_planners)(void);
static int rebuild_pending;
static DWORD rebuild_last;
static unsigned long rebuilds_saved;
static void hooked_rebuild_planners(void) {
    DWORD now = GetTickCount();
    if (rebuild_last && now - rebuild_last < REBUILD_GAP_MS) {
        if (rebuild_pending) rebuilds_saved++;
        rebuild_pending = 1;
        return;
    }
    rebuild_pending = 0;
    rebuild_last = now;
    orig_rebuild_planners();
}
static void hooked_galaxy_update(long long *self, unsigned int a, char b) {
    if (rebuild_pending && GetTickCount() - rebuild_last >= REBUILD_GAP_MS) {
        rebuild_pending = 0;
        rebuild_last = GetTickCount();
        orig_rebuild_planners();
    }
    orig_galaxy_update(self, a, b);
}

// --- Shortest routes between all worlds (0x6913e0, Floyd-Warshall): the same procedure step for step, with the
// inner loop four columns at a time, so the tables come out identical. EngineHook_noroutes.txt turns this off;
// EngineHook_routecheck.txt runs both and logs any difference.
#define RVA_ALL_ROUTES 0x6913e0
static int fast_routes_on = 1, route_check_on;
static void (*orig_all_routes)(long long *);
static unsigned long routes_runs, route_checks, route_diffs;
static double routes_ms, routes_orig_ms;

static int route_count(long long *self) { return (int)((self[2] - self[1]) >> 4); }

static void route_row(int *rowi, int *predi, const int *rowk, const int *predk, int from, int to, int dik) {
    const __m128i none = _mm_set1_epi32(-1), sign = _mm_set1_epi32((int)0x80000000), via = _mm_set1_epi32(dik);
    int j = from;
    for (; j + 4 <= to; j += 4) {
        __m128i dkj = _mm_loadu_si128((const __m128i *)(rowk + j));
        __m128i dij = _mm_loadu_si128((const __m128i *)(rowi + j));
        __m128i sum = _mm_add_epi32(dkj, via);
        __m128i shorter = _mm_cmpgt_epi32(_mm_xor_si128(dij, sign), _mm_xor_si128(sum, sign));   // sum < dij, unsigned
        __m128i take = _mm_andnot_si128(_mm_cmpeq_epi32(dkj, none), shorter);
        if (_mm_movemask_epi8(take) == 0) continue;
        __m128i pij = _mm_loadu_si128((const __m128i *)(predi + j));
        __m128i pkj = _mm_loadu_si128((const __m128i *)(predk + j));
        _mm_storeu_si128((__m128i *)(rowi + j), _mm_or_si128(_mm_and_si128(take, sum), _mm_andnot_si128(take, dij)));
        _mm_storeu_si128((__m128i *)(predi + j), _mm_or_si128(_mm_and_si128(take, pkj), _mm_andnot_si128(take, pij)));
    }
    for (; j < to; j++) {
        int dkj = rowk[j];
        if (dkj != -1 && (unsigned)dkj + (unsigned)dik < (unsigned)rowi[j]) {
            rowi[j] = (int)((unsigned)dkj + (unsigned)dik);
            predi[j] = predk[j];
        }
    }
}

static void fast_all_routes(long long *self) {
    long long *vt = *(long long **)self;
    unsigned (*weight)(long long *, int) = (void *)vt[3];
    int (*lane)(long long *, int, int) = (void *)vt[2];
    int n = route_count(self);
    for (int i = 0; i < route_count(self); i++) {          // each world's own weight (the engine keeps it / 100)
        long long at = self[1];
        unsigned w = weight(self, i);
        *(unsigned *)(at + (long long)i * 16 + 8) = w / 100;
    }
    for (int i = 0; i < route_count(self); i++) {          // the direct lanes
        for (int j = 0; j < route_count(self); j++) {
            long long cell = (long long)i * n + j;
            if (i == j) {
                ((int *)self[5])[cell] = 0;
                ((int *)self[6])[cell] = -1;
            } else {
                int cost = lane(self, i, j);
                ((int *)self[5])[cell] = cost;
                ((int *)self[6])[cell] = cost == -1 ? -1 : i;
            }
        }
    }
    if (n <= 0) return;
    int *dist = (int *)self[5], *pred = (int *)self[6];
    for (int k = 0; k < n; k++) {
        const int *rowk = dist + (long long)k * n, *predk = pred + (long long)k * n;
        for (int i = 0; i < n; i++) {
            int *rowi = dist + (long long)i * n, *predi = pred + (long long)i * n;
            if (i == k) {                                   // row k against itself: one column at a time
                for (int j = 0; j < n; j++) {
                    int dik = rowi[k], dkj = rowk[j];
                    if (dik != -1 && dkj != -1 && (unsigned)dkj + (unsigned)dik < (unsigned)rowi[j]) {
                        rowi[j] = (int)((unsigned)dkj + (unsigned)dik);
                        predi[j] = predk[j];
                    }
                }
                continue;
            }
            int dik = rowi[k];
            if (dik == -1) continue;
            route_row(rowi, predi, rowk, predk, 0, k + 1, dik);
            dik = rowi[k];                                  // (column k itself may just have changed)
            route_row(rowi, predi, rowk, predk, k + 1, n, dik);
        }
    }
}

static void hooked_all_routes(long long *self) {
    if (!route_check_on) {
        double t0 = profile_on ? now_ms() : 0;
        fast_all_routes(self);
        if (profile_on) { routes_runs++; routes_ms += now_ms() - t0; }
        return;
    }
    double t0 = now_ms();
    orig_all_routes(self);
    double t1 = now_ms();
    int n = route_count(self);
    size_t bytes = (size_t)n * n * sizeof(int);
    int *dist = n > 0 ? malloc(bytes) : NULL, *pred = n > 0 ? malloc(bytes) : NULL;
    if (dist && pred) {
        memcpy(dist, (void *)self[5], bytes);
        memcpy(pred, (void *)self[6], bytes);
    }
    double t2 = now_ms();
    fast_all_routes(self);
    double t3 = now_ms();
    routes_runs++;
    routes_orig_ms += t1 - t0;
    routes_ms += t3 - t2;
    if (dist && pred) {
        route_checks++;
        if (memcmp(dist, (void *)self[5], bytes) || memcmp(pred, (void *)self[6], bytes)) {
            route_diffs++;
            char line[120];
            snprintf(line, sizeof line, "ROUTES DIFFER (%d worlds)", n);
            test_log(line);
        }
    }
    free(dist);
    free(pred);
}

// --- An AI's list of objects in reach (0x662710): the engine tests every pair through virtual calls. This asks
// once per object, skips objects the player doesn't know, then measures as 0x662b30 does; same list, same order.
// EngineHook_noreach.txt turns this off.
#define RVA_REACH_LIST   0x662710
#define RVA_PLAYER_BY_ID 0x294bc0
#define RVA_PLAYERS      0xa16fd0
#define RVA_KNOWS        0x4ad9f0
#define RVA_LANE_TO      0x3f7b30
#define RVA_SQRTF        0x776d48
#define RVA_PUSH_BACK    0x45580
#define RVA_OUT_OF_REACH 0x8b4700
#define RVA_REACH        0xb15908
#define RVA_LANE_SCALE   0xb1590c
static int fast_reach_on = 1;
static unsigned char *reach_base;
static void (*orig_reach_list)(long long, long long, long long);
static long long (*player_by_id)(void *, int);
static char (*knows)(void *, long long);
static char (*lane_to)(long long, long long, long long);
static float (*engine_sqrtf)(float);
static void *(*push_back)(long long, long long *, long long *);
static unsigned long reach_runs, reach_rows_skipped, reach_checks, reach_diffs;
static double reach_ms, reach_orig_ms;

typedef long long (*vcall_int_fn)(long long, int);
typedef long long (*vcall_fn)(long long);

static void fast_reach_list(long long ai, long long list, long long out) {
    long long player = player_by_id(reach_base + RVA_PLAYERS, *(int *)(ai + 0x80));
    if (!player) return;
    unsigned n = *(unsigned *)(list + 0x10);
    long long *items = *(long long **)(list + 8);
    if (n == 0 || !items) return;
    char *known = malloc(n);
    long long *comp = malloc(n * sizeof *comp);
    float *pos = malloc(n * 3 * sizeof *pos);
    int *count = calloc(n, sizeof *count);
    if (!known || !comp || !pos || !count) {
        free(known); free(comp); free(pos); free(count);
        orig_reach_list(ai, list, out);
        return;
    }
    for (unsigned i = 0; i < n; i++) {                     // per object, as 0x662b30 asks it per pair
        long long obj = items[i];
        long long c = ((vcall_int_fn)(*(long long **)obj)[2])(obj, 3);
        long long where = ((vcall_fn)(*(long long **)c)[0x98 / 8])(c);
        known[i] = knows((void *)where, player) != 0;
        comp[i] = c;
        pos[i * 3] = *(float *)(obj + 0x78);
        pos[i * 3 + 1] = *(float *)(obj + 0x7c);
        pos[i * 3 + 2] = *(float *)(obj + 0x80);
    }
    int both = *(char *)(ai + 0x84) != 0;
    double out_of_reach = *(double *)(reach_base + RVA_OUT_OF_REACH);
    float reach = *(float *)(reach_base + RVA_REACH);
    float scale = *(float *)(reach_base + RVA_LANE_SCALE);
    for (unsigned i = 0; i < n; i++) {
        if (!known[i]) { reach_rows_skipped++; continue; }
        long long a = items[i];
        for (unsigned j = 0; j < n; j++) {
            long long b = items[j];
            if (a == b || (both && !known[j])) continue;
            float dz = pos[i * 3 + 1] - pos[j * 3 + 1];
            float dist = engine_sqrtf((pos[i * 3] - pos[j * 3]) * (pos[i * 3] - pos[j * 3]) + dz * dz
                                      + (pos[i * 3 + 2] - pos[j * 3 + 2]) * (pos[i * 3 + 2] - pos[j * 3 + 2]));
            double d = (double)dist;
            if (lane_to(comp[j], a, b)) d = d / (double)scale;
            else if (reach < dist) d = out_of_reach;
            if (0.0 <= d) { count[i]++; count[j]++; }
        }
    }
    for (unsigned i = 0; i < n; i++) {                     // the objects counted, in the list's order
        if (!count[i]) continue;
        long long *end = *(long long **)(out + 8);
        if (end != *(long long **)(out + 0x10)) {
            *end = items[i];
            *(long long **)(out + 8) = end + 1;
        } else {
            push_back(out, end, &items[i]);
        }
    }
    free(known); free(comp); free(pos); free(count);
}

static void hooked_reach_list(long long ai, long long list, long long out) {
    if (!route_check_on) {
        double t0 = profile_on ? now_ms() : 0;
        fast_reach_list(ai, list, out);
        if (profile_on) { reach_runs++; reach_ms += now_ms() - t0; }
        return;
    }
    long long *start = *(long long **)(out + 8);           // the engine's list first, then the hook's over the same input
    double t0 = now_ms();
    orig_reach_list(ai, list, out);
    double t1 = now_ms();
    long long *end = *(long long **)(out + 8);
    size_t count = (size_t)(end - start);
    long long *engine = count ? malloc(count * sizeof *engine) : NULL;
    if (count && !engine) return;
    if (count) memcpy(engine, start, count * sizeof *engine);
    *(long long **)(out + 8) = start;                      // (plain pointers: the vector is only shortened again)
    double t2 = now_ms();
    fast_reach_list(ai, list, out);
    double t3 = now_ms();
    long long *now = *(long long **)(out + 8);
    reach_runs++;
    reach_checks++;
    reach_orig_ms += t1 - t0;
    reach_ms += t3 - t2;
    if ((size_t)(now - start) != count || (count && memcmp(engine, start, count * sizeof *engine))) {
        reach_diffs++;
        char line[120];
        snprintf(line, sizeof line, "REACH LIST DIFFERS (%zu engine, %zu hook)", count, (size_t)(now - start));
        test_log(line);
    }
    free(engine);
}

// --- AI production plans (0x725c50, 0x6bfcf0): a plan without a target reads the first entry of a list that can
// be empty on large maps (crash). Then the plan is skipped for now and scored 0. EngineHook_noplanguard.txt turns
// this off.
#define RVA_PLACE_PLAN 0x725c50
#define RVA_SCORE_PLAN 0x6bfcf0
#define RVA_CLEAR_PLAN 0xe5160
static int plan_guard_on = 1;
static void (*orig_place_plan)(long long, long long);
static void (*orig_score_plan)(long long);
static void (*clear_plan)(long long, int);
static unsigned long plans_skipped;

static int plan_without_place(long long goal) {          // the engine's own path to the list (0x725c85-0x725caa)
    if (!goal || *(long long *)(goal + 0x58) != 0) return 0;
    long long a = *(long long *)(goal + 0x90);
    long long b = a ? *(long long *)(a + 0x28) : 0;
    long long holder = b ? *(long long *)(b + 0x38) : 0;
    long long *entries = holder ? (long long *)((vcall_fn)(*(long long **)holder)[0x40 / 8])(holder) : NULL;
    return !entries || !entries[0] || entries[0] == entries[1];
}

static void hooked_place_plan(long long self, long long plan) {
    if (plan_without_place(*(long long *)(plan + 0x20))) {
        plans_skipped++;
        return;
    }
    orig_place_plan(self, plan);
}

static void hooked_score_plan(long long plan) {
    if (*(char *)(*(long long *)(plan + 0x50) + 0xa8) == 0 && *(int *)(plan + 0x198) == 0
        && plan_without_place(*(long long *)(plan + 0x20))) {
        plans_skipped++;
        *(int *)(plan + 0x48) = 0;                         // as the engine does for a plan it can't score
        clear_plan(plan + 0x180, 0);
        return;
    }
    orig_score_plan(plan);
}

// --- AI planning setup (0x4e2060): the pass test for each world (0x3f2400) is repeated with the same inputs within
// one setup, so its answers are cached for that setup. EngineHook_nosetupmemo.txt turns this off;
// EngineHook_routecheck.txt compares against the engine's test.
#define RVA_PERCEPTION_SETUP 0x4e2060
#define RVA_WORLD_SEARCH     0x665160
#define RVA_PASS_TEST        0x3f2400
#define PASS_SLOTS           (1 << 18)
static int setup_memo_on = 1;
static void (*orig_perception_setup)(long long);
static void (*orig_world_search)(long long, unsigned, char);
static char (*orig_pass_test)(long long, long long *);
static unsigned long setups, searches, searches_forced, pass_kept, pass_tested, pass_checks, pass_diffs;
static double setups_ms, searches_ms, setup_max_ms;
static DWORD setup_thread;                       // inside a setup (this thread only)
static unsigned setup_generation;
static struct { unsigned long long k1, k2, k3, k4, k5; unsigned gen; char answer; } *pass_memo;

static unsigned long long mix64(unsigned long long x) {
    x ^= x >> 33; x *= 0xff51afd7ed558ccdull; x ^= x >> 33; x *= 0xc4ceb9fe1a85ec53ull; x ^= x >> 33;
    return x;
}

static char hooked_pass_test(long long search, long long *holder) {
    if (!setup_thread || GetCurrentThreadId() != setup_thread || !pass_memo || !holder) {
        return orig_pass_test(search, holder);
    }
    const unsigned long long *keep = (const unsigned long long *)(search + 0x108);
    // what the test reads: the world, the player (+0x108) and the flags +0x120..+0x125 (0x3f2400, 0x3f2510, 0x3f18c0)
    unsigned long long k1 = (unsigned long long)*holder, k2 = keep[0], k3 = keep[3] & 0xffffffffffffull, k4 = 0, k5 = 0;
    unsigned i = (unsigned)(mix64(k1 ^ mix64(k2 ^ mix64(k3 ^ mix64(k4 ^ k5))))) & (PASS_SLOTS - 1);
    for (int n = 0; n < 64; n++, i = (i + 1) & (PASS_SLOTS - 1)) {
        if (pass_memo[i].gen != setup_generation) {              // free: test once, keep the answer
            char answer = orig_pass_test(search, holder);
            pass_memo[i].k1 = k1; pass_memo[i].k2 = k2; pass_memo[i].k3 = k3; pass_memo[i].k4 = k4; pass_memo[i].k5 = k5;
            pass_memo[i].gen = setup_generation;
            pass_memo[i].answer = answer;
            pass_tested++;
            return answer;
        }
        if (pass_memo[i].k1 == k1 && pass_memo[i].k2 == k2 && pass_memo[i].k3 == k3 && pass_memo[i].k4 == k4
            && pass_memo[i].k5 == k5) {
            char answer = pass_memo[i].answer;
            if (route_check_on) {
                pass_checks++;
                if (orig_pass_test(search, holder) != answer) {
                    pass_diffs++;
                    if (pass_diffs <= 20) test_log("PASS TEST DIFFERS");
                }
            }
            pass_kept++;
            return answer;
        }
    }
    return orig_pass_test(search, holder);                        // (the table is full here: just test)
}

static void hooked_perception_setup(long long self) {
    double t0 = profile_on ? now_ms() : 0;
    int memo = setup_memo_on && !setup_thread && (pass_memo || (pass_memo = calloc(PASS_SLOTS, sizeof *pass_memo)));
    if (memo) {
        setup_generation++;
        if (setup_generation == 0) {                                // (wrapped: every slot free again)
            memset(pass_memo, 0, (size_t)PASS_SLOTS * sizeof *pass_memo);
            setup_generation = 1;
        }
        setup_thread = GetCurrentThreadId();
    }
    orig_perception_setup(self);
    if (memo) setup_thread = 0;
    if (profile_on) {
        double ms = now_ms() - t0;
        setups++;
        setups_ms += ms;
        if (ms > setup_max_ms) setup_max_ms = ms;
    }
}
static void hooked_world_search(long long self, unsigned kind, char force) {
    double t0 = now_ms();
    orig_world_search(self, kind, force);
    searches++;
    if (force) searches_forced++;
    searches_ms += now_ms() - t0;
}

// --- Shortest paths of a distance table (0x662140): the same Floyd-Warshall, row by row instead of column by
// column (faster on large tables, same results). EngineHook_nopaths.txt turns this off.
#define RVA_DIST_PATHS 0x662140
typedef struct { unsigned rows, cols; void *data; } engine_matrix;
static int fast_paths_on = 1;
static long long (*orig_dist_paths)(engine_matrix *, engine_matrix *, engine_matrix *);
static unsigned long paths_runs, paths_checks, paths_diffs;
static double paths_ms, paths_orig_ms;

static int fast_dist_paths(engine_matrix *in, engine_matrix *dist_m, engine_matrix *pred_m) {
    unsigned n = in->rows;
    if (n != in->cols || n != dist_m->rows || n != dist_m->cols || n != pred_m->rows || n != pred_m->cols)
        return -1;                                     // (the engine returns 0 then: let it)
    if (n == 0) return 1;
    double *d = dist_m->data;
    unsigned *pr = pred_m->data;
    if (!d || !pr || !in->data) return -1;
    for (unsigned k = 0; k < n; k++)                    // the diagonal must be 0 for the order not to matter
        if (((double *)in->data)[(size_t)k * n + k] != 0.0) return -1;
    memcpy(d, in->data, (size_t)n * n * sizeof(double));
    for (unsigned k = 0; k < n; k++) {
        const double *rowk = d + (size_t)k * n;
        for (unsigned i = 0; i < n; i++) {
            double *rowi = d + (size_t)i * n;
            double dik = rowi[k];
            if (!(0.0 <= dik)) continue;
            unsigned *predi = pr + (size_t)i * n;
            unsigned pik = predi[k];
            for (unsigned j = 0; j < n; j++) {
                double dkj = rowk[j];
                if (!(0.0 <= dkj)) continue;
                double sum = dik + dkj;
                double dij = rowi[j];
                if (dij < 0.0 || sum < dij) {
                    rowi[j] = sum;
                    predi[j] = pik;
                }
            }
        }
    }
    return 1;
}

static long long hooked_dist_paths(engine_matrix *in, engine_matrix *dist_m, engine_matrix *pred_m) {
    if (!route_check_on) {
        double t0 = profile_on ? now_ms() : 0;
        int r = fast_dist_paths(in, dist_m, pred_m);
        if (r < 0) return orig_dist_paths(in, dist_m, pred_m);
        if (profile_on) { paths_runs++; paths_ms += now_ms() - t0; }
        return 1;
    }
    unsigned n = pred_m->rows * pred_m->cols;
    unsigned *pred0 = n ? malloc((size_t)n * sizeof(unsigned)) : NULL;
    if (n && (!pred0 || !pred_m->data)) { free(pred0); return orig_dist_paths(in, dist_m, pred_m); }
    if (n) memcpy(pred0, pred_m->data, (size_t)n * sizeof(unsigned));
    double t0 = now_ms();
    long long r = orig_dist_paths(in, dist_m, pred_m);
    double t1 = now_ms();
    size_t dn = (size_t)dist_m->rows * dist_m->cols;
    double *d_engine = dn ? malloc(dn * sizeof(double)) : NULL;
    unsigned *p_engine = n ? malloc((size_t)n * sizeof(unsigned)) : NULL;
    if (r && dn && d_engine && p_engine && dist_m->data) {
        memcpy(d_engine, dist_m->data, dn * sizeof(double));
        memcpy(p_engine, pred_m->data, (size_t)n * sizeof(unsigned));
        memcpy(pred_m->data, pred0, (size_t)n * sizeof(unsigned));
        double t2 = now_ms();
        int done = fast_dist_paths(in, dist_m, pred_m);
        paths_ms += now_ms() - t2;
        paths_orig_ms += t1 - t0;
        paths_runs++;
        if (done > 0) {
            paths_checks++;
            if (memcmp(d_engine, dist_m->data, dn * sizeof(double)) || memcmp(p_engine, pred_m->data, (size_t)n * sizeof(unsigned))) {
                paths_diffs++;
                if (paths_diffs <= 20) test_log("DISTANCE PATHS DIFFER");
            }
        }
        memcpy(dist_m->data, d_engine, dn * sizeof(double));     // (the engine's own result stands)
        memcpy(pred_m->data, p_engine, (size_t)n * sizeof(unsigned));
    }
    free(pred0); free(d_engine); free(p_engine);
    return r;
}

// Engine work timed while profiling: 0x662c90 builds a player's table of distances between its objects (its
// pairwise loop dominated campaign start), 0x18d9f0 creates a texture from a file in memory (D3DX).
#define RVA_DISTANCE_TABLE  0x662c90
#define RVA_MAKE_TEXTURE    0x18d9f0
static void (*orig_distance_table)(unsigned char *);
static int (*orig_make_texture)(unsigned char *);
static unsigned long tables, textures, table_count[128];
static double table_ms[128];
static double tables_ms, textures_ms, textures_max;
static unsigned long textures_bytes;
static const char *player_name(int id);
static void hooked_distance_table(unsigned char *self) {
    double t0 = now_ms();
    orig_distance_table(self);
    double ms = now_ms() - t0;
    tables++;
    tables_ms += ms;
    int who = *(int *)(self + 0x80);
    if (who >= 0 && who < 128) { table_count[who]++; table_ms[who] += ms; }
    if (ms >= 100) {
        char line[160];
        snprintf(line, sizeof line, "DISTANCE TABLE %.0f ms for %s", ms, player_name(*(int *)(self + 0x80)));
        test_log(line);
    }
}
static int hooked_make_texture(unsigned char *self) {
    double t0 = now_ms();
    unsigned int *src = *(unsigned int **)(self + 0x70);
    int r = orig_make_texture(self);
    double ms = now_ms() - t0;
    textures++;
    textures_ms += ms;
    if (ms > textures_max) textures_max = ms;
    if (src) textures_bytes += src[4];
    return r;
}
static void engine_work_dump(void) {
    char line[200];
    if (tables) {
        snprintf(line, sizeof line, "DISTANCE TABLES %lu built in %.0f ms", tables, tables_ms);
        test_log(line);
        for (int n = 0; n < 10; n++) {             // the players that built the most
            int best = -1;
            for (int i = 0; i < 128; i++) if (table_count[i] && (best < 0 || table_ms[i] > table_ms[best])) best = i;
            if (best < 0) break;
            snprintf(line, sizeof line, "DISTANCE TABLES of %s: %lu in %.0f ms", player_name(best), table_count[best],
                     table_ms[best]);
            test_log(line);
            table_count[best] = 0;
        }
        memset(table_count, 0, sizeof table_count);
        memset(table_ms, 0, sizeof table_ms);
    }
    if (textures) {
        snprintf(line, sizeof line, "TEXTURES %lu made in %.0f ms (slowest %.0f ms, %lu MB of files)", textures, textures_ms,
                 textures_max, textures_bytes >> 20);
        test_log(line);
    }
    if (routes_runs) {
        if (route_check_on)
            snprintf(line, sizeof line, "ROUTE TABLES %lu: engine %.0f ms, hook %.0f ms; checked %lu, differing %lu",
                     routes_runs, routes_orig_ms, routes_ms, route_checks, route_diffs);
        else
            snprintf(line, sizeof line, "ROUTE TABLES %lu in %.0f ms", routes_runs, routes_ms);
        test_log(line);
        routes_runs = 0;
        routes_ms = routes_orig_ms = 0;
    }
    if (paths_runs) {
        if (route_check_on)
            snprintf(line, sizeof line, "DISTANCE PATHS %lu: engine %.0f ms, hook %.0f ms; checked %lu, differing %lu",
                     paths_runs, paths_orig_ms, paths_ms, paths_checks, paths_diffs);
        else
            snprintf(line, sizeof line, "DISTANCE PATHS %lu in %.0f ms", paths_runs, paths_ms);
        test_log(line);
        paths_runs = 0;
        paths_ms = paths_orig_ms = 0;
    }
    if (setups || searches) {
        snprintf(line, sizeof line, "PLANNING SETUPS %lu in %.0f ms (longest %.0f); world searches %lu (%lu forced) in %.0f ms;"
                 " pass tests %lu, %lu answers kept%s", setups, setups_ms, setup_max_ms, searches, searches_forced,
                 searches_ms, pass_tested, pass_kept, route_check_on ? "" : "");
        test_log(line);
        if (route_check_on) {
            snprintf(line, sizeof line, "PASS TESTS checked %lu, differing %lu", pass_checks, pass_diffs);
            test_log(line);
        }
        setups = searches = searches_forced = pass_tested = pass_kept = 0;
        setups_ms = searches_ms = setup_max_ms = 0;
    }
    if (reach_runs) {
        if (route_check_on)
            snprintf(line, sizeof line, "REACH LISTS %lu: engine %.0f ms, hook %.0f ms; checked %lu, differing %lu",
                     reach_runs, reach_orig_ms, reach_ms, reach_checks, reach_diffs);
        else
            snprintf(line, sizeof line, "REACH LISTS %lu in %.0f ms (%lu rows of unknown objects skipped)", reach_runs,
                     reach_ms, reach_rows_skipped);
        test_log(line);
        reach_runs = reach_rows_skipped = 0;
        reach_ms = reach_orig_ms = 0;
    }
    if (plans_skipped) {
        snprintf(line, sizeof line, "PRODUCTION PLANS without a place left for later: %lu", plans_skipped);
        test_log(line);
        plans_skipped = 0;
    }
    if (rebuilds_saved) {
        snprintf(line, sizeof line, "PLANNER REBUILDS saved: %lu", rebuilds_saved);
        test_log(line);
        rebuilds_saved = 0;
    }
    tables = textures = textures_bytes = 0;
    tables_ms = textures_ms = textures_max = 0;
}

// Every PROFILE_DUMP_MS: the busiest named calls and thread steps of the window, then their totals start again.
static void profile_dump(void) {
    static double last;
    double now = now_ms();
    if (last == 0) { last = now; return; }
    if (now - last < PROFILE_DUMP_MS) return;
    char line[300];
    snprintf(line, sizeof line, "---- profile: last %.0f s, garbage collection %.0f ms in %lu runs ----",
             (now - last) / 1000, gc_ms, gc_count);
    gc_ms = 0;
    gc_count = 0;
    test_log(line);
    last = now;
    for (int n = 0; n < 15; n++) {
        int best = -1;
        for (int i = 0; i < MAX_CALLS; i++)
            if (calls[i].script && calls[i].total > 0 && (best < 0 || calls[i].total > calls[best].total)) best = i;
        if (best < 0) break;
        snprintf(line, sizeof line, "PROF call %-34s %-40s %8.1f ms  max %7.1f  calls %lu", calls[best].name,
                 calls[best].src, calls[best].total, calls[best].max, calls[best].count);
        test_log(line);
        calls[best].total = -calls[best].total;          // (listed: skipped by the next pick)
    }
    for (int i = 0; i < MAX_CALLS; i++) { calls[i].total = 0; calls[i].max = 0; calls[i].count = 0; }
    for (int n = 0; n < 15; n++) {
        int best = -1;
        for (int i = 0; i < MAX_PROF; i++)
            if (prof_steps[i].src[0] && prof_steps[i].total > 0 && (best < 0 || prof_steps[i].total > prof_steps[best].total))
                best = i;
        if (best < 0) break;
        snprintf(line, sizeof line, "PROF step %-60s %8.1f ms  max %7.1f  steps %lu", prof_steps[best].src,
                 prof_steps[best].total, prof_steps[best].max, prof_steps[best].count);
        test_log(line);
        prof_steps[best].total = -prof_steps[best].total;
    }
    for (int i = 0; i < MAX_PROF; i++) { prof_steps[i].total = 0; prof_steps[i].max = 0; prof_steps[i].count = 0; }
    sample_dump();
    file_dump();
    lua_profile_dump();
    engine_work_dump();
}

// Called on every pumped window message: a gap of STALL_MS or more since the last one is a stall (logged with the
// slowest single script call in it); then the periodic dump.
static void profile_tick(void) {
    static double last;
    double now = now_ms();
    if (last != 0 && now - last >= STALL_MS) {
        char line[260];
        snprintf(line, sizeof line, "STALL %.0f ms; slowest script call in it: %s", now - last,
                 slowest_ms > 0 ? slowest : "none (the engine itself)");
        test_log(line);
    }
    last = now;
    slowest_ms = 0;
    profile_dump();
}

static void watch_thread(lua_State *L) {
    DWORD now = GetTickCount();
    int slot = -1;
    for (int i = 0; i < MAX_THREADS; i++) {
        if (threads[i].L == L) { slot = i; break; }
        if (slot < 0 && !threads[i].L) slot = i;
    }
    if (slot >= 0 && threads[slot].L != L && threads[slot].L) slot = -1;
    if (slot < 0) {                           // full: reuse the thread that ran least recently
        // full: reuse the least recently run short-lived thread (long-lived ones, like a campaign's
        // main script, stay listed so a stalled one shows its growing idle time)
        slot = -1;
        for (int i = 0; i < MAX_THREADS; i++)
            if (threads[i].runs < 50 && (slot < 0 || threads[i].last_run < threads[slot].last_run)) slot = i;
        if (slot < 0) slot = 0;
        threads[slot].runs = 0;
    }
    if (threads[slot].L != L) threads[slot].runs = 0;
    {
        threads[slot].L = L;
        threads[slot].last_run = now;
        threads[slot].runs++;
        describe_stack(L, threads[slot].where, sizeof threads[slot].where);
    }
    if (now - last_dump >= 5000) {
        last_dump = now;
        test_log("---- script threads ----");
        for (int i = 0; i < MAX_THREADS; i++) {
            if (!threads[i].L) continue;
            char line[600];
            snprintf(line, sizeof line, "thread %p  runs %lu  idle %lus  at %s", threads[i].L, threads[i].runs,
                     (now - threads[i].last_run) / 1000, threads[i].where);
            test_log(line);
        }
        test_log("---- named script calls ----");
        for (int i = 0; i < MAX_CALLS; i++) {
            if (!calls[i].script) continue;
            char line[200];
            snprintf(line, sizeof line, "script %p  %-40s  calls %lu  idle %lus", calls[i].script, calls[i].name,
                     calls[i].count, (now - calls[i].last) / 1000);
            test_log(line);
        }
    }
}

static int hooked_lua_resume(lua_State *L, int nargs, void *extra) {
    if (profile_on) lua_profile_state(L);
    double t0 = profile_on ? now_ms() : 0;
    script_depth++;
    lua_State *outer_thread = running_thread;
    running_thread = L;
    int status = orig_lua_resume(L, nargs, extra);
    running_thread = outer_thread;
    script_depth--;
    if (profile_on && lua_getstack_fn && lua_getinfo_fn) {
        double ms = now_ms() - t0;
        lua_Debug ar;
        char src[64] = "(finished or in the engine)";
        char outer[48] = "", inner[40] = "";
        for (int level = 0; level < 24 && lua_getstack_fn(L, level, &ar); level++) {   // innermost and outermost Lua
            memset(&ar.name, 0, offsetof(lua_Debug, i_ci) - offsetof(lua_Debug, name));
            if (!lua_getinfo_fn(L, "Sl", &ar)) break;
            if (strcmp(ar.short_src, "[C]") == 0) continue;
            const char *file = strrchr(ar.short_src, '/');
            file = file ? file + 1 : ar.short_src;
            if (!inner[0]) snprintf(inner, sizeof inner, "%s:%d", file, ar.currentline);
            snprintf(outer, sizeof outer, "%s", file);
        }
        if (inner[0]) snprintf(src, sizeof src, "%s @ %s", outer, inner);
        prof_step(src, ms);
        note_slow("thread step", src, ms);
    }
    if (lua_getstack_fn && thread_watch_on) watch_thread(L);
    if (status != 0) {
        const char *msg = lua_tostring_fn ? lua_tostring_fn(L, -1) : NULL;
        char buf[1200];
        char where[400];
        if (lua_getstack_fn) describe_stack(L, where, sizeof where); else where[0] = 0;
        snprintf(buf, sizeof buf, "SCRIPT THREAD FAILED (status %d, thread %p): %.600s  at %s", status, L,
                 msg ? msg : "(no message)", where);
        test_log(buf);
        test_log_flush();
        log_line(buf);
    }
    return status;
}

// --- Allied fleets join space battles ----------------------------------------------------------
// After 0x2ad100 picks the fleets of the attacker and defender, fleets of the defender's allies at war with the
// attacker are added to the defender's side.
#define RVA_BUILD_SIDES     0x2ad100    // (conflict manager, defender list, attacker list)
#define RVA_OBJECT_BY_ID    0x2aca60    // (conflict manager, object id) -> object
#define RVA_VECTOR_GROW     0x047aa0    // DynamicVectorClass<T*>::Resize(new capacity, 0, 1)
typedef struct { void *vtable; void **items; int count; int capacity; } DynVec;   // count +0x10, capacity +0x14
static unsigned long long (*orig_build_sides)(unsigned char *, DynVec *, DynVec *);
static unsigned char *(*object_by_id)(unsigned char *, int);
static void (*vector_grow)(DynVec *, unsigned, char, char);

static int relation(int from_id, int to_id) {     // 1 = enemy, 0 = ally, -1 = unknown
    unsigned char *player = get_player_by_id(module_base + RVA_PLAYER_LIST, from_id);
    if (!player) return -1;
    int *table = *(int **)(player + 0x370);
    return table ? table[to_id] : -1;
}

// A player's faction name: player+0x68 -> faction type, whose first member is its name (MSVC std::string).
static const char *player_name(int id) {
    unsigned char *player = get_player_by_id(module_base + RVA_PLAYER_LIST, id);
    if (!player || !*(unsigned char **)(player + 0x68)) return "?";
    unsigned char *str = *(unsigned char **)(player + 0x68);
    unsigned long long cap = *(unsigned long long *)(str + 0x18);
    return cap > 0xf ? *(const char **)str : (const char *)str;
}

#define RVA_OBJECT_TYPE     0x3973b0    // GameObject -> GameObjectType (name: std::string at +0xf8)
static unsigned char *(*object_type)(unsigned char *);
static const char *std_string(unsigned char *str) {
    return *(unsigned long long *)(str + 0x18) > 0xf ? *(const char **)str : (const char *)str;
}
static const char *type_name(unsigned char *object) {
    unsigned char *type = object_type ? object_type(object) : NULL;
    return type ? std_string(type + 0xf8) : "?";
}
// "N: type, type, ..." for a galactic fleet (container at +0xc0: items +0x10, count +0x18), nested once.
static void fleet_contents(unsigned char *fleet, char *out, size_t size) {
    unsigned char *box = *(unsigned char **)(fleet + 0xc0);
    size_t used = 0;
    out[0] = 0;
    if (!box) { snprintf(out, size, "(single object %s)", type_name(fleet)); return; }
    int n = *(int *)(box + 0x18);
    used += snprintf(out, size, "%d:", n);
    for (int i = 0; i < n && used < size - 60; i++) {
        unsigned char *item = (*(unsigned char ***)(box + 0x10))[i];
        if (!item) continue;
        used += snprintf(out + used, size - used, " %s", type_name(item));
        unsigned char *inner = *(unsigned char **)(item + 0xc0);
        if (inner && *(int *)(inner + 0x18) > 0) used += snprintf(out + used, size - used, "[%d]", *(int *)(inner + 0x18));
    }
}

// Orbital structures of an ally that joins a battle: the engine spawns the planet's orbital special
// structures for the defender; these are given back to their real owner in hooked_battle_spawn.
#define MAX_FIX 16
static struct { unsigned char *type; int owner; } owner_fix[MAX_FIX];
static int owner_fix_count;
// Starbase: if an ally owns the planet's starbase, it is spawned for the ally (0x407b60).
static int starbase_ally = -1;
#define RVA_STARBASE_TYPE   0x407b60
static unsigned char *(*orig_starbase_type)(void *, int, void *, int);
static unsigned char *hooked_starbase_type(void *types, int level, void *faction, int category) {
    if (category == 0x5c && starbase_ally >= 0) {
        unsigned char *ally = get_player_by_id(module_base + RVA_PLAYER_LIST, starbase_ally);
        if (ally && *(void **)(ally + 0x68)) {
            unsigned char *type = orig_starbase_type(types, level, *(void **)(ally + 0x68), category);
            if (!type) type = orig_starbase_type(types, level, faction, category);   // none for the ally's faction
            if (type && owner_fix_count < MAX_FIX) {
                owner_fix[owner_fix_count].type = type;
                owner_fix[owner_fix_count].owner = starbase_ally;
                owner_fix_count++;
                char line[200];
                snprintf(line, sizeof line, "BATTLE: %s starbase %s (level %d) will fight under its own owner",
                         player_name(starbase_ally), std_string(type + 0xf8), level);
                test_log(line);
            }
            starbase_ally = -1;
            if (type) return type;
        }
    }
    return orig_starbase_type(types, level, faction, category);
}

static void note_ally_structures(unsigned char *manager, unsigned char *planet, int attacker, int defender) {
    (void)manager;
    owner_fix_count = 0;
    starbase_ally = -1;
    unsigned char *sys = *(unsigned char **)(planet + 0xb8);
    if (!sys) return;
    int base_owner = *(int *)(sys + 0x13c);
    if (*(int *)(sys + 0x148) > 0 && base_owner >= 0 && base_owner != defender && base_owner != attacker
        && relation(defender, base_owner) == 0 && relation(base_owner, attacker) == 1) {
        starbase_ally = base_owner;
    }
    for (int list = 0; list < 2; list++) {
        unsigned char **items = *(unsigned char ***)(sys + (list ? 0x170 : 0x158));
        int count = *(int *)(sys + (list ? 0x178 : 0x160));
        for (int i = 0; items && i < count && owner_fix_count < MAX_FIX; i++) {
            unsigned char *object = items[i];
            if (!object) continue;
            int owner = *(int *)(object + 0x58);
            if (owner == defender || owner == attacker || owner < 0) continue;
            if (relation(defender, owner) != 0 || relation(owner, attacker) != 1) continue;
            unsigned char *type = object_type ? object_type(object) : NULL;
            if (!type) continue;
            unsigned char *tactical = *(unsigned char **)(type + 0x8d0);
            owner_fix[owner_fix_count].type = tactical ? tactical : type;
            owner_fix[owner_fix_count].owner = owner;
            owner_fix_count++;
            char line[200];
            snprintf(line, sizeof line, "BATTLE: %s structure %s will fight under its own owner", player_name(owner),
                     std_string((tactical ? tactical : type) + 0xf8));
            test_log(line);
        }
    }
}

static void push(DynVec *vec, void *item) {
    int cap = (vec->capacity * 2) >> 1;
    if (cap <= vec->count) {
        int extra = cap / 10 < 10 ? 10 : cap / 10;
        vector_grow(vec, extra + cap, 0, 1);
    }
    vec->items[vec->count++] = item;
}

// Allies that join a battle stay allied on the battle map (keep_battle_allies, frame tick).
#define MAX_BATTLE_ALLIES 8
static int battle_allies[MAX_BATTLE_ALLIES][2];
static int battle_ally_count;

static void set_relation_entry(int from_id, int to_id, int value) {
    unsigned char *player = get_player_by_id(module_base + RVA_PLAYER_LIST, from_id);
    int *table = player ? *(int **)(player + 0x370) : NULL;
    if (table && table[to_id] != value) table[to_id] = value;
}

static void keep_battle_allies(void) {
    if (!get_player_by_id) return;
    for (int i = 0; i < battle_ally_count; i++) {
        set_relation_entry(battle_allies[i][0], battle_allies[i][1], 0);
        set_relation_entry(battle_allies[i][1], battle_allies[i][0], 0);
    }
}

static void note_battle_ally(int defender, int ally) {
    for (int i = 0; i < battle_ally_count; i++)
        if (battle_allies[i][0] == defender && battle_allies[i][1] == ally) return;
    if (battle_ally_count < MAX_BATTLE_ALLIES) {
        battle_allies[battle_ally_count][0] = defender;
        battle_allies[battle_ally_count][1] = ally;
        battle_ally_count++;
    }
}

static unsigned long long hooked_build_sides(unsigned char *manager, DynVec *defenders, DynVec *attackers) {
    unsigned long long result = orig_build_sides(manager, defenders, attackers);
    if (*(int *)(manager + 0x478) == 0 || !get_player_by_id || !diplomacy_loaded()) return result;
    int *record = *(int **)(manager + 0x470);
    int attacker = record[1], defender = record[2];
    unsigned char *planet = object_by_id(manager, record[0]);
    if (!planet || !*(unsigned char **)(planet + 0xb8)) return result;
    DynVec *orbit = (DynVec *)(*(unsigned char **)(planet + 0xb8) + 0xc0);
    char head[160];
    static int last_attacker = -2, last_defender = -2, last_count = -1;
    int quiet = attacker == last_attacker && defender == last_defender && orbit->count == last_count;
    last_attacker = attacker; last_defender = defender; last_count = orbit->count;
    snprintf(head, sizeof head, "BATTLE SIDES: attacker %d %s defender %d %s, %d objects in orbit, lists def %d att %d",
             attacker, player_name(attacker), defender, player_name(defender), orbit->count, defenders->count,
             attackers->count);
    if (!quiet) {
        battle_ally_count = 0;        // a new conflict: its own allies
        test_log(head);
        unsigned char *local = get_local_player(module_base + RVA_PLAYER_LIST);
        int human = local ? *(int *)(local + 0x4c) : -1;
        if (inbound_unsettled) {
            // the engine looks at a world again right after a battle (a retreat): the last battle's fleets are
            // settled first, so its list is kept until then
            test_log("INBOUND: the last battle's fleets are not settled yet; its list is kept");
        } else if (defender == human || attacker == human) {
            human_retreated = 0;
            retreat_reset();
            battle_attacker = attacker;
            battle_defender = defender;
            note_inbound(planet, attacker, defender);
        }
        else if (!inbound_unsettled) inbound_count = 0;
        unsigned char *sys = *(unsigned char **)(planet + 0xb8);
        snprintf(head, sizeof head, "  orbit record +0x130..: %d %d %d %d | +0x140 %p | +0x148 %d +0x14c %d",
                 *(int *)(sys + 0x130), *(int *)(sys + 0x134), *(int *)(sys + 0x138), *(int *)(sys + 0x13c),
                 *(void **)(sys + 0x140), *(int *)(sys + 0x148), *(int *)(sys + 0x14c));
        test_log(head);
    }
    for (int i = 0; i < orbit->count; i++) {
        unsigned char *object = orbit->items[i];
        if (!object) continue;
        int owner = *(int *)(object + 0x58);
        char line[200];
        snprintf(line, sizeof line, "  object %p owner %d %s flags %02x rel(def->owner) %d rel(owner->att) %d",
                 object, owner, player_name(owner), *(unsigned char *)(object + 0x3a0),
                 relation(defender, owner), relation(owner, attacker));
        if (!quiet) {
            test_log(line);
            char contents[700];
            fleet_contents(object, contents, sizeof contents);
            snprintf(line, sizeof line, "    contents %.180s", contents);
            test_log(line);
        }
        if (*(unsigned char *)(object + 0x3a0) & 2) continue;
        if (owner == attacker || owner == defender || owner < 0) continue;
        // only into battles the human fights in: an AI-only battle with an added side is never resolved
        unsigned char *local = get_local_player(module_base + RVA_PLAYER_LIST);
        int human = local ? *(int *)(local + 0x4c) : -1;
        if ((defender == human || attacker == human) && relation(defender, owner) == 0 && relation(owner, attacker) == 1) {
            push(defenders, object);
            note_battle_ally(defender, owner);
            char line[160];
            snprintf(line, sizeof line, "BATTLE: player %d joins defender %d against attacker %d", owner, defender, attacker);
            test_log(line);
            log_line(line);
        } else if ((attacker == human || defender == human) && relation(attacker, owner) == 0
                   && relation(owner, defender) == 1) {
            // an ally of the attacker in orbit (the human's escort or requested fleet, or an enemy's ally): it attacks too
            push(attackers, object);
            note_battle_ally(attacker, owner);
            char line[160];
            snprintf(line, sizeof line, "BATTLE: player %d joins attacker %d against defender %d", owner, attacker, defender);
            test_log(line);
            log_line(line);
        }
    }
    {
        unsigned char *local = get_local_player(module_base + RVA_PLAYER_LIST);
        int human = local ? *(int *)(local + 0x4c) : -1;
        if (defender == human || attacker == human) note_ally_structures(manager, planet, attacker, defender);
        else { owner_fix_count = 0; starbase_ally = -1; }
    }
    return result;
}

// Space battle start (0x2af7c0): when the human has ships there with an ally, the human is made the defender, so
// the usual battle prompt appears and the ally joins.
#define RVA_START_SPACE_BATTLE 0x2af7c0
static void (*orig_start_space_battle)(unsigned char *, unsigned char *, int, int, void *, long long, long long, long long);
static void hooked_start_space_battle(unsigned char *manager, unsigned char *planet, int attacker, int defender,
                                      void *name, long long flag, long long x7, long long x8) {
    note_battle_planet(planet);
    unsigned char *local = get_local_player ? get_local_player(module_base + RVA_PLAYER_LIST) : NULL;
    if (defender == -1 && local && planet && *(unsigned char **)(planet + 0xb8) && diplomacy_loaded()) {
        int human = *(int *)(local + 0x4c);
        DynVec *orbit = (DynVec *)(*(unsigned char **)(planet + 0xb8) + 0xc0);
        int human_there = 0, ally_there = 0;
        for (int i = 0; i < orbit->count; i++) {
            unsigned char *object = orbit->items[i];
            if (!object) continue;
            int owner = *(int *)(object + 0x58);
            if (owner == human) human_there = 1;
            else if (owner != attacker && owner >= 0 && relation(human, owner) == 0 && relation(owner, attacker) == 1)
                ally_there = 1;
        }
        if (human != attacker && human_there && ally_there && relation(human, attacker) == 1) {
            char line[160];
            snprintf(line, sizeof line, "BATTLE START: human %d made defender against %s (ally in orbit)", human,
                     player_name(attacker));
            test_log(line);
            log_line(line);
            defender = human;
        }
    }
    orig_start_space_battle(manager, planet, attacker, defender, name, flag, x7, x8);
}

// Diagnostic: every object the engine creates for a battle (0x29f810: manager, type, owner id, position,
// facing, flags...). Logged as "SPAWN <type> for <faction>".
#define RVA_BATTLE_SPAWN    0x29f810
// a6.. are passed through as full 64-bit stack slots (declaring them narrower truncated whatever the
// engine passes there, which stalled every script after a Lua Spawn_Unit in battle.
typedef long long ll;
static long long *(*orig_battle_spawn)(void *, unsigned char *, int, void *, void *, ll, ll, ll, ll, ll);
// Engine_Spawn_Facing(dx, dy): units spawned in battle face that way until Engine_Spawn_Facing().
static int spawn_facing_on;
static float spawn_yaw;
static long long *hooked_battle_spawn(void *manager, unsigned char *type, int owner, void *pos, void *facing,
                                      ll a6, ll a7, ll a8, ll a9, ll a10) {
    float turned[4];
    if (spawn_facing_on && facing) {
        turned[0] = turned[1] = 0;           // level: the engine's roll and pitch (towards the map centre) tilted some ships
        turned[2] = spawn_yaw;
        turned[3] = 0;
        facing = turned;
    }
    for (int i = 0; i < owner_fix_count; i++) {
        if (owner_fix[i].type == type && owner_fix[i].owner != owner) {
            owner = owner_fix[i].owner;
            owner_fix[i] = owner_fix[--owner_fix_count];      // each structure once
            break;
        }
    }
    long long *result = orig_battle_spawn(manager, type, owner, pos, facing, a6, a7, a8, a9, a10);
#ifndef RELEASE_BUILD                 // the players' copy keeps no spawn log; shots and debris are never logged
    if (thread_watch_on && type && get_player_by_id && _strnicmp(std_string(type + 0xf8), "PROJ_", 5) != 0) {
        char line[200];
        snprintf(line, sizeof line, "SPAWN %s for %s%s", std_string(type + 0xf8), player_name(owner),
                 result ? "" : " (FAILED)");
        test_log(line);
    }
#endif
    return result;
}

// --- Text overrides: Engine_Set_Text(text_id, text | nil) from any script --------------------------
// Game texts are looked up by CRC32 of their id (0x1fb370).
#define RVA_TEXT_BY_CRC     0x1fb370
typedef struct { union { wchar_t buf[8]; wchar_t *ptr; } u; unsigned long long size, cap; } MsWString;
#define MAX_TEXT_OVERRIDES 128
static struct { unsigned crc; MsWString *text; } text_overrides[MAX_TEXT_OVERRIDES];
static void *(*orig_text_by_crc)(void *, unsigned, unsigned char *);
static unsigned crc32_of(const char *s) {
    unsigned crc = 0xffffffff;
    for (; *s; s++) {
        crc ^= (unsigned char)*s;
        for (int k = 0; k < 8; k++) crc = (crc >> 1) ^ (0xedb88320 & (0u - (crc & 1)));
    }
    return ~crc;
}
static void *hooked_text_by_crc(void *db, unsigned crc, unsigned char *found) {
    void *result = orig_text_by_crc(db, crc, found);
    for (int i = 0; i < 0; i++) {
        if (text_overrides[i].text && text_overrides[i].crc == crc) {
            static unsigned last_crc;
            if (crc != last_crc) {
                last_crc = crc;
                char line[80];
                snprintf(line, sizeof line, "TEXT OVERRIDE USED crc %08x", crc);
                test_log(line);
            }
            if (found) *found = 1;
            return text_overrides[i].text;
        }
    }
    return result;
}
// Engine_Set_Text(text_id, text | nil): changes the text database entry itself; nil restores it.
#define RVA_TEXT_DB         0xa7bc58
#define RVA_WSTRING_ASSIGN  0x0228a0    // std::wstring::assign(wstring*, const wchar_t*, length)
static void *(*wstring_assign)(void *, const wchar_t *, unsigned long long);
#define MAX_SAVED_TEXTS 8192                     // windows rewrite hundreds of tooltips: a hash on the crc
static struct { unsigned crc; wchar_t *original; } saved_texts[MAX_SAVED_TEXTS];
static int saved_text_count;
// The slot of a saved text: its own if it has one, else (create) a free one; -1 when none.
static int saved_text_slot(unsigned crc, int create) {
    unsigned i = (crc * 2654435761u) & (MAX_SAVED_TEXTS - 1);
    for (int n = 0; n < MAX_SAVED_TEXTS; n++, i = (i + 1) & (MAX_SAVED_TEXTS - 1)) {
        if (!saved_texts[i].original) {
            if (!create || saved_text_count >= MAX_SAVED_TEXTS * 3 / 4) return -1;
            return (int)i;
        }
        if (saved_texts[i].crc == crc) return (int)i;
    }
    return -1;
}
static int lua_engine_set_text(lua_State *L) {
    const char *key = lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    if (!key || !orig_text_by_crc || !wstring_assign) return 0;
    const char *value = lua_gettop(L) >= 2 ? lua_tostring_fn(L, 2) : NULL;
    unsigned crc = crc32_of(key);
    unsigned char found = 0;
    MsWString *entry = orig_text_by_crc(module_base + RVA_TEXT_DB, crc, &found);
    if (!entry || !found) return 0;
    int slot = saved_text_slot(crc, 1);
    if (slot < 0) {
        static int warned;
        if (!warned) { warned = 1; test_log("SET TEXT: table FULL"); }
        return 0;
    }
    if (!saved_texts[slot].original) {              // keep the original once, to restore it
        const wchar_t *cur = entry->cap > 7 ? entry->u.ptr : entry->u.buf;
        wchar_t *copy = calloc(entry->size + 1, sizeof(wchar_t));
        if (!copy) return 0;
        memcpy(copy, cur, entry->size * sizeof(wchar_t));
        saved_texts[slot].crc = crc;
        saved_texts[slot].original = copy;
        saved_text_count++;
    }
    // (not logged: windows set dozens of tooltips per frame while scrolling)
    const wchar_t *cur = entry->cap > 7 ? entry->u.ptr : entry->u.buf;
    if (value) {
        int n = MultiByteToWideChar(CP_UTF8, 0, value, -1, NULL, 0);
        if (n <= 0) return 0;
        wchar_t *wide = calloc(n, sizeof(wchar_t));
        if (!wide) return 0;
        MultiByteToWideChar(CP_UTF8, 0, value, -1, wide, n);
        if (entry->size != (unsigned long long)(n - 1) || wmemcmp(cur, wide, n - 1) != 0)
            wstring_assign(entry, wide, n - 1);     // unchanged texts are left alone
        free(wide);
    } else {
        wstring_assign(entry, saved_texts[slot].original, wcslen(saved_texts[slot].original));
    }
    return 0;
}

// --- Engine_Set_Object_Text(type_name, text_id, text | nil) ------------------------------------------
// Object types copy their texts at load, so the copy inside the type is replaced.
#define RVA_TYPE_MANAGER    0xb2f020
#define RVA_FIND_TYPE       0x407c00    // (type manager, const std::string *name) -> GameObjectType*
typedef struct { union { char buf[16]; char *ptr; } u; unsigned long long size, cap; } MsString;
static unsigned char *(*find_type)(void *, MsString *);
#define TYPE_SCAN_BYTES 0x4000
#define MAX_TYPE_TEXTS 256
static struct { unsigned char *type; unsigned crc; MsWString *field; wchar_t *original; } type_texts[MAX_TYPE_TEXTS];

static const wchar_t *wstr_chars(const MsWString *w) { return w->cap > 7 ? w->u.ptr : w->u.buf; }

static int same_wstring(const MsWString *w, const wchar_t *text, size_t len) {
    if (w->size != len || w->cap < w->size || w->cap > 0x100000) return 0;
    const wchar_t *chars = wstr_chars(w);
    if (w->cap > 7 && IsBadReadPtr(chars, (len + 1) * sizeof(wchar_t))) return 0;
    return memcmp(chars, text, len * sizeof(wchar_t)) == 0;
}

static int lua_engine_set_object_text(lua_State *L) {
    const char *type_name = lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    const char *key = lua_tostring_fn ? lua_tostring_fn(L, 2) : NULL;
    const char *value = lua_gettop(L) >= 3 ? lua_tostring_fn(L, 3) : NULL;
    if (!type_name || !key || !find_type || !orig_text_by_crc || !wstring_assign) return 0;
    MsString name;
    memset(&name, 0, sizeof name);
    size_t n = strlen(type_name);
    if (n < 16) { memcpy(name.u.buf, type_name, n); name.cap = 15; }
    else { name.u.ptr = (char *)type_name; name.cap = n; }
    name.size = n;
    unsigned char *type = find_type(module_base + RVA_TYPE_MANAGER, &name);
    if (!type) return 0;
    unsigned crc = crc32_of(key);
    int slot = -1;
    for (int i = 0; i < MAX_TYPE_TEXTS; i++) {
        if (type_texts[i].type == type && type_texts[i].crc == crc) { slot = i; break; }
        if (slot < 0 && !type_texts[i].type) slot = i;
    }
    if (slot < 0) return 0;
    if (!type_texts[slot].type) {                    // first time: find the field holding the text
        unsigned char found = 0;
        MsWString *entry = orig_text_by_crc(module_base + RVA_TEXT_DB, crc, &found);
        if (!entry || !found) return 0;
        const wchar_t *original = wstr_chars(entry);
        size_t len = entry->size;
        {                                             // Engine_Set_Text may have changed the database already
            int i = saved_text_slot(crc, 0);
            if (i >= 0 && saved_texts[i].original) {
                original = saved_texts[i].original;
                len = wcslen(original);
            }
        }
        for (int off = 0; off + (int)sizeof(MsWString) <= TYPE_SCAN_BYTES; off += 8) {
            if (IsBadReadPtr(type + off, sizeof(MsWString))) break;
            MsWString *w = (MsWString *)(type + off);
            if (same_wstring(w, original, len)) {
                type_texts[slot].type = type;
                type_texts[slot].crc = crc;
                type_texts[slot].field = w;
                type_texts[slot].original = calloc(len + 1, sizeof(wchar_t));
                if (type_texts[slot].original) memcpy(type_texts[slot].original, original, len * sizeof(wchar_t));
                break;
            }
        }
        if (!type_texts[slot].type) {
            char line[200];
            snprintf(line, sizeof line, "SET OBJECT TEXT %s %s: text not found in the type", type_name, key);
            test_log(line);
            return 0;
        }
    }
    if (value) {
        int wn = MultiByteToWideChar(CP_UTF8, 0, value, -1, NULL, 0);
        if (wn <= 0) return 0;
        wchar_t *wide = calloc(wn, sizeof(wchar_t));
        if (!wide) return 0;
        MultiByteToWideChar(CP_UTF8, 0, value, -1, wide, wn);
        wstring_assign(type_texts[slot].field, wide, wn - 1);
        free(wide);
    } else if (type_texts[slot].original) {
        wstring_assign(type_texts[slot].field, type_texts[slot].original, wcslen(type_texts[slot].original));
    }
    return 0;
}

// --- Rebellion battle prompt: Begin + Auto-Resolve for the mod's linked rebellion battle -----
// While armed (Engine_Rebellion_Prompt(1)), the prompt (0x3ca480) shows Auto-Resolve too. A click on it calls the
// script's DiplomacyRebellionAutoresolve(), then clears the link, closes the prompt and lifts the battle pause as
// the engine does for a normal auto-resolve.
#define RVA_BATTLE_PROMPT   0x3ca480
#define RVA_PROMPT_CLICK    0x347850
#define RVA_LINK_PENDING    0xb30545
#define RVA_GETTABLE        0x7b8e90
#define RVA_TYPE            0x7b9e00
#define RVA_PCALL           0x7b9280
#define RVA_BATTLE_MANAGER  0xb153e0    // +0x2c battle pause count, +0xf0 a LINK_TACTICAL battle is pending
#define RVA_CLOSE_PROMPT    0x28c6c0    // (battle manager)
#define RVA_LIFT_PAUSE      0x28c720    // (battle manager, 1)
#define RVA_ADD_PAUSE       0x28bb80    // (battle manager): one more pause (the pause button, the Esc menu)
#define RVA_HIDE_PROMPT     0x3d26e0    // hides the battle prompt bar's buttons
#define RVA_CLEAR_LINK      0x28c640    // (battle manager + 0xf0): clears a pending LINK_TACTICAL battle
#define LUA_STATE_GLOBAL    0x20        // lua_State.l_G (shared by a state's threads)
#define MAX_MAIN_STATES     16384
static void (*orig_battle_prompt)(void *, void *, char);
static void (*orig_prompt_click)(unsigned char *);
static void (*lua_gettable_fn)(lua_State *, int);
static int (*lua_type_fn)(lua_State *, int);
static int (*lua_pcall_fn)(lua_State *, int, int, int);
static void (*clear_link)(unsigned char *);
static void (*close_prompt)(unsigned char *);
static void (*lift_pause)(unsigned char *, char);
static void (*add_pause)(unsigned char *);
static void (*hide_prompt)(void);
static lua_State *main_states[MAX_MAIN_STATES];
static void *main_globals[MAX_MAIN_STATES];      // each main state's l_G, read when it was created
static int main_state_count;
static volatile int rebellion_prompt;
static lua_State *rebellion_state;
// Every script's main state, with its global state (only the stored pointers are compared later: a state
// may have been closed since). A global state at a freed one's address replaces the dead entry.
static void remember_main_state(lua_State *L) {
    void *g = *(void **)((unsigned char *)L + LUA_STATE_GLOBAL);
    for (int i = 0; i < main_state_count; i++) {
        if (main_globals[i] == g) {
            main_states[i] = L;
            return;
        }
    }
    if (main_state_count < MAX_MAIN_STATES) {
        main_states[main_state_count] = L;
        main_globals[main_state_count++] = g;
    }
}

// The world of the latest battle (its prompt, or a space battle starting there): Engine_Battle_Planet() returns its
// type name to the battle's scripts (the court's bribed garrisons).
static char battle_planet[64];
static int battle_serial;           // counts battles (prompts and space battle starts): Engine_Battle_Serial()
static void note_battle_planet(unsigned char *planet) {
    const char *name = planet ? type_name(planet) : NULL;
    if (name && name[0]) snprintf(battle_planet, sizeof battle_planet, "%s", name);
    battle_serial++;
    zoomed_planet[0] = 0;           // a battle leaves the planet view without a "zoomed out" event
}

static int lua_battle_serial(lua_State *L) {
    lua_pushnumber(L, battle_serial);
    return 1;
}

static int lua_battle_planet(lua_State *L) {
    if (!battle_planet[0]) return 0;
    lua_pushstring(L, battle_planet);
    return 1;
}

// --- Spies at work -------------------------------------------------------------------------------------
// 0x70f510 runs when a spy reports on a planet. The human's reports are kept as "PLANET|UNIT_TYPE" for Engine_Spied().
#define RVA_SYSTEM_SPY      0x70f510
#define MAX_SPIED           16
static void *(*orig_system_spy)(void *, unsigned char *, unsigned char *, unsigned char *);
static char spied[MAX_SPIED][96];
static int spied_count;

static int is_envoy(unsigned char *unit);
static void note_envoy_slot(unsigned char *planet);
static void *hooked_system_spy(void *ability, unsigned char *unit, unsigned char *player, unsigned char *planet) {
    void *result = orig_system_spy(ability, unit, player, planet);
    if (planet && is_envoy(unit)) {             // an Envoy dropped in a world's special slot (its spy ability)
        note_envoy_slot(planet);
        return result;
    }
    unsigned char *local = get_local_player ? get_local_player(module_base + RVA_PLAYER_LIST) : NULL;
    if (unit && planet && local && *(int *)(unit + 0x58) == *(int *)(local + 0x4c) && spied_count < MAX_SPIED) {
        const char *where = type_name(planet), *who = type_name(unit);
        snprintf(spied[spied_count], sizeof spied[0], "%s|%s", where ? where : "", who ? who : "");
        spied_count++;
    }
    return result;
}

// --- Envoys in a world's special slot ---------------------------------------------------------------------------
// The mod's Envoy (DIPLOMACY_ENVOY, a spy ability that sees nothing) may use the slot on any inhabited world named by
// Engine_Envoy_Worlds, own and friendly ones included (0x3d2020, 0x70f8e0, 0x48d900). Its slot reads "Delegate".
// Engine_Envoy_Slots() returns the worlds where one was placed.
#define RVA_ABILITY_TARGET_OK 0x48d900
#define RVA_SPY_CAN_TARGET    0x70f8e0
#define RVA_SLOT_KIND         0x3d2020
#define MAX_ENVOY_SLOTS       16
#define MAX_ENVOY_WORLDS      400
static unsigned long long (*orig_ability_target_ok)(void *, unsigned char *, unsigned char *);
static unsigned long long (*orig_spy_can_target)(void *, unsigned char *, unsigned char *);
static int (*orig_slot_kind)(void *, void *, unsigned char **, unsigned char *, const char **);
static char envoy_slots[MAX_ENVOY_SLOTS][64];
static int envoy_slot_count;
static char *envoy_worlds;                      // ";A;B;...;" upper case, or NULL: every world
static int envoy_in_slot_check;

static int is_envoy(unsigned char *unit) {
    const char *t = unit ? type_name(unit) : NULL;
    return t && _stricmp(t, "DIPLOMACY_ENVOY") == 0;
}

static int envoy_world_ok(unsigned char *planet) {
    if (!envoy_worlds) return 1;
    const char *name = type_name(planet);
    if (!name) return 0;
    char key[72];
    snprintf(key, sizeof key, ";%s;", name);
    for (char *c = key; *c; c++) *c = (char)toupper((unsigned char)*c);
    return strstr(envoy_worlds, key) != NULL;
}

static int lua_envoy_worlds(lua_State *L) {
    const char *list = lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    if (!list) return 0;
    size_t n = strlen(list);
    char *all = malloc(n + 3);
    if (!all) return 0;
    all[0] = ';';
    for (size_t i = 0; i < n; i++) all[i + 1] = (char)toupper((unsigned char)list[i]);
    all[n + 1] = ';';
    all[n + 2] = 0;
    char *old = envoy_worlds;
    envoy_worlds = all;
    free(old);
    return 0;
}

static unsigned long long hooked_ability_target_ok(void *ability, unsigned char *unit, unsigned char *planet) {
    if (planet && is_envoy(unit)) return envoy_world_ok(planet);
    return orig_ability_target_ok(ability, unit, planet);
}

static unsigned long long hooked_spy_can_target(void *ability, unsigned char *unit, unsigned char *planet) {
    if (unit && planet && is_envoy(unit)) {
        int ok = envoy_world_ok(planet);
        if (ok) envoy_in_slot_check = 1;
        return ok;
    }
    return orig_spy_can_target(ability, unit, planet);
}

// Posted envoys (Engine_Envoy_Posted) keep showing in their world's slot (redrawn after 0x3eb200). A left click on
// one is a recall, reported by Engine_Envoy_Recalls().
#define RVA_PLANET_SLOTS      0x3eb200
#define RVA_TEXT_TO_WIDE      0x1f9fe0
#define RVA_TEXT_TABLE        0xa7bc58
#define MAX_POSTED            16
static void (*orig_planet_slots)(unsigned char *, unsigned char **, char);
static long long (*text_to_wide)(void *, const char *, void *);
static char *envoy_posted;                      // ";A;B;...;" upper case, or NULL: none
static struct { unsigned char *widget; char planet[64]; DWORD shown; } posted_widgets[MAX_POSTED];
static int posted_widget_count;
static char envoy_recalls[MAX_POSTED][64];
static int envoy_recall_count;
static unsigned long long delegate_label[4] = {0, 0, 0, 7};     // engine wide string (made once, kept)
static int delegate_label_made;

static int lua_envoy_posted(lua_State *L) {
    const char *list = lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    char *all = NULL;
    if (list && list[0]) {
        size_t n = strlen(list);
        all = malloc(n + 3);
        if (!all) return 0;
        all[0] = ';';
        for (size_t i = 0; i < n; i++) all[i + 1] = (char)toupper((unsigned char)list[i]);
        all[n + 1] = ';';
        all[n + 2] = 0;
    }
    char *old = envoy_posted;
    envoy_posted = all;
    free(old);
    return 0;
}

static int lua_envoy_recalls(lua_State *L) {
    if (envoy_recall_count == 0) return 0;
    char all[MAX_POSTED * 65];
    all[0] = 0;
    for (int i = 0; i < envoy_recall_count; i++) {
        if (i) strcat(all, ";");
        strcat(all, envoy_recalls[i]);
    }
    envoy_recall_count = 0;
    lua_pushstring(L, all);
    return 1;
}

static void hooked_planet_slots(unsigned char *gui, unsigned char **record, char hide) {
    orig_planet_slots(gui, record, hide);
    if (!envoy_posted || !record || !record[0] || !text_to_wide) return;
    const char *name = type_name(record[0]);
    if (!name) return;
    unsigned char *slot = record[0x29];
    if (!slot) return;
    char key[72];
    snprintf(key, sizeof key, ";%s;", name);
    for (char *c = key; *c; c++) *c = (char)toupper((unsigned char)*c);
    if (!strstr(envoy_posted, key)) {
        // the planet panels' widgets are reused for whichever world is in view: this one shows no posted envoy now
        for (int i = 0; i < posted_widget_count; i++)
            if (posted_widgets[i].widget == slot) posted_widgets[i].shown = 0;
        return;
    }
    void **vt = *(void ***)slot;
    static float orange[4] = {247 / 255.0f, 170 / 255.0f, 70 / 255.0f, 1.0f};
    static float white[4] = {1.0f, 1.0f, 1.0f, 1.0f};
    if (!delegate_label_made) {
        delegate_label_made = 1;
        text_to_wide(module_base + RVA_TEXT_TABLE, "TEXT_ABILITY_SLOT_DELEGATE", delegate_label);
    }
    ((void (*)(unsigned char *, char))vt[0x78 / 8])(slot, 0);
    ((void (*)(unsigned char *, void *, int, int))vt[0x148 / 8])(slot, delegate_label, 1, 0);
    ((void (*)(unsigned char *, float *))vt[0x10 / 8])(slot, orange);
    ((void (*)(unsigned char *, const char *, float *))vt[0xa0 / 8])(slot, "i_button_bothan_civilian.tga", white);
    *(long long *)(slot + 0x48 + 8 * 1) = 3;                // the kind: a spy's slot (an envoy's)
    *(long long *)(slot + 0x48 + 8 * 2) = 0;                // no unit in it
    if (record[0x2a]) {
        void **vt2 = *(void ***)record[0x2a];
        ((void (*)(unsigned char *, char))vt2[0x78 / 8])(record[0x2a], 1);
    }
    for (int i = 0; i < posted_widget_count; i++) {
        if (posted_widgets[i].widget == slot) {
            snprintf(posted_widgets[i].planet, sizeof posted_widgets[i].planet, "%s", name);
            posted_widgets[i].shown = GetTickCount();
            return;
        }
    }
    int at = posted_widget_count;
    if (at >= MAX_POSTED) {                     // full (the widgets are reused): the one seen longest ago goes
        at = 0;
        for (int i = 1; i < posted_widget_count; i++)
            if (posted_widgets[i].shown < posted_widgets[at].shown) at = i;
    } else {
        posted_widget_count++;
    }
    posted_widgets[at].widget = slot;
    snprintf(posted_widgets[at].planet, sizeof posted_widgets[0].planet, "%s", name);
    posted_widgets[at].shown = GetTickCount();
}

// Engine_Set_Build_Limit(type name, n): sets the type's Build_Limit_Current_Per_Player (offset found by name in
// the engine's XML field table; a different game version leaves it alone).
#define RVA_BUILD_LIMIT_FIELD 0xa2d3b0
static unsigned char *type_by_name(const char *name);
static int lua_set_build_limit(lua_State *L) {
    const char *name = lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    const char *n = lua_tostring_fn ? lua_tostring_fn(L, 2) : NULL;
    if (!name || !n || !module_base) return 0;
    unsigned char *entry = module_base + RVA_BUILD_LIMIT_FIELD;
    const char *field = *(const char **)entry;
    if (!field || IsBadReadPtr(field, 31) || memcmp(field, "Build_Limit_Current_Per_Player", 31) != 0) return 0;
    long long offset = *(long long *)(entry + 0x10);
    unsigned char *type = type_by_name(name);
    if (!type || offset <= 0 || offset > 0x2000) return 0;
    *(int *)(type + offset) = atoi(n);
    lua_pushnumber(L, 1);
    return 1;
}

// A left click on a posted envoy's slot (its picture or its label to the left; the slot's centre in pixels at
// widget +0x30/+0x34) recalls it. Seen in the window's messages (the engine plays no click sound for the slot).
static void envoy_slot_clicked(unsigned char *widget);
static void envoy_slot_mouse(int x, int y) {
    DWORD now = GetTickCount();
    for (int i = 0; i < posted_widget_count; i++) {
        unsigned char *w = posted_widgets[i].widget;
        if (!w || now - posted_widgets[i].shown > 500) continue;
        float cx = *(float *)(w + 0x30), cy = *(float *)(w + 0x34);
        if (x >= cx - 115 && x <= cx + 22 && y >= cy - 20 && y <= cy + 20) {
            envoy_slot_clicked(w);
            return;
        }
    }
}

static void envoy_slot_clicked(unsigned char *widget) {
    if (!envoy_posted) return;
    for (int i = 0; i < posted_widget_count; i++) {
        if (posted_widgets[i].widget != widget) continue;
        char key[72];
        snprintf(key, sizeof key, ";%s;", posted_widgets[i].planet);
        for (char *c = key; *c; c++) *c = (char)toupper((unsigned char)*c);
        if (strstr(envoy_posted, key) && envoy_recall_count < MAX_POSTED) {
            snprintf(envoy_recalls[envoy_recall_count], sizeof envoy_recalls[0], "%s", posted_widgets[i].planet);
            envoy_recall_count++;
        }
        return;
    }
}

static int hooked_slot_kind(void *gui, void *fleets, unsigned char **unit, unsigned char *planet, const char **label) {
    envoy_in_slot_check = 0;
    int kind = orig_slot_kind(gui, fleets, unit, planet, label);
    if (kind == 3 && envoy_in_slot_check && label) *label = "TEXT_ABILITY_SLOT_DELEGATE";
    envoy_in_slot_check = 0;
    return kind;
}

static void note_envoy_slot(unsigned char *planet) {
    const char *where = type_name(planet);
    char line[128];
    snprintf(line, sizeof line, "ENVOY SLOT at %s", where ? where : "?");
    test_log(line);
    if (where && envoy_slot_count < MAX_ENVOY_SLOTS) {
        snprintf(envoy_slots[envoy_slot_count], sizeof envoy_slots[0], "%s", where);
        envoy_slot_count++;
    }
}

static int lua_envoy_slots(lua_State *L) {
    if (envoy_slot_count == 0) return 0;
    char all[MAX_ENVOY_SLOTS * 65];
    all[0] = 0;
    for (int i = 0; i < envoy_slot_count; i++) {
        if (i) strcat(all, ";");
        strcat(all, envoy_slots[i]);
    }
    envoy_slot_count = 0;
    lua_pushstring(L, all);
    return 1;
}

static int lua_spied(lua_State *L) {
    if (spied_count == 0) return 0;
    char all[MAX_SPIED * 97];
    all[0] = 0;
    for (int i = 0; i < spied_count; i++) {
        if (i) strcat(all, ";");
        strcat(all, spied[i]);
    }
    spied_count = 0;
    lua_pushstring(L, all);
    return 1;
}

static void hooked_battle_prompt(void *gui, void *planet, char flag) {
    note_battle_planet((unsigned char *)planet);
    char *pending = (char *)(module_base + RVA_LINK_PENDING);
    if (rebellion_prompt && clear_link && *pending) {
        char saved = *pending;
        *pending = 0;
        orig_battle_prompt(gui, planet, flag);
        *pending = saved;
        test_log("REBELLION PROMPT shown with auto-resolve");
        return;
    }
    orig_battle_prompt(gui, planet, flag);
}

static void hooked_prompt_click(unsigned char *button) {
    if (rebellion_prompt && clear_link && button && *(int *)(button + 0xa8) == 0x236) {
        rebellion_prompt = 0;
        lua_State *L = rebellion_state;
        if (L && lua_pcall_fn && room_for(L, 8, "a battle prompt")) {
            int top = lua_gettop(L);
            lua_pushstring(L, "DiplomacyRebellionAutoresolve");
            lua_gettable_fn(L, LUA_GLOBALSINDEX);
            if (lua_type_fn(L, -1) == 6) {                 // LUA_TFUNCTION
                int status = lua_pcall_fn(L, 0, 0, 0);
                char line[300];
                snprintf(line, sizeof line, "REBELLION PROMPT auto-resolve: script %s%s", status == 0 ? "done" : "error: ",
                         status == 0 ? "" : (lua_tostring_fn ? lua_tostring_fn(L, -1) : "?"));
                test_log(line);
            } else {
                test_log("REBELLION PROMPT auto-resolve: no script handler");
            }
            lua_settop(L, top);
        }
        unsigned char *manager = module_base + RVA_BATTLE_MANAGER;
        clear_link(manager + 0xf0);
        *(char *)(module_base + RVA_LINK_PENDING) = 0;
        close_prompt(manager);
        hide_prompt();
        for (int i = 0; i < 16 && *(int *)(manager + 0x2c) > 0; i++) lift_pause(manager, 1);
        test_log("REBELLION PROMPT closed: no battle");
        return;
    }
    orig_prompt_click(button);
}

// Engine_Set_Human_Planets(count): the human's world count (see refuse_victory).
static int lua_set_human_planets(lua_State *L) {
    human_planets = lua_gettop(L) >= 1 ? (int)luaL_checknumber(L, 1) : -1;
    return 0;
}

// --- GUI clicks straight to Lua -------------------------------------------------------------------------
// Clicks on components whose names start with a prefix given to Engine_Gui_Listen are passed to the script's
// DiplomacyGuiClick(name, button) (from 0x32e9b0; right clicks from 0x350cc0). Story events still see them.
#define RVA_GUI_CLICKED     0x32e9b0
#define RVA_CLICK_SOUND     0x350cc0    // (widget, 1 = right click)
#define RVA_WIDGET_NAME     0x34c630    // widget -> its component name
static void (*orig_gui_clicked)(void *, const char *);
static void (*orig_click_sound)(unsigned char *, char);
static const char *(*widget_name)(unsigned char *);
static char gui_prefix[256];
static lua_State *gui_state;
static volatile int gui_busy;          // inside a call from the hook into Lua

static int gui_listened(const char *name) {
    if (!name || !gui_prefix[0]) return 0;
    const char *p = gui_prefix;
    while (*p) {
        const char *end = strchr(p, ',');
        size_t n = end ? (size_t)(end - p) : strlen(p);
        if (n > 0 && _strnicmp(name, p, n) == 0) return 1;
        if (!end) break;
        p = end + 1;
    }
    return 0;
}

// The active game mode (galactic / land / space) from the mode object's vtable. Clicks are not delivered during
// battles, where the campaign's scripts are suspended.
#define RVA_ACTIVE_MODE     0xb15418
#define RVA_LAND_MODE_VT    0x8673a0
#define RVA_SPACE_MODE_VT   0x8792f8
static int in_battle(void) {
    if (!module_base) return 0;
    void **mode = *(void ***)(module_base + RVA_ACTIVE_MODE);
    if (!mode) return 0;
    void *vt = *mode;
    return vt == module_base + RVA_LAND_MODE_VT || vt == module_base + RVA_SPACE_MODE_VT;
}

static void gui_to_lua(const char *name, const char *button) {
    lua_State *L = gui_state;
    if (!L || !lua_pcall_fn || !(name[0] == '?' || gui_listened(name)) || in_battle() || busy_now()
        || !room_for(L, 8, "a GUI click"))
        return;
    check_frame(L, "before a GUI click");
    int top = lua_gettop(L);
    lua_pushstring(L, "DiplomacyGuiClick");
    lua_gettable_fn(L, LUA_GLOBALSINDEX);
    if (lua_type_fn(L, -1) == 6) {                       // LUA_TFUNCTION
        lua_pushstring(L, name);
        lua_pushstring(L, button);
        if (lua_pcall_fn(L, 2, 0, 0) != 0) {
            char line[400];
            snprintf(line, sizeof line, "GUI CLICK %s: script error %s", name,
                     lua_tostring_fn ? lua_tostring_fn(L, -1) : "?");
            test_log(line);
            log_line(line);
        }
    }
    lua_settop(L, top);
    check_frame(L, "after a GUI click");
}

// Clicks reach Lua on the next frame (gui_tick), once the engine is done with the button: a script redrawing the
// clicked button inside the engine's own click handling left it stuck in its pressed look, without its highlight.
#define MAX_CLICKS 8
static char click_names[MAX_CLICKS][96], click_buttons[MAX_CLICKS][8];
static int click_count;

static void queue_click(const char *name, const char *button) {
    if (!name || !gui_listened(name) || click_count >= MAX_CLICKS) return;
    snprintf(click_names[click_count], sizeof click_names[0], "%s", name);
    snprintf(click_buttons[click_count], sizeof click_buttons[0], "%s", button);
    click_count++;
}

static unsigned char *custom_component(const char *name);

static void deliver_clicks(void) {
    int n = click_count;
    click_count = 0;
    for (int i = 0; i < n; i++) {
        gui_busy = 1;
        gui_to_lua(click_names[i], click_buttons[i]);
        gui_busy = 0;
    }
}

static void hooked_gui_clicked(void *story, const char *name) {
    orig_gui_clicked(story, name);
    if (name && _strnicmp(name, "dp_", 3) != 0) queue_click(name, "left");   // (dp_: see press_and_release)
}

// --- Frame ticks for the windows -------------------------------------------------------------------------
// Engine_Gui_Tick(1) calls the script's DiplomacyGuiTick(ms) about 30 times a second, also while paused;
// Engine_Gui_Tick(0) stops it. Stops by itself when the campaign's Lua state closes.
#define RVA_LUA_CLOSE       0x7b8890
static char selected_planet[64];
static char zoomed_planet[64];        // the planet the galactic camera is zoomed in on (see hooked_zoom_in)      // the selected planet's type name (see hooked_select_planet)
static int hp_tick_wanted(void);
static int gui_tick_on;
static DWORD gui_tick_last;
static DWORD gui_thread;
static int gui_hide_pending;
static BOOL (WINAPI *orig_peek_message)(LPMSG, HWND, UINT, UINT, UINT);
static void (*orig_lua_close)(lua_State *);
static void hide_custom_shells(void);
static void hide_panel_buttons(void);

static void gui_tick(void) {
    if (GetCurrentThreadId() != gui_thread || gui_busy || script_depth > 0 || busy_now()) return;
    if (gui_hide_pending) {
        gui_hide_pending = 0;
        hide_custom_shells();
    }
    static int was_battle;
    static DWORD battle_hide_last;
    int battle = in_battle();
    if (battle != was_battle) {
        was_battle = battle;
        battle_hide_last = 0;
        test_log(battle ? "GUI: battle mode, panel buttons and windows hidden" : "GUI: back on the galactic map");
        if (!battle) {
            battle_ally_count = 0;
            battle_hold_reset();
            spawn_facing_on = 0;
        }
    }
    if (battle) {                     // the battle's command bar shows the panel buttons again as it rebuilds
        keep_battle_allies();
        DWORD now = GetTickCount();
        if (now - battle_hide_last >= 250) {
            battle_hide_last = now;
            hide_custom_shells();
            hide_panel_buttons();
        }
        click_count = 0;
        return;                       // no window ticks into the suspended campaign scripts
    }
    if (click_count) deliver_clicks();
    lua_State *L = gui_state;
    if (!(gui_tick_on || hp_tick_wanted()) || !L || !lua_pcall_fn || !script_depth_tracked) return;
    DWORD now = GetTickCount();
    DWORD elapsed = now - gui_tick_last;
    if (elapsed < 30) return;
    gui_tick_last = now;
    if (elapsed > 500) elapsed = 30;
    if (!room_for(L, 8, "the GUI tick")) return;
    gui_busy = 1;
    check_frame(L, "before a GUI tick");
    int top = lua_gettop(L);
    lua_pushstring(L, "DiplomacyGuiTick");
    lua_gettable_fn(L, LUA_GLOBALSINDEX);
    if (lua_type_fn(L, -1) == 6) {
        lua_pushnumber(L, (double)elapsed);
        if (lua_pcall_fn(L, 1, 0, 0) != 0) {
            char line[400];
            snprintf(line, sizeof line, "GUI TICK: script error %s (ticks stopped)",
                     lua_tostring_fn ? lua_tostring_fn(L, -1) : "?");
            test_log(line);
            log_line(line);
            gui_tick_on = 0;
        }
    }
    lua_settop(L, top);
    check_frame(L, "after a GUI tick");
    gui_busy = 0;
}

static void agent_poll(void);

// The mouse wheel: turns since the last Engine_Mouse call. While a window captures it (Engine_Wheel_Capture)
// the game doesn't see it (no camera zoom behind the window).
static int wheel_delta, wheel_capture;
static int lua_wheel_capture(lua_State *L) {
    wheel_capture = lua_gettop(L) >= 1 && luaL_checknumber(L, 1) != 0;
    wheel_delta = 0;
    return 0;
}

// The Escape key: while a script captures it (Engine_Escape_Capture, a cutscene playing) the game doesn't see it (no
// options menu); Engine_Escape_Pressed returns the presses since its last call.
static int escape_capture, escape_count;
static int lua_escape_capture(lua_State *L) {
    escape_capture = lua_gettop(L) >= 1 && luaL_checknumber(L, 1) != 0;
    escape_count = 0;
    return 0;
}
static int lua_escape_pressed(lua_State *L) {
    lua_pushnumber(L, escape_count);
    escape_count = 0;
    return 1;
}

// --- Textures at their own size: on cards that support any size, DDS textures load as they are instead of being
// resampled to a power of two (Thrawn's 2000x2000 planets took a minute at each campaign start).
typedef long (WINAPI *make_texture_fn)(void *, const void *, UINT, UINT, UINT, UINT, DWORD, int, int, DWORD, DWORD,
                                        DWORD, void *, void *, void **);
static make_texture_fn orig_d3dx_texture;
static int npot_textures_on = 1;                // EngineHook_pow2.txt: off
static int npot_state;                         // 0 not checked, 1 the card takes any size, -1 it doesn't
static unsigned long npot_loads;
static int is_pow2(UINT v) { return v && !(v & (v - 1)); }
static long WINAPI hooked_d3dx_texture(void *device, const void *data, UINT size, UINT width, UINT height, UINT mips,
                                       DWORD usage, int format, int pool, DWORD filter, DWORD mip_filter, DWORD key,
                                       void *info, void *palette, void **out) {
    if (width == 0xffffffffu && height == 0xffffffffu && device && data && size >= 128
        && memcmp(data, "DDS ", 4) == 0) {
        if (npot_state == 0) {                   // IDirect3DDevice9::GetDeviceCaps (vtable 7), D3DCAPS9.TextureCaps (+60)
            unsigned char caps[512];
            memset(caps, 0, sizeof caps);
            long (WINAPI *get_caps)(void *, void *) = (*(long (WINAPI ***)(void *, void *))device)[7];
            DWORD tex = get_caps(device, caps) >= 0 ? *(DWORD *)(caps + 60) : 0x2;
            npot_state = (!(tex & 0x2) && !(tex & 0x100)) ? 1 : -1;     // no POW2 limit, not even conditional
            char line[120];
            snprintf(line, sizeof line, "textures: %s", npot_state > 0 ? "loaded at their own size (the card takes any size)"
                                                                       : "rounded to powers of two (as before)");
            log_line(line);
        }
        const unsigned char *d = data;
        UINT h = *(const UINT *)(d + 12), w = *(const UINT *)(d + 16);
        UINT caps2 = *(const UINT *)(d + 112);
        UINT pf_flags = *(const UINT *)(d + 80);
        UINT file_mips = (*(const UINT *)(d + 8) & 0x20000) ? *(const UINT *)(d + 28) : 1;
        UINT full = 1;
        for (UINT m = w > h ? w : h; m > 1; m >>= 1) full++;
        int dxt = (pf_flags & 0x4) && d[84] == 'D' && d[85] == 'X' && d[86] == 'T';   // DXT1-5 only
        // only big DXT textures that bring every mipmap with them (the planets): nothing for D3DX to make up
        if (npot_state > 0 && dxt && !(caps2 & 0x200 /* cube map */) && !(caps2 & 0x200000 /* volume */)
            && (!is_pow2(w) || !is_pow2(h)) && w >= 1024 && h >= 1024 && w % 4 == 0 && h % 4 == 0 && file_mips == full
            && (mips == 0 || mips == 0xffffffffu)) {
            width = height = 0xfffffffeu;         // D3DX_DEFAULT_NONPOW2
            if (npot_loads++ < 40) {
                char line[120];
                snprintf(line, sizeof line, "texture at its own size: %ux%u, %u mipmaps", w, h, file_mips);
                log_line(line);
            }
        }
    }
    return orig_d3dx_texture(device, data, size, width, height, mips, usage, format, pool, filter, mip_filter, key, info,
                             palette, out);
}
static void hook_d3dx_once(void) {
    static int done;
    if (done) return;
    done = 1;
    HMODULE d3dx = GetModuleHandleA("d3dx9_43.dll");
    void *fn = d3dx ? (void *)GetProcAddress(d3dx, "D3DXCreateTextureFromFileInMemoryEx") : NULL;
    if (!fn || MH_CreateHook(fn, (void *)hooked_d3dx_texture, (void **)&orig_d3dx_texture) != MH_OK
        || MH_EnableHook(fn) != MH_OK) {
        log_line("texture size hook failed: textures load as before");
        return;
    }
    log_line("texture size hook installed");
}

static void press_and_release(UINT message);
// The mouse buttons as the engine sees them (not as window messages: none come this way): each change while the
// game is in front (or the mouse is on it) is a press or a release for press_and_release.
static HWND game_window;
static BOOL CALLBACK find_game_window(HWND hwnd, LPARAM unused);
static void poll_buttons(void) {
    static int was_left, was_right;
    int swap = GetSystemMetrics(SM_SWAPBUTTON);
    int left = (GetAsyncKeyState(swap ? VK_RBUTTON : VK_LBUTTON) & 0x8000) != 0;
    int right = (GetAsyncKeyState(swap ? VK_LBUTTON : VK_RBUTTON) & 0x8000) != 0;
    if (left == was_left && right == was_right) return;
    if (!game_window || !IsWindow(game_window)) {
        game_window = NULL;
        EnumWindows(find_game_window, 0);
    }
    POINT at;
    RECT box;
    int front = game_window && (GetForegroundWindow() == game_window
                                || (GetCursorPos(&at) && GetWindowRect(game_window, &box) && PtInRect(&box, at)));
    if (left != was_left && (front || !left)) press_and_release(left ? WM_LBUTTONDOWN : WM_LBUTTONUP);
    if (right != was_right && (front || !right)) press_and_release(right ? WM_RBUTTONDOWN : WM_RBUTTONUP);
    was_left = left;
    was_right = right;
}
static BOOL WINAPI hooked_peek_message(LPMSG msg, HWND hwnd, UINT first, UINT last, UINT remove) {
    BOOL result = orig_peek_message(msg, hwnd, first, last, remove);
    static DWORD last_peek;                            // (where a long load goes: nothing polled for 2 s or more)
    DWORD peek_now = GetTickCount();
    if (last_peek && peek_now - last_peek >= 2000) {
        char gap[64];
        snprintf(gap, sizeof gap, "SLOW: no frames for %lu ms", (unsigned long)(peek_now - last_peek));
        test_log(gap);
    }
    last_peek = peek_now;
    if (result && msg && (remove & PM_REMOVE) && msg->message == WM_MOUSEWHEEL) {
        wheel_delta += GET_WHEEL_DELTA_WPARAM(msg->wParam);
        if (wheel_capture) msg->message = WM_NULL;
    }
    if (result && msg && (remove & PM_REMOVE) && escape_capture && msg->wParam == VK_ESCAPE
        && (msg->message == WM_KEYDOWN || msg->message == WM_KEYUP || msg->message == WM_CHAR)) {
        if (msg->message == WM_KEYDOWN) escape_count++;
        msg->message = WM_NULL;
    }
    if (result && msg && (remove & PM_REMOVE) && (msg->message == WM_RBUTTONDOWN || msg->message == WM_LBUTTONDOWN)
        && hp_pad_click((short)LOWORD(msg->lParam), (short)HIWORD(msg->lParam), msg->message == WM_LBUTTONDOWN)) msg->message = WM_NULL;
    if (result && msg && (remove & PM_REMOVE) && msg->message == WM_LBUTTONDOWN && envoy_posted)
        envoy_slot_mouse((short)LOWORD(msg->lParam), (short)HIWORD(msg->lParam));
    poll_buttons();
    if (npot_textures_on) hook_d3dx_once();
    gui_tick();
    agent_poll();
    start_hold_tick();
    if (profile_on) profile_tick();
    if (test_log_dirty && GetTickCount() - test_log_flushed >= LOG_FLUSH_MS) test_log_flush();
    return result;
}

static void hooked_lua_close(lua_State *L) {
    if (gui_state && *(void **)((unsigned char *)L + LUA_STATE_GLOBAL) ==
                     *(void **)((unsigned char *)gui_state + LUA_STATE_GLOBAL)) {
        gui_state = NULL;
        gui_tick_on = 0;
        gui_prefix[0] = 0;
        gui_hide_pending = 1;
        selected_planet[0] = 0;       // a new campaign starts with nothing selected
        zoomed_planet[0] = 0;
        test_log("GUI: the listening script was closed; its windows are hidden");
        trail_dump(*(void **)((unsigned char *)L + LUA_STATE_GLOBAL));
    }
    orig_lua_close(L);
}

static int lua_gui_tick(lua_State *L) {
    gui_tick_on = lua_gettop(L) >= 1 && luaL_checknumber(L, 1) != 0;
    gui_tick_last = GetTickCount();
    set_global_value(L, GUI_TICK_GLOBAL, NULL, gui_tick_on);
    return 0;
}

// Engine_Pause(): the pause count. Engine_Pause(1) adds a pause, Engine_Pause(0) lifts one; both return the count.
static int lua_pause(lua_State *L) {
    unsigned char *manager = module_base + RVA_BATTLE_MANAGER;
    if (!add_pause || !lift_pause || !module_base) return 0;      // nil: this game build is not the known one
    if (lua_gettop(L) >= 1) {
        if (luaL_checknumber(L, 1) != 0) add_pause(manager);
        else if (*(int *)(manager + 0x2c) > 0) lift_pause(manager, 1);
    }
    lua_pushnumber(L, (double)*(int *)(manager + 0x2c));
    return 1;
}

// Engine_Start_Hold(1/0): during a new campaign's first minute, slow frames (the start-up work of a large map)
// pause the galaxy's clock until the game keeps up. Ends by itself after HOLD_MAX_MS; ignores frames while the game
// is in the background.
#define HOLD_SLOW_MS     700
#define HOLD_RELEASE_MS  1500
#define HOLD_MAX_MS      (2 * 60 * 1000)
static int start_hold_on, start_hold_paused;
static double hold_last, hold_quiet_since, hold_since;
static unsigned long hold_count;
static double hold_total_ms, hold_paused_at;

static void start_hold_release(void) {
    unsigned char *manager = module_base + RVA_BATTLE_MANAGER;
    if (start_hold_paused) {
        if (*(int *)(manager + 0x2c) > 0) lift_pause(manager, 1);
        start_hold_paused = 0;
        hold_total_ms += now_ms() - hold_paused_at;
    }
}

static void start_hold_tick(void) {
    if (!start_hold_on || !add_pause || !lift_pause || !module_base) return;
    double now = now_ms();
    double gap = hold_last != 0 ? now - hold_last : 0;
    hold_last = now;
    if (now - hold_since >= HOLD_MAX_MS) {
        start_hold_release();
        start_hold_on = 0;
        test_log("START HOLD: off (time limit)");
        return;
    }
    if (gap >= HOLD_SLOW_MS && (!game_window || !IsWindow(game_window))) {
        game_window = NULL;
        EnumWindows(find_game_window, 0);           // (looked up on a slow frame only: rare)
    }
    if (gap >= HOLD_SLOW_MS && (!game_window || GetForegroundWindow() == game_window)) {
        hold_quiet_since = now;
        if (!start_hold_paused) {
            add_pause(module_base + RVA_BATTLE_MANAGER);
            start_hold_paused = 1;
            hold_paused_at = now;
            hold_count++;
        }
    } else if (start_hold_paused && now - hold_quiet_since >= HOLD_RELEASE_MS) {
        start_hold_release();
    }
}

static int lua_start_hold(lua_State *L) {
    int on = lua_gettop(L) >= 1 && luaL_checknumber(L, 1) != 0;
    if (on && !start_hold_on) {
        start_hold_on = 1;
        hold_since = hold_last = now_ms();
        hold_count = 0;
        hold_total_ms = 0;
        test_log("START HOLD: on");
    } else if (!on && start_hold_on) {
        start_hold_release();
        start_hold_on = 0;
        char line[120];
        snprintf(line, sizeof line, "START HOLD: off; the clock was held %lu times, %.0f s in all", hold_count,
                 hold_total_ms / 1000);
        test_log(line);
    }
    lua_pushnumber(L, start_hold_on);
    return 1;
}

static int lua_ticks(lua_State *L) {
    lua_pushnumber(L, (double)GetTickCount());
    return 1;
}

// Engine_Play_Sound(event): plays a 2D sound event through the GUI's sound path (0x2d5010), usable outside a script.
#define RVA_PLAY_SOUND      0x2d5010
#define RVA_SOUND_MANAGER   0xb27e60
typedef struct { union { char buf[16]; char *ptr; } u; size_t size, cap; } msvc_string;
static int (*play_sound_fn)(void *, msvc_string *, int, char, unsigned);
static int lua_play_sound(lua_State *L) {
    const char *name = lua_gettop(L) >= 1 && lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    if (!name || !play_sound_fn) return 0;
    size_t n = strlen(name);
    msvc_string str;
    char *heap = NULL;
    memset(&str, 0, sizeof str);
    if (n < 16) {
        memcpy(str.u.buf, name, n + 1);
        str.cap = 15;
    } else {
        heap = (char *)malloc(n + 1);
        if (!heap) return 0;
        memcpy(heap, name, n + 1);
        str.u.ptr = heap;
        str.cap = n;
    }
    str.size = n;
    int handle = play_sound_fn(module_base + RVA_SOUND_MANAGER, &str, 0, 0, 0);
    free(heap);
    lua_pushnumber(L, (double)handle);      // the engine's result: a sound instance, or 0/-1 when none started
    return 1;
}

// Engine_Stop_Sound(handle): stops a sound Engine_Play_Sound started, as the engine's own kill (0x2d4250) does.
#define RVA_SFX_2D          0xa7d108
#define RVA_SFX_STREAM      0xa7d530
#define RVA_2D_PLAYING      0x228bf0    // (player, sound id) -> char
#define RVA_2D_STOP         0x228ac0    // (player, channel)
#define RVA_STREAM_PLAYING  0x22ac10
#define RVA_STREAM_STOP     0x22a9d0
static char (*sfx_2d_playing)(void *, int);
static void (*sfx_2d_stop)(void *, int);
static char (*sfx_stream_playing)(void *, int);
static void (*sfx_stream_stop)(void *, int);
static int lua_stop_sound(lua_State *L) {
    if (lua_gettop(L) < 1 || !sfx_2d_stop || !sfx_stream_stop) return 0;
    int handle = (int)luaL_checknumber(L, 1);
    unsigned char *manager = module_base + RVA_SOUND_MANAGER;
    int count = *(int *)(manager + 0x78);
    unsigned char **entries = *(unsigned char ***)(manager + 0x70);
    for (int i = 0; entries && i < count; i++) {
        unsigned char *e = entries[i];
        if (!e || *(int *)(e + 0x70) != handle) continue;
        int id = *(int *)(e + 0x40);
        int channel = *(int *)(e + 0x38), stream = *(int *)(e + 0x3c);
        if (id != 0 && channel >= 0 && sfx_2d_playing(module_base + RVA_SFX_2D, id) == 1) {
            sfx_2d_stop(module_base + RVA_SFX_2D, channel);
            *(int *)(e + 0x38) = -1;
        }
        if (id != 0 && stream >= 0 && sfx_stream_playing(module_base + RVA_SFX_STREAM, id) == 1) {
            sfx_stream_stop(module_base + RVA_SFX_STREAM, stream);
            *(int *)(e + 0x3c) = -1;
        }
        *(int *)(e + 0x30) = 0;
        *(int *)(e + 0x40) = 0;
        lua_pushnumber(L, 1);
        return 1;
    }
    return 0;
}

// Engine_Sound_Playing(handle): 1 while a sound Engine_Play_Sound started plays, 0 if its entry is there but
// silent (its id loaded, no channel playing it), -1 while it is still loading (id 0), nil once the entry is gone.
static int lua_sound_playing(lua_State *L) {
    if (lua_gettop(L) < 1 || !sfx_2d_playing || !sfx_stream_playing) return 0;
    int handle = (int)luaL_checknumber(L, 1);
    unsigned char *manager = module_base + RVA_SOUND_MANAGER;
    int count = *(int *)(manager + 0x78);
    unsigned char **entries = *(unsigned char ***)(manager + 0x70);
    for (int i = 0; entries && i < count; i++) {
        unsigned char *e = entries[i];
        if (!e || *(int *)(e + 0x70) != handle) continue;
        int id = *(int *)(e + 0x40);
        if (id == 0) { lua_pushnumber(L, -1); return 1; }
        int on = (*(int *)(e + 0x38) >= 0 && sfx_2d_playing(module_base + RVA_SFX_2D, id) == 1)
              || (*(int *)(e + 0x3c) >= 0 && sfx_stream_playing(module_base + RVA_SFX_STREAM, id) == 1);
        lua_pushnumber(L, on ? 1 : 0);
        return 1;
    }
    return 0;
}

static void hooked_click_sound(unsigned char *widget, char right) {
    orig_click_sound(widget, right);
    if (right == 1 && widget && widget_name) {
        const char *name = widget_name(widget);
        if (name && _strnicmp(name, "dp_", 3) != 0) queue_click(name, "right");
    }
}

// --- Screen text behind windows -------------------------------------------
// Engine_Screen_Text(false) hides the story SCREEN_TEXT messages while a window is open; true shows them again.
#define RVA_ADD_SCREEN_TEXT 0x2dfd10
static void (*orig_add_screen_text)(unsigned char *, void *, long long, float, int, char, float *);
static unsigned char *screen_text_manager;
static volatile int screen_text_hidden;

static void set_screen_text_hidden(int hidden) {
    unsigned char *m = screen_text_manager;
    if (!m) return;
    int count = *(int *)(m + 0x1178);
    void ***items = *(void ****)(m + 0x1170);
    for (int i = 0; items && i < count; i++) {
        unsigned char *widget = items[i] ? (unsigned char *)items[i][0] : NULL;
        if (widget) (*(void (**)(unsigned char *, char))(*(unsigned char **)widget + 0x78))(widget, (char)hidden);
    }
}

// A message whose id starts with "~" continues the previous message's line (a word in its own colour).
#define RVA_SCREEN_TEXT_LAYOUT 0x31d750
#define RVA_WIDGET_POSITION    0x352650
static void (*orig_screen_text_layout)(unsigned char *, float);
static void (*set_widget_position)(unsigned char *, float *, void *, char);
static int glued_text_on;
static int glued_item(unsigned char *item) {
    MsString *id = (MsString *)(item + 0x10);
    return id->size > 0 && (id->cap > 15 ? id->u.ptr : id->u.buf)[0] == '~';
}
static void hooked_screen_text_layout(unsigned char *manager, float elapsed) {
    orig_screen_text_layout(manager, elapsed);
    int count = *(int *)(manager + 0x1178);
    unsigned char **items = *(unsigned char ***)(manager + 0x1170);
    if (!items || count < 2 || !set_widget_position || !*(unsigned char **)items[0] || !*(unsigned char **)items[1])
        return;
    float spacing = *(float *)(*(unsigned char **)items[1] + 0x34) - *(float *)(*(unsigned char **)items[0] + 0x34);
    float shift = 0.0f;
    for (int i = 1; i < count; i++) {
        unsigned char *widget = *(unsigned char **)items[i];
        if (!widget) continue;
        float pos[2] = {*(float *)(widget + 0x30), *(float *)(widget + 0x34) - shift};
        if (glued_item(items[i])) {
            unsigned char *before = *(unsigned char **)items[i - 1];
            if (!before) continue;
            unsigned char *text = *(unsigned char **)(before + 0x670);
            pos[0] = *(float *)(before + 0x30) + (text ? (float)*(int *)(text + 0x10) : 0.0f);
            pos[1] = *(float *)(before + 0x34);
            shift += spacing;
        } else if (shift == 0.0f) continue;
        set_widget_position(widget, pos, NULL, 1);
    }
}
static void hooked_add_screen_text(unsigned char *manager, void *text, long long id, float time, int teletype,
                                   char flag, float *color) {
    screen_text_manager = manager;
    MsWString *w = (MsWString *)text, shown;
    static wchar_t glued[512];
    const char *name = (const char *)id;
    if (name && name[0] == '~' && w && w->size >= 1 && w->size < 512 && wstr_chars(w)[0] == L'~') {
        size_t len = w->size - 1;
        memcpy(glued, wstr_chars(w) + 1, len * sizeof(wchar_t));
        glued[len] = 0;
        memset(&shown, 0, sizeof shown);
        if (len <= 7) { memcpy(shown.u.buf, glued, (len + 1) * sizeof(wchar_t)); shown.cap = 7; }
        else { shown.u.ptr = glued; shown.cap = len; }
        shown.size = len;
        text = &shown;
    }
    orig_add_screen_text(manager, text, id, time, teletype, flag, color);
    if (screen_text_hidden) set_screen_text_hidden(1);
}
static int lua_glued_text(lua_State *L) { (void)L; return 0; }

// Engine_Screen_Text(visible): show or hide the galaxy's screen messages.
static int lua_screen_text(lua_State *L) {
    screen_text_hidden = lua_gettop(L) >= 1 && luaL_checknumber(L, 1) == 0;
    set_screen_text_hidden(screen_text_hidden);
    return 0;
}

// The listening (prefixes, frame ticks) is also kept in the script's globals, so a saved game listens again
// once loaded: the hook's own memory starts empty after the load closed the old scripts.
static void set_global_value(lua_State *L, const char *name, const char *text, double number) {
    if (!lua_rawset_fn || !room_for(L, 8, "a global value")) return;
    int top = lua_gettop(L);
    push_globals(L);
    lua_pushstring(L, name);
    if (text) lua_pushstring(L, text);
    else lua_pushnumber(L, number);
    lua_rawset_fn(L, top + 1);
    lua_settop(L, top);
}

static void listen_in(lua_State *L, const char *prefix) {
    gui_state = NULL;
    strncpy(gui_prefix, prefix, sizeof gui_prefix - 1);
    gui_prefix[sizeof gui_prefix - 1] = 0;
    void *g = *(void **)((unsigned char *)L + LUA_STATE_GLOBAL);
    for (int i = 0; i < main_state_count; i++) {
        if (main_globals[i] == g) gui_state = main_states[i];
    }
    gui_thread = GetCurrentThreadId();
}

static void reattach_gui(lua_State *L) {
    if (!lua_rawget_fn || !lua_tostring_fn || !room_for(L, 8, "the load")) return;
    int top = lua_gettop(L);
    push_globals(L);
    lua_pushstring(L, GUI_LISTEN_GLOBAL);
    lua_rawget_fn(L, top + 1);
    if (value_at(L, top + 2)->type == 4) {
        listen_in(L, lua_tostring_fn(L, top + 2));
        lua_pushstring(L, GUI_TICK_GLOBAL);
        lua_rawget_fn(L, top + 1);
        gui_tick_on = int_at(L, top + 3) != 0;
        gui_tick_last = GetTickCount();
        char line[400];
        snprintf(line, sizeof line, "GUI clicks on %s* go to Lua again after a load (state %s, ticks %s)",
                 gui_prefix, gui_state ? "found" : "NOT found", gui_tick_on ? "on" : "off");
        test_log(line);
    }
    lua_settop(L, top);
}

// Engine_Gui_Listen("prefix1,prefix2"): clicks on components named prefix... call DiplomacyGuiClick(name, button).
static int lua_gui_listen(lua_State *L) {
    const char *prefix = lua_gettop(L) >= 1 && lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    gui_state = NULL;
    gui_prefix[0] = 0;
    if (!prefix) return 0;
    listen_in(L, prefix);
    set_global_value(L, GUI_LISTEN_GLOBAL, gui_prefix, 0);
    char line[120];
    snprintf(line, sizeof line, "GUI clicks on %s* go to Lua (state %s)", gui_prefix, gui_state ? "found" : "NOT found");
    test_log(line);
    return 0;
}

// --- Particles between planets (the underworld's lane haze) -----------------------------------------
// Engine_Spawn_Between(planet A, planet B, particle[, t0, t1, spacing]) spawns a particle, or a row of them, along
// the lane, as FoC does for its corruption line (0x3ff230). Returns how many were spawned.
#define RVA_GAME_OBJECTS    0xb15418    // pointer; its [3] is the game object manager
#define RVA_OBJECTS_OF_TYPE 0x2a87d0    // (manager, type, 0) -> list: +8 items (object**), +0x10 count
static long long (*objects_of_type)(void *, unsigned char *, long long);

static unsigned char *type_by_name(const char *name) {
    if (!find_type || !name) return NULL;
    MsString s;
    memset(&s, 0, sizeof s);
    size_t n = strlen(name);
    if (n < 16) { memcpy(s.u.buf, name, n); s.cap = 15; }
    else { s.u.ptr = (char *)name; s.cap = n; }
    s.size = n;
    return find_type(module_base + RVA_TYPE_MANAGER, &s);
}

static unsigned char *first_object_of(void *manager, unsigned char *type) {
    long long list = objects_of_type(manager, type, 0);
    if (!list || *(int *)(list + 0x10) <= 0) return NULL;
    unsigned char **items = *(unsigned char ***)(list + 8);
    return items ? items[0] : NULL;
}

static int lua_spawn_between(lua_State *L) {
    const char *a = lua_gettop(L) >= 3 && lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    const char *b = a ? lua_tostring_fn(L, 2) : NULL;
    const char *particle = b ? lua_tostring_fn(L, 3) : NULL;
    int ok = 0;
    void **objects = *(void ***)(module_base + RVA_GAME_OBJECTS);
    if (particle && objects && objects_of_type && orig_battle_spawn && get_local_player) {
        void *manager = objects[3];
        unsigned char *pa = first_object_of(manager, type_by_name(a));
        unsigned char *pb = first_object_of(manager, type_by_name(b));
        unsigned char *ptype = type_by_name(particle);
        unsigned char *local = get_local_player(module_base + RVA_PLAYER_LIST);
        if (pa && pb && ptype && local) {
            float t0 = 0.5f, t1 = 0.5f, spacing = 0, delta[3], length = 0;
            if (lua_gettop(L) >= 6) {
                const char *s0 = lua_tostring_fn(L, 4), *s1 = lua_tostring_fn(L, 5), *s2 = lua_tostring_fn(L, 6);
                if (s0 && s1 && s2) { t0 = (float)atof(s0); t1 = (float)atof(s1); spacing = (float)atof(s2); }
            }
            for (int i = 0; i < 3; i++) {
                delta[i] = *(float *)(pb + 0x78 + 4 * i) - *(float *)(pa + 0x78 + 4 * i);
                length += delta[i] * delta[i];
            }
            length = sqrtf(length);
            int n = 1;
            if (spacing > 1.0f) {
                n = (int)(length * fabsf(t1 - t0) / spacing) + 1;
                if (n > 40) n = 40;
            }
            static int logged;
            if (logged < 3) {
                char line[120];
                snprintf(line, sizeof line, "Spawn_Between %s-%s length %.0f: %d particles", a, b, length, n);
                test_log(line);
                logged++;
            }
            for (int k = 0; k < n; k++) {
                float t = (n == 1) ? (t0 + t1) * 0.5f : t0 + (t1 - t0) * k / (float)(n - 1);
                float pos[3], facing[4] = {0, 0, 0, 0};
                for (int i = 0; i < 3; i++) pos[i] = *(float *)(pa + 0x78 + 4 * i) + delta[i] * t;
                if (orig_battle_spawn(manager, ptype, *(int *)(local + 0x4c), pos, facing, 0, 0, 0, 0, 0)) ok++;
            }
        }
    }
    lua_pushnumber(L, ok);
    return 1;
}

// --- Reinforcement timers ------------------------------------------------------------------------------------
// Fleets in hyperspace headed at a battle the human fights in are noted with their time left (positions sampled by
// Engine_Fleet_Sample). Engine_Inbound() lists them; Engine_Inbound_Arrive(i) puts a fleet's units into its owner's
// reinforcement pool.
#define RVA_MODES           0xb153e0    // the game modes (galactic, battle)
#define RVA_PARENT_MODE     0x28aa00    // (modes, battle mode) -> the galactic mode it belongs to (0 in skirmish)
#define RVA_MODE_DATA       0x28aaa0    // (modes, battle mode) -> the galactic side's battle data
#define RVA_MAP_AT          0x045af0    // (map, &iterator, &key) -> iterator (find or insert)
#define RVA_INT_VECTOR_GROW 0x021ec0    // DynamicVectorClass<int>::Resize(new capacity, 0, 1)
#define RVA_POOL_CHANGED    0x4d31a0    // (player's battle reinforcements, index, -1): the pool shown again
#define RVA_PLAYER_MODE     0x4b06d0    // (player +0x360 list) -> the player's entry for the current mode
static long long (*parent_mode)(void *, long long);
static unsigned char *(*mode_data)(void *, long long);
static long long *(*map_at)(void *, long long *, int *);
static void (*int_vector_grow)(void *, unsigned, char, char);
static void (*pool_changed)(unsigned char *, long long, long long);
static unsigned char *(*player_mode)(unsigned char *);

#define MAX_TRACKED 1024
typedef struct { unsigned char *fleet; float pos[3], v[3], speed; double t; unsigned char *at, *from; } Tracked;
// speed: its last while moving; at: the world whose orbit it is in (its box +0x40); from: the world it was at before
static Tracked tracks_a[MAX_TRACKED], tracks_b[MAX_TRACKED];
static Tracked *tracks = tracks_a;
static double last_sample;
static unsigned char *fleet_type;

static Tracked *track_slot(Tracked *table, unsigned char *fleet, int create) {
    unsigned i = (unsigned)(((uintptr_t)fleet >> 4) * 2654435761u) & (MAX_TRACKED - 1);
    for (int n = 0; n < MAX_TRACKED; n++, i = (i + 1) & (MAX_TRACKED - 1)) {
        if (table[i].fleet == fleet) return &table[i];
        if (!table[i].fleet) {
            if (!create) return NULL;
            table[i].fleet = fleet;
            return &table[i];
        }
    }
    return NULL;
}

static long long galactic_fleets(void) {
    void **objects = *(void ***)(module_base + RVA_GAME_OBJECTS);
    if (!objects || !objects_of_type) return 0;
    if (!fleet_type) fleet_type = type_by_name("Galactic_Fleet");
    return fleet_type ? objects_of_type(objects[3], fleet_type, 0) : 0;
}

// Engine_Fleet_Sample(game time): every fleet's position (at most every 0.4 s of game time).
static int lua_fleet_sample(lua_State *L) {
    double now = lua_gettop(L) >= 1 ? luaL_checknumber(L, 1) : 0;
    if (now >= last_sample && now - last_sample < 0.4) return 0;
    last_sample = now;
    long long list = galactic_fleets();
    if (!list) return 0;
    int n = *(int *)(list + 0x10);
    unsigned char **items = *(unsigned char ***)(list + 8);
    Tracked *next = (tracks == tracks_a) ? tracks_b : tracks_a;
    memset(next, 0, sizeof tracks_a);
    for (int i = 0; items && i < n; i++) {
        unsigned char *f = items[i];
        if (!f) continue;
        Tracked *old = track_slot(tracks, f, 0), *s = track_slot(next, f, 1);
        if (!s) break;
        for (int k = 0; k < 3; k++) s->pos[k] = *(float *)(f + 0x78 + 4 * k);
        s->t = now;
        unsigned char *box = *(unsigned char **)(f + 0xc0);
        unsigned char *at = box ? *(unsigned char **)(box + 0x40) : NULL;
        s->at = old ? old->at : NULL;
        s->from = old ? old->from : NULL;
        if (at && at != s->at) {
            if (s->at) s->from = s->at;
            s->at = at;
        }
        if (old && now - old->t > 0.05) {
            for (int k = 0; k < 3; k++) s->v[k] = (float)((s->pos[k] - old->pos[k]) / (now - old->t));
            float speed = sqrtf(s->v[0] * s->v[0] + s->v[1] * s->v[1] + s->v[2] * s->v[2]);
            s->speed = speed >= 0.5f ? speed : old->speed;
        } else if (old) {
            memcpy(s->v, old->v, sizeof s->v);
            memcpy(s->pos, old->pos, sizeof s->pos);
            s->t = old->t;
            s->speed = old->speed;
        }
    }
    tracks = next;
    return 0;
}

#define MAX_INBOUND 64
#define MAX_INBOUND_UNITS 64
typedef struct {
    unsigned char *fleet;
    unsigned char *origin;          // a fleet in orbit of a neighbouring world (border reinforcements), else NULL
    char origin_name[48];
    char left_name[48];             // the world it set off from (a border fleet's own world)
    int owner, count, arrived, retreated;       // retreated: it jumped out of the battle (Engine_Inbound_Retreat)
    float eta, heading;
    int ids[MAX_INBOUND_UNITS];
    unsigned char *types[MAX_INBOUND_UNITS];
} Inbound;
static Inbound inbound[MAX_INBOUND];
static unsigned char *inbound_planet;

// Whether a fleet flying this way meets another world first (it is bound there, not for the battle: a fleet's next
// stop lies straight ahead on its hyperlane). The worlds: the galactic GUI's planet rows (+0xde0, count +0xde8).
static int nearer_stop(unsigned char *planet, unsigned char *f, const float *v, float speed, float dist) {
    unsigned char *gui = module_base + 0xb27f60;
    int count = *(int *)(gui + 0xde8);
    unsigned char *rows = *(unsigned char **)(gui + 0xde0);
    if (!rows || count <= 0 || count > 4096) return 0;
    for (int i = 0; i < count; i++) {
        unsigned char *q = *(unsigned char **)(rows + (long long)i * 0x188);
        if (!q || q == planet || !readable(q + 0x78, 12)) continue;
        float u[3], len = 0, along = 0;
        for (int k = 0; k < 3; k++) {
            u[k] = *(float *)(q + 0x78 + 4 * k) - *(float *)(f + 0x78 + 4 * k);
            len += u[k] * u[k];
            along += u[k] * v[k];
        }
        len = sqrtf(len);
        if (len < 1.0f || len >= dist - 1.0f) continue;
        if (along / (speed * len) >= 0.999f) return 1;
    }
    return 0;
}

// Border reinforcements: fleets one hyperlane away also join, if they belong to a side or to a side's ally at war
// with the other side (lanes and treaties come from the script). Survivors are moved to the battle's world after.
#define RVA_LEAVE_ORBIT     0x4358c0    // (fleet's behaviour 4, fleet, planet): the fleet leaves that world's orbit
static void (*leave_orbit)(void *, unsigned char *, unsigned char *);
#define MAX_BORDER_WORLDS 1200
#define MAX_BONDS 96
static struct { char name[40]; char next[360]; } border_lanes[MAX_BORDER_WORLDS];
static int border_lane_count;
static char border_bonds[MAX_BONDS][2][40];
static int border_bond_count;
static int enemies_in_orbit(unsigned char *planet, int owner);

static int bonded(int a, int b) {
    const char *na = player_name(a), *nb = player_name(b);
    for (int i = 0; i < border_bond_count; i++) {
        if ((!_stricmp(border_bonds[i][0], na) && !_stricmp(border_bonds[i][1], nb))
            || (!_stricmp(border_bonds[i][0], nb) && !_stricmp(border_bonds[i][1], na))) return 1;
    }
    return 0;
}

// The side a fleet's owner fights on, or -1 when it stays out.
static int border_side(int owner, int attacker, int defender) {
    if (owner == attacker || owner == defender) return owner;
    if (bonded(owner, defender) && !bonded(owner, attacker) && relation(owner, attacker) == 1) return defender;
    if (bonded(owner, attacker) && !bonded(owner, defender) && relation(owner, defender) == 1) return attacker;
    return -1;
}

// A world's hyperlanes: its system's lane list (+0x40, 0x10 bytes each: the other world, that lane's line; count
// +0x48), as the engine's lane refresh (0x3ffc20) reads it.
static int lane_count_of(unsigned char *planet) {
    unsigned char *sys = planet ? *(unsigned char **)(planet + 0xb8) : NULL;
    return sys && *(unsigned char **)(sys + 0x40) ? *(int *)(sys + 0x48) : 0;
}
static unsigned char *lane_other(unsigned char *planet, int i) {
    unsigned char *sys = *(unsigned char **)(planet + 0xb8);
    return *(unsigned char **)(*(unsigned char **)(sys + 0x40) + (long long)i * 0x10);
}
static unsigned char *lane_line(unsigned char *planet, int i) {
    unsigned char *sys = *(unsigned char **)(planet + 0xb8);
    return *(unsigned char **)(*(unsigned char **)(sys + 0x40) + (long long)i * 0x10 + 8);
}

static void note_border(unsigned char *planet, int attacker, int defender) {
    if (!fleet_type || !object_type || lane_count_of(planet) <= 0) return;
    float total = 0;                                   // the moving fleets' average speed
    int moving = 0;
    for (int i = 0; i < MAX_TRACKED; i++)
        if (tracks[i].fleet && tracks[i].speed >= 0.5f) { total += tracks[i].speed; moving++; }
    float average = moving ? total / moving : 0;
    float *p = (float *)(planet + 0x78);
    int lanes = lane_count_of(planet);
    for (int lane = 0; lane < lanes && lane < 64; lane++) {
        unsigned char *there = lane_other(planet, lane);
        unsigned char *sys = there && there != planet ? *(unsigned char **)(there + 0xb8) : NULL;
        if (!sys) continue;
        char world[48];
        snprintf(world, sizeof world, "%s", type_name(there));
        DynVec *orbit = (DynVec *)(sys + 0xc0);
        float w[3], dist = 0;
        for (int k = 0; k < 3; k++) {
            w[k] = p[k] - *(float *)(there + 0x78 + 4 * k);
            dist += w[k] * w[k];
        }
        dist = sqrtf(dist);
        for (int i = 0; i < orbit->count && inbound_count < MAX_INBOUND; i++) {
            unsigned char *f = orbit->items[i];
            if (!f || (*(unsigned char *)(f + 0x3a0) & 2) || object_type(f) != fleet_type) continue;
            int owner = *(int *)(f + 0x58);
            int side = owner >= 0 ? border_side(owner, attacker, defender) : -1;
            if (side < 0) continue;                    // (also over an enemy's world)
            Tracked *s = track_slot(tracks, f, 0);
            float speed = (s && s->speed >= 0.5f) ? s->speed : average;
            Inbound *in = &inbound[inbound_count];
            in->fleet = f;
            in->origin = there;
            snprintf(in->origin_name, sizeof in->origin_name, "%s", world);
            snprintf(in->left_name, sizeof in->left_name, "%s", world);
            in->arrived = 0;
            in->retreated = 0;
            in->owner = owner;
            in->eta = speed >= 0.5f ? dist / speed : 10.0f;
            in->heading = atan2f(w[1], w[0]) * 57.2957795f;
            if (in->heading < 0) in->heading += 360.0f;
            in->count = 0;
            unsigned char *box = *(unsigned char **)(f + 0xc0);
            int units = box ? *(int *)(box + 0x18) : 0;
            for (int k = 0; k < units && in->count < MAX_INBOUND_UNITS; k++) {
                unsigned char *u = (*(unsigned char ***)(box + 0x10))[k];
                if (!u) continue;
                in->ids[in->count] = *(int *)(u + 0x50);
                in->types[in->count] = object_type(u);
                in->count++;
            }
            if (in->count == 0) continue;
            inbound_count++;
            if (owner != attacker && owner != defender) note_battle_ally(side, owner);
            char line[220];
            snprintf(line, sizeof line, "BORDER: %s fleet of %d at %s, %.1f s from the battle (%.0f units at %.1f/s)",
                     player_name(owner), in->count, world, in->eta, dist, speed);
            test_log(line);
        }
    }
}

// Engine_Border_Lanes(world, "WORLD,WORLD,..."): that world's hyperlanes; no arguments forgets them all.
static int lua_border_lanes(lua_State *L) {
    const char *world = lua_gettop(L) >= 2 && lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    const char *next = world ? lua_tostring_fn(L, 2) : NULL;
    if (!world || !next) {
        border_lane_count = 0;
        return 0;
    }
    int i = 0;
    while (i < border_lane_count && _stricmp(border_lanes[i].name, world)) i++;
    if (i == border_lane_count) {
        if (border_lane_count >= MAX_BORDER_WORLDS) return 0;
        border_lane_count++;
    }
    strncpy(border_lanes[i].name, world, sizeof border_lanes[i].name - 1);
    border_lanes[i].name[sizeof border_lanes[i].name - 1] = 0;
    strncpy(border_lanes[i].next, next, sizeof border_lanes[i].next - 1);
    border_lanes[i].next[sizeof border_lanes[i].next - 1] = 0;
    return 0;
}

// Engine_Border_Bonds("A|B;C|D"): the pairs of powers whose treaties bring each other's border fleets in
// (alliances, vassals, protectorates).
static int lua_border_bonds(lua_State *L) {
    const char *text = lua_gettop(L) >= 1 && lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    border_bond_count = 0;
    if (!text) return 0;
    static char copy[MAX_BONDS * 80];
    strncpy(copy, text, sizeof copy - 1);
    copy[sizeof copy - 1] = 0;
    char *rest = NULL;
    for (char *pair = strtok_s(copy, ";", &rest); pair && border_bond_count < MAX_BONDS;
         pair = strtok_s(NULL, ";", &rest)) {
        char *bar = strchr(pair, '|');
        if (!bar) continue;
        *bar = 0;
        strncpy(border_bonds[border_bond_count][0], pair, 39);
        border_bonds[border_bond_count][0][39] = 0;
        strncpy(border_bonds[border_bond_count][1], bar + 1, 39);
        border_bonds[border_bond_count][1][39] = 0;
        border_bond_count++;
    }
    return 0;
}

// The attacker's hyperlane into the battle's world in degrees, or -1 (Engine_Battle_Lane).
static float battle_lane = -1;

static char battle_from[48];       // the world the attacker's fleet came from
static void note_battle_lane(unsigned char *planet, int attacker) {
    battle_lane = -1;
    battle_from[0] = 0;
    unsigned char *sys = *(unsigned char **)(planet + 0xb8);
    DynVec *orbit = sys ? (DynVec *)(sys + 0xc0) : NULL;
    for (int i = 0; orbit && i < orbit->count && battle_lane < 0; i++) {
        unsigned char *f = orbit->items[i];
        if (!f || *(int *)(f + 0x58) != attacker) continue;
        Tracked *s = track_slot(tracks, f, 0);
        unsigned char *from = s ? (s->at == planet ? s->from : s->at) : NULL;
        if (!from || from == planet) continue;
        float dx = *(float *)(planet + 0x78) - *(float *)(from + 0x78);
        float dy = *(float *)(planet + 0x7c) - *(float *)(from + 0x7c);
        battle_lane = atan2f(dy, dx) * 57.2957795f;
        if (battle_lane < 0) battle_lane += 360.0f;
        snprintf(battle_from, sizeof battle_from, "%s", type_name(from));
    }
}

static void note_inbound(unsigned char *planet, int attacker, int defender) {
    inbound_count = 0;
    note_battle_lane(planet, attacker);
    inbound_planet = planet;
    long long list = galactic_fleets();
    if (!list || !planet) return;
    int n = *(int *)(list + 0x10);
    unsigned char **items = *(unsigned char ***)(list + 8);
    float *p = (float *)(planet + 0x78);
    for (int i = 0; items && i < n && inbound_count < MAX_INBOUND; i++) {
        unsigned char *f = items[i];
        Tracked *s = f ? track_slot(tracks, f, 0) : NULL;
        if (!s) continue;
        float speed = sqrtf(s->v[0] * s->v[0] + s->v[1] * s->v[1] + s->v[2] * s->v[2]);
        float w[3], dist = 0, dot = 0;
        for (int k = 0; k < 3; k++) {
            w[k] = p[k] - *(float *)(f + 0x78 + 4 * k);
            dist += w[k] * w[k];
            dot += w[k] * s->v[k];
        }
        dist = sqrtf(dist);
        if (speed < 0.5f || dist < 1.0f || dot / (speed * dist) < 0.995f) continue;
        if (nearer_stop(planet, f, s->v, speed, dist)) continue;
        int owner = *(int *)(f + 0x58);
        if (owner < 0) continue;
        Inbound *in = &inbound[inbound_count];
        in->fleet = f;
        in->origin = NULL;
        in->origin_name[0] = 0;
        unsigned char *left = s->at ? s->at : s->from;
        snprintf(in->left_name, sizeof in->left_name, "%s", left && left != planet ? type_name(left) : "");
        in->arrived = 0;
        in->retreated = 0;
        in->owner = owner;
        in->eta = dist / speed;
        in->heading = atan2f(s->v[1], s->v[0]) * 57.2957795f;     // (fleets on one hyperlane share it)
        if (in->heading < 0) in->heading += 360.0f;
        in->count = 0;
        unsigned char *box = *(unsigned char **)(f + 0xc0);
        int units = box ? *(int *)(box + 0x18) : 0;
        for (int k = 0; k < units && in->count < MAX_INBOUND_UNITS; k++) {
            unsigned char *u = (*(unsigned char ***)(box + 0x10))[k];
            if (!u) continue;
            in->ids[in->count] = *(int *)(u + 0x50);
            in->types[in->count] = object_type ? object_type(u) : NULL;
            in->count++;
        }
        if (in->count == 0) continue;
        inbound_count++;
        char line[200];
        snprintf(line, sizeof line, "INBOUND: %s fleet of %d, %.1f s from the battle (%.0f units at %.1f/s)",
                 player_name(owner), in->count, in->eta, dist, speed);
        test_log(line);
    }
    note_border(planet, attacker, defender);
}


// A fleet in hyperspace pulled into a world's orbit, as the engine does when a battle starts (0x569700).
#define RVA_PULL_IN         0x569700    // (?, the attacker's fleet, planet): the sides' inbound fleets into orbit
#define RVA_FLEET_TO_ORBIT  0x4338d0
#define RVA_FLEET_STOP_A    0x4355f0
#define RVA_FLEET_STOP_B    0x435690
#define RVA_ORBIT_LIST      0x058570
#define RVA_ORBIT_ADD       0x220ed0
static void (*orig_pull_in)(void *, unsigned char *, unsigned char *);
static unsigned long long (*fleet_to_orbit)(void *, unsigned char *, unsigned char *, int, char);
static void (*fleet_stop_a)(void *, unsigned char *, long long);
static void (*fleet_stop_b)(void *, unsigned char *, long long);
static void *(*orbit_list)(void);
static void (*orbit_add)(void *, void *);

static void pull_into_orbit(unsigned char *fleet, unsigned char *planet) {
    if (!fleet_to_orbit || !fleet || !planet) return;
    typedef void *(*behaviour_fn)(unsigned char *, int);
    void *behaviour = ((behaviour_fn)(*(void ***)fleet)[2])(fleet, 4);
    if (!behaviour) return;
    fleet_to_orbit(behaviour, fleet, planet, -2, 1);
    fleet_stop_a(behaviour, fleet, 0);
    fleet_stop_b(behaviour, fleet, 0);
    unsigned char *loco = *(unsigned char **)(fleet + 0xa8);
    if (loco && *(long long *)(loco + 0xc0) != *(long long *)(loco + 0xb8))
        *(long long *)(loco + 0xc0) = *(long long *)(loco + 0xb8);
    unsigned char *box = *(unsigned char **)(fleet + 0xc0);
    if (box) *(box + 0x7c) = 1;
    orbit_add(orbit_list(), fleet + 0x38);
}

// In a battle the human fights in, the two sides' fleets in hyperspace are not pulled in at the start: they come
// through the reinforcement timers instead (the fleets of AI-only battles are pulled in as before).
static void hooked_pull_in(void *a, unsigned char *fleet, unsigned char *planet) {
    unsigned char *local = get_local_player ? get_local_player(module_base + RVA_PLAYER_LIST) : NULL;
    int human = local ? *(int *)(local + 0x4c) : -1;
    if (fleet && planet && human >= 0 && (*(int *)(fleet + 0x58) == human || *(int *)(planet + 0x58) == human)
        && diplomacy_loaded()) {
        test_log("INBOUND: the sides' fleets in hyperspace are left to the reinforcement timers");
        return;
    }
    orig_pull_in(a, fleet, planet);
}

// Whether a player's enemies still hold a world's orbit after a battle (ships, or the starbase).
static int enemies_in_orbit(unsigned char *planet, int owner) {
    unsigned char *sys = planet ? *(unsigned char **)(planet + 0xb8) : NULL;
    if (!sys) return 0;
    if (*(int *)(sys + 0x148) > 0 && *(int *)(sys + 0x13c) >= 0 && relation(owner, *(int *)(sys + 0x13c)) == 1) return 1;
    DynVec *orbit = (DynVec *)(sys + 0xc0);
    for (int i = 0; i < orbit->count; i++) {
        unsigned char *object = orbit->items[i];
        if (object && *(int *)(object + 0x58) >= 0 && relation(owner, *(int *)(object + 0x58)) == 1) return 1;
    }
    return 0;
}

// Engine_Inbound_Settle(): after the battle, fleets that arrived in it are put in orbit. Returns
// "owner|stay" or "owner|retreat" per fleet.
static int owner_fleet_in_orbit(unsigned char *planet, int owner, int skip_border) {
    unsigned char *sys = planet ? *(unsigned char **)(planet + 0xb8) : NULL;
    if (!sys || !fleet_type || !object_type) return 0;
    DynVec *orbit = (DynVec *)(sys + 0xc0);
    for (int i = 0; i < orbit->count; i++) {
        unsigned char *f = orbit->items[i];
        if (!f || *(int *)(f + 0x58) != owner || object_type(f) != fleet_type) continue;
        int border = 0;
        for (int k = 0; skip_border && k < inbound_count; k++) if (inbound[k].fleet == f && inbound[k].origin) border = 1;
        if (!border) return 1;
    }
    return 0;
}

static int lua_inbound_settle(lua_State *L) {
    static char out[6000];
    int used = 0;
    // 1: the battle goes on without the human (Engine_Battle_Continue next): border fleets stay at the battle's world
    int go_on = lua_gettop(L) >= 1 && luaL_checknumber(L, 1) != 0;
    out[0] = 0;
    inbound_unsettled = 0;
    long long list = galactic_fleets();
    int n = list ? *(int *)(list + 0x10) : 0;
    unsigned char **items = list ? *(unsigned char ***)(list + 8) : NULL;
    for (int i = 0; i < inbound_count; i++) {
        if (!inbound[i].arrived) continue;
        inbound[i].arrived = 0;
        int alive = 0;
        for (int k = 0; items && k < n; k++) if (items[k] == inbound[i].fleet) alive = 1;
        unsigned char *box = alive ? *(unsigned char **)(inbound[i].fleet + 0xc0) : NULL;
        int units = box ? *(int *)(box + 0x18) : 0;
        int retreat = alive && units > 0 && enemies_in_orbit(inbound_planet, inbound[i].owner);
        char line[160];
        snprintf(line, sizeof line, "INBOUND: %s fleet %d after the battle: %s, %d units%s", player_name(inbound[i].owner),
                 i + 1, alive ? "alive" : "gone", units, retreat ? ", retreats" : "");
        test_log(line);
        if (alive && units > 0 && inbound[i].origin && ((!go_on && retreat) || inbound[i].retreated
                                                         || owner_fleet_in_orbit(inbound_planet, inbound[i].owner, 1))) {
            // a border fleet that left the fight, lost it, or would merge into a fleet of its owner's there: it is
            // still at its own world (it never left it on the galaxy map)
            continue;
        } else if (alive && units > 0 && inbound[i].origin && go_on) {
            typedef void *(*behaviour_fn)(unsigned char *, int);
            void *behaviour = ((behaviour_fn)(*(void ***)inbound[i].fleet)[2])(inbound[i].fleet, 4);
            if (!behaviour || !leave_orbit) continue;
            leave_orbit(behaviour, inbound[i].fleet, inbound[i].origin);
            pull_into_orbit(inbound[i].fleet, inbound_planet);
            if (used < (int)sizeof out - 80)
                used += snprintf(out + used, sizeof out - used, "%s|stay\n", player_name(inbound[i].owner));
        } else if (alive && units > 0 && inbound[i].origin) {
            // from a neighbouring world: out of its orbit, into the battle's; the script sends it home
            typedef void *(*behaviour_fn)(unsigned char *, int);
            void *behaviour = ((behaviour_fn)(*(void ***)inbound[i].fleet)[2])(inbound[i].fleet, 4);
            if (!behaviour || !leave_orbit) continue;
            leave_orbit(behaviour, inbound[i].fleet, inbound[i].origin);
            pull_into_orbit(inbound[i].fleet, inbound_planet);
            if (used < (int)sizeof out - 200) {
                used += snprintf(out + used, sizeof out - used, "%s|%s|%s|", player_name(inbound[i].owner),
                                 retreat ? "retreat" : "stay", inbound[i].origin_name);
                for (int k = 0; k < units && used < (int)sizeof out - 60; k++) {
                    unsigned char *u = (*(unsigned char ***)(box + 0x10))[k];
                    if (u) used += snprintf(out + used, sizeof out - used, "%s%s", k ? "," : "", type_name(u));
                }
                used += snprintf(out + used, sizeof out - used, "\n");
            }
        } else if (alive && units > 0) {
            pull_into_orbit(inbound[i].fleet, inbound_planet);
            if (used < (int)sizeof out - 80)
                used += snprintf(out + used, sizeof out - used, "%s|%s\n", player_name(inbound[i].owner),
                                 (retreat && !go_on) || inbound[i].retreated ? "retreat" : "stay");
        }
    }
    inbound_count = 0;
    lua_pushstring(L, out);
    return 1;
}


// Battles with more than two teams: while the player's side and an enemy both have ships, Engine_Battle_Hold(1)
// holds the victory checks (0x344710). They are run again when the hold ends.
#define RVA_VICTORY_CHECK   0x344710
#define MAX_HELD 48
static char (*orig_victory_check)(long long *, long long *, int, int);
static int battle_hold, held_count, held_ids[MAX_HELD], held_extra[MAX_HELD];
static long long *held_manager, *held_conditions;
static long long *last_conditions_logged;

static char hooked_victory_check(long long *manager, long long *conditions, int type, int player) {
    held_manager = manager;                            // (kept for Engine_Battle_End_Check)
    held_conditions = conditions;
    if (conditions && conditions != last_conditions_logged && conditions[0] && conditions[1] > conditions[0]) {
        last_conditions_logged = conditions;           // the battle's conditions, once: "type/player" pairs
        char line[600];
        int used = snprintf(line, sizeof line, "VICTORY CONDITIONS:");
        for (long long e = conditions[0]; e < conditions[1] && used < (int)sizeof line - 24; e += 0x30)
            used += snprintf(line + used, sizeof line - used, " %d/%s", *(int *)e, player_name(*(int *)(e + 4)));
        test_log(line);
    }
    if (battle_hold) {
        int known = 0;
        for (int i = 0; i < held_count; i++) if (held_ids[i] == type && held_extra[i] == player) known = 1;
        if (!known && held_count < MAX_HELD) {
            held_extra[held_count] = player;
            held_ids[held_count++] = type;
            char line[120];
            snprintf(line, sizeof line, "BATTLE HOLD: victory check %d for %s held", type, player_name(player));
            test_log(line);
        }
        return 0;
    }
    return orig_victory_check(manager, conditions, type, player);
}

// Engine_Battle_End_Check(): after the human's retreat, tests the retreat condition for every power at war with
// the human. Returns 1 when one of them won.
static int lua_battle_end_check(lua_State *L) {
    int won = 0;
    unsigned char *local = get_local_player ? get_local_player(module_base + RVA_PLAYER_LIST) : NULL;
    if (local && held_manager && held_conditions && orig_victory_check && human_retreated) {
        int human = *(int *)(local + 0x4c);
        for (int p = 0; p < 64 && !won; p++) {
            if (p == human || !get_player_by_id(module_base + RVA_PLAYER_LIST, p) || relation(p, human) != 1) continue;
            if (orig_victory_check(held_manager, held_conditions, 0xc, p)) {
                won = 1;
                char line[120];
                snprintf(line, sizeof line, "RETREAT: %s wins the battle the human left", player_name(p));
                test_log(line);
            }
        }
    }
    lua_pushnumber(L, won);
    return 1;
}

static void battle_hold_reset(void) {
    battle_hold = 0;
    held_count = 0;
    held_manager = held_conditions = NULL;
}

// Engine_Battle_Hold(on): 1 holds the battle's victory checks, 0 ends the hold and makes the held checks.
static int lua_battle_hold(lua_State *L) {
    int on = lua_gettop(L) >= 1 && luaL_checknumber(L, 1) != 0;
    if (on == battle_hold) return 0;
    battle_hold = on;
    char line[120];
    snprintf(line, sizeof line, "BATTLE HOLD: %s (%d checks held)", on ? "on" : "off", held_count);
    test_log(line);
    if (!on) {
        int n = held_count;
        held_count = 0;
        for (int i = 0; i < n && held_manager && orig_victory_check; i++)
            orig_victory_check(held_manager, held_conditions, held_ids[i], held_extra[i]);
    }
    return 0;
}


// Engine_Battle_Allies(): one line per power that joined the battle beside a side: "ally faction|side faction".
static int lua_battle_allies(lua_State *L) {
    static char out[600];
    int used = 0;
    out[0] = 0;
    for (int i = 0; i < battle_ally_count && used < (int)sizeof out - 80; i++)
        used += snprintf(out + used, sizeof out - used, "%s|%s\n", player_name(battle_allies[i][1]),
                         player_name(battle_allies[i][0]));
    lua_pushstring(L, out);
    return 1;
}

// Engine_Pool_Types(faction): the unit types in that power's reinforcement pool ("" if not a side).
static int lua_pool_types(lua_State *L) {
    static char out[3000];
    int used = 0;
    out[0] = 0;
    const char *name = lua_gettop(L) >= 1 && lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    int id = -1;
    for (int i = 0; name && i < 64; i++) {
        if (get_player_by_id(module_base + RVA_PLAYER_LIST, i) && !_stricmp(player_name(i), name)) { id = i; break; }
    }
    long long current = *(long long *)(module_base + RVA_GAME_OBJECTS);
    long long galactic = (current && parent_mode) ? parent_mode(module_base + RVA_MODES, current) : 0;
    unsigned char *data = galactic ? mode_data(module_base + RVA_MODES, current) : NULL;
    // only a side of the battle has a pool: the map lookup inserts a missing player (a pool with no reinforcement
    // manager, which the engine then crashes on)
    unsigned char *player = id >= 0 ? get_player_by_id(module_base + RVA_PLAYER_LIST, id) : NULL;
    unsigned char *list = player ? *(unsigned char **)(player + 0x360) : NULL;
    unsigned char *entry = (list && player_mode) ? player_mode(list) : NULL;
    unsigned char *shown = (entry && *(unsigned char **)(entry + 0x50))
        ? *(unsigned char **)(*(unsigned char **)(entry + 0x50) + 0x38) : NULL;
    if (id >= 0 && shown && data && map_at && object_type) {
        int key = id;
        long long it = 0;
        long long *found = map_at(data + 0x40, &it, &key);
        unsigned char *node = found ? *(unsigned char **)found : NULL;
        unsigned char *manager = *(unsigned char **)(galactic + 0x18);
        int count = node ? *(int *)(node + 0x28) : 0;
        for (int k = 0; manager && k < count && used < (int)sizeof out - 80; k++) {
            int object_id = (*(int **)(node + 0x20))[k];
            if (object_id == 0x3fffff) continue;
            unsigned char *object = object_by_id(manager, object_id);
            unsigned char *type = object ? object_type(object) : NULL;
            if (type) used += snprintf(out + used, sizeof out - used, "%s%s", used ? "," : "", std_string(type + 0xf8));
        }
    }
    lua_pushstring(L, out);
    return 1;
}

static int lua_spawn_facing(lua_State *L) {
    if (lua_gettop(L) < 2) {
        spawn_facing_on = 0;
        return 0;
    }
    float dx = (float)luaL_checknumber(L, 1), dy = (float)luaL_checknumber(L, 2);
    if (dx == 0 && dy == 0) {
        spawn_facing_on = 0;
        return 0;
    }
    spawn_yaw = atan2f(dy, dx) * 57.2957795f;
    if (spawn_yaw < 0) spawn_yaw += 360.0f;
    spawn_facing_on = 1;
    return 0;
}

// Engine_Inbound(): one line per inbound fleet: "owner faction|seconds left|heading (degrees)|type,type,...|world"
// (world: the neighbouring world a border fleet comes from, else empty).
static int lua_inbound(lua_State *L) {
    static char out[6000];
    int used = 0;
    out[0] = 0;
    for (int i = 0; i < inbound_count && used < (int)sizeof out - 200; i++) {
        used += snprintf(out + used, sizeof out - used, "%s|%.2f|%.0f|", player_name(inbound[i].owner), inbound[i].eta,
                         inbound[i].heading);
        for (int k = 0; k < inbound[i].count && used < (int)sizeof out - 100; k++) {
            unsigned char *type = inbound[i].types[k];
            used += snprintf(out + used, sizeof out - used, "%s%s", k ? "," : "", type ? std_string(type + 0xf8) : "?");
        }
        used += snprintf(out + used, sizeof out - used, "|%s|%s\n", inbound[i].origin_name, inbound[i].left_name);
    }
    lua_pushstring(L, out);
    return 1;
}

// Engine_Inbound_Arrive(i[, "TYPE,TYPE"]): fleet i's units into its owner's pool. Returns how many, or -1.
static int listed_type(const char *list, unsigned char *type) {
    if (!list) return 1;
    if (!type) return 0;
    const char *name = std_string(type + 0xf8);
    size_t n = strlen(name);
    for (const char *at = list; *at; ) {
        const char *end = strchr(at, ',');
        size_t len = end ? (size_t)(end - at) : strlen(at);
        if (len == n && !_strnicmp(at, name, n)) return 1;
        if (!end) break;
        at = end + 1;
    }
    return 0;
}

static int lua_inbound_arrive(lua_State *L) {
    int i = (int)luaL_checknumber(L, 1) - 1, added = 0;
    const char *only = lua_gettop(L) >= 2 && lua_tostring_fn ? lua_tostring_fn(L, 2) : NULL;
    if (i < 0 || i >= inbound_count || !parent_mode || !mode_data || !map_at || !int_vector_grow) {
        lua_pushnumber(L, 0);
        return 1;
    }
    long long current = *(long long *)(module_base + RVA_GAME_OBJECTS);
    long long galactic = current ? parent_mode(module_base + RVA_MODES, current) : 0;
    unsigned char *data = galactic ? mode_data(module_base + RVA_MODES, current) : NULL;   // (the battle's entry)
    Inbound *in = &inbound[i];
    if (data) {
        int key = in->owner;
        long long it = 0;
        long long *found = map_at(data + 0x40, &it, &key);
        unsigned char *node = found ? *(unsigned char **)found : NULL;
        unsigned char *player = get_player_by_id(module_base + RVA_PLAYER_LIST, in->owner);
        unsigned char *list = player ? *(unsigned char **)(player + 0x360) : NULL;
        unsigned char *entry = (list && player_mode) ? player_mode(list) : NULL;
        unsigned char *shown = (entry && *(unsigned char **)(entry + 0x50))
            ? *(unsigned char **)(*(unsigned char **)(entry + 0x50) + 0x38) : NULL;
        // the reinforcement manager keeps one slot per pool entry (+0x88): without it no entry may be added
        if (!shown || !pool_changed) {
            char line[160];
            snprintf(line, sizeof line, "INBOUND: %s has no reinforcement manager in this battle", player_name(in->owner));
            test_log(line);
            in->arrived = 1;
            inbound_unsettled = 1;
            lua_pushnumber(L, -1);
            return 1;
        }
        for (int k = 0; node && k < in->count; k++) {
            if (!listed_type(only, in->types[k])) continue;
            int count = *(int *)(node + 0x28), cap = (*(int *)(node + 0x2c) * 2) >> 1;
            if (cap <= count) {
                int extra = cap / 10 < 10 ? 10 : cap / 10;
                int_vector_grow(node + 0x18, cap + extra, 0, 1);
            }
            count = *(int *)(node + 0x28);
            (*(int **)(node + 0x20))[count] = in->ids[k];
            *(int *)(node + 0x28) = count + 1;
            added++;
            pool_changed(shown, count, -1);
        }
    }
    in->arrived = 1;
    inbound_unsettled = 1;
    char line[160];
    snprintf(line, sizeof line, "INBOUND: %s fleet %d arrives: %d of %d units into the pool", player_name(in->owner),
             i + 1, added, in->count);
    test_log(line);
    lua_pushnumber(L, added);
    return 1;
}

// Engine_Battle_Lane(): the attacker's lane heading (degrees) and whether the human is the attacker: "heading|1", or
// "" when unknown.
static int lua_battle_lane(lua_State *L) {
    char out[96] = "";
    unsigned char *local = get_local_player ? get_local_player(module_base + RVA_PLAYER_LIST) : NULL;
    if (battle_lane >= 0 && local)
        snprintf(out, sizeof out, "%.1f|%d|%s", battle_lane, *(int *)(local + 0x4c) == battle_attacker ? 1 : 0,
                 battle_from);
    lua_pushstring(L, out);
    return 1;
}

// Engine_Rotate(x, y, degrees): the vector turned counter-clockwise (the battle scripts have no math library).
static int lua_rotate(lua_State *L) {
    double x = luaL_checknumber(L, 1), y = luaL_checknumber(L, 2), a = luaL_checknumber(L, 3) / 57.2957795;
    lua_pushnumber(L, x * cos(a) - y * sin(a));
    lua_pushnumber(L, x * sin(a) + y * cos(a));
    return 2;
}

// Engine_Inbound_Retreat(i): fleet i (1-based) jumped out of the battle (its own retreat): it is not put in orbit of
// the battle's world afterwards (a border fleet stays home, a fleet from hyperspace is sent away by the script).
static int lua_inbound_retreat(lua_State *L) {
    int i = (int)luaL_checknumber(L, 1) - 1;
    if (i >= 0 && i < inbound_count) inbound[i].retreated = 1;
    return 0;
}

// The battle's Auto-Resolve button: with more than two powers the battle script resolves it instead
// (Engine_Autoresolve_Own, Engine_Autoresolve_Take).
#define RVA_TACTICAL_GUI_EVENT  0x0dc5d0
#define RVA_TACTICAL_RESOLVE    0x0dc8b0
static void (*orig_tactical_gui_event)(int *);
static void (*orig_tactical_resolve)(void);
static int autoresolve_own, autoresolve_pressed, autoresolve_replay, autoresolve_replayed;

// The engine's own Auto-Resolve press, sent from inside its GUI event handling.
static void replay_autoresolve(void) {
    static unsigned char event[0x40];
    memset(event, 0, sizeof event);
    *(int *)event = 1;
    memcpy(event + 8, "IDC_AUTORESOLVE", 15);
    *(long long *)(event + 0x18) = 15;
    *(long long *)(event + 0x20) = 15;
    test_log("AUTORESOLVE: the engine's own Auto-Resolve finishes the battle");
    orig_tactical_gui_event((int *)event);
}

static void hooked_tactical_gui_event(int *event) {
    if (autoresolve_replay && orig_tactical_gui_event) {
        autoresolve_replay = 0;
        replay_autoresolve();
    }
    if (autoresolve_own && event && event[0] == 1 && *(long long *)(event + 6) == 15) {
        const char *name = *(unsigned long long *)(event + 8) > 0xf ? *(const char **)(event + 2) : (const char *)(event + 2);
        if (!memcmp(name, "IDC_AUTORESOLVE", 15)) {
            autoresolve_pressed = 1;
            test_log("AUTORESOLVE: pressed, the battle script resolves it (more than two powers)");
            void **dialog = *(void ***)(module_base + 0xb31400);   // the Battle Options dialog closes, as after
            if (dialog && *dialog) ((void (*)(void *))(*(void ***)dialog)[0x38 / 8])(dialog);   // the engine's own
            return;
        }
    }
    orig_tactical_gui_event(event);
}

static void hooked_tactical_resolve(void) {
    if (autoresolve_own) {
        autoresolve_pressed = 1;
        test_log("AUTORESOLVE: called, the battle script resolves it (more than two powers)");
        return;
    }
    orig_tactical_resolve();
}

// Engine_Human_Retreated(): 1 once the human's retreat is complete (0x340750).
#define RVA_RETREAT_DONE        0x340750
static char (*orig_retreat_done)(long long);
static int human_retreated;

// Engine_Retreats(): every power's retreat state in this battle, one line each.
#define MAX_RETREATS 16
static struct { int player, state; DWORD since; } retreats[MAX_RETREATS];
static int retreat_count;

static void retreat_reset(void) { retreat_count = 0; }

static void note_retreat(int player, int state) {
    if (player < 0 || state <= 0) return;
    int i = 0;
    while (i < retreat_count && retreats[i].player != player) i++;
    if (i == retreat_count) {
        if (retreat_count >= MAX_RETREATS) return;
        retreat_count++;
        retreats[i].player = player;
        retreats[i].state = 0;
        retreats[i].since = GetTickCount();
    }
    if (retreats[i].state != state) {
        char line[120];
        snprintf(line, sizeof line, "RETREAT: %s state %d after %.1f s", player_name(player), state,
                 (GetTickCount() - retreats[i].since) / 1000.0);
        test_log(line);
        retreats[i].state = state;
    }
}

static int lua_retreats(lua_State *L) {
    char out[MAX_RETREATS * 72];
    int used = 0;
    out[0] = 0;
    for (int i = 0; i < retreat_count; i++)
        used += snprintf(out + used, sizeof out - used, "%s|%d|%.1f\n", player_name(retreats[i].player),
                         retreats[i].state, (GetTickCount() - retreats[i].since) / 1000.0);
    lua_pushstring(L, out);
    return 1;
}

// Engine_Victory_Test("FACTION"): that power's condition 0xb ("no enemy of it left here") tested now, so a battle whose
// enemies all left ends at once. Returns 1 when it won.
static int lua_victory_test(lua_State *L) {
    const char *name = lua_gettop(L) >= 1 && lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    int winner = -1, won = 0;
    for (int i = 0; name && i < 64; i++)
        if (get_player_by_id(module_base + RVA_PLAYER_LIST, i) && !_stricmp(player_name(i), name)) { winner = i; break; }
    if (winner >= 0 && !battle_hold && held_manager && held_conditions && orig_victory_check)
        won = orig_victory_check(held_manager, held_conditions, 0xb, winner) != 0;
    if (won) {
        char line[120];
        snprintf(line, sizeof line, "VICTORY: %s wins (no enemy of it left)", name);
        test_log(line);
    }
    lua_pushnumber(L, won);
    return 1;
}

// With extra powers in a battle the engine may never end it after the human's retreat, so a completed human
// retreat always ends it.
static char hooked_retreat_done(long long state) {
    char result = orig_retreat_done(state);
    if (state && *(int *)(state + 0x18) >= 1 && *(int *)(state + 0x18) <= 3)
        note_retreat(*(int *)(state + 0x1c), *(int *)(state + 0x18));
    if (state && *(int *)(state + 0x18) == 3 && get_local_player) {
        unsigned char *local = get_local_player(module_base + RVA_PLAYER_LIST);
        if (local && *(int *)(state + 0x1c) == *(int *)(local + 0x4c)) {
            if (!human_retreated) test_log("RETREAT: the human's retreat is complete; the battle hold ends");
            human_retreated = 1;
            battle_hold = 0;
            held_count = 0;
            if (!result && diplomacy_loaded()) {
                test_log("RETREAT: the engine found no side left to win; the battle ends anyway");
                result = 1;
            }
        }
    }
    return result;
}

static int lua_human_retreated(lua_State *L) {
    lua_pushnumber(L, human_retreated);
    return 1;
}

static int lua_autoresolve_own(lua_State *L) {
    autoresolve_own = lua_gettop(L) >= 1 && luaL_checknumber(L, 1) != 0;
    if (autoresolve_own) autoresolve_replayed = 0;
    if (!autoresolve_own) autoresolve_pressed = 0;
    return 0;
}

// Engine_Autoresolve_Finish("WINNER"): ends the battle with that power's victory. Returns 1 once won.
static int lua_autoresolve_finish(lua_State *L) {
    const char *name = lua_gettop(L) >= 1 && lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    autoresolve_own = 0;
    autoresolve_pressed = 0;
    battle_hold = 0;
    held_count = 0;
    if (!autoresolve_replayed) {                         // first: the engine's own Auto-Resolve (next GUI event)
        autoresolve_replayed = 1;
        autoresolve_replay = 1;
        lua_pushnumber(L, 0);
        return 1;
    }
    int winner = -1, won = 0;
    for (int i = 0; name && i < 64; i++)
        if (get_player_by_id(module_base + RVA_PLAYER_LIST, i) && !_stricmp(player_name(i), name)) { winner = i; break; }
    if (winner >= 0 && held_manager && held_conditions && orig_victory_check)
        won = orig_victory_check(held_manager, held_conditions, 0xb, winner) != 0;
    char line[120];
    snprintf(line, sizeof line, "AUTORESOLVE: %s %s", name ? name : "?", won ? "wins the battle" : "has not won yet");
    test_log(line);
    lua_pushnumber(L, won);
    return 1;
}

// Engine_Declare_Win("WINNER"): declares that power's victory condition at once (0x343b90).
static int lua_declare_win(lua_State *L) {
    const char *name = lua_gettop(L) >= 1 && lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    autoresolve_own = 0;
    autoresolve_pressed = 0;
    battle_hold = 0;
    held_count = 0;
    int winner = -1, done = 0;
    for (int i = 0; name && i < 64; i++)
        if (get_player_by_id(module_base + RVA_PLAYER_LIST, i) && !_stricmp(player_name(i), name)) { winner = i; break; }
    if (winner >= 0 && held_manager && held_conditions && orig_declare_victory) {
        for (long long e = held_conditions[0]; e && e < held_conditions[1] && !done; e += 0x30) {
            if (*(int *)e == 0xb && *(int *)(e + 4) == winner) done = orig_declare_victory(held_manager, (int *)e) != 0;
        }
    }
    char line[120];
    snprintf(line, sizeof line, "AUTORESOLVE: %s %s", name ? name : "?", done ? "declared the winner" : "not declared");
    test_log(line);
    lua_pushnumber(L, done);
    return 1;
}

static int lua_autoresolve_take(lua_State *L) {
    lua_pushnumber(L, autoresolve_pressed);
    autoresolve_pressed = 0;
    return 1;
}

// Engine_Battle_Continue(): after the human leaves a battle others still fight, the engine resolves it between
// them. Returns "attacker|other" or "".
static int lua_battle_continue(lua_State *L) {
    static char out[120];
    out[0] = 0;
    unsigned char *planet = inbound_planet;
    unsigned char *sys = planet ? *(unsigned char **)(planet + 0xb8) : NULL;
    unsigned char *local = get_local_player ? get_local_player(module_base + RVA_PLAYER_LIST) : NULL;
    int human = local ? *(int *)(local + 0x4c) : -1;
    if (!sys || !fleet_type || !object_type || !leave_orbit || !fleet_to_orbit || !orig_pull_in) {
        lua_pushstring(L, out);
        return 1;
    }
    DynVec *orbit = (DynVec *)(sys + 0xc0);
    int base_owner = *(int *)(sys + 0x148) > 0 ? *(int *)(sys + 0x13c) : -1;
    unsigned char *mover = NULL;
    int other = -1;
    for (int i = 0; i < orbit->count && !mover; i++) {
        unsigned char *f = orbit->items[i];
        if (!f || object_type(f) != fleet_type) continue;
        int a = *(int *)(f + 0x58);
        if (a < 0 || a == human) continue;
        if (base_owner >= 0 && base_owner != human && relation(a, base_owner) == 1) { mover = f; other = base_owner; }
        for (int k = 0; k < orbit->count && !mover; k++) {
            unsigned char *g = orbit->items[k];
            int b = g && object_type(g) == fleet_type ? *(int *)(g + 0x58) : -1;
            if (b >= 0 && b != human && b != a && relation(a, b) == 1) { mover = f; other = b; }
        }
    }
    if (mover) {
        typedef void *(*behaviour_fn)(unsigned char *, int);
        void *behaviour = ((behaviour_fn)(*(void ***)mover)[2])(mover, 4);
        if (behaviour) {
            int attacker = *(int *)(mover + 0x58);
            leave_orbit(behaviour, mover, planet);
            unsigned long long conflict = fleet_to_orbit(behaviour, mover, planet, -2, 0) & 0xff;
            void *arrival = ((behaviour_fn)(*(void ***)mover)[2])(mover, 1);
            if (conflict && arrival) orig_pull_in(arrival, mover, planet);
            // then the battle itself, as the engine starts one after an arrival (the fleet's manager +0x2b8, the
            // arriving owner, -1: the engine picks the defender)
            unsigned char *fleet_manager = *(unsigned char **)(mover + 0x2b8);
            if (conflict && fleet_manager && orig_start_space_battle)
                orig_start_space_battle(fleet_manager, planet, attacker, -1, NULL, 0, 0, 0);
            snprintf(out, sizeof out, "%s|%s", player_name(attacker), player_name(other));
            char line[200];
            snprintf(line, sizeof line, "BATTLE GOES ON: %s against %s at %s without the human (conflict %d)",
                     player_name(attacker), player_name(other), type_name(planet), (int)conflict);
            test_log(line);
        }
    }
    lua_pushstring(L, out);
    return 1;
}

#ifndef RELEASE_BUILD
// Engine_Fleets([type]) and Engine_Peek(address, words): fleet and memory dumps. Test build only.
static int lua_fleets(lua_State *L) {
    const char *name = lua_gettop(L) >= 1 && lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    static char out[8000];
    int used = 0;
    out[0] = 0;
    void **objects = *(void ***)(module_base + RVA_GAME_OBJECTS);
    unsigned char *type = type_by_name(name ? name : "Galactic_Fleet");
    if (objects && objects_of_type && type && object_by_id) {
        long long list = objects_of_type(objects[3], type, 0);
        int n = list ? *(int *)(list + 0x10) : 0;
        unsigned char **items = list ? *(unsigned char ***)(list + 8) : NULL;
        for (int i = 0; items && i < n && used < (int)sizeof out - 400; i++) {
            unsigned char *f = items[i];
            if (!f) continue;
            unsigned char *loco = *(unsigned char **)(f + 0xa8);
            used += snprintf(out + used, sizeof out - used, "%p o%d %s (%.0f,%.0f) loco %p", f, *(int *)(f + 0x58),
                             player_name(*(int *)(f + 0x58)), *(float *)(f + 0x78), *(float *)(f + 0x7c), loco);
            if (loco && !IsBadReadPtr(loco, 0xc8)) {
                int *b = *(int **)(loco + 0xb8), *e = *(int **)(loco + 0xc0);
                int steps = (b && e) ? (int)(e - b) : 0;
                used += snprintf(out + used, sizeof out - used, " step %d/%d:", *(int *)(loco + 0x80), steps);
                for (int k = 0; k < steps && k < 8; k++) {
                    unsigned char *pl = object_by_id(objects[3], b[k]);
                    unsigned char *pt = pl ? *(unsigned char **)(pl + 0x298) : NULL;
                    used += snprintf(out + used, sizeof out - used, " %s", pt ? std_string(pt + 0xf8) : "?");
                }
            }
            used += snprintf(out + used, sizeof out - used, " | ");
        }
    }
    lua_pushstring(L, out);
    return 1;
}
static int lua_peek(lua_State *L) {
    const char *a = lua_gettop(L) >= 2 && lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    const char *w = a ? lua_tostring_fn(L, 2) : NULL;
    static char out[8000];
    int used = 0;
    out[0] = 0;
    if (a && w) {
        unsigned char *p = (unsigned char *)(uintptr_t)_strtoui64(a, NULL, 16);
        int words = atoi(w);
        for (int i = 0; i < words && used < (int)sizeof out - 60; i++) {
            if (IsBadReadPtr(p + i * 4, 4)) break;
            int v = *(int *)(p + i * 4);
            float fv = *(float *)(p + i * 4);
            used += snprintf(out + used, sizeof out - used, "%x:%d/%g ", i * 4, v, fv);
        }
    }
    lua_pushstring(L, out);
    return 1;
}
#endif

// --- Hyperlane colours ---------------------------------------------------------------------------------
// Each lane owns a TradeRouteLine with six colour states (enemy, ally, neutral, good, evil, corrupt). Each faction's
// lanes take its own colour (Factions.xml <Color>, or Engine_Lane_Colors). Engine_Trade_Lanes draws trade lanes,
// Engine_Lanes_Refresh re-reads planets' lanes.
#define RVA_LANE_STATE      0x5c28e0
#define RVA_LANE_SET        0x5c32a0
#define RVA_LANE_APPLY      0x5c2590
#define RVA_LANES_REFRESH   0x3ffc20
#define RVA_PATH_TEXTURE    0xb15870    // std::string: the fleet move path's texture
#define RVA_PATH_COLOR      0xb2775c    // four floats
#define RVA_PATH_WIDTH      0xb2776c
#define RVA_STRING_ASSIGN   0x22730     // (std::string *, const char *, size_t)
#define MAX_LANE_COLORS     96
#define MAX_TRADE           24
static int (*orig_lane_state)(unsigned char *, unsigned char *);
static void (*orig_lane_set)(unsigned char *, int);
static unsigned long long (*orig_lane_apply)(unsigned char *, void *, void *, void *, int);
static void (*lanes_refresh)(void *, unsigned char *, char);
static void (*string_assign)(void *, const char *, size_t);
static struct { char name[48]; float rgba[4]; } lane_colors[MAX_LANE_COLORS];
static int lane_color_count;
static char trade_human[48], trade_partners[MAX_TRADE][48];
static int trade_count;
static int lane_mode;               // for the next apply: 0 as the engine has it, 1 the owner's colour, 2 trade
static float lane_rgba[4];
static int faction_color_at = -1;   // the colour's offset in a faction object (-2: not found)
static int faction_color_floats;

// The offset of <Color> in a faction object: the New Republic's (239, 139, 9, 255), as bytes or as floats 0-1.
static void find_faction_color(unsigned char *faction) {
    static const float want[4] = {239 / 255.0f, 139 / 255.0f, 9 / 255.0f, 1.0f};
    faction_color_at = -2;
    for (int o = 0; o + 16 <= 0x800; o += 4) {
        if (faction[o] == 239 && faction[o + 1] == 139 && faction[o + 2] == 9 && faction[o + 3] == 255) {
            faction_color_at = o, faction_color_floats = 0;
            break;
        }
        float *f = (float *)(faction + o);
        int ok = 1;
        for (int i = 0; i < 4; i++) if (fabsf(f[i] - want[i]) > 0.002f) ok = 0;
        if (ok) {
            faction_color_at = o, faction_color_floats = 1;
            break;
        }
    }
    char line[96];
    snprintf(line, sizeof line, "hyperlane colours: faction colour at +0x%x (%s)", faction_color_at,
             faction_color_at < 0 ? "not found" : (faction_color_floats ? "floats" : "bytes"));
    log_line(line);
}

static int faction_color(unsigned char *player, float *rgba) {
    unsigned char *faction = player ? *(unsigned char **)(player + 0x68) : NULL;
    if (!faction || faction_color_at < 0) return 0;
    if (faction_color_floats) {
        memcpy(rgba, faction + faction_color_at, 16);
    } else {
        for (int i = 0; i < 4; i++) rgba[i] = faction[faction_color_at + i] / 255.0f;
    }
    rgba[3] = 1.0f;
    return 1;
}

static const char *player_faction(unsigned char *player) {
    if (!player || !*(unsigned char **)(player + 0x68)) return NULL;
    return std_string(*(unsigned char **)(player + 0x68));
}

static int trade_partner(const char *name) {
    for (int i = 0; i < trade_count; i++) if (!_stricmp(trade_partners[i], name)) return 1;
    return 0;
}

static int hooked_lane_state(unsigned char *a, unsigned char *b) {
    int state = orig_lane_state(a, b);
    lane_mode = 0;
    if (!diplomacy_loaded()) return state;
    const char *fa = player_faction(a), *fb = player_faction(b);
    if (!fa || !fb) return state;
    if (trade_human[0] && ((!_stricmp(fa, trade_human) && trade_partner(fb))
                           || (!_stricmp(fb, trade_human) && trade_partner(fa)))) {
        lane_mode = 2;
        return 1;
    }
    if (state >= 3) {
        for (int i = 0; i < lane_color_count; i++) {
            if (!_stricmp(lane_colors[i].name, fa)) {
                memcpy(lane_rgba, lane_colors[i].rgba, sizeof lane_rgba);
                lane_mode = 1;
                break;
            }
        }
        if (!lane_mode) {
            if (faction_color_at == -1) {
                for (int id = 0; id < 64 && faction_color_at == -1; id++) {
                    const char *name = player_name(id);
                    unsigned char *p = get_player_by_id(module_base + RVA_PLAYER_LIST, id);
                    if (p && name && !_stricmp(name, "REBEL")) find_faction_color(*(unsigned char **)(p + 0x68));
                }
                if (faction_color_at == -1) faction_color_at = -2;
            }
            if (faction_color(a, lane_rgba)) lane_mode = 1;
        }
    }
    return state;
}

// Routes (Engine_Route_Lanes): moving fleets of the listed powers stay visible with the game's fleet arrow, and a
// line to their destination is drawn for fleets without one (0x46350, 0x47370, 0x46f10).
#define MAX_ROUTES 128
#define RVA_VISIBILITY      0x3a51e0
#define RVA_SHOW_OBJECT     0x38c730
static void (*orig_visibility)(unsigned char *, unsigned char *);
static void (*show_object)(unsigned char *);
static unsigned char *revealed[MAX_ROUTES];
static int revealed_count;

static int is_revealed(unsigned char *object) {
    for (int i = 0; i < revealed_count; i++) if (revealed[i] == object) return 1;
    return 0;
}

static void reveal_object(unsigned char *object) {
    if (*(unsigned char *)(object + 0x39f)) return;
    *(unsigned char *)(object + 0x39f) = 1;
    if (*(void **)(object + 0x2a0) && show_object) show_object(object);
}

static void hooked_visibility(unsigned char *object, unsigned char *player) {
    orig_visibility(object, player);
    if (revealed_count && object && !*(unsigned char *)(object + 0x39f) && is_revealed(object) && get_local_player
        && player == get_local_player(module_base + RVA_PLAYER_LIST)) {
        unsigned char *box = *(unsigned char **)(object + 0xc0);
        if (!(box && *(void **)(box + 0x40))) reveal_object(object);    // (not once it is in a world's orbit)
    }
}
#define RVA_PATH_LINE_NEW   0x046350
#define RVA_PATH_LINE_DRAW  0x047370
#define RVA_PATH_LINE_FREE  0x046f10
#define RVA_ENGINE_ALLOC    0x769c58
#define RVA_BAND_TEXTURE    0xb15850    // std::string
#define RVA_BAND_WIDTH      0x8007d4    // float
typedef struct { unsigned char *line; float rgba[4]; int misses; unsigned char *seg; void *scene; } Route;
static Route routes_on[MAX_ROUTES], routes_next[MAX_ROUTES];
static int lane_route_count, lane_route_next_count;
static void *(*engine_alloc)(size_t);
static unsigned char *(*path_line_new)(unsigned char *, int);
static char (*path_line_draw)(unsigned char *, void *, const float *, const float *, const char *, const float *, float,
                              void *, int);
static void (*path_line_free)(unsigned char *, unsigned);

static void *galactic_scene(void) {
    void **mode = module_base ? *(void ***)(module_base + RVA_ACTIVE_MODE) : NULL;
    if (!mode || in_battle()) return NULL;
    typedef void *(*scene_fn)(void *);
    return ((scene_fn)(*(void ***)mode)[0x100 / 8])(mode);
}

static void route_free(Route *r, void *scene) {
    if (r->seg && r->scene == scene && path_line_free) path_line_free(r->seg, 1);
    r->seg = NULL;
}

static void route_draw(Route *r, const float *from, const float *to, void *scene) {
    if (!scene || !engine_alloc || !path_line_new || !path_line_draw) return;
    if (!r->seg) {
        unsigned char *block = engine_alloc(0x20);
        if (!block) return;
        r->seg = path_line_new(block, 0);
        r->scene = scene;
    }
    unsigned char *texture = module_base + RVA_BAND_TEXTURE;
    path_line_draw(r->seg, scene, from, to, std_string(texture), r->rgba, *(float *)(module_base + RVA_BAND_WIDTH),
                   NULL, 1);
}

// A lane whose look must change while its state doesn't is applied again, with its animation flag cleared.
static void hooked_lane_set(unsigned char *line, int state) {
    if (line && lane_mode && state >= 0 && state < 6 && *(int *)(line + 0x3a8) == state) {
        unsigned char *slot = line + state * 0x90;
        int changed = lane_mode == 1 ? memcmp(slot + 4, lane_rgba, 16) != 0
                                                         : memcmp(slot + 4, module_base + RVA_PATH_COLOR, 16) != 0;
        unsigned char *render = *(unsigned char **)(line + 0x3b0);
        if (changed && render) {
            *(unsigned char *)(render + 0x18) = 0;
            *(int *)(line + 0x3a8) = -1;
        }
    }
    orig_lane_set(line, state);
}

static unsigned long long hooked_lane_apply(unsigned char *line, void *a, void *b, void *c, int state) {
    if (line && state >= 0 && state < 6) {
        unsigned char *slot = line + state * 0x90;
        if (lane_mode == 1 && state >= 3) {
            memcpy(slot + 4, lane_rgba, 16);
            memcpy(slot + 0x14, lane_rgba, 16);
        } else if (lane_mode == 2 && state == 1) {
            unsigned char *texture = module_base + RVA_PATH_TEXTURE;
            memcpy(slot + 4, module_base + RVA_PATH_COLOR, 16);
            memcpy(slot + 0x14, module_base + RVA_PATH_COLOR, 16);
            memcpy(slot + 0x24, module_base + RVA_PATH_WIDTH, 4);
            if (string_assign) string_assign(slot + 0x50, std_string(texture), *(size_t *)(texture + 0x10));
        }
    }
    lane_mode = 0;
    return orig_lane_apply(line, a, b, c, state);
}

static int lua_lane_colors(lua_State *L) {
    const char *text = lua_gettop(L) >= 1 && lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    lane_color_count = 0;
    while (text && *text && lane_color_count < MAX_LANE_COLORS) {
        char name[48];
        int r, g, b, used = 0;
        if (sscanf(text, " %47[^ ;] %d %d %d%n", name, &r, &g, &b, &used) == 4 && used > 0) {
            strcpy(lane_colors[lane_color_count].name, name);
            lane_colors[lane_color_count].rgba[0] = r / 255.0f;
            lane_colors[lane_color_count].rgba[1] = g / 255.0f;
            lane_colors[lane_color_count].rgba[2] = b / 255.0f;
            lane_colors[lane_color_count].rgba[3] = 1.0f;
            lane_color_count++;
        }
        const char *next = strchr(text, ';');
        text = next ? next + 1 : NULL;
    }
    return 0;
}

static int lua_trade_lanes(lua_State *L) {
    const char *human = lua_gettop(L) >= 2 && lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    const char *list = human ? lua_tostring_fn(L, 2) : NULL;
    trade_human[0] = 0;
    trade_count = 0;
    if (!human) return 0;
    snprintf(trade_human, sizeof trade_human, "%s", human);
    while (list && *list && trade_count < MAX_TRADE) {
        const char *end = strchr(list, ';');
        size_t n = end ? (size_t)(end - list) : strlen(list);
        if (n > 0 && n < sizeof trade_partners[0]) {
            memcpy(trade_partners[trade_count], list, n);
            trade_partners[trade_count][n] = 0;
            trade_count++;
        }
        list = end ? end + 1 : NULL;
    }
    return 0;
}

static int lua_route_lanes(lua_State *L) {
    const char *list = lua_gettop(L) >= 1 && lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    unsigned char *gui = module_base + 0xb27f60;
    int rows_n = *(int *)(gui + 0xde8);
    unsigned char *rows = *(unsigned char **)(gui + 0xde0);
    lane_route_next_count = 0;
    unsigned char *reveal_next[MAX_ROUTES];
    int reveal_next_count = 0;
    static unsigned char *ends[MAX_ROUTES][2];
    memset(ends, 0, sizeof ends);
    void *scene = galactic_scene();
    if (!scene) {
        lua_pushnumber(L, lane_route_count);
        return 1;
    }
    if (list && *list && rows && rows_n > 0 && rows_n <= 4096 && get_player_by_id) {
        int shown[64] = {0};
        for (int id = 0; id < 64; id++) {
            if (!get_player_by_id(module_base + RVA_PLAYER_LIST, id)) continue;
            const char *name = player_name(id);
            size_t n = strlen(name);
            for (const char *at = list; *at; ) {
                const char *end = strchr(at, ';');
                size_t len = end ? (size_t)(end - at) : strlen(at);
                if (len == n && !_strnicmp(at, name, n)) { shown[id] = 1; break; }
                if (!end) break;
                at = end + 1;
            }
        }
        for (int t = 0; t < MAX_TRACKED && lane_route_next_count < MAX_ROUTES; t++) {
            Tracked *f = &tracks[t];
            if (!f->fleet) continue;
            int owner = *(int *)(f->fleet + 0x58);
            float speed = sqrtf(f->v[0] * f->v[0] + f->v[1] * f->v[1]);
            if (owner < 0 || owner >= 64 || !shown[owner] || speed < 0.5f) continue;
            unsigned char *box = *(unsigned char **)(f->fleet + 0xc0);
            if (box && *(void **)(box + 0x40)) continue;    // (in a world's orbit, leaving or arriving: no arrow yet)
            if (box && *(void **)(box + 0x50) && orig_visibility && reveal_next_count < MAX_ROUTES) {
                reveal_next[reveal_next_count++] = f->fleet;     // kept shown: the engine draws its own arrow
                reveal_object(f->fleet);
            }
            if (box && *(void **)(box + 0x50) && *(unsigned char *)(f->fleet + 0x39f)) continue;   // (the engine's)
            unsigned char *best_line = NULL, *best_from = NULL, *best_to = NULL;
            float best_off = 0;
            for (int i = 0; i < rows_n && !best_line; i++) {
                unsigned char *a = *(unsigned char **)(rows + (long long)i * 0x188);
                int lanes = a ? lane_count_of(a) : 0;
                for (int k = 0; k < lanes && k < 64; k++) {
                    unsigned char *b = lane_other(a, k);
                    if (!b) continue;
                    float ax = *(float *)(a + 0x78), ay = *(float *)(a + 0x7c);
                    float lx = *(float *)(b + 0x78) - ax, ly = *(float *)(b + 0x7c) - ay;
                    float len2 = lx * lx + ly * ly;
                    if (len2 < 1.0f) continue;
                    float len = sqrtf(len2);
                    if ((lx * f->v[0] + ly * f->v[1]) / (len * speed) < 0.995f) continue;   // heading for b
                    float px = f->pos[0] - ax, py = f->pos[1] - ay;
                    float along = (px * lx + py * ly) / len2;
                    if (along < -0.01f || along > 1.01f) continue;
                    float ox = px - along * lx, oy = py - along * ly;
                    float off = sqrtf(ox * ox + oy * oy);
                    if (off > 0.02f * len + 3.0f) continue;
                    if (!best_line || off < best_off) {
                        best_line = lane_line(a, k);
                        best_from = a;
                        best_to = b;
                        best_off = off;
                    }
                }
            }
            if (!best_line || !best_from) continue;
            Route *r = &routes_next[lane_route_next_count++];
            r->line = f->fleet;
            unsigned char *player = get_player_by_id(module_base + RVA_PLAYER_LIST, owner);
            if (!faction_color(player, r->rgba)) memcpy(r->rgba, module_base + RVA_PATH_COLOR, 16);
            r->misses = 0;
            r->seg = NULL;
            r->scene = NULL;
            ends[lane_route_next_count - 1][0] = f->fleet;
            ends[lane_route_next_count - 1][1] = best_to;
        }
    }
    // fleets no longer travelling: the engine looks at them again (hidden when the player has no sight of them)
    unsigned char *local = get_local_player ? get_local_player(module_base + RVA_PLAYER_LIST) : NULL;
    unsigned char *stopped[MAX_ROUTES];
    int stopped_count = 0;
    for (int i = 0; i < revealed_count; i++) {
        int kept = 0, alive = 0;
        for (int k = 0; k < reveal_next_count; k++) if (reveal_next[k] == revealed[i]) kept = 1;
        if (kept) continue;
        for (int t = 0; t < MAX_TRACKED && !alive; t++) if (tracks[t].fleet == revealed[i]) alive = 1;
        if (alive) stopped[stopped_count++] = revealed[i];
    }
    memcpy(revealed, reveal_next, sizeof(unsigned char *) * reveal_next_count);
    revealed_count = reveal_next_count;
    for (int i = 0; i < stopped_count && local && orig_visibility; i++) orig_visibility(stopped[i], local);
    // a fleet not found this once (between two samples) keeps its arrow one more time
    for (int i = 0; i < lane_route_count && lane_route_next_count < MAX_ROUTES; i++) {
        int found = 0;
        for (int k = 0; k < lane_route_next_count; k++) if (routes_next[k].line == routes_on[i].line) found = 1;
        if (!found && routes_on[i].misses < 1) {
            routes_next[lane_route_next_count] = routes_on[i];
            routes_next[lane_route_next_count++].misses++;
        }
    }
    // arrows of fleets no longer travelling are removed; the others are drawn from where their fleet is now
    int changed = 0;
    for (int i = 0; i < lane_route_count; i++) {
        int kept = 0;
        for (int k = 0; k < lane_route_next_count && !kept; k++) {
            if (routes_next[k].line != routes_on[i].line) continue;
            kept = 1;
            routes_next[k].seg = routes_on[i].scene == scene ? routes_on[i].seg : NULL;
            routes_next[k].scene = routes_on[i].scene == scene ? scene : NULL;
        }
        if (!kept) {
            route_free(&routes_on[i], scene);
            changed = 1;
        }
    }
    for (int k = 0; k < lane_route_next_count; k++) {
        if (!ends[k][0] || !ends[k][1]) continue;
        if (!routes_next[k].seg) changed = 1;
        route_draw(&routes_next[k], (float *)(ends[k][0] + 0x78), (float *)(ends[k][1] + 0x78), scene);
    }
    memcpy(routes_on, routes_next, sizeof routes_on);
    lane_route_count = lane_route_next_count;
    static int logged_routes = -1;
    if (changed && lane_route_count != logged_routes) {
        char line[80];
        snprintf(line, sizeof line, "ROUTES: %d fleet arrows drawn", lane_route_count);
        test_log(line);
        logged_routes = lane_route_count;
    }
    lua_pushnumber(L, lane_route_count);
    return 1;
}

// Engine_Safe_Path("POWER", "FROM", "TO"): a hyperlane route through safe space only (own and bonded worlds
// first, then neutral ones without enemies in orbit), fewest jumps. Returns "WORLD;...;TO" or "".
#define SAFE_OTHER_COST 1000
static int safe_world_cost(unsigned char *planet, int power, int neutral) {
    int owner = *(int *)(planet + 0x58);
    unsigned char *sys = *(unsigned char **)(planet + 0xb8);
    if (!sys) return -1;
    if (*(int *)(sys + 0x148) > 0) {                   // a starbase
        int base = *(int *)(sys + 0x13c);
        if (base >= 0 && base != neutral && base != power && relation(power, base) == 1) return -1;
    }
    DynVec *orbit = (DynVec *)(sys + 0xc0);
    for (int i = 0; i < orbit->count; i++) {
        unsigned char *object = orbit->items[i];
        int o = object ? *(int *)(object + 0x58) : -1;
        if (o >= 0 && o != neutral && o != power && relation(power, o) == 1) return -1;
    }
    if (owner == power || (owner >= 0 && bonded(owner, power))) return 1;
    if (owner >= 0 && owner != neutral && relation(power, owner) == 1) return -1;
    return SAFE_OTHER_COST;
}

static int lua_safe_path(lua_State *L) {
    static char out[2400];
    static unsigned char *worlds[4096];
    static int dist[4096], prev[4096];
    static char done[4096];
    const char *power_name = lua_gettop(L) >= 3 && lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    const char *from_name = power_name ? lua_tostring_fn(L, 2) : NULL, *to_name = power_name ? lua_tostring_fn(L, 3) : NULL;
    unsigned char *gui = module_base + 0xb27f60;
    int n = *(int *)(gui + 0xde8);
    unsigned char *rows = *(unsigned char **)(gui + 0xde0);
    out[0] = 0;
    if (!from_name || !to_name || !rows || n <= 0 || n > 4096 || !get_player_by_id || !object_type) {
        lua_pushstring(L, out);
        return 1;
    }
    int power = -1, neutral = -1, from = -1, to = -1;
    for (int id = 0; id < 64; id++) {
        if (!get_player_by_id(module_base + RVA_PLAYER_LIST, id)) continue;
        if (!_stricmp(player_name(id), power_name)) power = id;
        if (!_stricmp(player_name(id), "NEUTRAL")) neutral = id;
    }
    for (int i = 0; i < n; i++) {
        worlds[i] = *(unsigned char **)(rows + (long long)i * 0x188);
        dist[i] = 0x7fffffff;
        prev[i] = -1;
        done[i] = 0;
        if (!worlds[i]) continue;
        const char *name = type_name(worlds[i]);
        if (from < 0 && !_stricmp(name, from_name)) from = i;
        if (to < 0 && !_stricmp(name, to_name)) to = i;
    }
    if (power < 0 || from < 0 || to < 0 || from == to) {
        lua_pushstring(L, out);
        return 1;
    }
    dist[from] = 0;
    for (;;) {
        int u = -1;
        for (int i = 0; i < n; i++) if (!done[i] && dist[i] != 0x7fffffff && (u < 0 || dist[i] < dist[u])) u = i;
        if (u < 0 || u == to) break;
        done[u] = 1;
        int lanes = lane_count_of(worlds[u]);
        for (int k = 0; k < lanes && k < 64; k++) {
            unsigned char *b = lane_other(worlds[u], k);
            int v = -1;
            for (int i = 0; b && i < n; i++) if (worlds[i] == b) { v = i; break; }
            if (v < 0 || done[v]) continue;
            int cost = v == to ? 1 : safe_world_cost(b, power, neutral);
            if (cost < 0) continue;
            if (dist[u] + cost < dist[v]) {
                dist[v] = dist[u] + cost;
                prev[v] = u;
            }
        }
    }
    if (dist[to] != 0x7fffffff) {
        int chain[512], len = 0;
        for (int v = to; v != from && v >= 0 && len < 512; v = prev[v]) chain[len++] = v;
        int used = 0;
        for (int i = len - 1; i >= 0 && used < (int)sizeof out - 64; i--)
            used += snprintf(out + used, sizeof out - used, "%s%s", used ? ";" : "", type_name(worlds[chain[i]]));
    }
    lua_pushstring(L, out);
    return 1;
}

// Engine_Faction_Colour("FACTION"): its Factions.xml <Color> as r, g, b (0-1); nothing when unknown.
static int lua_faction_colour(lua_State *L) {
    const char *name = lua_gettop(L) >= 1 && lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    for (int id = 0; name && get_player_by_id && id < 64; id++) {
        unsigned char *p = get_player_by_id(module_base + RVA_PLAYER_LIST, id);
        if (!p || _stricmp(player_name(id), name)) continue;
        if (faction_color_at == -1) {
            for (int k = 0; k < 64 && faction_color_at == -1; k++) {
                unsigned char *q = get_player_by_id(module_base + RVA_PLAYER_LIST, k);
                if (q && !_stricmp(player_name(k), "REBEL")) find_faction_color(*(unsigned char **)(q + 0x68));
            }
            if (faction_color_at == -1) faction_color_at = -2;
        }
        float rgba[4];
        if (!faction_color(p, rgba)) return 0;
        lua_pushnumber(L, rgba[0]);
        lua_pushnumber(L, rgba[1]);
        lua_pushnumber(L, rgba[2]);
        return 3;
    }
    return 0;
}

static int lua_lanes_refresh(lua_State *L) {
    const char *list = lua_gettop(L) >= 1 && lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    void **objects = *(void ***)(module_base + RVA_GAME_OBJECTS);
    int done = 0;
    if (!list || !objects || !objects_of_type || !lanes_refresh) return 0;
    while (*list) {
        const char *end = strchr(list, ';');
        size_t n = end ? (size_t)(end - list) : strlen(list);
        char name[64];
        if (n > 0 && n < sizeof name) {
            memcpy(name, list, n);
            name[n] = 0;
            unsigned char *planet = first_object_of(objects[3], type_by_name(name));
            if (planet && *(void **)(planet + 0xb8)) {
                lanes_refresh(NULL, planet, 0);
                done++;
            }
        }
        if (!end) break;
        list = end + 1;
    }
    lua_pushnumber(L, done);
    return 1;
}


// --- The selected planet -----------------------------------------------------------------------------
// Engine_Selected_Planet(): the planet selected on the galaxy map (0x3de570), or nil.
#define RVA_SELECT_PLANET   0x3de570
static unsigned long long (*orig_select_planet)(unsigned char *, unsigned char *, char);
static const char *type_name(unsigned char *object);

static unsigned long long hooked_select_planet(unsigned char *bar, unsigned char *planet, char flag) {
    unsigned long long result = orig_select_planet(bar, planet, flag);
    if (!planet) {
        selected_planet[0] = 0;
    } else if (result) {
        const char *name = type_name(planet);
        snprintf(selected_planet, sizeof selected_planet, "%s", name ? name : "");
    }
    return result;
}

static int lua_selected_planet(lua_State *L) {
    if (!selected_planet[0]) return 0;
    lua_pushstring(L, selected_planet);
    return 1;
}

// --- The planet zoomed in on -------------------------------------------------------------------------
// Engine_Zoomed_Planet(): the planet the camera is zoomed in on (0x32f320 / 0x32f380), or nil.
#define RVA_ZOOM_IN_EVENT   0x32f320
#define RVA_ZOOM_OUT_EVENT  0x32f380
static void (*orig_zoom_in)(void *, unsigned char *);
static void (*orig_zoom_out)(void *, unsigned char *);

static void hooked_zoom_in(void *events, unsigned char *planet) {
    const char *name = planet ? type_name(planet) : NULL;
    snprintf(zoomed_planet, sizeof zoomed_planet, "%s", name ? name : "");
    orig_zoom_in(events, planet);
}

static void hooked_zoom_out(void *events, unsigned char *planet) {
    zoomed_planet[0] = 0;
    orig_zoom_out(events, planet);
}

static int lua_zoomed_planet(lua_State *L) {
    if (!zoomed_planet[0]) return 0;
    lua_pushstring(L, zoomed_planet);
    return 1;
}

// --- Players are never destroyed during a game --------------------------------------------------------------
// A player still in the game's player list is never deleted when its reference count drops to zero (0x27f290):
// a stray release could delete it and crash the next lookup. The first few cases are logged.
#define RVA_PLAYER_DELETE   0x27f290    // (player, flags): PlayerClass's deleting destructor
static void *(*orig_player_delete)(unsigned char *, unsigned);
static int player_saves;
static void *hooked_player_delete(unsigned char *player, unsigned flags) {
    // only a deletion from inside Lua (a script handle collected): the game ending a session deletes every player
    // while its list still holds them, and that must go ahead
    int from_lua = 0;
    unsigned long long *sp0 = (unsigned long long *)__builtin_frame_address(0);
    for (int k = 0; k < 1500 && readable(sp0 + k, 8); k++) {
        unsigned long long v = sp0[k];
        if (v >= (unsigned long long)module_base + 0x7b0000 && v < (unsigned long long)module_base + 0x7d0000) {
            from_lua = 1;
            break;
        }
    }
    if (!from_lua) return orig_player_delete(player, flags);
    unsigned char *list = module_base + RVA_PLAYER_LIST;
    unsigned char **items = *(unsigned char ***)(list + 0x20);
    int count = *(int *)(list + 0x28);
    for (int i = 0; items && i < count && i < 4096; i++) {
        if (items[i] != player) continue;
        *(int *)(player + 8) = 0x10000;                // far from zero: stray releases cannot reach it again
        if (player_saves++ < 10) {
            char line[700];
            char *p = line;
            p += snprintf(p, 200, "PLAYER KEPT: player %d (%s) was released to nothing while in the game; stack:",
                          *(int *)(player + 0x4c), get_player_by_id ? player_name(*(int *)(player + 0x4c)) : "?");
            unsigned long long *sp = (unsigned long long *)__builtin_frame_address(0);
            for (int k = 0, n = 0; k < 600 && n < 24 && readable(sp + k, 8); k++) {
                unsigned long long v = sp[k];
                if (v > (unsigned long long)module_base + 0x1000 && v < (unsigned long long)module_base + 0x800000) {
                    p += snprintf(p, line + sizeof line - p, " %llx", v - (unsigned long long)module_base);
                    n++;
                }
            }
            log_line(line);
            test_log(line);
        }
        return player;
    }
    return orig_player_delete(player, flags);
}

// --- Battle tallies: units that are gone ----------------------------------------------------------------
// Units destroyed while a conflict is set up leave entries whose object is gone, and the tally (0x60b0d0) crashed
// reading them. Such entries are dropped first; their reference is kept, since the object may still be alive.
#define RVA_FORCE_TALLY     0x60b0d0
#define RVA_UNIT_FORCE      0x60c710
typedef void (*force_tally_fn)(long long, long long *, long long *, unsigned, long long *);
typedef unsigned char *(*unit_force_fn)(long long, long long *);
typedef void (*ref_fn)(long long);
static force_tally_fn orig_force_tally;
static unit_force_fn unit_force;
static int tally_drops;

static void hooked_force_tally(long long conflict, long long *units, long long *out, unsigned player, long long *best) {
    long long *begin = units ? (long long *)units[0] : NULL, *end = units ? (long long *)units[1] : NULL;
    long long n = end - begin;
    if (begin && n > 0 && n < 100000 && readable(begin, (size_t)n * 8)) {
        long long kept = 0;
        for (long long i = 0; i < n; i++) {
            long long entry = begin[i];
            int ok = entry && readable((void *)entry, 8) && readable(*(void **)entry, 0x178);
            if (ok) {
                long long probe = entry;
                (*(ref_fn *)(*(long long *)entry))(entry);                 // a reference for the lookup to release
                unsigned char *force = unit_force(conflict, &probe);
                ok = force && readable(force + 0x1b50, 0x18);
                if (!ok && tally_drops < 50) {
                    unsigned char *object = ((unsigned char *(*)(long long))(*(void ***)entry)[0x170 / 8])(entry);
                    char line[200];
                    snprintf(line, sizeof line, "BATTLE TALLY: dropped a unit with no force (%s, side player %u)",
                             object ? type_name(object) : "?", player);
                    log_line(line);
                    tally_drops++;
                }
            }
            if (ok) begin[kept++] = entry;
        }
        if (kept < n) units[1] = (long long)(begin + kept);
    }
    orig_force_tally(conflict, units, out, player, best);
}

// --- Extra rows in the galactic income tooltip ---------------------------------------------------------
// Engine_Income_Rows("label\tvalue\n...") adds rows after "Total Income", laid out like it.
#define RVA_ADD_ROW         0x2df0c0
#define RVA_TEXT_LOOKUP     0x1fa460    // (text database, const char *id) -> std::wstring*
typedef struct { union { wchar_t buf[8]; wchar_t *ptr; } u; size_t size, cap; } msvc_wstring;
typedef long long *(*add_row_fn)(long long, void *, msvc_wstring *, long long, float *, char, int, int, char,
                                 unsigned);
static add_row_fn orig_add_row;
static msvc_wstring *(*text_lookup)(void *, const char *);
#define MAX_INCOME_ROWS 24
static wchar_t income_labels[MAX_INCOME_ROWS][96], income_values[MAX_INCOME_ROWS][24];
static int income_row_count, income_injecting, income_after_total;
static struct { void *tmpl; float *p5; char p6; int p7, p8; char p9; unsigned p10; } total_label;

static const wchar_t *wstr_data(msvc_wstring *s) { return s->cap > 7 ? s->u.ptr : s->u.buf; }

static void wstr_set(msvc_wstring *s, const wchar_t *text) {      // a view on `text` (never freed by the callee)
    memset(s, 0, sizeof *s);
    s->size = wcslen(text);
    if (s->size < 8) {
        wcscpy(s->u.buf, text);
        s->cap = 7;
    } else {
        s->u.ptr = (wchar_t *)text;
        s->cap = s->size;
    }
}

static int lua_income_rows(lua_State *L) {
    const char *text = lua_gettop(L) >= 1 && lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    income_row_count = 0;
    while (text && *text && income_row_count < MAX_INCOME_ROWS) {
        const char *tab = strchr(text, '\t'), *end = strchr(text, '\n');
        if (!end) end = text + strlen(text);
        if (tab && tab < end) {
            int k = income_row_count++;
            int n = MultiByteToWideChar(CP_UTF8, 0, text, (int)(tab - text), income_labels[k], 95);
            income_labels[k][n] = 0;
            n = MultiByteToWideChar(CP_UTF8, 0, tab + 1, (int)(end - tab - 1), income_values[k], 23);
            income_values[k][n] = 0;
        }
        text = *end ? end + 1 : end;
    }
    return 0;
}

static long long *hooked_add_row(long long tip, void *tmpl, msvc_wstring *text, long long parent, float *p5,
                                 char p6, int p7, int p8, char p9, unsigned p10) {
    long long *result = orig_add_row(tip, tmpl, text, parent, p5, p6, p7, p8, p9, p10);
    if (income_injecting || !text) return result;
    if (income_after_total && p6 == 1) {                  // the total's value: the mod's rows follow
        income_after_total = 0;
        income_injecting = 1;
        for (int k = 0; k < income_row_count; k++) {
            msvc_wstring s;
            wstr_set(&s, income_labels[k]);
            orig_add_row(tip, total_label.tmpl, &s, parent, total_label.p5, total_label.p6, total_label.p7,
                         total_label.p8, total_label.p9, total_label.p10);
            wstr_set(&s, income_values[k]);
            orig_add_row(tip, tmpl, &s, parent, p5, p6, p7, p8, p9, p10);
        }
        income_injecting = 0;
        return result;
    }
    income_after_total = 0;
    if (income_row_count > 0 && text_lookup && p6 == 0) {
        msvc_wstring *total = text_lookup(module_base + RVA_TEXT_DB, "TEXT_ECONOMY_TOTAL_INCOME");
        if (total && total->size == text->size && wcscmp(wstr_data(total), wstr_data(text)) == 0) {
            income_after_total = 1;
            total_label.tmpl = tmpl; total_label.p5 = p5; total_label.p6 = p6; total_label.p7 = p7;
            total_label.p8 = p8; total_label.p9 = p9; total_label.p10 = p10;
        }
    }
    return result;
}

// --- A movie's place on the screen ---------------------------------------------------------------------
// Engine_Movie_Rect(x, y, w, h): the next overlay movie uses that rectangle instead of the whole screen.
#define RVA_MOVIE_START     0x44d920
#define RVA_TEXTURE_RECT    0x25ff10
typedef unsigned long long (*movie_start_fn)(void *, const char *, unsigned long long, void *, unsigned long long,
                                             unsigned long long);
static movie_start_fn orig_movie_start;
static void *(*orig_texture_rect)(void *, float, float, float, float, void *);
static float movie_rect[4];
static int movie_rect_armed, movie_starting;
static void *hooked_texture_rect(void *self, float x, float y, float w, float h, void *texture) {
    if (movie_starting && movie_rect_armed && x == 0.0f && y == 0.0f && w == 1.0f && h == 1.0f) {
        movie_rect_armed = 0;
        return orig_texture_rect(self, movie_rect[0], movie_rect[1], movie_rect[2], movie_rect[3], texture);
    }
    return orig_texture_rect(self, x, y, w, h, texture);
}
static unsigned long long hooked_movie_start(void *self, const char *name, unsigned long long a3, void *a4,
                                             unsigned long long a5, unsigned long long a6) {
    movie_starting = 1;
    unsigned long long result = orig_movie_start(self, name, a3, a4, a5, a6);
    movie_starting = 0;
    return result;
}
static int lua_movie_rect(lua_State *L) {
    if (lua_gettop(L) >= 4) {
        for (int i = 0; i < 4; i++) movie_rect[i] = (float)luaL_checknumber(L, i + 1);
        movie_rect_armed = 1;
    } else movie_rect_armed = 0;
    return 0;
}

// --- Planets that pay their owner nothing ------------------------------------------------------------
// Engine_Planet_Income_Off("FACTION"): that faction's planets pay it nothing (0x3f68b0); Engine_Planet_Income_Real(1)
// lets scripts read the real values. Engine_Taxes(): the local player's planet taxes, added up with the top bar.
#define RVA_PLANET_INCOME   0x3f68b0
#define RVA_TEXT_CRC        0x215a30
static float (*orig_planet_income)(void *, unsigned char *, char);
static unsigned (*text_crc)(const char *, int, unsigned);
static char income_off_faction[64];
static int income_real;
static int taxes_summing, taxes_player, taxes_known;
static float taxes_sum, taxes_last;
static unsigned charged_crc[2];
static float planet_taxes(unsigned char *planet) {
    unsigned char *economy = *(unsigned char **)(planet + 0xb8);
    if (!economy || !text_crc) return 0.0f;
    if (!charged_crc[0]) {
        charged_crc[0] = text_crc("TEXT_ECONOMY_BASE_INCOME", 24, 0);
        charged_crc[1] = text_crc("TEXT_ECONOMY_TAX_COLLECTION_AGENCIES", 36, 0);
    }
    unsigned char *head = *(unsigned char **)(economy + 0x268);
    float total = 0.0f;
    int guard = 0;
    for (unsigned char *node = head ? *(unsigned char **)head : NULL; node && node != head && guard < 256; guard++) {
        unsigned crc = *(unsigned *)(node + 0x18);
        if (crc == charged_crc[0] || crc == charged_crc[1]) total += *(float *)(node + 0x10);
        node = *(unsigned char **)node;
    }
    return total;
}
static float hooked_planet_income(void *self, unsigned char *planet, char foreign) {
    float value = orig_planet_income(self, planet, foreign);
    if (taxes_summing && planet && !foreign && *(int *)(planet + 0x58) == taxes_player) taxes_sum += planet_taxes(planet);
    if (income_off_faction[0] && !income_real && !foreign && planet) {
        int owner = *(int *)(planet + 0x58);
        if (owner >= 0 && get_player_by_id && _stricmp(player_name(owner), income_off_faction) == 0) return 0.0f;
    }
    return value;
}
static int lua_planet_income_off(lua_State *L) {
    const char *name = lua_gettop(L) >= 1 && lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    if (name) {
        strncpy(income_off_faction, name, sizeof income_off_faction - 1);
        income_off_faction[sizeof income_off_faction - 1] = 0;
    } else income_off_faction[0] = 0;
    return 0;
}
static int lua_planet_income_real(lua_State *L) {
    income_real = lua_gettop(L) >= 1 && luaL_checknumber(L, 1) != 0;
    return 0;
}
static int lua_taxes(lua_State *L) {
    if (!taxes_known) return 0;
    lua_pushnumber(L, taxes_last);
    return 1;
}

// --- The top bar's income: net of the scripts' own charges ---------------------------------------------
// Engine_Shown_Income(n) adds n to the income the top bar shows (0x3e8a80) only; the payment itself is untouched.
#define RVA_PLAYER_INCOME   0x4b16f0
#define RVA_TOP_BAR         0x3e8a80
#define TOP_BAR_SIZE        5921
static float (*orig_player_income)(void *, void *, char);
static volatile float shown_income_delta;
static unsigned char *top_bar_code;
static float hooked_player_income(void *manager, void *player, char paying) {
    unsigned char *from = (unsigned char *)__builtin_return_address(0);
    int top_bar = !paying && player && top_bar_code && from >= top_bar_code && from < top_bar_code + TOP_BAR_SIZE;
    if (top_bar) { taxes_summing = 1; taxes_sum = 0.0f; taxes_player = *(int *)((unsigned char *)player + 0x4c); }
    float value = orig_player_income(manager, player, paying);
    if (top_bar) {
        taxes_summing = 0;
        taxes_last = taxes_sum;
        taxes_known = 1;
        value += shown_income_delta;
    }
    return value;
}
static int lua_shown_income(lua_State *L) {
    shown_income_delta = lua_gettop(L) >= 1 ? (float)luaL_checknumber(L, 1) : 0.0f;
    return 0;
}

// Engine_Screen_Size(): the game window's client width and height in pixels (0, 0 if not found).
static HWND game_window;
static BOOL CALLBACK find_game_window(HWND hwnd, LPARAM unused) {
    (void)unused;
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid == GetCurrentProcessId() && IsWindowVisible(hwnd) && !GetWindow(hwnd, GW_OWNER)) {
        game_window = hwnd;
        return FALSE;
    }
    return TRUE;
}

// --- Test commands (test build only): AgentCommands.txt in the game folder, one command per line, results in
// AgentResults.txt. click <component>, mouse <x> <y> [right], move <x> <y>, key <vk>, type <text>, wait <ms>,
// front / back.
static unsigned char *custom_component(const char *name);    // (command bar, name) -> live widget
#ifdef RELEASE_BUILD                // the players' copy has no test commands
static void agent_poll(void) {}
#else
static char agent_cmd_path[MAX_PATH], agent_out_path[MAX_PATH];
static DWORD agent_next, agent_resume_at;
static HWND grab_saved_window;       // grab/release: the desktop's window and cursor while the game takes real input
static POINT grab_saved_cursor;
static int agent_line;              // the next command line to run (a "wait" resumes there)

static void agent_result(const char *text) {
    FILE *f = fopen(agent_out_path, "a");
    if (f) { fprintf(f, "%10lu  %s\n", GetTickCount(), text); fclose(f); }
}

static void agent_find_window(void) {
    if (!game_window || !IsWindow(game_window)) {
        game_window = NULL;
        EnumWindows(find_game_window, 0);
    }
}

// keepactive on: the game keeps running in the background during tests; off restores the normal behaviour.
static WNDPROC orig_wndproc;
static int keep_active;

static void envoy_slot_mouse(int x, int y);
static LRESULT CALLBACK keep_active_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    if (keep_active) {
        if (msg == WM_ACTIVATEAPP && !wp) wp = TRUE;
        else if (msg == WM_ACTIVATE && LOWORD(wp) == WA_INACTIVE) wp = MAKEWPARAM(WA_ACTIVE, HIWORD(wp));
        else if (msg == WM_NCACTIVATE && !wp) wp = TRUE;
        else if (msg == WM_KILLFOCUS) return 0;
    }
    return CallWindowProcA(orig_wndproc, hwnd, msg, wp, lp);
}

static void set_keep_active(int on) {
    if (!game_window) return;
    if (on && !orig_wndproc)
        orig_wndproc = (WNDPROC)SetWindowLongPtrA(game_window, GWLP_WNDPROC, (LONG_PTR)keep_active_proc);
    keep_active = on;
    // Windows also slows a background process (power throttling, a lower priority): not while testing
    typedef BOOL (WINAPI *set_info_fn)(HANDLE, int, void *, DWORD);
    set_info_fn set_info = (set_info_fn)GetProcAddress(GetModuleHandleA("kernel32.dll"), "SetProcessInformation");
    struct { ULONG version, control, state; } throttle = {1, on ? 1u : 0u, 0};   // ProcessPowerThrottling: speed
    if (set_info) set_info(GetCurrentProcess(), 4, &throttle, sizeof throttle);
    SetPriorityClass(GetCurrentProcess(), on ? ABOVE_NORMAL_PRIORITY_CLASS : NORMAL_PRIORITY_CLASS);
    if (on) {                                   // wake it if it already paused
        SendMessageA(game_window, WM_ACTIVATEAPP, TRUE, 0);
        SendMessageA(game_window, WM_ACTIVATE, WA_ACTIVE, 0);
        SendMessageA(game_window, WM_SETFOCUS, 0, 0);
    }
}

static int agent_run(char *line) {          // returns a wait in ms (0: go on)
    char cmd[32] = "", a[200] = "", b[64] = "", c[32] = "", out[4200];
    if (sscanf(line, "%31s %199s %63s %31s", cmd, a, b, c) < 1) return 0;
    agent_find_window();
    if (!_stricmp(cmd, "click")) {
        unsigned char *w = custom_component(a);
        if (w) ((void (*)(void *, int))(*(void ***)w)[0x208 / 8])(w, 1);
        snprintf(out, sizeof out, "click %s: %s", a, w ? "ok" : "NO SUCH COMPONENT");
    } else if (!_stricmp(cmd, "mouse") || !_stricmp(cmd, "move")) {
        LPARAM pos = MAKELPARAM(atoi(a), atoi(b));
        int right = !_stricmp(c, "right");
        if (game_window) {
            SendMessageA(game_window, WM_MOUSEMOVE, 0, pos);
            if (!_stricmp(cmd, "mouse")) {
                if (!right && envoy_posted) envoy_slot_mouse(atoi(a), atoi(b));    // (sent clicks skip the queue)
                SendMessageA(game_window, right ? WM_RBUTTONDOWN : WM_LBUTTONDOWN, right ? MK_RBUTTON : MK_LBUTTON, pos);
                SendMessageA(game_window, right ? WM_RBUTTONUP : WM_LBUTTONUP, 0, pos);
            }
        }
        snprintf(out, sizeof out, "%s %s %s: %s", cmd, a, b, game_window ? "sent" : "NO WINDOW");
    } else if (!_stricmp(cmd, "down") || !_stricmp(cmd, "up") || !_stricmp(cmd, "hold")) {
        // down x y / hold x y (move with the button held) / up x y: a drag spread over frames ("wait" between)
        LPARAM pos = MAKELPARAM(atoi(a), atoi(b));
        if (game_window) {
            if (!_stricmp(cmd, "down")) {
                SendMessageA(game_window, WM_MOUSEMOVE, 0, pos);
                SendMessageA(game_window, WM_LBUTTONDOWN, MK_LBUTTON, pos);
            } else if (!_stricmp(cmd, "hold")) {
                SendMessageA(game_window, WM_MOUSEMOVE, MK_LBUTTON, pos);
            } else {
                SendMessageA(game_window, WM_MOUSEMOVE, MK_LBUTTON, pos);
                SendMessageA(game_window, WM_LBUTTONUP, 0, pos);
            }
        }
        snprintf(out, sizeof out, "%s %s %s: %s", cmd, a, b, game_window ? "sent" : "NO WINDOW");
    } else if (!_stricmp(cmd, "wheel")) {         // wheel <notches> [x y]: + zooms in, - out
        // posted (not sent): the camera reads the wheel from the game's message loop; the window procedure
        // also drops it unless the "has input focus" flag (0xa110d0) is set (keepactive keeps it set)
        int x = *b ? atoi(b) : 800, y = *c ? atoi(c) : 450, n = atoi(a);
        if (game_window) {
            POINT p = {x, y};
            ClientToScreen(game_window, &p);
            unsigned char *focus = module_base + 0xa110d0, was = *focus;
            *focus = 1;
            SendMessageA(game_window, WM_MOUSEMOVE, 0, MAKELPARAM(x, y));
            for (int i = 0; i < abs(n); i++)
                PostMessageA(game_window, WM_MOUSEWHEEL, MAKEWPARAM(0, (short)(n > 0 ? WHEEL_DELTA : -WHEEL_DELTA)), MAKELPARAM(p.x, p.y));
            (void)was;                          // posted: read by the game's own message loop (kept set)
        }
        snprintf(out, sizeof out, "wheel %s: %s", a, game_window ? "sent" : "NO WINDOW");
    } else if (!_stricmp(cmd, "key")) {
        WPARAM vk = (WPARAM)strtol(a, NULL, 0);
        if (game_window) {
            SendMessageA(game_window, WM_KEYDOWN, vk, 1);
            SendMessageA(game_window, WM_KEYUP, vk, (LPARAM)0xC0000001);
        }
        snprintf(out, sizeof out, "key %s: %s", a, game_window ? "sent" : "NO WINDOW");
    } else if (!_stricmp(cmd, "postkey")) {   // postkey <vk>: through the message queue, as a real key press
        WPARAM vk = (WPARAM)strtol(a, NULL, 0);
        if (game_window) {
            PostMessageA(game_window, WM_KEYDOWN, vk, 1);
            PostMessageA(game_window, WM_KEYUP, vk, (LPARAM)0xC0000001);
        }
        snprintf(out, sizeof out, "postkey %s: %s", a, game_window ? "posted" : "NO WINDOW");
    } else if (!_stricmp(cmd, "type")) {        // type <text>: characters into the focused text box
        if (game_window)
            for (const char *p = a; *p; p++) SendMessageA(game_window, WM_CHAR, (WPARAM)(unsigned char)*p, 1);
        snprintf(out, sizeof out, "type %s: %s", a, game_window ? "sent" : "NO WINDOW");
    } else if (!_stricmp(cmd, "call")) {        // call <global Lua function> [argument]: the mod's test hooks
        lua_State *L = gui_state;
        const char *arg = line + strlen(cmd);
        while (*arg == ' ') arg++;
        arg += strlen(a);
        while (*arg == ' ') arg++;
        char argument[256];
        snprintf(argument, sizeof argument, "%s", arg);
        argument[strcspn(argument, "\r\n")] = 0;
        if (!L || !lua_pcall_fn || script_depth > 0 || gui_busy || busy_now()) {
            snprintf(out, sizeof out, "call %s: NOT READY (no campaign script yet)", a);
        } else {
            gui_busy = 1;
            room_for(L, 8, "an agent call");
            int top = lua_gettop(L);
            lua_pushstring(L, a);
            lua_gettable_fn(L, LUA_GLOBALSINDEX);
            if (lua_type_fn(L, -1) != 6) {
                snprintf(out, sizeof out, "call %s: NO SUCH FUNCTION", a);
            } else {
                lua_pushstring(L, argument);
                if (lua_pcall_fn(L, 1, 1, 0) != 0) {
                    snprintf(out, sizeof out, "call %s: ERROR %.300s", a, lua_tostring_fn ? lua_tostring_fn(L, -1) : "?");
                } else {
                    const char *r = lua_tostring_fn ? lua_tostring_fn(L, -1) : NULL;
                    snprintf(out, sizeof out, "call %s %s: %.3800s", a, argument, r ? r : "ok");
                }
            }
            lua_settop(L, top);
            gui_busy = 0;
        }
    } else if (!_stricmp(cmd, "keepactive")) {
        set_keep_active(_stricmp(a, "off") != 0);
        snprintf(out, sizeof out, "keepactive %s: %s", keep_active ? "on" : "off", game_window ? "ok" : "NO WINDOW");
    } else if (!_stricmp(cmd, "quit")) {          // quit: the game ends itself (no elevated helper needed)
        test_log("AGENT quit");
        test_log_flush();
        TerminateProcess(GetCurrentProcess(), 0);
    } else if (!_stricmp(cmd, "wait")) {
        return atoi(a);
    } else if (!_stricmp(cmd, "padclick")) {      // padclick x y: as a right click on the Base Layout screen
        snprintf(out, sizeof out, "padclick: %d", hp_pad_click(atoi(a), atoi(b), 0));
    } else if (!_stricmp(cmd, "grab")) {          // grab: the game in front with the cursor on it (real input)
        GetCursorPos(&grab_saved_cursor);
        grab_saved_window = GetForegroundWindow();
        HWND user_window = grab_saved_window;
        if (game_window) {
            DWORD fg = GetWindowThreadProcessId(user_window, NULL), me = GetCurrentThreadId();
            AttachThreadInput(me, fg, TRUE);
            SetForegroundWindow(game_window);
            AttachThreadInput(me, fg, FALSE);
            RECT r;
            GetClientRect(game_window, &r);
            POINT c = {r.right / 2, r.bottom / 2};
            ClientToScreen(game_window, &c);
            SetCursorPos(c.x, c.y);
        }
        snprintf(out, sizeof out, "grab: %s", game_window ? "ok" : "NO WINDOW");
    } else if (!_stricmp(cmd, "cursor")) {        // cursor x y: the real cursor to client x, y (after grab: hovers)
        int x = atoi(a), y = atoi(b);
        POINT c = {x, y};
        if (game_window) ClientToScreen(game_window, &c);
        SetCursorPos(c.x, c.y);
        snprintf(out, sizeof out, "cursor %d %d: %s", x, y, game_window ? "set" : "NO WINDOW");
    } else if (!_stricmp(cmd, "realwheel")) {     // realwheel <notches>: real wheel input (after grab)
        int n = atoi(a);
        for (int i = 0; i < abs(n); i++) {
            INPUT in;
            memset(&in, 0, sizeof in);
            in.type = INPUT_MOUSE;
            in.mi.dwFlags = MOUSEEVENTF_WHEEL;
            in.mi.mouseData = (DWORD)(n > 0 ? WHEEL_DELTA : -WHEEL_DELTA);
            SendInput(1, &in, sizeof in);
        }
        snprintf(out, sizeof out, "realwheel %s: sent", a);
    } else if (!_stricmp(cmd, "release")) {       // release: the desktop's window and cursor back, game behind
        SetCursorPos(grab_saved_cursor.x, grab_saved_cursor.y);
        if (grab_saved_window) {
            DWORD fg = GetWindowThreadProcessId(GetForegroundWindow(), NULL), me = GetCurrentThreadId();
            AttachThreadInput(me, fg, TRUE);
            SetForegroundWindow(grab_saved_window);
            AttachThreadInput(me, fg, FALSE);
        }
        if (game_window) SetWindowPos(game_window, HWND_BOTTOM, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        snprintf(out, sizeof out, "release: ok");
    } else if (!_stricmp(cmd, "front") || !_stricmp(cmd, "back")) {
        if (game_window) SetWindowPos(game_window, !_stricmp(cmd, "front") ? HWND_TOP : HWND_BOTTOM, 0, 0, 0, 0,
                                      SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        snprintf(out, sizeof out, "%s: %s", cmd, game_window ? "ok" : "NO WINDOW");
    } else {
        snprintf(out, sizeof out, "unknown command: %s", cmd);
    }
    agent_result(out);
    return 0;
}

static void agent_poll(void) {
    DWORD now = GetTickCount();
    if (now < agent_next || now < agent_resume_at || !agent_cmd_path[0]) return;
    agent_next = now + 100;
    agent_find_window();
    if (!game_window || GetCurrentThreadId() != GetWindowThreadProcessId(game_window, NULL)) return;
    FILE *f = fopen(agent_cmd_path, "r");
    if (!f) { agent_line = 0; return; }
    char line[300];
    int n = 0, done = 1;
    while (fgets(line, sizeof line, f)) {
        if (n++ < agent_line) continue;
        agent_line = n;
        int wait = agent_run(line);
        if (wait > 0) {                         // resume after the wait, at the next line
            agent_resume_at = GetTickCount() + (DWORD)wait;
            done = 0;
            break;
        }
    }
    fclose(f);
    if (done) {
        remove(agent_cmd_path);
        agent_line = 0;
        agent_result("done");
    }
}
#endif

static int lua_screen_size(lua_State *L) {
    if (!game_window || !IsWindow(game_window)) {
        game_window = NULL;
        EnumWindows(find_game_window, 0);
    }
    RECT r = {0, 0, 0, 0};
    if (game_window) GetClientRect(game_window, &r);
    lua_pushnumber(L, r.right - r.left);
    lua_pushnumber(L, r.bottom - r.top);
    return 2;
}

// Engine_Mouse(): the cursor in the game window's client pixels and whether the left button is held
// (x, y, 1 | 0), for dragging GUI parts such as scroll bars. 0, 0, 0 if the window isn't found.
static int lua_mouse(lua_State *L) {
    if (!game_window || !IsWindow(game_window)) {
        game_window = NULL;
        EnumWindows(find_game_window, 0);
    }
    POINT p = {0, 0};
    int down = 0;
    if (game_window && GetCursorPos(&p) && ScreenToClient(game_window, &p)) {
        int button = GetSystemMetrics(SM_SWAPBUTTON) ? VK_RBUTTON : VK_LBUTTON;
        down = (GetAsyncKeyState(button) & 0x8000) ? 1 : 0;
    }
    lua_pushnumber(L, p.x);
    lua_pushnumber(L, p.y);
    lua_pushnumber(L, down);
    lua_pushnumber(L, wheel_delta / 120.0);     // wheel notches since the last call (up > 0)
    wheel_delta = 0;
    return 4;
}

// Engine_Rebellion_Prompt(1 | 0): arm or disarm the rebellion prompt for the calling script.
static int lua_rebellion_prompt(lua_State *L) {
    rebellion_prompt = lua_gettop(L) >= 1 && luaL_checknumber(L, 1) != 0;
    rebellion_state = NULL;
    void *g = *(void **)((unsigned char *)L + LUA_STATE_GLOBAL);
    for (int i = 0; rebellion_prompt && i < main_state_count; i++) {
        if (main_globals[i] == g) rebellion_state = main_states[i];
    }
    if (rebellion_prompt) {
        char line[120];
        snprintf(line, sizeof line, "REBELLION PROMPT armed (script state %s)", rebellion_state ? "found" : "NOT found");
        test_log(line);
    }
    return 0;
}

// --- GUI functions for custom components ------------------------------------------------------------
// The Lua GUI functions only know the engine's built-in components (0x347b70). When that lookup fails, a mod
// component's live widget is found as FORCE_CLICK_GUI does (0x2f5bf0) and returned through a stand-in entry.
#define RVA_FIND_COMPONENT  0x347b70
#define RVA_COMMAND_BAR     0xb27f60
#define RVA_FIND_WIDGET     0x2f5bf0    // (command bar, name) -> live widget
#define MAX_CUSTOM_ENTRIES  4096   // every mod component ever looked up (the windows have well over 512)
static void **(*orig_find_component)(const char *);
static unsigned char *(*find_widget)(unsigned char *, const char *);
static struct { char name[64]; unsigned hash; void *entry[9]; } custom_entries[MAX_CUSTOM_ENTRIES];
static int custom_entry_count;

// The mod's window buttons report no click, so the hook detects them (poll_buttons): a mouse button released where
// it was pressed is passed to Lua, which finds the component under the cursor. Engine_Gui_Pressed(),
// Engine_Gui_Visible(name), Engine_Cursor().
static int press_button;                // 0 none, 1 left, 2 right
static POINT press_at;

static void press_and_release(UINT message) {
    int down = message == WM_LBUTTONDOWN ? 1 : message == WM_RBUTTONDOWN ? 2 : 0;
    int up = message == WM_LBUTTONUP ? 1 : message == WM_RBUTTONUP ? 2 : 0;
    POINT at = {0, 0};
    GetCursorPos(&at);
    if (down) {
        press_button = down;
        press_at = at;
    } else if (up) {
        int still = abs(at.x - press_at.x) <= 8 && abs(at.y - press_at.y) <= 8;
        if (press_button == up && still && click_count < MAX_CLICKS) {
            snprintf(click_names[click_count], sizeof click_names[0], "?");
            snprintf(click_buttons[click_count], sizeof click_buttons[0], "%s", up == 1 ? "left" : "right");
            click_count++;
        }
        press_button = 0;
    }
}

static int lua_gui_pressed(lua_State *L) {
    if (!press_button) return 0;
    lua_pushnumber(L, press_button);
    return 1;
}

static int lua_cursor(lua_State *L) {
    POINT p = {0, 0};
    if (game_window) {
        GetCursorPos(&p);
        ScreenToClient(game_window, &p);
    }
    lua_pushnumber(L, p.x);
    lua_pushnumber(L, p.y);
    return 2;
}

static int lua_gui_visible(lua_State *L) {
    const char *name = lua_gettop(L) >= 1 && lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    unsigned char *w = name ? custom_component(name) : NULL;
    if (!w || (w[0xc0] & 2)) return 0;                  // nil: hidden (or no such component)
    lua_pushnumber(L, 1);
    return 1;
}

static unsigned char *custom_component(const char *name);

// Hides every resolved custom component named "*_shell" (the windows): widget method +0x78 = set hidden,
// as GUI_Component_Visibility does it.
static void hide_custom_shells(void) {
    for (int i = 0; i < custom_entry_count; i++) {
        size_t n = strlen(custom_entries[i].name);
        if (n < 6 || _stricmp(custom_entries[i].name + n - 6, "_shell") != 0) continue;
        if (!_strnicmp(custom_entries[i].name, "dp_rt_", 6)) continue;     // the battle's reinforcement banner
        unsigned char *w = custom_component(custom_entries[i].name);
        if (w) ((void (*)(void *, char))(*(void ***)w)[0x78 / 8])(w, 1);
    }
}

// The galactic panel buttons (b_diplomacy_panel_*, b_senate_panel_*, in the hero frames).
static void hide_panel_buttons(void) {
    for (int i = 0; i < custom_entry_count; i++) {
        const char *name = custom_entries[i].name;
        if (_strnicmp(name, "b_diplomacy_panel", 17) != 0 && _strnicmp(name, "b_senate_panel", 14) != 0) continue;
        unsigned char *w = custom_component(name);
        if (w) ((void (*)(void *, char))(*(void ***)w)[0x78 / 8])(w, 1);
    }
}

static unsigned char *custom_component(const char *name) {
    return find_widget ? find_widget(module_base + RVA_COMMAND_BAR, name) : NULL;
}

static unsigned name_hash(const char *name) {      // case-insensitive FNV-1a
    unsigned h = 2166136261u;
    for (; *name; name++) h = (h ^ (unsigned char)tolower((unsigned char)*name)) * 16777619u;
    return h;
}

static void **hooked_find_component(const char *name) {
    void **entry = orig_find_component(name);
    if (entry || !name) return entry;
    unsigned hash = name_hash(name);
    for (int i = 0; i < custom_entry_count; i++) {
        if (custom_entries[i].hash == hash && _stricmp(custom_entries[i].name, name) == 0) {
            custom_entries[i].entry[1] = custom_component(name);    // components are rebuilt per mode
            return custom_entries[i].entry[1] ? custom_entries[i].entry : NULL;
        }
    }
    unsigned char *component = custom_component(name);
    char line[160];
    snprintf(line, sizeof line, "GUI custom component %s: %p", name, (void *)component);
    test_log(line);
    if (!component) return NULL;
    if (custom_entry_count >= MAX_CUSTOM_ENTRIES) {
        test_log("GUI custom component table FULL: raise MAX_CUSTOM_ENTRIES");
        return NULL;
    }
    int i = custom_entry_count++;
    strncpy(custom_entries[i].name, name, sizeof custom_entries[i].name - 1);
    custom_entries[i].hash = hash;
    custom_entries[i].entry[0] = custom_entries[i].name;
    custom_entries[i].entry[1] = component;
    return custom_entries[i].entry;
}

// --- Space battles: a group's attack spreads over the target's hardpoints ---------------------------------------
// A hull click with two or more ships selected gives each ship its own living hardpoint, in shuffled order, instead
// of all firing at one. Other orders are unchanged.
#define RVA_ATTACK_EXECUTE  0x3af790    // AttackEventClass execute (event)
#define RVA_UNIT_ATTACK     0x38d730    // (unit, target, hardpoint id, 1, 0, -1, flag)
#define RVA_SPREAD_OBJECT   0x2aca60    // (object manager, id)
#define RVA_SELECTION_LIST  0x2ad080    // (object manager, player id) -> list: +8 end node, +0x10 first; node +8 next
#define RVA_SIM_FRAME       0xb0a320
#define MAX_SPREAD          64
static void (*orig_attack_execute)(unsigned char *);
static long long (*orig_unit_attack)(void *, void *, int, char, int, unsigned, char);
static unsigned char *(*spread_object)(void *, int);
static unsigned char *(*selection_list)(void *, int);
static void *spread_target;
static int spread_ids[MAX_SPREAD], spread_count, spread_next, spread_logged, spread_notes;   // (notes: log lines, at most 60)

static long long hooked_unit_attack(void *unit, void *target, int hardpoint, char a, int b, unsigned c, char d) {
    if (spread_count > 0 && target == spread_target && hardpoint == 0) {
        int id = spread_ids[spread_next++ % spread_count];
        int count = spread_count;
        spread_count = 0;                              // (a unit's orders to its own group keep what it was given)
        long long result = orig_unit_attack(unit, target, id, a, b, c, d);
        spread_count = count;
        if (spread_logged < 12 && spread_notes++ < 60) {                     // (the first orders of each spread: what each ship was given)
            char line[96];
            snprintf(line, sizeof line, "SPREAD: ship -> hardpoint %d: %s", id, (char)result == 1 ? "taken" : "refused");
            test_log(line);
            spread_logged++;
        }
        if ((char)result == 1) return result;
    }
    return orig_unit_attack(unit, target, hardpoint, a, b, c, d);
}

static void plan_spread(unsigned char *event) {
    spread_count = 0;
    if (!diplomacy_loaded()) return;
    unsigned char *mode = *(unsigned char **)(module_base + RVA_ACTIVE_MODE);
    if (!mode || *(void **)mode != module_base + RVA_SPACE_MODE_VT) return;
    if (*(int *)(event + 0x4c) != 0 || *(int *)(event + 0x250) != 0) {
        char line[96];
        snprintf(line, sizeof line, "SPREAD: not spread (hardpoint %d picked, list %d)", *(int *)(event + 0x4c),
                 *(int *)(event + 0x250));
        if (spread_notes++ < 60) test_log(line);
        return;
    }
    void *objects = *(void **)(mode + 0x18);
    unsigned char *target = spread_object(objects, *(int *)(event + 0x48));
    unsigned char *points = target ? *(unsigned char **)(target + 0x2d0) : NULL;
    unsigned char *list = selection_list(objects, *(int *)(event + 0x24));
    if (!points || !list) return;
    int units = 0;
    for (unsigned char *n = *(unsigned char **)(list + 0x10); n != list + 8 && units < 2; n = *(unsigned char **)(n + 8)) {
        if (*(void **)(n + 0x18)) units++;
    }
    if (units < 2) { if (spread_notes++ < 60) test_log("SPREAD: not spread (one ship selected)"); return; }
    int total = *(int *)(points + 0x10), count = 0;
    unsigned char **array = *(unsigned char ***)(points + 8);
    for (int i = 0; i < total && count < MAX_SPREAD; i++) {
        unsigned char *hp = array[i];
        unsigned char *data = hp ? *(unsigned char **)(hp + 0x20) : NULL;
        if (data && data[0x4c] && data[0x4d] == 1 && *(float *)(hp + 0x28) > 0 && *(int *)(data + 0x20) != 0)
            spread_ids[count++] = *(int *)(data + 0x20);
    }
    // the same order on every machine: from the game's own frame count and the target, never the clock
    unsigned int seed = (unsigned int)*(int *)(module_base + RVA_SIM_FRAME) * 2654435761u
                        ^ (unsigned int)*(int *)(event + 0x48) * 40503u;
    for (int i = count - 1; i > 0; i--) {
        seed = seed * 1103515245u + 12345u;
        int j = (int)((seed >> 16) % (unsigned int)(i + 1));
        int swap = spread_ids[i];
        spread_ids[i] = spread_ids[j];
        spread_ids[j] = swap;
    }
    spread_target = target;
    spread_next = 0;
    spread_count = count;
    spread_logged = 0;
    char line[96];
    snprintf(line, sizeof line, "SPREAD: group attack, %d living hardpoints on the target", count);
    if (spread_notes++ < 60) test_log(line);
}

static void hooked_attack_execute(unsigned char *event) {
    plan_spread(event);
    orig_attack_execute(event);
    spread_count = 0;
}

static void hook(unsigned char *base, DWORD rva, void *detour, void **original, const char *what) {
    if (MH_CreateHook(base + rva, detour, original) != MH_OK || MH_EnableHook(base + rva) != MH_OK) {
        log_line(what);
    }
}

static void install_attack_spread(unsigned char *base) {
    static const unsigned char execute_sig[8] = {0x48,0x89,0x4c,0x24,0x08,0x55,0x56,0x57};
    static const unsigned char attack_sig[8] = {0x48,0x89,0x5c,0x24,0x18,0x44,0x88,0x4c};
    if (memcmp(base + RVA_ATTACK_EXECUTE, execute_sig, 8) != 0 || memcmp(base + RVA_UNIT_ATTACK, attack_sig, 8) != 0) {
        log_line("attack orders not found: no hardpoint spread");
        return;
    }
    spread_object = (void *)(base + RVA_SPREAD_OBJECT);
    selection_list = (void *)(base + RVA_SELECTION_LIST);
    hook(base, RVA_UNIT_ATTACK, (void *)hooked_unit_attack, (void **)&orig_unit_attack, "hardpoint spread failed");
    hook(base, RVA_ATTACK_EXECUTE, (void *)hooked_attack_execute, (void **)&orig_attack_execute, "hardpoint spread failed");
    log_line("group attacks spread over hardpoints");
}

// --- Planets are never despawned ------------------------------------------------------------------------------------
// A script that despawns every object of a faction at a world also gets the world itself when that faction owns it;
// the planet is then gone for every later script and the engine crashes (0x395708). Planets: object +0x335 != -1.
#define RVA_LUA_DESPAWN 0x5752a0    // GameObjectWrapper::Despawn(wrapper, Lua state); wrapper +0x60 the object
static void *(*orig_lua_despawn)(unsigned char *wrapper, void *state);

static void *hooked_lua_despawn(unsigned char *wrapper, void *state) {
    unsigned char *object = wrapper ? *(unsigned char **)(wrapper + 0x60) : NULL;
    if (object && *(signed char *)(object + 0x335) != -1) {
        char line[160];
        snprintf(line, sizeof line, "refused a script's Despawn of the planet %s", type_name(object));
        log_line(line);
        return NULL;
    }
    return orig_lua_despawn(wrapper, state);
}

static void install_despawn_guard(unsigned char *base) {
    static const unsigned char sig[10] = {0x48,0x89,0x5c,0x24,0x18,0x57,0x48,0x83,0xec,0x20};
    if (memcmp(base + RVA_LUA_DESPAWN, sig, sizeof sig) != 0) {
        log_line("Despawn not found: no planet guard");
        return;
    }
    hook(base, RVA_LUA_DESPAWN, (void *)hooked_lua_despawn, (void **)&orig_lua_despawn, "planet guard failed");
    log_line("planets are never despawned by scripts");
}

// --- Hardpoints from the galaxy map --------------------------------------------------------------------------------
// Build pads on the planet's Base Layout screen take a right click. The turret is stored in the planet's persistent
// turret list (planet+0xb8, +8) with a placeholder position (x = y = PENDING + id, z = -id); the pad with that id
// gives it its real position in battle.
#define RVA_LAYOUT_SELF     0xb27f60    // the galactic GUI; +0x2150 its planet, +0x2a34 Base Layout is up
#define RVA_LAYOUT_REFRESH  0x3d9ea0
#define RVA_COMPONENT_TABLE 0xa174e8    // the engine's own components, by id, 72 bytes apart
#define RVA_PAD_START       0x42d8b0
#define RVA_PAD_STORE       0x42f160
#define RVA_PERSIST_ADD     0x4b6c70
#define RVA_PERSIST_FIND    0x4b7c00
#define RVA_PERSIST_REMOVE  0x4b7530
#define RVA_TYPE_BY_ID      0x407db0
#define RVA_COLOR_OF        0x33e340
#define RVA_BONE_SHOW       0x34ba10
#define RVA_BONE_MATRIX     0x354c80
#define PAD_FIRST 0x307
#define PAD_LAST  0x32e
#define HP_PENDING 10000000.0f
#define HP_SCALE   1.6f
#define HP_SCALE_BUILT 3.0f
#define HP_PALETTE 24

static void (*orig_layout_refresh)(unsigned char *);
static void (*orig_pad_start)(void *, unsigned char *);
static void (*orig_pad_store)(void *, unsigned char *, unsigned char *, char);
static unsigned long long (*orig_persist_find)(unsigned char *, float *, int *);
static unsigned long long (*orig_persist_add)(unsigned char *, unsigned char *, float *, unsigned, int);
static char (*persist_remove)(unsigned char *, int);
static unsigned char *(*type_by_id)(void *, int);
static float *(*color_of)(void *, int);
static void (*bone_show)(void *, int, int);
static void (*bone_matrix)(void *, int, float *);
static int hp_picked, hp_selected, hp_store_id, hp_on;
static float hp_picked_x, hp_picked_y;
static unsigned char *hp_base_planet;
static int hp_base_marker[PAD_LAST - PAD_FIRST + 1];
static float hp_base[PAD_LAST - PAD_FIRST + 1][2];

static unsigned char *hp_component(int id) {
    return *(unsigned char **)(module_base + RVA_COMPONENT_TABLE + (long long)id * 72);
}

static unsigned char *hp_planet(void) {
    if (!hp_on) return NULL;
    unsigned char *self = module_base + RVA_LAYOUT_SELF;
    return self[0x2a34] ? *(unsigned char **)(self + 0x2150) : NULL;
}

static const char *hp_type_name(unsigned char *type) {
    return *(unsigned long long *)(type + 0x110) > 15 ? *(char **)(type + 0xf8) : (char *)(type + 0xf8);
}

// Whether a marker is a pad a hardpoint can be built on.
static int hp_is_pad(unsigned char *marker) {
    unsigned char *type = readable(marker, 0x10) ? type_by_id(module_base + RVA_TYPE_MANAGER, *(int *)(marker + 4)) : NULL;
    return type && _stricmp(hp_type_name(type), "SKIRMISH_BUILD_PAD") == 0;
}

static unsigned char *hp_entry(unsigned char *planet, int id, int *index) {
    unsigned char *pack = planet ? *(unsigned char **)(planet + 0xb8) : NULL;
    if (!pack) return NULL;
    unsigned char *data = *(unsigned char **)(pack + 0x10);
    int count = *(int *)(pack + 0x18);
    for (int i = 0; i < count; i++) {
        unsigned char *e = data + (long long)i * 0x18;
        if (*(float *)(e + 0xc) == -(float)id) {
            if (index) *index = i;
            return e;
        }
    }
    return NULL;
}

// The palette colour nearest the planet owner's (build.py makes dp_hp_NN.tga: 22 hues, then white and grey).
static int hp_palette_of(unsigned char *planet) {
    unsigned char *player = get_player_by_id(module_base + RVA_PLAYER_LIST, *(int *)(planet + 0x58));
    if (!player || !*(unsigned char **)(player + 0x68)) return HP_PALETTE - 1;
    float *c = color_of(*(unsigned char **)(player + 0x68), 0);
    if (!readable(c, 16)) return HP_PALETTE - 1;
    float r = c[0], g = c[1], b = c[2];
    if (r > 1.5f || g > 1.5f || b > 1.5f) { r /= 255.0f; g /= 255.0f; b /= 255.0f; }
    float hi = r > g ? (r > b ? r : b) : (g > b ? g : b);
    float lo = r < g ? (r < b ? r : b) : (g < b ? g : b);
    if (hi - lo < 0.12f) return hi > 0.7f ? HP_PALETTE - 2 : HP_PALETTE - 1;
    float hue = hi == r ? (g - b) / (hi - lo) : hi == g ? 2.0f + (b - r) / (hi - lo) : 4.0f + (r - g) / (hi - lo);
    if (hue < 0.0f) hue += 6.0f;
    return (int)(hue * (HP_PALETTE - 2) / 6.0f + 0.5f) % (HP_PALETTE - 2);
}

// What stands on a pad, as the icon the battle's build menu shows for it.
static const char *hp_icon_of(int type_id) {
    unsigned char *type = type_by_id(module_base + RVA_TYPE_MANAGER, type_id);
    if (!type) return NULL;
    const char *name = hp_type_name(type);
    int rebel = _strnicmp(name, "Rebel", 5) == 0;
    if (strstr(name, "ANTI_VEHICLE")) return rebel ? "i_button_r_anti_vehicle.tga" : "i_button_e_anti_vehicle.tga";
    if (strstr(name, "ANTI_INFANTRY")) return rebel ? "i_button_r_anti_infantry.tga" : "i_button_e_anti_infantry.tga";
    if (strstr(name, "ANTI_AIRCRAFT")) return rebel ? "i_button_r_anti_aircraft.tga" : "i_button_e_anti_aircraft.tga";
    if (strstr(name, "BACTA")) return "i_button_bacta_tank.tga";
    if (strstr(name, "REPAIR")) return "i_button_e_repair_facility.tga";
    if (strstr(name, "SENSOR")) return "i_button_sensor_node.tga";
    return NULL;
}

// Where a pad's component sits. Reading the component once it is scaled gives a different answer, so each pad's place is
// read once, as the screen lays it out at its plain size, and kept: repainting never moves it.
static void hp_position(int id, unsigned char *c, unsigned char *planet, float *x, float *y) {
    int i = id - PAD_FIRST, key = *(int *)*(unsigned char **)(c + 0x50);
    if (planet != hp_base_planet) {
        memset(hp_base_marker, 0, sizeof hp_base_marker);
        hp_base_planet = planet;
    }
    if (hp_base_marker[i] != key) {
        float pos[4] = {0, 0, 0, 0};
        void **vt = *(void ***)c;
        ((void *(*)(void *, float *))vt[0x50 / 8])(c, pos);
        hp_base_marker[i] = key;
        hp_base[i][0] = pos[0];
        hp_base[i][1] = pos[1];
    }
    *x = hp_base[i][0];
    *y = hp_base[i][1];
}

// The pads on screen glow in the owner's colour, larger than the map's small marks; a built one shines.
static void hp_paint(void) {
    unsigned char *planet = hp_planet();
    if (!planet) return;
    int colour = hp_palette_of(planet);
    for (int id = PAD_FIRST; id <= PAD_LAST; id++) {
        unsigned char *c = hp_component(id);
        unsigned char *marker = c ? *(unsigned char **)(c + 0x50) : NULL;
        if (!marker || !hp_is_pad(marker)) continue;
        char texture[48];
        int key = *(int *)marker;
        unsigned char *built = hp_entry(planet, key, NULL);
        const char *icon = built ? hp_icon_of(*(int *)built) : NULL;
        float scale = icon ? HP_SCALE_BUILT : HP_SCALE;
        if (key == hp_selected) snprintf(texture, sizeof texture, "dp_hp_sel.tga");
        else if (icon) snprintf(texture, sizeof texture, "%s", icon);
        else snprintf(texture, sizeof texture, "dp_hp_%02d%s.tga", colour, built ? "b" : "");
        void **vt = *(void ***)c;
        ((void (*)(void *, const char *, int))vt[0xa0 / 8])(c, texture, 0);
        float at_x, at_y;
        hp_position(id, c, planet, &at_x, &at_y);
        void *model = *(void **)(c + 0x88);
        int bone = *(int *)(c + 0xa0);
        if (model && bone >= 0) {
            float m[12] = {scale, 0, 0, at_x, 0, scale, 0, at_y, 0, 0, 1, 7.0f};
            bone_show(model, bone, 1);
            bone_matrix(model, bone, m);
        }
    }
}

static void hooked_layout_refresh(unsigned char *self) {
    orig_layout_refresh(self);
    hp_paint();
}

// A click on a pad of the Base Layout screen: the pad's id for Lua, and the click goes no further. A left click over the
// open menu belongs to the menu (HP_MENU in build.py).
static int hp_pad_click(int x, int y, int left) {
    unsigned char *planet = hp_planet();
    if (!planet || !game_window) return 0;
    RECT r;
    GetClientRect(game_window, &r);
    float h = (float)r.bottom, w = (float)r.right, unit = h / 768.0f, best = 16.0f * h / 900.0f;
    float shell_x = (x - w / 2) / unit, shell_y = (h / 2 - y) / unit;
    if (left && hp_selected && shell_x > -490.0f && shell_x < -290.0f && shell_y > -41.0f && shell_y < 191.0f) return 0;
    int found = 0;
    float fx = 0, fy = 0;
    for (int id = PAD_FIRST; id <= PAD_LAST; id++) {
        unsigned char *c = hp_component(id);
        unsigned char *marker = c ? *(unsigned char **)(c + 0x50) : NULL;
        if (!marker || !hp_is_pad(marker)) continue;
        float at_x, at_y;
        hp_position(id, c, planet, &at_x, &at_y);
        float px = w / 2 + at_x * unit, py = h / 2 - at_y * unit;
        float d = sqrtf((px - x) * (px - x) + (py - y) * (py - y));
        if (d <= best) {
            best = d;
            found = *(int *)marker;
            fx = at_x;
            fy = at_y;
        }
    }
    if (!found) return 0;
    hp_picked = found;
    hp_picked_x = fx;
    hp_picked_y = fy;
    return 1;
}

// A pad starts in a battle: what is finished on it from now on is kept, like the turrets built on the galaxy map.
static void hooked_pad_start(void *self, unsigned char *pad) {
    unsigned char *type = pad ? *(unsigned char **)(pad + 0x298) : NULL;
    if (type && diplomacy_loaded() && _stricmp(hp_type_name(type), "SKIRMISH_BUILD_PAD") == 0) type[0xcc] = 1;
    orig_pad_start(self, pad);
}

// The pad asks what stands on it: a turret built on the galaxy map learns where it is.
static unsigned long long hooked_persist_find(unsigned char *pack, float *pos, int *owner) {
    int id = *(int *)((unsigned char *)pos - 0x78 + 0x50);
    unsigned char *data = *(unsigned char **)(pack + 0x10);
    int count = *(int *)(pack + 0x18);
    for (int i = 0; i < count; i++) {
        float *e = (float *)(data + (long long)i * 0x18);
        if (e[3] == -(float)id && e[1] >= HP_PENDING) {
            e[1] = pos[0];
            e[2] = pos[1];
        }
    }
    return orig_persist_find(pack, pos, owner);
}

// A building finished on a pad in battle: its entry is named after the pad.
static void hooked_pad_store(void *self, unsigned char *pad, unsigned char *child, char store) {
    hp_store_id = (store == 1 && pad) ? *(int *)(pad + 0x50) : 0;
    orig_pad_store(self, pad, child, store);
    hp_store_id = 0;
}

static unsigned long long hooked_persist_add(unsigned char *pack, unsigned char *type, float *pos, unsigned level, int owner) {
    unsigned long long r = orig_persist_add(pack, type, pos, level, owner);
    if (r && hp_store_id && *(int *)(pack + 0x18) > 0) {
        float *e = (float *)(*(unsigned char **)(pack + 0x10) + (long long)(*(int *)(pack + 0x18) - 1) * 0x18);
        e[3] = -(float)hp_store_id;
    }
    return r;
}

static int hp_tick_wanted(void) {
    return hp_picked || hp_selected;
}

// Engine_Layout_Open(): the planet whose Base Layout is on screen (type name), nil if none.
static int lua_layout_open(lua_State *L) {
    unsigned char *planet = hp_planet();
    if (!planet) return 0;
    const char *name = type_name(planet);
    if (!name) return 0;
    lua_pushstring(L, name);
    return 1;
}

// Engine_Layout_Pick(): "id|x|y" of a pad clicked since the last call (x, y on the shell's scale), nil if none.
static int lua_layout_pick(lua_State *L) {
    if (!hp_picked) return 0;
    char out[64];
    snprintf(out, sizeof out, "%d|%.1f|%.1f", hp_picked, hp_picked_x, hp_picked_y);
    hp_picked = 0;
    lua_pushstring(L, out);
    return 1;
}

// Engine_Layout_Select(id or 0): the pad the menu is open for shows white.
static int lua_layout_select(lua_State *L) {
    const char *id = lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    hp_selected = id ? atoi(id) : 0;
    hp_paint();
    return 0;
}

// Engine_Hardpoint_At(id): the type built on that pad of the planet on screen, nil if none.
static int lua_hardpoint_at(lua_State *L) {
    const char *id = lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    unsigned char *e = id ? hp_entry(hp_planet(), atoi(id), NULL) : NULL;
    unsigned char *type = e ? type_by_id(module_base + RVA_TYPE_MANAGER, *(int *)e) : NULL;
    if (!type) return 0;
    lua_pushstring(L, hp_type_name(type));
    return 1;
}

// Engine_Hardpoint_Build(id, type): the turret stands on that pad, for the planet's owner. 1 if it was added.
static int lua_hardpoint_build(lua_State *L) {
    const char *id_text = lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    const char *name = lua_tostring_fn ? lua_tostring_fn(L, 2) : NULL;
    unsigned char *planet = hp_planet();
    unsigned char *pack = planet ? *(unsigned char **)(planet + 0xb8) : NULL;
    unsigned char *type = name ? type_by_name(name) : NULL;
    if (!id_text || !pack || !type) return 0;
    int id = atoi(id_text);
    if (hp_entry(planet, id, NULL)) return 0;
    float pos[3] = {HP_PENDING + (float)id, HP_PENDING + (float)id, -(float)id};
    if (!orig_persist_add(pack, type, pos, 0, *(int *)(planet + 0x58))) return 0;
    hp_paint();
    lua_pushnumber(L, 1);
    return 1;
}

// Engine_Hardpoint_Remove(id): nothing stands on that pad any more. 1 if something did.
static int lua_hardpoint_remove(lua_State *L) {
    const char *id_text = lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    unsigned char *planet = hp_planet();
    int index = -1;
    if (!id_text || !hp_entry(planet, atoi(id_text), &index)) return 0;
    persist_remove(*(unsigned char **)(planet + 0xb8) + 8, index);
    hp_paint();
    lua_pushnumber(L, 1);
    return 1;
}

// Engine_Planet_Flash(name, seconds): the world's minimap dot flashes its new owner's colour (after 0x3ea1b0).
#define RVA_PLANET_ROWS 0x3ea1b0
#define MAX_FLASHES 32
static void (*orig_planet_rows)(unsigned char *);
static struct { char name[64]; DWORD until; } hp_flashes[MAX_FLASHES];

static void hooked_planet_rows(unsigned char *self) {
    orig_planet_rows(self);
    DWORD now = GetTickCount();
    int any = 0;
    for (int f = 0; f < MAX_FLASHES; f++) if (hp_flashes[f].until && now >= hp_flashes[f].until) hp_flashes[f].until = 0;
    for (int f = 0; f < MAX_FLASHES; f++) any |= hp_flashes[f].until != 0;
    if (!any) return;
    int count = *(int *)(self + 0xde8);
    unsigned char *rows = *(unsigned char **)(self + 0xde0);
    float dim = (now / 400) & 1 ? 1.0f : 0.35f;
    for (int i = 0; i < count; i++) {
        unsigned char *row = rows + (long long)i * 0x188;
        unsigned char *planet = *(unsigned char **)row;
        if (!planet) continue;
        const char *name = type_name(planet);
        if (!name) continue;
        for (int f = 0; f < MAX_FLASHES; f++) {
            if (!hp_flashes[f].until || _stricmp(hp_flashes[f].name, name) != 0) continue;
            unsigned char *player = get_player_by_id(module_base + RVA_PLAYER_LIST, *(int *)(planet + 0x58));
            float *c = (player && *(unsigned char **)(player + 0x68)) ? color_of(*(unsigned char **)(player + 0x68), 0) : NULL;
            if (!readable(c, 16)) break;
            float colour[4] = {c[0] * dim, c[1] * dim, c[2] * dim, c[3]};
            for (int off = 0x138; off <= 0x168; off += 0x30) {
                void **comp = *(void ***)(row + off);
                if (comp) ((void (*)(void *, float *))(*(void ***)comp)[0x10 / 8])(comp, colour);
            }
            break;
        }
    }
}

static int lua_planet_flash(lua_State *L) {
    const char *name = lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    const char *secs = lua_tostring_fn ? lua_tostring_fn(L, 2) : NULL;
    if (!name || !secs) return 0;
    DWORD until = GetTickCount() + (DWORD)(atof(secs) * 1000);
    int slot = 0;
    for (int f = 0; f < MAX_FLASHES; f++) {
        if (!hp_flashes[f].until || _stricmp(hp_flashes[f].name, name) == 0) { slot = f; break; }
    }
    snprintf(hp_flashes[slot].name, sizeof hp_flashes[slot].name, "%s", name);
    hp_flashes[slot].until = until;
    return 0;
}

// --- The planet info dialog ---------------------------------------------------------------------------------------
// Engine_Planet_Info("PLANET") opens the planet's IDD_PLANET_INFO dialog (0xd3c20), closing any open one first.
#define RVA_PLANET_INFO_OPEN  0xd3c20
#define RVA_PLANET_INFO_CLOSE 0xd3dc0
static int lua_planet_info(lua_State *L) {
    static const unsigned char open_sig[8] = {0x40,0x53,0x48,0x83,0xec,0x60,0x80,0x3d};
    static const unsigned char close_sig[8] = {0x48,0x83,0xec,0x28,0x80,0x3d,0xfe,0xe2};
    const char *name = lua_gettop(L) >= 1 && lua_tostring_fn ? lua_tostring_fn(L, 1) : NULL;
    void **objects = module_base ? *(void ***)(module_base + RVA_GAME_OBJECTS) : NULL;
    if (!name || !objects || !objects_of_type || memcmp(module_base + RVA_PLANET_INFO_OPEN, open_sig, 8) != 0
            || memcmp(module_base + RVA_PLANET_INFO_CLOSE, close_sig, 8) != 0) return 0;
    unsigned char *planet = first_object_of(objects[3], type_by_name(name));
    if (!planet) return 0;
    ((void (*)(void))(module_base + RVA_PLANET_INFO_CLOSE))();
    ((void (*)(void *))(module_base + RVA_PLANET_INFO_OPEN))(planet);
    lua_pushnumber(L, 1);
    return 1;
}

static void install_hardpoints(unsigned char *base) {
    static const unsigned char refresh_sig[7] = {0x48,0x8b,0xc4,0x48,0x89,0x48,0x08};
    if (memcmp(base + RVA_LAYOUT_REFRESH, refresh_sig, 7) != 0) {
        log_line("base layout not found: no hardpoints from the galaxy map");
        return;
    }
    persist_remove = (void *)(base + RVA_PERSIST_REMOVE);
    type_by_id = (void *)(base + RVA_TYPE_BY_ID);
    color_of = (void *)(base + RVA_COLOR_OF);
    bone_show = (void *)(base + RVA_BONE_SHOW);
    bone_matrix = (void *)(base + RVA_BONE_MATRIX);
    hook(base, RVA_PLANET_ROWS, (void *)hooked_planet_rows, (void **)&orig_planet_rows, "planet rows");
    hook(base, RVA_LAYOUT_REFRESH, (void *)hooked_layout_refresh, (void **)&orig_layout_refresh, "base layout");
    hook(base, RVA_PAD_START, (void *)hooked_pad_start, (void **)&orig_pad_start, "pad start");
    hook(base, RVA_PAD_STORE, (void *)hooked_pad_store, (void **)&orig_pad_store, "pad store");
    hook(base, RVA_PERSIST_ADD, (void *)hooked_persist_add, (void **)&orig_persist_add, "persist add");
    hook(base, RVA_PERSIST_FIND, (void *)hooked_persist_find, (void **)&orig_persist_find, "persist find");
    hp_on = 1;
    log_line("hardpoints from the galaxy map installed");
}

static void install(void) {
    unsigned char *base = (unsigned char *)GetModuleHandleA(NULL);
    char exe[MAX_PATH];
    GetModuleFileNameA(NULL, exe, MAX_PATH);
    if (!strstr(exe, "StarWarsG.exe")) return;   // only the game engine itself
    if (profile_on) start_sampler();
    if (profile_on && memcmp(base + RVA_SETHOOK, "\x41\x8b\xc0\x48\x85\xd2", 6) == 0) lua_sethook_fn = (void *)(base + RVA_SETHOOK);
    for (size_t i = 0; i < sizeof(SIGNATURES) / sizeof(SIGNATURES[0]); i++) {
        if (memcmp(base + SIGNATURES[i].rva, SIGNATURES[i].bytes, 8) != 0) {
            log_line("engine build not recognised: nothing patched");
            return;
        }
    }
    lua_pushnumber   = (void *)(base + RVA_PUSHNUMBER);
    luaL_checknumber = (void *)(base + RVA_CHECKNUMBER);
    luaL_openlib     = (void *)(base + RVA_OPENLIB);
    lua_gettop       = (void *)(base + RVA_GETTOP);
    lua_settop       = (void *)(base + RVA_SETTOP);
    lua_pushstring   = (void *)(base + RVA_PUSHSTRING);
    lua_pushcclosure = (void *)(base + RVA_PUSHCCLOSURE);
    lua_settable     = (void *)(base + RVA_SETTABLE);
    if (MH_Initialize() != MH_OK ||
        MH_CreateHook(base + RVA_LUAOPEN_TABLE, (void *)hooked_luaopen_table, (void **)&orig_luaopen_table) != MH_OK ||
        MH_EnableHook(base + RVA_LUAOPEN_TABLE) != MH_OK) {
        log_line("hook install failed");
        return;
    }
    log_line("hook installed (Lua math library)");
    {
        static const unsigned char update_sig[8] = {0x48,0x8b,0xc4,0x56,0x48,0x81,0xec,0xf0};
        static const unsigned char rebuild_sig[8] = {0x48,0x89,0x5c,0x24,0x20,0x57,0x48,0x83};
        if (defer_rebuild_on && memcmp(base + RVA_GALAXY_UPDATE, update_sig, 8) == 0
            && memcmp(base + RVA_REBUILD_PLANNERS, rebuild_sig, 8) == 0) {
            hook(base, RVA_REBUILD_PLANNERS, (void *)hooked_rebuild_planners, (void **)&orig_rebuild_planners,
                 "planner rebuild hook failed");
            hook(base, RVA_GALAXY_UPDATE, (void *)hooked_galaxy_update, (void **)&orig_galaxy_update,
                 "galaxy update hook failed");
        }
    }
    {
        static const unsigned char routes_sig[16] = {0x40,0x53,0x56,0x57,0x41,0x56,0x48,0x83,0xec,0x48,0x48,0x8b,0x51,0x10,
                                                     0x33,0xf6};
        if (fast_routes_on && memcmp(base + RVA_ALL_ROUTES, routes_sig, 16) == 0) {
            hook(base, RVA_ALL_ROUTES, (void *)hooked_all_routes, (void **)&orig_all_routes, "route table hook failed");
        }
        static const unsigned char reach_sig[16] = {0x4c,0x89,0x44,0x24,0x18,0x48,0x89,0x4c,0x24,0x08,0x55,0x41,0x55,0x48,
                                                    0x81,0xec};
        static const unsigned char sqrt_sig[4] = {0x48,0x83,0xec,0x38};
        if (fast_reach_on && memcmp(base + RVA_REACH_LIST, reach_sig, 16) == 0) {
            reach_base = base;
            player_by_id = (void *)(base + RVA_PLAYER_BY_ID);
            knows = (void *)(base + RVA_KNOWS);
            lane_to = (void *)(base + RVA_LANE_TO);
            engine_sqrtf = (void *)(base + RVA_SQRTF);
            push_back = (void *)(base + RVA_PUSH_BACK);
            (void)sqrt_sig;
            hook(base, RVA_REACH_LIST, (void *)hooked_reach_list, (void **)&orig_reach_list, "reach list hook failed");
        }
        static const unsigned char paths_sig[16] = {0x40,0x56,0x57,0x41,0x54,0x41,0x55,0x48,0x83,0xec,0x28,0x44,0x8b,0x29,0x49,0x8b};
        if (fast_paths_on && memcmp(base + RVA_DIST_PATHS, paths_sig, 16) == 0) {
            hook(base, RVA_DIST_PATHS, (void *)hooked_dist_paths, (void **)&orig_dist_paths, "distance paths hook failed");
        }
        static const unsigned char plan_sig[16] = {0x48,0x8b,0xc4,0x53,0x41,0x55,0x48,0x81,0xec,0xb8,0x00,0x00,0x00,0x0f,
                                                   0x29,0x78};
        static const unsigned char score_sig[16] = {0x40,0x53,0x57,0x41,0x57,0x48,0x83,0xec,0x30,0x65,0x48,0x8b,0x04,0x25,
                                                    0x58,0x00};
        if (plan_guard_on && memcmp(base + RVA_PLACE_PLAN, plan_sig, 16) == 0
            && memcmp(base + RVA_SCORE_PLAN, score_sig, 16) == 0) {
            clear_plan = (void *)(base + RVA_CLEAR_PLAN);
            hook(base, RVA_PLACE_PLAN, (void *)hooked_place_plan, (void **)&orig_place_plan, "production plan guard failed");
            hook(base, RVA_SCORE_PLAN, (void *)hooked_score_plan, (void **)&orig_score_plan, "production plan guard failed");
        }
    }
    {
        static const unsigned char setup_sig[16] = {0x40,0x55,0x53,0x56,0x41,0x56,0x48,0x8d,0x6c,0x24,0xf8,0x48,0x81,0xec,0x08,0x01};
        static const unsigned char pass_sig[16] = {0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x6c,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x57};
        if (setup_memo_on && memcmp(base + RVA_PERCEPTION_SETUP, setup_sig, 16) == 0
            && memcmp(base + RVA_PASS_TEST, pass_sig, 16) == 0) {
            hook(base, RVA_PASS_TEST, (void *)hooked_pass_test, (void **)&orig_pass_test, "pass test hook failed");
            hook(base, RVA_PERCEPTION_SETUP, (void *)hooked_perception_setup, (void **)&orig_perception_setup,
                 "planning setup hook failed");
        } else if (profile_on) {
            hook(base, RVA_PERCEPTION_SETUP, (void *)hooked_perception_setup, (void **)&orig_perception_setup,
                 "planning setup timing failed");
        }
    }
    if (profile_on) {
        hook(base, RVA_WORLD_SEARCH, (void *)hooked_world_search, (void **)&orig_world_search, "world search timing failed");
        hook(base, RVA_DISTANCE_TABLE, (void *)hooked_distance_table, (void **)&orig_distance_table, "distance table timing failed");
        hook(base, RVA_MAKE_TEXTURE, (void *)hooked_make_texture, (void **)&orig_make_texture, "texture timing failed");
    }
    InitializeCriticalSection(&index_lock);
    if (MH_CreateHookApi(L"kernel32", "CreateFileA", (void *)hooked_create_file,
                                       (void **)&orig_create_file) == MH_OK)
        MH_EnableHook(MH_ALL_HOOKS);
    module_base = base;
    install_attack_spread(base);
    install_despawn_guard(base);
    install_hardpoints(base);
    crash_base = base;
    static const unsigned char getinfo_next_sig[9] = {0x8b,0x4c,0x24,0x68,0x41,0x0f,0xb6,0x45,0x01};
    getinfo_guard_ok = memcmp(base + RVA_GETINFO_NEXT, getinfo_next_sig, 9) == 0;
    if (!getinfo_guard_ok) log_line("getinfo guard off (unknown game build)");
    AddVectoredExceptionHandler(1, crash_report);
    {   // the player guard: PlayerClass's deleting destructor
        static const unsigned char player_delete_sig[15] = {0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83,0xec,0x20,0x8b,0xda,
                                                            0x48,0x8b,0xf9};
        if (memcmp(base + RVA_PLAYER_DELETE, player_delete_sig, 15) == 0)
            hook(base, RVA_PLAYER_DELETE, (void *)hooked_player_delete, (void **)&orig_player_delete, "player guard hook failed");
        else log_line("player guard: signature differs, off");
    }
    {   // the garbage collector: Lua busy while it runs
        static const unsigned char gc_sig[15] = {0x48,0x89,0x5c,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x57,0x48,0x83,0xec,0x20};
        if (memcmp(base + RVA_LUA_GC, gc_sig, 15) == 0)
            hook(base, RVA_LUA_GC, (void *)hooked_lua_gc, (void **)&orig_lua_gc, "Lua GC hook failed");
        else log_line("Lua GC hook: signature differs, off");
    }
    {   // lua_checkstack: 48 89 5c 24 08 57 48 83 ec 20 4c 8b 41 10
        static const unsigned char checkstack_sig[14] = {0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83,0xec,0x20,0x4c,0x8b,0x41,0x10};
        if (memcmp(base + RVA_CHECKSTACK, checkstack_sig, 14) == 0) lua_checkstack_fn = (void *)(base + RVA_CHECKSTACK);
        else log_line("lua_checkstack not found (unknown game build): stack room only checked");
    }
    static const unsigned char save_sig[8]     = {0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x6c};
    static const unsigned char load_sig[8]     = {0x48,0x8b,0xc4,0x55,0x41,0x54,0x41,0x55};
    static const unsigned char newtable_sig[8] = {0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83};
    static const unsigned char rawget_sig[8]   = {0x40,0x53,0x48,0x83,0xec,0x20,0x48,0x8b};
    static const unsigned char rawgeti_sig[8]  = {0x40,0x53,0x48,0x83,0xec,0x20,0x45,0x8b};
    static const unsigned char link_sig[8]     = {0x48,0x8b,0x41,0x20,0x4c,0x8b,0x48,0x10};
    if (memcmp(base + RVA_SAVE_STATE, save_sig, 8) == 0 && memcmp(base + RVA_LOAD_STATE, load_sig, 8) == 0
        && memcmp(base + RVA_NEWTABLE, newtable_sig, 8) == 0 && memcmp(base + RVA_RAWSET, newtable_sig, 8) == 0
        && memcmp(base + RVA_RAWGET, rawget_sig, 8) == 0 && memcmp(base + RVA_RAWGETI, rawgeti_sig, 8) == 0
        && memcmp(base + RVA_NEXT, rawget_sig, 8) == 0 && memcmp(base + RVA_LINK, link_sig, 8) == 0) {
        lua_newtable_fn  = (void *)(base + RVA_NEWTABLE);
        lua_pushvalue_fn = (void *)(base + RVA_PUSHVALUE);
        lua_rawget_fn    = (void *)(base + RVA_RAWGET);
        lua_rawgeti_fn   = (void *)(base + RVA_RAWGETI);
        lua_rawset_fn    = (void *)(base + RVA_RAWSET);
        lua_next_fn      = (void *)(base + RVA_NEXT);
        lua_realloc_fn   = (void *)(base + RVA_REALLOC);
        lua_link_fn      = (void *)(base + RVA_LINK);
        hook(base, RVA_SAVE_STATE, (void *)hooked_save_state, (void **)&orig_save_state, "save hook failed");
        hook(base, RVA_LOAD_STATE, (void *)hooked_load_state, (void **)&orig_load_state, "load hook failed");
        log_line("saved games keep script upvalues");
        static const unsigned char frame_sig[5] = {0x48,0x89,0x5c,0x24,0x08};
        if (memcmp(base + RVA_GC_TRAVERSE, frame_sig, 5) == 0 && memcmp(base + RVA_REALLOC_CI, frame_sig, 5) == 0
            && memcmp(base + RVA_REALLOC_STACK, frame_sig, 5) == 0) {
            hook(base, RVA_GC_TRAVERSE, (void *)hooked_gc_traverse, (void **)&orig_gc_traverse, "frame guard failed");
            hook(base, RVA_REALLOC_CI, (void *)hooked_realloc_ci, (void **)&orig_realloc_ci, "frame guard failed");
            hook(base, RVA_REALLOC_STACK, (void *)hooked_realloc_stack, (void **)&orig_realloc_stack, "frame guard failed");
            log_line("script frame guard installed");
        }
    } else {
        log_line("save/load functions not found: saved games lose script upvalues");
    }
    static const unsigned char victory_sig[8] = {0x40,0x53,0x56,0x57,0x48,0x83,0xec,0x50};
    static const unsigned char print_sig[8]   = {0x48,0x89,0x54,0x24,0x10,0x4c,0x89,0x44};
    static const unsigned char local_sig[8] = {0x4c,0x8b,0x09,0x48,0x8b,0x51,0x08,0x4c};
    static const unsigned char by_id_sig[8] = {0x85,0xd2,0x78,0x11,0x3b,0x51,0x28,0x7d};
    if (memcmp(base + RVA_LOCAL_PLAYER, local_sig, 8) == 0 && memcmp(base + RVA_PLAYER_BY_ID, by_id_sig, 8) == 0) {
        get_local_player = (void *)(base + RVA_LOCAL_PLAYER);
        get_player_by_id = (void *)(base + RVA_PLAYER_BY_ID);
    }
    if (memcmp(base + RVA_DECLARE_VICTORY, victory_sig, 8) == 0 && memcmp(base + RVA_DEBUG_PRINT, print_sig, 8) == 0) {
        if (thread_watch_on)          // diagnostics only: the engine prints a great deal (retail: an empty function)
            hook(base, RVA_DEBUG_PRINT, (void *)hooked_debug_print, (void **)&orig_debug_print, "debug print hook failed");
        hook(base, RVA_DECLARE_VICTORY, (void *)hooked_declare_victory, (void **)&orig_declare_victory,
             "victory hook failed");
        log_line("diagnostic hooks installed (victory log)");
    }
    static const unsigned char alert_sig[8] = {0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x6c};
    static const unsigned char tostr_sig[8] = {0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83};
    if (memcmp(base + RVA_LUA_ALERT, alert_sig, 8) == 0 && memcmp(base + RVA_TOSTRING, tostr_sig, 8) == 0) {
        lua_tostring_fn = (void *)(base + RVA_TOSTRING);
        hook(base, RVA_LUA_ALERT, (void *)hooked_lua_alert, (void **)&orig_lua_alert, "lua alert hook failed");
        static const unsigned char serr_sig[8] = {0x48,0x85,0xd2,0x0f,0x84,0x75,0x02,0x00};
        if (memcmp(base + RVA_SCRIPT_ERROR, serr_sig, 8) == 0)
            hook(base, RVA_SCRIPT_ERROR, (void *)hooked_script_error, (void **)&orig_script_error,
                 "script error hook failed");
        log_line("lua error log installed");
        static const unsigned char text_sig[8] = {0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x74};
        if (memcmp(base + RVA_TEXT_BY_CRC, text_sig, 8) == 0) {
            hook(base, RVA_TEXT_BY_CRC, (void *)hooked_text_by_crc, (void **)&orig_text_by_crc, "text hook failed");
            static const unsigned char assign_sig[8] = {0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x6c};
            if (memcmp(base + RVA_WSTRING_ASSIGN, assign_sig, 8) == 0) wstring_assign = (void *)(base + RVA_WSTRING_ASSIGN);
            static const unsigned char findtype_sig[8] = {0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x74};
            if (memcmp(base + RVA_FIND_TYPE, findtype_sig, 8) == 0) find_type = (void *)(base + RVA_FIND_TYPE);
            log_line("text overrides installed");
        }
        static const unsigned char resume_sig[8] = {0x48,0x89,0x5c,0x24,0x20,0x89,0x54,0x24};
        static const unsigned char getstack_sig[8] = {0x4c,0x8b,0x49,0x58,0x85,0xd2,0x7e,0x22};
        static const unsigned char getinfo_sig[8] = {0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x6c};
        if (memcmp(base + RVA_GETSTACK, getstack_sig, 8) == 0 && memcmp(base + RVA_GETINFO, getinfo_sig, 8) == 0) {
            lua_getstack_fn = (void *)(base + RVA_GETSTACK);
            lua_getinfo_fn = (void *)(base + RVA_GETINFO);
        }
        if (memcmp(base + RVA_RESUME, resume_sig, 8) == 0) {
            hook(base, RVA_RESUME, (void *)hooked_lua_resume, (void **)&orig_lua_resume, "resume hook failed");
            log_line("script thread failure log installed");
            static const unsigned char sides_sig[8] = {0x48,0x89,0x5c,0x24,0x18,0x56,0x57,0x41};
            static const unsigned char byid_sig[8]  = {0x4c,0x8b,0xd9,0x44,0x8b,0xd2,0x41,0x81};
            static const unsigned char grow_sig[8]  = {0x40,0x57,0x48,0x83,0xec,0x30,0x48,0x89};
            if (get_player_by_id && memcmp(base + RVA_BUILD_SIDES, sides_sig, 8) == 0
                && memcmp(base + RVA_OBJECT_BY_ID, byid_sig, 8) == 0 && memcmp(base + RVA_VECTOR_GROW, grow_sig, 8) == 0) {
                object_by_id = (void *)(base + RVA_OBJECT_BY_ID);
                parent_mode = (void *)(base + RVA_PARENT_MODE);
                mode_data = (void *)(base + RVA_MODE_DATA);
                map_at = (void *)(base + RVA_MAP_AT);
                int_vector_grow = (void *)(base + RVA_INT_VECTOR_GROW);
                pool_changed = (void *)(base + RVA_POOL_CHANGED);
                player_mode = (void *)(base + RVA_PLAYER_MODE);
                fleet_to_orbit = (void *)(base + RVA_FLEET_TO_ORBIT);
                leave_orbit = (void *)(base + RVA_LEAVE_ORBIT);
                fleet_stop_a = (void *)(base + RVA_FLEET_STOP_A);
                fleet_stop_b = (void *)(base + RVA_FLEET_STOP_B);
                orbit_list = (void *)(base + RVA_ORBIT_LIST);
                orbit_add = (void *)(base + RVA_ORBIT_ADD);
                hook(base, RVA_PULL_IN, (void *)hooked_pull_in, (void **)&orig_pull_in, "pull-in hook failed");
                hook(base, RVA_TACTICAL_GUI_EVENT, (void *)hooked_tactical_gui_event, (void **)&orig_tactical_gui_event,
                     "tactical GUI event hook failed");
                hook(base, RVA_TACTICAL_RESOLVE, (void *)hooked_tactical_resolve, (void **)&orig_tactical_resolve,
                     "tactical resolve hook failed");
                hook(base, RVA_RETREAT_DONE, (void *)hooked_retreat_done, (void **)&orig_retreat_done,
                     "retreat hook failed");
                hook(base, RVA_VICTORY_CHECK, (void *)hooked_victory_check, (void **)&orig_victory_check,
                     "victory check hook failed");
                static const unsigned char type_sig[8] = {0x40,0x53,0x48,0x83,0xec,0x20,0x48,0x8b};
                if (memcmp(base + RVA_OBJECT_TYPE, type_sig, 8) == 0) object_type = (void *)(base + RVA_OBJECT_TYPE);
                vector_grow = (void *)(base + RVA_VECTOR_GROW);
                hook(base, RVA_BUILD_SIDES, (void *)hooked_build_sides, (void **)&orig_build_sides, "sides hook failed");
                log_line("allied fleets join space battles");
                static const unsigned char sbtype_sig[8] = {0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x6c};
                if (memcmp(base + RVA_STARBASE_TYPE, sbtype_sig, 8) == 0) {
                    hook(base, RVA_STARBASE_TYPE, (void *)hooked_starbase_type, (void **)&orig_starbase_type,
                         "starbase hook failed");
                }
                static const unsigned char spawn_sig[8] = {0x4c,0x89,0x4c,0x24,0x20,0x48,0x89,0x54};
                if (memcmp(base + RVA_BATTLE_SPAWN, spawn_sig, 8) == 0) {
                    hook(base, RVA_BATTLE_SPAWN, (void *)hooked_battle_spawn, (void **)&orig_battle_spawn,
                         "spawn hook failed");
                }
                static const unsigned char start_sig[8] = {0x48,0x85,0xd2,0x0f,0x84,0x39,0x04,0x00};
                if (memcmp(base + RVA_START_SPACE_BATTLE, start_sig, 8) == 0) {
                    hook(base, RVA_START_SPACE_BATTLE, (void *)hooked_start_space_battle,
                         (void **)&orig_start_space_battle, "battle start hook failed");
                }
            }
            static const unsigned char find_component_sig[8] = {0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x6c};
            static const unsigned char widget_sig[8] = {0x40,0x53,0x48,0x83,0xec,0x20,0x4c,0x8b};
#ifndef NO_GUI_LOOKUP
            if (memcmp(base + RVA_FIND_COMPONENT, find_component_sig, 8) == 0 && memcmp(base + RVA_FIND_WIDGET, widget_sig, 8) == 0) {
                find_widget = (void *)(base + RVA_FIND_WIDGET);
                hook(base, RVA_FIND_COMPONENT, (void *)hooked_find_component, (void **)&orig_find_component,
                     "component lookup hook failed");
                log_line("GUI functions work on custom components");
            }
#endif
            static const unsigned char prompt_sig[8] = {0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x74};
            static const unsigned char click_sig[8]  = {0x48,0x83,0xec,0x28,0x81,0xb9,0xa8,0x00};
            static const unsigned char gettable_sig[8] = {0x40,0x53,0x48,0x83,0xec,0x20,0x48,0x8b};
            static const unsigned char type_sig2[8]    = {0x48,0x83,0xec,0x28,0x85,0xd2,0x7e,0x1a};
            static const unsigned char pcall_sig[8]    = {0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83};
            if (memcmp(base + RVA_GETTABLE, gettable_sig, 8) == 0 && memcmp(base + RVA_TYPE, type_sig2, 8) == 0
                && memcmp(base + RVA_PCALL, pcall_sig, 8) == 0) {
                lua_gettable_fn = (void *)(base + RVA_GETTABLE);
                lua_type_fn = (void *)(base + RVA_TYPE);
                lua_pcall_fn = (void *)(base + RVA_PCALL);
            }
            static const unsigned char clear_sig[8] = {0x48,0x8d,0x41,0x10,0xc6,0x01,0x00,0x33};
            static const unsigned char close_sig[8] = {0x40,0x53,0x48,0x83,0xec,0x20,0x48,0x8b};
            static const unsigned char lift_sig[8]  = {0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83};
            if (memcmp(base + RVA_CLEAR_LINK, clear_sig, 8) == 0 && memcmp(base + RVA_CLOSE_PROMPT, close_sig, 8) == 0
                && memcmp(base + RVA_LIFT_PAUSE, lift_sig, 8) == 0) {
                clear_link = (void *)(base + RVA_CLEAR_LINK);
                close_prompt = (void *)(base + RVA_CLOSE_PROMPT);
                lift_pause = (void *)(base + RVA_LIFT_PAUSE);
            }
            static const unsigned char add_sig[10] = {0x40,0x53,0x48,0x83,0xec,0x20,0x83,0x79,0x2c,0x00};
            if (lift_pause && memcmp(base + RVA_ADD_PAUSE, add_sig, 10) == 0) add_pause = (void *)(base + RVA_ADD_PAUSE);
            static const unsigned char hide_sig[8] = {0x48,0x83,0xec,0x28,0xb9,0x33,0x02,0x00};
            if (memcmp(base + RVA_HIDE_PROMPT, hide_sig, 8) == 0) hide_prompt = (void *)(base + RVA_HIDE_PROMPT);
            else clear_link = NULL;     // all or nothing: the click then works as before
            static const unsigned char clicked_sig[8] = {0x48,0x85,0xd2,0x74,0x5d,0x53,0x48,0x81};
            if (lua_pcall_fn && memcmp(base + RVA_GUI_CLICKED, clicked_sig, 8) == 0) {
                hook(base, RVA_GUI_CLICKED, (void *)hooked_gui_clicked, (void **)&orig_gui_clicked, "gui click hook failed");
                log_line("GUI clicks can go to Lua");
                static const unsigned char close_lua_sig[8] = {0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83};
                if (memcmp(base + RVA_LUA_CLOSE, close_lua_sig, 8) == 0)
                    hook(base, RVA_LUA_CLOSE, (void *)hooked_lua_close, (void **)&orig_lua_close, "lua close hook failed");
                static const unsigned char sound_play_sig[8] = {0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x74};
                if (memcmp(base + RVA_PLAY_SOUND, sound_play_sig, 8) == 0) play_sound_fn = (void *)(base + RVA_PLAY_SOUND);
                static const unsigned char stop2d_sig[8] = {0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x74};
                static const unsigned char play2d_sig[8] = {0x48,0x83,0xec,0x28,0x85,0xd2,0x74,0x24};
                static const unsigned char stops_sig[8] = {0x48,0x89,0x6c,0x24,0x10,0x48,0x89,0x74};
                static const unsigned char plays_sig[8] = {0x48,0x83,0xec,0x28,0x4c,0x8b,0xd9,0x85};
                if (memcmp(base + RVA_2D_STOP, stop2d_sig, 8) == 0 && memcmp(base + RVA_2D_PLAYING, play2d_sig, 8) == 0
                    && memcmp(base + RVA_STREAM_STOP, stops_sig, 8) == 0 && memcmp(base + RVA_STREAM_PLAYING, plays_sig, 8) == 0) {
                    sfx_2d_stop = (void *)(base + RVA_2D_STOP);
                    sfx_2d_playing = (void *)(base + RVA_2D_PLAYING);
                    sfx_stream_stop = (void *)(base + RVA_STREAM_STOP);
                    sfx_stream_playing = (void *)(base + RVA_STREAM_PLAYING);
                } else log_line("sound stop: signatures differ, Engine_Stop_Sound off");
                if (MH_CreateHookApi(L"user32", "PeekMessageA", (void *)hooked_peek_message,
                                     (void **)&orig_peek_message) != MH_OK
                    || MH_EnableHook(MH_ALL_HOOKS) != MH_OK) log_line("frame tick hook failed");
                static const unsigned char sound_sig[8] = {0x40,0x53,0x48,0x83,0xec,0x50,0x48,0x8b};
                static const unsigned char wname_sig[8] = {0x48,0x8b,0x81,0x80,0x00,0x00,0x00,0x48};
                if (memcmp(base + RVA_CLICK_SOUND, sound_sig, 8) == 0 && memcmp(base + RVA_WIDGET_NAME, wname_sig, 8) == 0) {
                    widget_name = (void *)(base + RVA_WIDGET_NAME);
                    hook(base, RVA_CLICK_SOUND, (void *)hooked_click_sound, (void **)&orig_click_sound, "right click hook failed");
                }
            }
            static const unsigned char objects_sig[8] = {0x40,0x55,0x41,0x54,0x41,0x57,0x48,0x83};
            if (memcmp(base + RVA_OBJECTS_OF_TYPE, objects_sig, 8) == 0) objects_of_type = (void *)(base + RVA_OBJECTS_OF_TYPE);
            static const unsigned char select_planet_sig[8] = {0x48,0x89,0x5c,0x24,0x18,0x55,0x56,0x57};
            if (memcmp(base + RVA_SELECT_PLANET, select_planet_sig, 8) == 0)
                hook(base, RVA_SELECT_PLANET, (void *)hooked_select_planet, (void **)&orig_select_planet,
                     "select planet hook failed");
            static const unsigned char spy_sig[8] = {0x48,0x8b,0xc4,0x55,0x41,0x54,0x41,0x55};
            if (memcmp(base + RVA_SYSTEM_SPY, spy_sig, 8) == 0)
                hook(base, RVA_SYSTEM_SPY, (void *)hooked_system_spy, (void **)&orig_system_spy, "spy hook failed");
            else log_line("system spy: signature differs, Engine_Spied off");
            static const unsigned char target_ok_sig[16] = {0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x74,0x24,0x18,0x48,0x89,0x7c,0x24,0x20,0x55};
            if (memcmp(base + RVA_ABILITY_TARGET_OK, target_ok_sig, 16) == 0)
                hook(base, RVA_ABILITY_TARGET_OK, (void *)hooked_ability_target_ok, (void **)&orig_ability_target_ok,
                     "ability target hook failed");
            else log_line("envoy slots: signature differs, envoys only on others' worlds");
            static const unsigned char spy_target_sig[16] = {0x48,0x85,0xd2,0x74,0x35,0x4d,0x85,0xc0,0x74,0x30,0x80,0xba,0x35,0x03,0x00,0x00};
            static const unsigned char slot_kind_sig[16] = {0x48,0x89,0x5c,0x24,0x18,0x55,0x56,0x57,0x41,0x54,0x41,0x55,0x48,0x83,0xec,0x20};
            if (memcmp(base + RVA_SPY_CAN_TARGET, spy_target_sig, 16) == 0 && memcmp(base + RVA_SLOT_KIND, slot_kind_sig, 16) == 0) {
                hook(base, RVA_SPY_CAN_TARGET, (void *)hooked_spy_can_target, (void **)&orig_spy_can_target,
                     "envoy slot target hook failed");
                hook(base, RVA_SLOT_KIND, (void *)hooked_slot_kind, (void **)&orig_slot_kind, "envoy slot label hook failed");
            }
            else log_line("envoy slots: signature differs, the slot shows only on others' worlds");
            static const unsigned char planet_slots_sig[16] = {0x40,0x55,0x53,0x56,0x57,0x41,0x54,0x41,0x55,0x41,0x57,0x48,0x8b,0xec,0x48,0x81};
            static const unsigned char text_wide_sig[8] = {0x40,0x55,0x57,0x41,0x56,0x48,0x83,0xec};
            if (memcmp(base + RVA_PLANET_SLOTS, planet_slots_sig, 16) == 0 && memcmp(base + RVA_TEXT_TO_WIDE, text_wide_sig, 8) == 0) {
                text_to_wide = (void *)(base + RVA_TEXT_TO_WIDE);
                hook(base, RVA_PLANET_SLOTS, (void *)hooked_planet_slots, (void **)&orig_planet_slots,
                     "posted envoy slot hook failed");
            }
            else log_line("envoy slots: signature differs, posted envoys not shown in their slots");
            static const unsigned char lane_state_sig[8] = {0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83};
            static const unsigned char lane_set_sig[8] = {0x48,0x83,0xec,0x58,0x4c,0x8b,0x81,0xb0};
            static const unsigned char lane_apply_sig[8] = {0x4c,0x89,0x4c,0x24,0x20,0x4c,0x89,0x44};
            if (memcmp(base + RVA_LANE_STATE, lane_state_sig, 8) == 0 && memcmp(base + RVA_LANE_SET, lane_set_sig, 8) == 0
                && memcmp(base + RVA_LANE_APPLY, lane_apply_sig, 8) == 0) {
                lanes_refresh = (void *)(base + RVA_LANES_REFRESH);
                string_assign = (void *)(base + RVA_STRING_ASSIGN);
                engine_alloc = (void *)(base + RVA_ENGINE_ALLOC);
                path_line_new = (void *)(base + RVA_PATH_LINE_NEW);
                path_line_draw = (void *)(base + RVA_PATH_LINE_DRAW);
                path_line_free = (void *)(base + RVA_PATH_LINE_FREE);
                static const unsigned char visibility_sig[8] = {0x48,0x89,0x5c,0x24,0x10,0x48,0x89,0x6c};
                if (memcmp(base + RVA_VISIBILITY, visibility_sig, 8) == 0) {
                    show_object = (void *)(base + RVA_SHOW_OBJECT);
                    hook(base, RVA_VISIBILITY, (void *)hooked_visibility, (void **)&orig_visibility,
                         "visibility hook failed");
                } else log_line("visibility: signature differs, hidden route fleets get a line only");
                hook(base, RVA_LANE_STATE, (void *)hooked_lane_state, (void **)&orig_lane_state, "lane state hook failed");
                hook(base, RVA_LANE_SET, (void *)hooked_lane_set, (void **)&orig_lane_set, "lane set hook failed");
                hook(base, RVA_LANE_APPLY, (void *)hooked_lane_apply, (void **)&orig_lane_apply, "lane apply hook failed");
                log_line("hyperlane colours installed");
            } else log_line("hyperlanes: signatures differ, lane colours off");
            static const unsigned char zoom_event_sig[8] = {0x48,0x85,0xd2,0x74,0x59,0x48,0x89,0x5c};
            if (memcmp(base + RVA_ZOOM_IN_EVENT, zoom_event_sig, 8) == 0
                && memcmp(base + RVA_ZOOM_OUT_EVENT, zoom_event_sig, 8) == 0) {
                hook(base, RVA_ZOOM_IN_EVENT, (void *)hooked_zoom_in, (void **)&orig_zoom_in, "zoom in hook failed");
                hook(base, RVA_ZOOM_OUT_EVENT, (void *)hooked_zoom_out, (void **)&orig_zoom_out, "zoom out hook failed");
            } else log_line("planet zoom: signatures differ, Engine_Zoomed_Planet off");
            static const unsigned char tally_sig[8] = {0x48,0x89,0x54,0x24,0x10,0x55,0x41,0x54};
            static const unsigned char unit_force_sig[8] = {0x48,0x89,0x5c,0x24,0x10,0x48,0x89,0x74};
            if (memcmp(base + RVA_FORCE_TALLY, tally_sig, 8) == 0 && memcmp(base + RVA_UNIT_FORCE, unit_force_sig, 8) == 0) {
                unit_force = (void *)(base + RVA_UNIT_FORCE);
                hook(base, RVA_FORCE_TALLY, (void *)hooked_force_tally, (void **)&orig_force_tally, "battle tally hook failed");
            } else log_line("battle tally: signatures differ, guard off");
            static const unsigned char add_row_sig[8] = {0x4c,0x89,0x4c,0x24,0x20,0x48,0x89,0x54};
            static const unsigned char lookup_sig[8] = {0x40,0x56,0x57,0x48,0x83,0xec,0x68,0x65};
            if (memcmp(base + RVA_ADD_ROW, add_row_sig, 8) == 0 && memcmp(base + RVA_TEXT_LOOKUP, lookup_sig, 8) == 0) {
                text_lookup = (void *)(base + RVA_TEXT_LOOKUP);
                hook(base, RVA_ADD_ROW, (void *)hooked_add_row, (void **)&orig_add_row, "income rows hook failed");
            }
            static const unsigned char movie_start_sig[10] = {0x48,0x89,0x5c,0x24,0x10,0x48,0x89,0x6c,0x24,0x18};
            static const unsigned char texture_rect_sig[11] = {0x48,0x8b,0xc4,0x48,0x89,0x58,0x08,0x48,0x89,0x70,0x10};
            if (memcmp(base + RVA_MOVIE_START, movie_start_sig, 10) == 0
                    && memcmp(base + RVA_TEXTURE_RECT, texture_rect_sig, 11) == 0) {
                hook(base, RVA_MOVIE_START, (void *)hooked_movie_start, (void **)&orig_movie_start, "movie start hook failed");
                hook(base, RVA_TEXTURE_RECT, (void *)hooked_texture_rect, (void **)&orig_texture_rect,
                     "movie rectangle hook failed");
            } else log_line("movie rectangle: signatures differ, off");
            static const unsigned char planet_income_sig[12] = {0x40,0x55,0x41,0x54,0x41,0x55,0x41,0x57,0x48,0x83,0xec,0x58};
            static const unsigned char text_crc_sig[7] = {0x41,0xf7,0xd0,0x85,0xd2,0x7e,0x28};
            if (memcmp(base + RVA_PLANET_INCOME, planet_income_sig, 12) == 0) {
                hook(base, RVA_PLANET_INCOME, (void *)hooked_planet_income, (void **)&orig_planet_income,
                     "planet income hook failed");
                if (memcmp(base + RVA_TEXT_CRC, text_crc_sig, 7) == 0) text_crc = (void *)(base + RVA_TEXT_CRC);
                else log_line("text crc: signature differs, charged income off");
            } else log_line("planet income: signature differs, off");
            static const unsigned char player_income_sig[12] = {0x48,0x8b,0xc4,0x44,0x88,0x40,0x18,0x56,0x41,0x54,0x41,0x55};
            if (memcmp(base + RVA_PLAYER_INCOME, player_income_sig, 12) == 0) {
                top_bar_code = base + RVA_TOP_BAR;
                hook(base, RVA_PLAYER_INCOME, (void *)hooked_player_income, (void **)&orig_player_income,
                     "player income hook failed");
            } else log_line("player income: signature differs, top bar shows the gross");
            static const unsigned char text_add_sig[8] = {0x48,0x85,0xd2,0x0f,0x84,0x08,0x02,0x00};
            static const unsigned char text_layout_sig[12] = {0x48,0x8b,0xc4,0x48,0x89,0x58,0x18,0x48,0x89,0x70,0x20,0x55};
            static const unsigned char widget_position_sig[8] = {0x48,0x89,0x5c,0x24,0x18,0x48,0x89,0x74};
            if (memcmp(base + RVA_ADD_SCREEN_TEXT, text_add_sig, 8) == 0) {
                hook(base, RVA_ADD_SCREEN_TEXT, (void *)hooked_add_screen_text, (void **)&orig_add_screen_text,
                     "screen text hook failed");
                if (memcmp(base + RVA_SCREEN_TEXT_LAYOUT, text_layout_sig, 12) == 0
                        && memcmp(base + RVA_WIDGET_POSITION, widget_position_sig, 8) == 0) {
                    set_widget_position = (void *)(base + RVA_WIDGET_POSITION);
                    hook(base, RVA_SCREEN_TEXT_LAYOUT, (void *)hooked_screen_text_layout,
                         (void **)&orig_screen_text_layout, "screen text layout hook failed");
                    glued_text_on = 1;
                } else log_line("screen text layout: signatures differ, glued words off");
            }
            if (memcmp(base + RVA_BATTLE_PROMPT, prompt_sig, 8) == 0 && memcmp(base + RVA_PROMPT_CLICK, click_sig, 8) == 0) {
                hook(base, RVA_BATTLE_PROMPT, (void *)hooked_battle_prompt, (void **)&orig_battle_prompt, "prompt hook failed");
                hook(base, RVA_PROMPT_CLICK, (void *)hooked_prompt_click, (void **)&orig_prompt_click, "click hook failed");
                log_line("rebellion battle prompt installed");
            }
            static const unsigned char call_sig[8] = {0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x6c};
            if (memcmp(base + RVA_CALL_BY_NAME, call_sig, 8) == 0) {
                hook(base, RVA_CALL_BY_NAME, (void *)hooked_call_by_name, (void **)&orig_call_by_name, "call hook failed");
                if (orig_lua_resume) script_depth_tracked = 1;
            }
        }
    }
}

// --- POWRPROF pass-through ---------------------------------------------------------------------
typedef LONG (WINAPI *CallNtPowerInformation_t)(int, PVOID, ULONG, PVOID, ULONG);
__declspec(dllexport) LONG WINAPI CallNtPowerInformation(int level, PVOID in, ULONG in_len, PVOID out, ULONG out_len) {
    static CallNtPowerInformation_t real;
    if (!real) {
        char path[MAX_PATH];
        GetSystemDirectoryA(path, MAX_PATH);
        strcat(path, "\\powrprof.dll");
        real = (CallNtPowerInformation_t)GetProcAddress(LoadLibraryA(path), "CallNtPowerInformation");
    }
    return real ? real(level, in, in_len, out, out_len) : (LONG)0xC0000002;   // STATUS_NOT_IMPLEMENTED
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved) {
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(inst);
        GetModuleFileNameA(inst, log_path, MAX_PATH);
        char *slash = strrchr(log_path, '\\');
        if (slash) strcpy(slash + 1, FILE_LOG);
        strcpy(test_log_path, log_path);
        slash = strrchr(test_log_path, '\\');
        if (slash) strcpy(slash + 1, FILE_SCRIPT_LOG);
#ifndef RELEASE_BUILD                 // test commands: only in the mod's own build
        strcpy(agent_cmd_path, test_log_path);
        strcpy(agent_out_path, test_log_path);
        slash = strrchr(agent_cmd_path, '\\');
        if (slash) strcpy(slash + 1, "AgentCommands.txt");
        slash = strrchr(agent_out_path, '\\');
        if (slash) strcpy(slash + 1, "AgentResults.txt");
        DeleteFileA(agent_cmd_path);  // no leftover commands run at start
        {
            char diag[MAX_PATH];
            strcpy(diag, test_log_path);
            slash = strrchr(diag, '\\');
            if (slash) strcpy(slash + 1, "EngineHook_diag.txt");
            thread_watch_on = GetFileAttributesA(diag) != INVALID_FILE_ATTRIBUTES;
            strcpy(slash ? slash + 1 : diag, "EngineHook_profile.txt");
            profile_on = GetFileAttributesA(diag) != INVALID_FILE_ATTRIBUTES;
            strcpy(slash ? slash + 1 : diag, "EngineHook_routecheck.txt");
            route_check_on = GetFileAttributesA(diag) != INVALID_FILE_ATTRIBUTES;
        }
#endif
        {
            char off[MAX_PATH];
            strcpy(off, log_path);
            char *cut = strrchr(off, '\\');
            strcpy(cut ? cut + 1 : off, FILE_SWITCH("noindex"));
            file_index_on = GetFileAttributesA(off) == INVALID_FILE_ATTRIBUTES;
            strcpy(cut ? cut + 1 : off, FILE_SWITCH("pow2"));
            npot_textures_on = GetFileAttributesA(off) == INVALID_FILE_ATTRIBUTES;
            strcpy(cut ? cut + 1 : off, FILE_SWITCH("nodefer"));
            defer_rebuild_on = GetFileAttributesA(off) == INVALID_FILE_ATTRIBUTES;
            strcpy(cut ? cut + 1 : off, FILE_SWITCH("noroutes"));
            fast_routes_on = GetFileAttributesA(off) == INVALID_FILE_ATTRIBUTES;
            strcpy(cut ? cut + 1 : off, FILE_SWITCH("noreach"));
            fast_reach_on = GetFileAttributesA(off) == INVALID_FILE_ATTRIBUTES;
            strcpy(cut ? cut + 1 : off, FILE_SWITCH("noplanguard"));
            plan_guard_on = GetFileAttributesA(off) == INVALID_FILE_ATTRIBUTES;
            strcpy(cut ? cut + 1 : off, FILE_SWITCH("nopaths"));
            fast_paths_on = GetFileAttributesA(off) == INVALID_FILE_ATTRIBUTES;
            strcpy(cut ? cut + 1 : off, FILE_SWITCH("nosetupmemo"));
            setup_memo_on = GetFileAttributesA(off) == INVALID_FILE_ATTRIBUTES;
        }
#ifdef RELEASE_BUILD
        // The players' copy keeps its logs in the mod's own folder (Logs\), so nothing but this file stays next to
        // the game; without the mod in the launch options it writes nothing. Logs of earlier versions kept here go.
        {
            static const char *const old_files[] = {"TRPlus_Engine.log", "TRPlus_Scripts.log",
                                                    "TRPlus_Crash_Engine.log", "TRPlus_Crash_Scripts.log",
                                                    "TRPlus_Crash.dmp"};
            char old[MAX_PATH];
            for (int i = 0; i < 5; i++) { sibling_path(old, old_files[i]); DeleteFileA(old); }
            log_path[0] = test_log_path[0] = 0;
            if (diplomacy_loaded() && mod_folder[0]) {
                char logs[MAX_PATH];
                snprintf(logs, MAX_PATH, "%s\\Logs", mod_folder);
                CreateDirectoryA(logs, NULL);
                snprintf(log_path, MAX_PATH, "%s\\" FILE_LOG, logs);
                snprintf(test_log_path, MAX_PATH, "%s\\" FILE_SCRIPT_LOG, logs);
                DeleteFileA(log_path);
                DeleteFileA(test_log_path);
                log_line("MOD: loaded (the hook's game changes are on)");
            }
        }
#else
        DeleteFileA(log_path);        // both logs start fresh each game start
        DeleteFileA(test_log_path);
#endif
        rebuild_at_start();           // Workshop copy only: put the mod's merged files together first
        install();
    }
    return TRUE;
}
