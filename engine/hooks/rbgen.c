// --- Data generators for the start-up rebuild --------------------------------------------------
// Some of the mod's data files (planet positions, hyperlanes, ...) are worked out from Thrawn's Revenge's
// own files by small Lua scripts that ship inside Rebuild.rcp. The mod's build runs the same scripts, so
// both must give the same bytes. A script gets the table `gen`:
//   gen.read(root, path)                       file contents or nil (root 0 = Thrawn's Data, 1 = game folder)
//   gen.list(root, folder, pattern, recursive)  file paths below the root ("XML\\Planets.xml"), sorted by
//                                              their lower case bytes; pattern (* and ?) on the file name
//   gen.text(key)                              Thrawn's English text of a key as UTF-8, or nil
//   gen.load(name)                             another script's result (each script runs once)
//   gen.read_range(root, path, offset, size)   part of a file (archives)
//   gen.data(name)                             one of the mod's data blobs carried in Rebuild.rcp, or nil
//   gen.option(name)                           a build option: always nil here (the player's copy is the
//                                              default build)
//   gen.img_*                                  Pillow's image functions (rbimage.c)
// and returns a table {[output path] = file contents}.
// Built on its own (Lua 5.5 with -Dl_strcoll=strcmp, so string order never depends on a locale).
#include <windows.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "rbgen.h"
#include "rbimage.h"

static const rbgen_host *host;
static lua_State *G;

// the path of rel under a root; root 0 is layered: the first Data folder of the stack that has the file
static int root_path(int root, const char *rel, char *path) {
    if (root == 0 && host->layer_count > 0) {
        for (int i = 0; i < host->layer_count; i++) {
            if (snprintf(path, MAX_PATH, "%s\\%s", host->layers[i], rel) >= MAX_PATH) return 0;
            if (GetFileAttributesA(path) != INVALID_FILE_ATTRIBUTES) return 1;
        }
        return snprintf(path, MAX_PATH, "%s\\%s", host->layers[host->layer_count - 1], rel) < MAX_PATH;
    }
    return snprintf(path, MAX_PATH, "%s\\%s", host->roots[root], rel) < MAX_PATH;
}

static int gen_read(lua_State *L) {
    int root = (int)luaL_checkinteger(L, 1);
    const char *rel = luaL_checkstring(L, 2);
    if (root < 0 || root > 1 || !host->roots[root]) return luaL_error(L, "gen.read: bad root %d", root);
    char path[MAX_PATH];
    if (!root_path(root, rel, path)) { lua_pushnil(L); return 1; }
    HANDLE f = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (f == INVALID_HANDLE_VALUE) { lua_pushnil(L); return 1; }
    DWORD n = GetFileSize(f, NULL), got = 0;
    char *data = n != INVALID_FILE_SIZE ? malloc(n ? n : 1) : NULL;
    int ok = data && ReadFile(f, data, n, &got, NULL) && got == n;
    CloseHandle(f);
    if (!ok) { free(data); return luaL_error(L, "gen.read: could not read %s", rel); }
    lua_pushlstring(L, data, n);
    free(data);
    return 1;
}

static int gen_read_range(lua_State *L) {
    int root = (int)luaL_checkinteger(L, 1);
    const char *rel = luaL_checkstring(L, 2);
    lua_Integer offset = luaL_checkinteger(L, 3), size = luaL_checkinteger(L, 4);
    if (root < 0 || root > 1 || !host->roots[root]) return luaL_error(L, "gen.read_range: bad root %d", root);
    if (offset < 0 || size < 0 || size > 0x40000000) return luaL_error(L, "gen.read_range: bad range");
    char path[MAX_PATH];
    if (!root_path(root, rel, path)) { lua_pushnil(L); return 1; }
    HANDLE f = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (f == INVALID_HANDLE_VALUE) { lua_pushnil(L); return 1; }
    char *data = malloc(size ? (size_t)size : 1);
    LARGE_INTEGER at; at.QuadPart = offset;
    DWORD got = 0;
    int ok = data && SetFilePointerEx(f, at, NULL, FILE_BEGIN) && ReadFile(f, data, (DWORD)size, &got, NULL);
    CloseHandle(f);
    if (!ok) { free(data); return luaL_error(L, "gen.read_range: could not read %s", rel); }
    lua_pushlstring(L, data, got);
    free(data);
    return 1;
}

static int gen_data(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    char key[300];
    snprintf(key, sizeof key, "data/%s", name);
    unsigned int size;
    const char *d = host->script(key, &size);
    if (!d) lua_pushnil(L); else lua_pushlstring(L, d, size);
    return 1;
}

// wildcard match of a lower case name against a lower case pattern (* and ?)
static int wild(const char *p, const char *s) {
    for (; *p; p++, s++) {
        if (*p == '*') {
            for (const char *t = s; ; t++) { if (wild(p + 1, t)) return 1; if (!*t) return 0; }
        }
        if (!*s || (*p != '?' && *p != *s)) return 0;
    }
    return !*s;
}

typedef struct { char **item; int n, cap; } name_list;

static void walk(const char *base, const char *rel, const char *pattern, int recursive, name_list *out) {
    char spec[MAX_PATH];
    if (rel[0]) snprintf(spec, MAX_PATH, "%s\\%s\\*", base, rel);
    else snprintf(spec, MAX_PATH, "%s\\*", base);
    WIN32_FIND_DATAA fd;
    HANDLE h = FindFirstFileA(spec, &fd);
    if (h == INVALID_HANDLE_VALUE) return;
    do {
        if (!strcmp(fd.cFileName, ".") || !strcmp(fd.cFileName, "..")) continue;
        char sub[MAX_PATH];
        snprintf(sub, MAX_PATH, rel[0] ? "%s\\%s" : "%s%s", rel, fd.cFileName);
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
            if (recursive) walk(base, sub, pattern, recursive, out);
            continue;
        }
        char low[MAX_PATH];
        size_t i = 0;
        for (; fd.cFileName[i] && i < MAX_PATH - 1; i++) low[i] = (char)tolower((unsigned char)fd.cFileName[i]);
        low[i] = 0;
        if (!wild(pattern, low)) continue;
        if (out->n == out->cap) { out->cap = out->cap ? out->cap * 2 : 64; out->item = realloc(out->item, out->cap * sizeof *out->item); }
        out->item[out->n++] = _strdup(sub);
    } while (FindNextFileA(h, &fd));
    FindClose(h);
}

static int lower_cmp(const void *a, const void *b) {
    const unsigned char *x = *(const unsigned char **)a, *y = *(const unsigned char **)b;
    for (;; x++, y++) {
        int cx = tolower(*x), cy = tolower(*y);
        if (cx != cy || !cx) return cx - cy;
    }
}

static int upper_cmp(const void *a, const void *b) {
    const unsigned char *x = *(const unsigned char **)a, *y = *(const unsigned char **)b;
    for (;; x++, y++) {
        int cx = toupper(*x), cy = toupper(*y);
        if (cx != cy || !cx) return cx - cy;
    }
}

static void add_name(name_list *l, const char *s) {
    if (l->n == l->cap) { l->cap = l->cap ? l->cap * 2 : 64; l->item = realloc(l->item, l->cap * sizeof *l->item); }
    l->item[l->n++] = _strdup(s);
}

static void add_owned(name_list *l, char *s) {
    if (l->n == l->cap) { l->cap = l->cap ? l->cap * 2 : 64; l->item = realloc(l->item, l->cap * sizeof *l->item); }
    l->item[l->n++] = s;
}

static void free_names(name_list *l) {
    for (int i = 0; i < l->n; i++) free(l->item[i]);
    free(l->item);
    memset(l, 0, sizeof *l);
}

// a folder's files and subfolders (names), each in upper case order
static void entries(const char *base, const char *rel, name_list *files, name_list *dirs) {
    char spec[MAX_PATH];
    if (rel[0]) snprintf(spec, MAX_PATH, "%s\\%s\\*", base, rel);
    else snprintf(spec, MAX_PATH, "%s\\*", base);
    WIN32_FIND_DATAA fd;
    HANDLE h = FindFirstFileA(spec, &fd);
    if (h == INVALID_HANDLE_VALUE) return;
    do {
        if (!strcmp(fd.cFileName, ".") || !strcmp(fd.cFileName, "..")) continue;
        add_name(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY ? dirs : files, fd.cFileName);
    } while (FindNextFileA(h, &fd));
    FindClose(h);
    qsort(files->item, files->n, sizeof *files->item, upper_cmp);
    qsort(dirs->item, dirs->n, sizeof *dirs->item, upper_cmp);
}

static void files_of(const char *base, const char *rel, const char *pattern, name_list *out) {
    name_list files = {0}, dirs = {0};
    entries(base, rel, &files, &dirs);
    for (int i = 0; i < files.n; i++) {
        char low[MAX_PATH], sub[MAX_PATH];
        size_t k = 0;
        for (; files.item[i][k] && k < MAX_PATH - 1; k++) low[k] = (char)tolower((unsigned char)files.item[i][k]);
        low[k] = 0;
        if (!wild(pattern, low)) continue;
        snprintf(sub, MAX_PATH, rel[0] ? "%s\\%s" : "%s%s", rel, files.item[i]);
        add_name(out, sub);
    }
    free_names(&files);
    free_names(&dirs);
}

// Python's Path.rglob order: a folder's files, then each subfolder's files, then on into the last subfolder
static void walk_rglob(const char *base, const char *folder, const char *pattern, name_list *out) {
    files_of(base, folder, pattern, out);
    name_list stack = {0};
    add_name(&stack, folder);
    while (stack.n) {
        char *path = stack.item[--stack.n];
        name_list files = {0}, dirs = {0};
        entries(base, path, &files, &dirs);
        for (int i = 0; i < dirs.n; i++) {
            char sub[MAX_PATH];
            snprintf(sub, MAX_PATH, path[0] ? "%s\\%s" : "%s%s", path, dirs.item[i]);
            files_of(base, sub, pattern, out);
            add_name(&stack, sub);
        }
        free_names(&files);
        free_names(&dirs);
        free(path);
    }
    free(stack.item);
}

static int gen_list(lua_State *L) {
    int root = (int)luaL_checkinteger(L, 1);
    const char *folder = luaL_checkstring(L, 2);
    const char *pattern = luaL_checkstring(L, 3);
    int rglob = lua_type(L, 4) == LUA_TSTRING && !strcmp(lua_tostring(L, 4), "walk");
    int recursive = lua_toboolean(L, 4);
    if (root < 0 || root > 1 || !host->roots[root]) return luaL_error(L, "gen.list: bad root %d", root);
    char low[MAX_PATH];
    size_t i = 0;
    for (; pattern[i] && i < MAX_PATH - 1; i++) low[i] = (char)tolower((unsigned char)pattern[i]);
    low[i] = 0;
    name_list out = {0};
    if (root == 0 && host->layer_count > 1) {
        // every layer's files once: Thrawn's in its order, then what the layers above add
        for (int l = host->layer_count - 1; l >= 0; l--) {
            name_list one = {0};
            if (rglob) walk_rglob(host->layers[l], folder, low, &one);
            else walk(host->layers[l], folder, low, recursive, &one);
            for (int k = 0; k < one.n; k++) {
                int seen = 0;
                for (int m = 0; m < out.n && !seen; m++) seen = !_stricmp(out.item[m], one.item[k]);
                if (seen) free(one.item[k]);
                else add_owned(&out, one.item[k]);
            }
            free(one.item);
        }
        if (!rglob) qsort(out.item, out.n, sizeof *out.item, lower_cmp);
    } else {
        const char *base = root == 0 && host->layer_count == 1 ? host->layers[0] : host->roots[root];
        if (rglob) walk_rglob(base, folder, low, &out);
        else {
            walk(base, folder, low, recursive, &out);
            qsort(out.item, out.n, sizeof *out.item, lower_cmp);
        }
    }
    lua_createtable(L, out.n, 0);
    for (int k = 0; k < out.n; k++) {
        lua_pushstring(L, out.item[k]);
        lua_rawseti(L, -2, k + 1);
        free(out.item[k]);
    }
    free(out.item);
    return 1;
}

// UTF-16 to UTF-8; surrogate pairs joined, lone surrogates kept (as Python's "surrogatepass")
static int gen_text(lua_State *L) {
    size_t len;
    const char *key = luaL_checklstring(L, 1, &len);
    const unsigned short *v;
    unsigned int n;
    if (!host->text(key, (unsigned int)len, &v, &n)) { lua_pushnil(L); return 1; }
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    for (unsigned int i = 0; i < n; i++) {
        unsigned int c = v[i];
        if (c >= 0xd800 && c <= 0xdbff && i + 1 < n && v[i + 1] >= 0xdc00 && v[i + 1] <= 0xdfff)
            c = 0x10000 + ((c - 0xd800) << 10) + (v[++i] - 0xdc00);
        char u[4];
        int k;
        if (c < 0x80) { u[0] = (char)c; k = 1; }
        else if (c < 0x800) { u[0] = (char)(0xc0 | c >> 6); u[1] = (char)(0x80 | (c & 63)); k = 2; }
        else if (c < 0x10000) { u[0] = (char)(0xe0 | c >> 12); u[1] = (char)(0x80 | ((c >> 6) & 63)); u[2] = (char)(0x80 | (c & 63)); k = 3; }
        else { u[0] = (char)(0xf0 | c >> 18); u[1] = (char)(0x80 | ((c >> 12) & 63)); u[2] = (char)(0x80 | ((c >> 6) & 63)); u[3] = (char)(0x80 | (c & 63)); k = 4; }
        luaL_addlstring(&b, u, k);
    }
    luaL_pushresult(&b);
    return 1;
}

int rbaudio_mp3(const unsigned char *data, size_t n, short **pcm, size_t *samples, int *channels, int *rate);
void rbaudio_free(short *pcm);

// gen.mp3_decode(data) -> 16-bit little endian samples (channels interleaved), channels, sample rate
static int gen_mp3_decode(lua_State *L) {
    size_t n;
    const char *data = luaL_checklstring(L, 1, &n);
    short *pcm;
    size_t samples;
    int channels, rate;
    if (!rbaudio_mp3((const unsigned char *)data, n, &pcm, &samples, &channels, &rate))
        return luaL_error(L, "gen.mp3_decode: not an MP3");
    lua_pushlstring(L, (const char *)pcm, samples * sizeof *pcm);
    rbaudio_free(pcm);
    lua_pushinteger(L, channels);
    lua_pushinteger(L, rate);
    return 3;
}

static int gen_text_keys(lua_State *L) {
    lua_newtable(L);
    const char *key;
    unsigned int len;
    for (unsigned int i = 0; host->text_key && host->text_key(i, &key, &len); i++) {
        lua_pushlstring(L, key, len);
        lua_rawseti(L, -2, (lua_Integer)i + 1);
    }
    return 1;
}

static int gen_load(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    lua_getfield(L, LUA_REGISTRYINDEX, "rbgen_results");
    if (lua_getfield(L, -1, name) != LUA_TNIL) return 1;
    lua_pop(L, 1);
    unsigned int size;
    const char *src = host->script(name, &size);
    if (!src) return luaL_error(L, "no generator %s", name);
    char chunk[128];
    snprintf(chunk, sizeof chunk, "@%s", name);
    if (luaL_loadbufferx(L, src, size, chunk, "t") != LUA_OK) return lua_error(L);
    lua_call(L, 0, 1);
    lua_pushvalue(L, -1);
    lua_setfield(L, -3, name);
    return 1;
}

// build options exist only in the mod's own build: the player's copy is always the default build
static int gen_option(lua_State *L) {
    luaL_checkstring(L, 1);
    lua_pushnil(L);
    return 1;
}

int rbgen_open(const rbgen_host *h) {
    host = h;
    G = luaL_newstate();
    if (!G) return 0;
    luaL_openselectedlibs(G, LUA_GLIBK | LUA_MATHLIBK | LUA_STRLIBK | LUA_TABLIBK | LUA_UTF8LIBK, 0);
    lua_newtable(G);
    lua_setfield(G, LUA_REGISTRYINDEX, "rbgen_results");
    static const luaL_Reg fns[] = {{"read", gen_read}, {"list", gen_list}, {"text", gen_text},
                                   {"load", gen_load}, {"option", gen_option},
                                   {"read_range", gen_read_range}, {"data", gen_data}, {"text_keys", gen_text_keys},
                                   {"mp3_decode", gen_mp3_decode},
                                   {NULL, NULL}};
    luaL_newlib(G, fns);
    rbimage_register(G);
    lua_setglobal(G, "gen");
    return 1;
}

static int output_of(lua_State *L) {
    lua_pushcfunction(L, gen_load);
    lua_pushvalue(L, 1);
    lua_call(L, 1, 1);
    if (!lua_istable(L, -1)) return luaL_error(L, "generator %s returned no table", lua_tostring(L, 1));
    lua_getfield(L, -1, lua_tostring(L, 2));
    if (lua_type(L, -1) != LUA_TSTRING) return luaL_error(L, "generator %s made no %s", lua_tostring(L, 1), lua_tostring(L, 2));
    return 1;
}

int rbgen_output(const char *script, const char *output, unsigned char **data, size_t *len, char *err, size_t err_len) {
    *data = NULL; *len = 0;
    if (!G) { snprintf(err, err_len, "generators not started"); return 0; }
    lua_settop(G, 0);
    lua_pushcfunction(G, output_of);
    lua_pushstring(G, script);
    lua_pushstring(G, output);
    if (lua_pcall(G, 2, 1, 0) != LUA_OK) {
        snprintf(err, err_len, "%s", lua_tostring(G, -1) ? lua_tostring(G, -1) : "generator error");
        lua_settop(G, 0);
        return 0;
    }
    size_t n;
    const char *s = lua_tolstring(G, -1, &n);
    *data = malloc(n ? n : 1);
    if (*data) { memcpy(*data, s, n); *len = n; }
    lua_settop(G, 0);
    return *data != NULL;
}

// paints the image a generator made (its result's icons[icon]) into a 32-bit BMP held in buf, at (x, y)
int rbgen_paint(const char *script, const char *icon, unsigned char *buf, size_t n, int x, int y, char *err, size_t err_len) {
    if (!G) { snprintf(err, err_len, "generators not started"); return 0; }
    lua_settop(G, 0);
    lua_pushcfunction(G, gen_load);
    lua_pushstring(G, script);
    if (lua_pcall(G, 1, 1, 0) != LUA_OK) {
        snprintf(err, err_len, "%s", lua_tostring(G, -1) ? lua_tostring(G, -1) : "generator error");
        lua_settop(G, 0);
        return 0;
    }
    void *image = NULL;
    if (lua_istable(G, -1) && lua_getfield(G, -1, "icons") == LUA_TTABLE) {
        lua_getfield(G, -1, icon);
        image = rbimage_check(G, -1);
    }
    if (!image) {
        snprintf(err, err_len, "generator %s made no icon %s", script, icon);
        lua_settop(G, 0);
        return 0;
    }
    rbimage_paint_bmp(buf, n, image, x, y);
    lua_settop(G, 0);
    return 1;
}

// every output and icon a script made, for tests: fn(name, data, n, NULL) for files, fn(name, NULL, 0, image)
int rbgen_each(const char *script, void (*fn)(const char *, const char *, size_t, void *, void *), void *ctx) {
    if (!G) return 0;
    lua_settop(G, 0);
    lua_pushcfunction(G, gen_load);
    lua_pushstring(G, script);
    if (lua_pcall(G, 1, 1, 0) != LUA_OK) { fn(lua_tostring(G, -1), NULL, 0, NULL, ctx); lua_settop(G, 0); return 0; }
    if (!lua_istable(G, 1)) { lua_settop(G, 0); return 0; }
    lua_pushnil(G);
    while (lua_next(G, 1)) {
        if (lua_type(G, -2) == LUA_TSTRING && lua_type(G, -1) == LUA_TSTRING) {
            size_t n;
            const char *d = lua_tolstring(G, -1, &n);
            fn(lua_tostring(G, -2), d, n, NULL, ctx);
        }
        lua_pop(G, 1);
    }
    if (lua_getfield(G, 1, "icons") == LUA_TTABLE) {
        lua_pushnil(G);
        while (lua_next(G, 2)) {
            void *image = rbimage_check(G, -1);
            if (image && lua_type(G, -2) == LUA_TSTRING) fn(lua_tostring(G, -2), NULL, 0, image, ctx);
            lua_pop(G, 1);
        }
    }
    lua_settop(G, 0);
    return 1;
}

void rbgen_close(void) {
    if (G) lua_close(G);
    G = NULL;
    host = NULL;
}
