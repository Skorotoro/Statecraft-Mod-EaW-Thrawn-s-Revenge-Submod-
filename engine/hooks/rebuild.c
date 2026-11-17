// --- Rebuild at start ---------------------------------------------------------------------------
// A Workshop copy of the mod carries only its own files plus Data\Rebuild.rcp: recipes that put the
// remaining files back together from the player's own Thrawn's Revenge and game files (COPY a range of
// one of those files, or ADD bytes of the mod's own). This runs once from DllMain, before the game reads any
// data, and only when something changed since the last run (Data\Rebuild.stamp). The working copy of
// the mod (MODPATH, no Rebuild.rcp) is left alone.
//
// Rebuild.rcp (little endian): "RCP1"; uint32 sources, each: uint8 root, uint16 length, path, uint32 size;
// uint32 outputs, each: uint16 length, path (relative to Data), uint32 size, uint32 crc32, uint32 steps,
// each step: uint8 0 (ADD) uint32 length + bytes, or uint8 1 (COPY) uint16 source, uint32 offset, uint32 length.
// Roots: 0 = Thrawn's Revenge Data, 1 = the game folder, 2 = this mod's Data folder, 3 = the Workshop content
// folder (<item id>\Data\...). Other submods: after the outputs, "SETS" uint32 version, then the sources, scripts
// and outputs the plain part lacks (numbered after it), and uint32 sets, each: uint8 ids (uint8 length + Workshop
// id, highest first), uint32 n + n source numbers to check, uint32 n + n output numbers to make. Readers that
// stop after the plain outputs see Thrawn's Revenge alone. The set whose submods are all in the launch options
// and that names the most of them is used; root 0 then reads each file from the first of them that has it.
// Further steps: uint8 2 (TEXT) strings from Thrawn's text file by key (see rb_text_step); uint8 3 (GEN)
// uint16 script: the output as made by one of the data generators (rbgen.c); uint8 4 (PAINT) uint16 script,
// uint32 count, each uint8 length + icon name, uint32 x, uint32 y: the script's icons painted into the 32-bit
// BMP built by the steps before (the command bar atlas). "RCP2" files carry those
// scripts after the sources: uint32 count, each uint16 length + name, uint32 length + source.

#define REBUILD_TR_ID "1125571106"

#include <locale.h>
#include "rbgen.h"

static char rebuild_status[256];          // "" = nothing to do / done; otherwise why the mod is off
static char rebuild_warning[300];         // another submod in the launch options replaces files of this mod
static int rebuild_ran;

static unsigned int crc_table[256];
static unsigned int crc32_update(unsigned int crc, const unsigned char *p, size_t n) {
    if (!crc_table[1])
        for (unsigned int i = 0; i < 256; i++) {
            unsigned int c = i;
            for (int k = 0; k < 8; k++) c = (c & 1) ? 0xedb88320u ^ (c >> 1) : c >> 1;
            crc_table[i] = c;
        }
    crc = ~crc;
    while (n--) crc = crc_table[(crc ^ *p++) & 0xff] ^ (crc >> 8);
    return ~crc;
}

static unsigned char *read_whole(const char *path, DWORD *size) {
    HANDLE f = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (f == INVALID_HANDLE_VALUE) return NULL;
    DWORD n = GetFileSize(f, NULL), got = 0;
    unsigned char *data = (n != INVALID_FILE_SIZE) ? malloc(n ? n : 1) : NULL;
    if (data && !ReadFile(f, data, n, &got, NULL)) got = (DWORD)-1;
    CloseHandle(f);
    if (!data || got != n) { free(data); return NULL; }
    *size = n;
    return data;
}

// The folders the recipes refer to, found from the game's own path and the STEAMMOD= arguments.
static char rb_game[MAX_PATH], rb_tr[MAX_PATH], rb_mod[MAX_PATH];
static char rb_workshop[MAX_PATH];                 // ...\workshop\content\32470
static char rb_ids[16][32];                        // the STEAMMOD items of the launch options, in order
static int rb_id_count;
static char rb_own_id[32];                         // this mod's (none for a copy installed with MODPATH)
static char rb_layer[8][MAX_PATH];                 // root 0: the chosen submods' Data folders, then Thrawn's
static int rb_layer_count;
static char rb_set[8][32];                         // the chosen recipe file's submods
static int rb_set_count;
static char rb_recipe[MAX_PATH];

static int find_rebuild_folders(void) {
    char exe[MAX_PATH], steamapps[MAX_PATH];
    GetModuleFileNameA(NULL, exe, MAX_PATH);                       // ...\Star Wars Empire at War\corruption\StarWarsG.exe
    char *s = strrchr(exe, '\\'); if (!s) return 0; *s = 0;      // ...\corruption
    s = strrchr(exe, '\\'); if (!s) return 0; *s = 0;            // ...\Star Wars Empire at War
    strcpy(rb_game, exe);
    strcpy(steamapps, exe);
    s = strrchr(steamapps, '\\'); if (!s) return 0; *s = 0;      // ...\common
    s = strrchr(steamapps, '\\'); if (!s) return 0; *s = 0;      // ...\steamapps
    snprintf(rb_tr, MAX_PATH, "%s\\workshop\\content\\32470\\" REBUILD_TR_ID "\\Data", steamapps);
    snprintf(rb_workshop, MAX_PATH, "%s\\workshop\\content\\32470", steamapps);
    // every STEAMMOD item but Thrawn's Revenge; the mod's is the one that holds a Rebuild.rcp
    const char *cmd = GetCommandLineA();
    rb_id_count = 0;
    for (const char *p = cmd; (p = strstr(p, "STEAMMOD=")) != NULL; ) {
        p += 9;
        char id[32]; int n = 0;
        while (n < 31 && p[n] >= '0' && p[n] <= '9') { id[n] = p[n]; n++; }
        id[n] = 0;
        if (!n || strcmp(id, REBUILD_TR_ID) == 0 || rb_id_count == 16) continue;
        strcpy(rb_ids[rb_id_count++], id);
    }
    for (int i = 0; i < rb_id_count; i++) {
        char probe[MAX_PATH];
        snprintf(rb_mod, MAX_PATH, "%s\\%s\\Data", rb_workshop, rb_ids[i]);
        snprintf(probe, MAX_PATH, "%s\\Rebuild.rcp", rb_mod);
        if (GetFileAttributesA(probe) != INVALID_FILE_ATTRIBUTES) { strcpy(rb_own_id, rb_ids[i]); return 1; }
    }
    // or a copy installed by hand: MODPATH=<folder> (relative to the corruption folder, or a full path)
    const char *p = strstr(cmd, "MODPATH=");
    if (p) {
        p += 8;
        char path[MAX_PATH];
        int n = 0, quoted = *p == '"';
        if (quoted) p++;
        while (n < MAX_PATH - 1 && p[n] && (quoted ? p[n] != '"' : p[n] != ' ')) { path[n] = p[n]; n++; }
        path[n] = 0;
        char probe[MAX_PATH];
        if (n && (path[1] == ':' || path[0] == '\\')) snprintf(rb_mod, MAX_PATH, "%s\\Data", path);
        else if (n) snprintf(rb_mod, MAX_PATH, "%s\\corruption\\%s\\Data", rb_game, path);
        snprintf(probe, MAX_PATH, "%s\\Rebuild.rcp", rb_mod);
        if (n && GetFileAttributesA(probe) != INVALID_FILE_ATTRIBUTES) return 1;
    }
    rb_mod[0] = 0;
    return 0;
}

// A MasterTextFile .dat read for TEXT steps: uint32 count; count x (crc32, value length, key length);
// the values (UTF-16), then the keys (ASCII). Looked up by upper-case key; the first entry of a key wins.
typedef struct {
    unsigned char *data;
    unsigned int count, mask;
    unsigned int *slot;                    // hash table of entry index + 1 (0 = empty)
    const wchar_t **value; unsigned int *value_len;
    const char **key; unsigned int *key_len;
} rb_texts;

typedef struct { unsigned char root; char path[MAX_PATH]; DWORD size; HANDLE handle; rb_texts *texts; } rb_source;

static unsigned int rb_key_hash(const char *key, unsigned int len) {
    unsigned int h = 2166136261u;
    for (unsigned int i = 0; i < len; i++) h = (h ^ (unsigned char)toupper((unsigned char)key[i])) * 16777619u;
    return h;
}

static rb_texts *rb_load_texts(rb_source *s) {
    if (s->texts) return s->texts;
    DWORD n = 0;
    unsigned char *d = read_whole(s->path, &n);
    if (!d || n < 4) { free(d); return NULL; }
    rb_texts *t = calloc(1, sizeof *t);
    t->data = d;
    t->count = *(unsigned int *)d;
    if (4 + 12ull * t->count > n) { free(d); free(t); return NULL; }
    t->value = calloc(t->count + 1, sizeof *t->value); t->value_len = calloc(t->count + 1, sizeof(unsigned int));
    t->key = calloc(t->count + 1, sizeof *t->key); t->key_len = calloc(t->count + 1, sizeof(unsigned int));
    unsigned long long pos = 4 + 12ull * t->count;
    for (unsigned int i = 0; i < t->count; i++) {
        unsigned int vl = *(unsigned int *)(d + 4 + 12 * i + 4);
        if (pos + 2ull * vl > n) goto broken;
        t->value[i] = (const wchar_t *)(d + pos); t->value_len[i] = vl; pos += 2ull * vl;
    }
    for (unsigned int i = 0; i < t->count; i++) {
        unsigned int kl = *(unsigned int *)(d + 4 + 12 * i + 8);
        if (pos + kl > n) goto broken;
        t->key[i] = (const char *)(d + pos); t->key_len[i] = kl; pos += kl;
    }
    unsigned int size = 1;
    while (size < t->count * 2 + 2) size <<= 1;
    t->mask = size - 1;
    t->slot = calloc(size, sizeof *t->slot);
    for (unsigned int i = 0; i < t->count; i++) {
        unsigned int h = rb_key_hash(t->key[i], t->key_len[i]) & t->mask;
        for (;;) {
            unsigned int e = t->slot[h];
            if (!e) { t->slot[h] = i + 1; break; }
            if (t->key_len[e - 1] == t->key_len[i] && _strnicmp(t->key[e - 1], t->key[i], t->key_len[i]) == 0) break;
            h = (h + 1) & t->mask;
        }
    }
    s->texts = t;
    return t;
broken:
    free(t->value); free(t->value_len); free(t->key); free(t->key_len); free(d); free(t);
    return NULL;
}

static int rb_find_text(rb_texts *t, const char *key, unsigned int len, const wchar_t **value, unsigned int *value_len) {
    unsigned int h = rb_key_hash(key, len) & t->mask;
    for (unsigned int e; (e = t->slot[h]) != 0; h = (h + 1) & t->mask)
        if (t->key_len[e - 1] == len && _strnicmp(t->key[e - 1], key, len) == 0) {
            *value = t->value[e - 1]; *value_len = t->value_len[e - 1];
            return 1;
        }
    *value = L""; *value_len = 0;
    return 0;
}

// Python's whitespace (str.isspace / re's \s), which the build used to tidy the text
static int rb_space(wchar_t c) {
    return (c >= 0x09 && c <= 0x0d) || (c >= 0x1c && c <= 0x20) || c == 0x85 || c == 0xa0 || c == 0x1680
        || (c >= 0x2000 && c <= 0x200a) || c == 0x2028 || c == 0x2029 || c == 0x202f || c == 0x205f || c == 0x3000;
}

enum { RB_FIRST_LINE = 1, RB_COLLAPSE = 2, RB_STRIP = 4, RB_RSTRIP_DOT = 8, RB_SKIP_EMPTY = 16,
       RB_SKIP_RAW_EMPTY = 32, RB_NO_BACKSLASH = 64, RB_QUOTE = 128, RB_ESC_NL = 256 };

typedef struct { wchar_t *p; size_t n, cap; } rb_wbuf;
static void rb_wput(rb_wbuf *b, wchar_t c) {
    if (b->n == b->cap) { b->cap = b->cap ? b->cap * 2 : 256; b->p = realloc(b->p, b->cap * sizeof *b->p); }
    b->p[b->n++] = c;
}

// One TEXT step: the keys' texts tidied by flags, joined, ended, then written as Latin-1 ('?' for the rest).
// Returns the number of bytes written to out (at most room), or -1.
static long rb_text_step(rb_texts *t, unsigned int flags, const unsigned char *join, unsigned int join_len,
                         const unsigned char *end, unsigned int end_len, const unsigned char *keys,
                         unsigned int key_count, unsigned char *out, DWORD room) {
    rb_wbuf all = {0}, part = {0};
    int parts = 0;
    for (unsigned int k = 0; k < key_count; k++) {
        unsigned int len = keys[0];
        const wchar_t *v; unsigned int vn;
        rb_find_text(t, (const char *)keys + 1, len, &v, &vn);
        keys += 1 + len;
        if ((flags & RB_SKIP_RAW_EMPTY) && vn == 0) continue;
        if (flags & RB_FIRST_LINE)
            for (unsigned int i = 0; i < vn; i++) if (v[i] == L'\n') { vn = i; break; }
        part.n = 0;
        for (unsigned int i = 0; i < vn; i++) {
            if ((flags & RB_COLLAPSE) && rb_space(v[i])) {
                while (i + 1 < vn && rb_space(v[i + 1])) i++;
                rb_wput(&part, L' ');
            } else rb_wput(&part, v[i]);
        }
        size_t a = 0, b = part.n;
        if (flags & RB_STRIP) {
            while (a < b && rb_space(part.p[a])) a++;
            while (b > a && rb_space(part.p[b - 1])) b--;
        }
        if ((flags & RB_SKIP_EMPTY) && a == b) continue;
        if (flags & RB_RSTRIP_DOT) while (b > a && part.p[b - 1] == L'.') b--;
        if (parts++) for (unsigned int i = 0; i < join_len; i++) rb_wput(&all, join[i]);
        for (size_t i = a; i < b; i++) rb_wput(&all, part.p[i]);
    }
    for (unsigned int i = 0; i < end_len; i++) rb_wput(&all, end[i]);
    DWORD at = 0;
    long result = 0;
    for (size_t i = 0; i < all.n; i++) {
        wchar_t c = all.p[i];
        if ((flags & RB_NO_BACKSLASH) && c == L'\\') continue;
        if ((flags & RB_QUOTE) && c == L'"') c = L'\'';
        if ((flags & RB_ESC_NL) && c == L'\n') {
            if (at + 2 > room) { result = -1; break; }
            out[at++] = '\\'; out[at++] = 'n';
            continue;
        }
        if (c >= 0xd800 && c <= 0xdbff && i + 1 < all.n && all.p[i + 1] >= 0xdc00 && all.p[i + 1] <= 0xdfff) i++;
        if (at + 1 > room) { result = -1; break; }
        out[at++] = c < 256 ? (unsigned char)c : '?';
    }
    free(all.p); free(part.p);
    return result < 0 ? -1 : (long)at;
}

static int rb_launched(const char *id) {
    for (int i = 0; i < rb_id_count; i++) if (!strcmp(rb_ids[i], id)) return 1;
    return 0;
}

// Root 0's layers for a set of submods (none: Thrawn's Revenge alone).
static void rb_use_set(const unsigned char *ids) {
    rb_set_count = rb_layer_count = 0;
    for (unsigned int i = 0, at = 1; ids && i < ids[0] && rb_set_count < 7; i++, at += 1 + ids[at]) {
        unsigned int k = ids[at] < 31 ? ids[at] : 31;
        memcpy(rb_set[rb_set_count], ids + at + 1, k);
        rb_set[rb_set_count][k] = 0;
        snprintf(rb_layer[rb_layer_count++], MAX_PATH, "%s\\%s\\Data", rb_workshop, rb_set[rb_set_count++]);
    }
    strcpy(rb_layer[rb_layer_count++], rb_tr);
}

// Whether every submod of a set's id list is in the launch options; its count in *n.
static int rb_set_launched(const unsigned char *ids, int *n) {
    *n = ids[0];
    for (unsigned int i = 0, at = 1; i < ids[0]; i++, at += 1 + ids[at]) {
        char id[32];
        unsigned int k = ids[at] < 31 ? ids[at] : 31;
        memcpy(id, ids + at + 1, k);
        id[k] = 0;
        if (!rb_launched(id)) return 0;
    }
    return 1;
}

static int rb_root_path(char *out, unsigned char root, const char *rel) {
    if (root == 0) {                                   // the first layer that has the file
        for (int i = 0; i < rb_layer_count; i++) {
            snprintf(out, MAX_PATH, "%s\\%s", rb_layer[i], rel);
            if (GetFileAttributesA(out) != INVALID_FILE_ATTRIBUTES) return 1;
        }
        snprintf(out, MAX_PATH, "%s\\%s", rb_tr, rel);
        return 1;
    }
    const char *base = root == 1 ? rb_game : root == 2 ? rb_mod : root == 3 ? rb_workshop : NULL;
    if (!base) return 0;
    snprintf(out, MAX_PATH, "%s\\%s", base, rel);
    return 1;
}

// A submod in the launch options that no recipe file was made for, holding a file this mod rebuilds: one of the
// two copies hides the other, so the pair may not work together.
static void rb_check_overlap(const char *rel) {
    if (rebuild_warning[0]) return;
    for (int i = 0; i < rb_id_count; i++) {
        int known = !strcmp(rb_ids[i], rb_own_id);
        for (int k = 0; k < rb_set_count && !known; k++) known = !strcmp(rb_ids[i], rb_set[k]);
        if (known) continue;
        char probe[MAX_PATH];
        snprintf(probe, MAX_PATH, "%s\\%s\\Data\\%s", rb_workshop, rb_ids[i], rel);
        if (GetFileAttributesA(probe) != INVALID_FILE_ATTRIBUTES) {
            snprintf(rebuild_warning, sizeof rebuild_warning,
                     "The submod %s replaces files this mod also changes (%s). Loaded together they may not work: "
                     "remove it from the launch options, or wait for a compatible update.", rb_ids[i], rel);
            log_line(rebuild_warning);
            return;
        }
    }
}

// A quick fingerprint of everything a rebuild depends on: the recipe file and each source's size and time.
static unsigned int rb_fingerprint(const unsigned char *rcp, DWORD rcp_size, rb_source *src, const unsigned int *check,
                                   unsigned int count, int set) {
    unsigned int crc = crc32_update(0, rcp, rcp_size);
    crc = crc32_update(crc, (unsigned char *)&set, 4);
    for (unsigned int c = 0; c < count; c++) {
        unsigned int i = check ? check[c] : c;
        if (src[i].root == 2) continue;
        WIN32_FILE_ATTRIBUTE_DATA a;
        if (!GetFileAttributesExA(src[i].path, GetFileExInfoStandard, &a)) memset(&a, 0, sizeof a);
        crc = crc32_update(crc, (unsigned char *)&a.nFileSizeLow, 4);
        crc = crc32_update(crc, (unsigned char *)&a.ftLastWriteTime, 8);
    }
    return crc;
}

static int rb_copy(rb_source *s, DWORD offset, DWORD length, unsigned char *out) {
    if (!s->handle) {
        s->handle = CreateFileA(s->path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
        if (s->handle == INVALID_HANDLE_VALUE) { s->handle = NULL; return 0; }
    }
    LARGE_INTEGER at; at.QuadPart = offset;
    DWORD got = 0;
    return SetFilePointerEx(s->handle, at, NULL, FILE_BEGIN) && ReadFile(s->handle, out, length, &got, NULL)
           && got == length;
}

static int rb_write(const char *path, const unsigned char *data, DWORD size) {
    char dir[MAX_PATH];
    strcpy(dir, path);
    for (char *p = dir + strlen(rb_mod) + 1; *p; p++)               // make the folders below Data
        if (*p == '\\') { *p = 0; CreateDirectoryA(dir, NULL); *p = '\\'; }
    char tmp[MAX_PATH];
    snprintf(tmp, MAX_PATH, "%s.part", path);
    HANDLE f = CreateFileA(tmp, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, 0, NULL);
    if (f == INVALID_HANDLE_VALUE) return 0;
    DWORD put = 0;
    int ok = WriteFile(f, data, size, &put, NULL) && put == size;
    CloseHandle(f);
    if (ok) ok = MoveFileExA(tmp, path, MOVEFILE_REPLACE_EXISTING);
    if (!ok) DeleteFileA(tmp);
    return ok;
}

// The generators' view of the rebuild: Thrawn's text and the scripts carried in Rebuild.rcp
static rb_source rb_gen_texts;
static unsigned int rb_script_count;
static const char **rb_script_name;
static unsigned int *rb_script_name_len, *rb_script_size;
static const char **rb_script_src;
static int rb_gen_started;

static int rb_gen_text(const char *key, unsigned int len, const unsigned short **value, unsigned int *n) {
    rb_texts *t = rb_load_texts(&rb_gen_texts);
    const wchar_t *v;
    if (!t || !rb_find_text(t, key, len, &v, n)) return 0;
    *value = (const unsigned short *)v;
    return 1;
}

static int rb_gen_text_key(unsigned int i, const char **key, unsigned int *len) {
    rb_texts *t = rb_load_texts(&rb_gen_texts);
    if (!t || i >= t->count) return 0;
    *key = t->key[i];
    *len = t->key_len[i];
    return 1;
}

static int rb_chosen_set = -1;             // the submod set in use (its own copies of scripts: "@<set>/<name>")

static const char *rb_find_script(const char *name, unsigned int *size) {
    for (unsigned int i = 0; i < rb_script_count; i++)
        if (strlen(name) == rb_script_name_len[i] && !memcmp(name, rb_script_name[i], rb_script_name_len[i])) {
            *size = rb_script_size[i];
            return rb_script_src[i];
        }
    return NULL;
}

static const char *rb_gen_script(const char *name, unsigned int *size) {
    if (rb_chosen_set >= 0) {
        char own[300];
        snprintf(own, sizeof own, "@%d/%s", rb_chosen_set, name);
        const char *found = rb_find_script(own, size);
        if (found) return found;
    }
    return rb_find_script(name, size);
}

static rbgen_host rb_gen_host;

static void rb_gen_start(void) {
    if (rb_gen_started) return;
    rb_gen_started = 1;
    rb_gen_host.roots[0] = rb_tr;
    rb_gen_host.roots[1] = rb_game;
    for (int i = 0; i < rb_layer_count; i++) rb_gen_host.layers[i] = rb_layer[i];
    rb_gen_host.layer_count = rb_layer_count;
    rb_gen_host.text = rb_gen_text;
    rb_gen_host.text_key = rb_gen_text_key;
    rb_gen_host.script = rb_gen_script;
    rb_root_path(rb_gen_texts.path, 0, "Text\\MasterTextFile_ENGLISH.dat");
    rbgen_open(&rb_gen_host);
}

// Data\Rebuild.files: the files the last rebuild made. Any of them the current recipes no longer make (another
// submod set chosen, or an update) are deleted, so no file of another set is left behind.
static void rb_manifest(char **rel, unsigned int n) {
    char path[MAX_PATH];
    snprintf(path, MAX_PATH, "%s\\Rebuild.files", rb_mod);
    DWORD size = 0;
    unsigned char *old = read_whole(path, &size);
    if (old) {
        char *text = realloc(old, size + 1);
        if (text) {
            text[size] = 0;
            for (char *line = strtok(text, "\r\n"); line; line = strtok(NULL, "\r\n")) {
                int kept = 0;
                for (unsigned int i = 0; i < n && !kept; i++) kept = !_stricmp(rel[i], line);
                if (kept || strstr(line, "..") || line[0] == '\\' || strchr(line, ':')) continue;
                char out[MAX_PATH];
                snprintf(out, MAX_PATH, "%s\\%s", rb_mod, line);
                DeleteFileA(out);
            }
            free(text);
        } else free(old);
    }
    HANDLE f = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, 0, NULL);
    if (f == INVALID_HANDLE_VALUE) return;
    for (unsigned int i = 0; i < n; i++) {
        DWORD put;
        WriteFile(f, rel[i], (DWORD)strlen(rel[i]), &put, NULL);
        WriteFile(f, "\r\n", 2, &put, NULL);
    }
    CloseHandle(f);
}

#define RB_NEED(n) do { if (pos + (n) > rcp_size) goto bad_file; } while (0)

// Steps past one output; 0 if the file ends inside it.
static int rb_skip_output(const unsigned char *rcp, DWORD rcp_size, DWORD *at) {
    DWORD pos = *at;
    RB_NEED(2);
    pos += 2 + *(unsigned short *)(rcp + pos);
    RB_NEED(12);
    DWORD steps = *(DWORD *)(rcp + pos + 8);
    pos += 12;
    for (DWORD k = 0; k < steps; k++) {
        RB_NEED(1);
        unsigned char kind = rcp[pos++];
        if (kind == 0) { RB_NEED(4); pos += 4 + *(DWORD *)(rcp + pos); }
        else if (kind == 1) pos += 10;
        else if (kind == 2) {
            RB_NEED(6); pos += 6 + *(unsigned short *)(rcp + pos + 4);
            RB_NEED(2); pos += 2 + *(unsigned short *)(rcp + pos);
            RB_NEED(2);
            unsigned short keys = *(unsigned short *)(rcp + pos); pos += 2;
            for (unsigned int i = 0; i < keys; i++) { RB_NEED(1); pos += 1 + rcp[pos]; }
        }
        else if (kind == 3) pos += 2;
        else if (kind == 4) {
            RB_NEED(6);
            unsigned int icons = *(unsigned int *)(rcp + pos + 2); pos += 6;
            for (unsigned int i = 0; i < icons; i++) { RB_NEED(1); RB_NEED(9u + rcp[pos]); pos += 9 + rcp[pos]; }
        }
        else return 0;
    }
    RB_NEED(0);
    *at = pos;
    return 1;
bad_file:
    return 0;
}

// A script name + source (RCP2 layout) into slot i of the script tables.
static int rb_read_script(const unsigned char *rcp, DWORD rcp_size, DWORD *at, unsigned int i) {
    DWORD pos = *at;
    RB_NEED(2);
    unsigned short n = *(unsigned short *)(rcp + pos); pos += 2;
    RB_NEED(n + 4u);
    rb_script_name[i] = (const char *)rcp + pos; rb_script_name_len[i] = n; pos += n;
    DWORD len = *(DWORD *)(rcp + pos); pos += 4;
    RB_NEED(len);
    rb_script_src[i] = (const char *)rcp + pos; rb_script_size[i] = len; pos += len;
    *at = pos;
    return 1;
bad_file:
    return 0;
}

// A source entry (root, path relative to it, size); the path is placed under its root once the set is chosen.
static int rb_read_source(const unsigned char *rcp, DWORD rcp_size, DWORD *at, rb_source *s) {
    DWORD pos = *at;
    RB_NEED(3);
    s->root = rcp[pos];
    unsigned short n = *(unsigned short *)(rcp + pos + 1); pos += 3;
    RB_NEED(n + 4u);
    if (n >= MAX_PATH || s->root > 3) return 0;
    memcpy(s->path, rcp + pos, n); s->path[n] = 0; pos += n;
    s->size = *(DWORD *)(rcp + pos); pos += 4;
    *at = pos;
    return 1;
bad_file:
    return 0;
}

// A made file that doesn't match the recipe is kept next to the log (Statecraft_Mismatch_<name>), with its size and
// crc, so a player's report shows how their copy differs.
static void rb_save_mismatch(const char *rel, const unsigned char *data, size_t size, DWORD want_size,
                             unsigned int want_crc) {
    char line[MAX_PATH + 120];
    snprintf(line, sizeof line, "rebuild: %s made %lu bytes, crc %08x; the recipe wants %lu bytes, crc %08x", rel,
             (unsigned long)size, crc32_update(0, data, size), (unsigned long)want_size, want_crc);
    log_line(line);
#ifndef REBUILD_TEST
    if (!log_path[0]) return;
    const char *base = strrchr(rel, '\\');
    char path[MAX_PATH];
    strcpy(path, log_path);
    char *slash = strrchr(path, '\\');
    if (!slash) return;
    snprintf(slash + 1, MAX_PATH - (slash + 1 - path), "Statecraft_Mismatch_%s", base ? base + 1 : rel);
    HANDLE f = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, 0, NULL);
    if (f == INVALID_HANDLE_VALUE) return;
    DWORD put;
    WriteFile(f, data, (DWORD)size, &put, NULL);
    CloseHandle(f);
#endif
}

// Thrawn's text file (MasterTextFile_ENGLISH.dat) may differ from the one the recipes were made with: tools such
// as map editors rewrite it. The files made from it then follow the player's copy instead of stopping the mod.
static int rb_is_text(const char *path) {
    const char *base = strrchr(path, '\\');
    return !_stricmp(base ? base + 1 : path, "MasterTextFile_ENGLISH.dat");
}

static int rb_grow(unsigned char **buf, DWORD *cap, unsigned long long need) {
    if (need <= *cap) return 1;
    if (need > 0x10000000) return 0;
    DWORD n = *cap ? *cap : 4096;
    while (n < need) n *= 2;
    unsigned char *p = realloc(*buf, n);
    if (!p) return 0;
    *buf = p; *cap = n;
    return 1;
}

static void run_rebuild(void) {
    rebuild_ran = 1;
#ifndef REBUILD_TEST
    if (!find_rebuild_folders()) return;                          // not a Workshop copy: nothing to do
#endif
    char path[MAX_PATH], line[512];
    snprintf(rb_recipe, MAX_PATH, "%s\\Rebuild.rcp", rb_mod);
    DWORD rcp_size = 0;
    unsigned char *rcp = read_whole(rb_recipe, &rcp_size);
    if (!rcp || rcp_size < 8 || (memcmp(rcp, "RCP1", 4) != 0 && memcmp(rcp, "RCP2", 4) != 0)) {
        snprintf(rebuild_status, sizeof rebuild_status, "the mod's Rebuild.rcp is missing or damaged");
        free(rcp);
        return;
    }
    DWORD pos = 4;
    unsigned int count = *(unsigned int *)(rcp + pos); pos += 4;
    if (count > 65536) { free(rcp); snprintf(rebuild_status, sizeof rebuild_status, "the mod's Rebuild.rcp is damaged; please re-subscribe"); return; }
    rb_source *src = calloc(count ? count : 1, sizeof *src);
    unsigned int outputs = 0, done = 0, all_n = 0, plain_count = count, plain_outputs = 0;
    unsigned char *buf = NULL;
    char **written = NULL, **all_out = NULL;
    DWORD *out_pos = NULL;
    const unsigned int *check = NULL, *make = NULL;
    unsigned int check_n = 0, make_n = 0;
    int chosen = -1;
    rb_chosen_set = -1;
    for (unsigned int i = 0; i < count; i++)
        if (!rb_read_source(rcp, rcp_size, &pos, &src[i])) goto bad_file;
    if (rcp[3] == '2') {                                          // the generator scripts
        RB_NEED(4);
        rb_script_count = *(unsigned int *)(rcp + pos); pos += 4;
        if (rb_script_count > 4096) goto bad_file;
        rb_script_name = calloc(rb_script_count + 1, sizeof *rb_script_name);
        rb_script_src = calloc(rb_script_count + 1, sizeof *rb_script_src);
        rb_script_name_len = calloc(rb_script_count + 1, sizeof *rb_script_name_len);
        rb_script_size = calloc(rb_script_count + 1, sizeof *rb_script_size);
        for (unsigned int i = 0; i < rb_script_count; i++)
            if (!rb_read_script(rcp, rcp_size, &pos, i)) goto bad_file;
    }

    // where each output starts: the plain ones, then those of the SETS section
    RB_NEED(4);
    outputs = plain_outputs = *(unsigned int *)(rcp + pos); pos += 4;
    if (outputs > 100000) goto bad_file;
    out_pos = malloc((outputs ? outputs : 1) * sizeof *out_pos);
    for (unsigned int o = 0; o < outputs; o++) {
        out_pos[o] = pos;
        if (!rb_skip_output(rcp, rcp_size, &pos)) goto bad_file;
    }
    if (pos + 8 <= rcp_size && !memcmp(rcp + pos, "SETS", 4) && *(unsigned int *)(rcp + pos + 4) == 1) {
        pos += 8;
        RB_NEED(4);
        unsigned int more = *(unsigned int *)(rcp + pos); pos += 4;
        if (count + more > 65536) goto bad_file;
        rb_source *grown = realloc(src, (count + more) * sizeof *src);
        if (!grown) goto bad_file;
        src = grown;
        memset(src + count, 0, more * sizeof *src);
        for (unsigned int i = 0; i < more; i++)
            if (!rb_read_source(rcp, rcp_size, &pos, &src[count + i])) goto bad_file;
        count += more;
        RB_NEED(4);
        more = *(unsigned int *)(rcp + pos); pos += 4;
        if (more > 4096) goto bad_file;
        if (more) {
            unsigned int total = rb_script_count + more;
            rb_script_name = realloc(rb_script_name, (total + 1) * sizeof *rb_script_name);
            rb_script_src = realloc(rb_script_src, (total + 1) * sizeof *rb_script_src);
            rb_script_name_len = realloc(rb_script_name_len, (total + 1) * sizeof *rb_script_name_len);
            rb_script_size = realloc(rb_script_size, (total + 1) * sizeof *rb_script_size);
            if (!rb_script_name || !rb_script_src || !rb_script_name_len || !rb_script_size) goto bad_file;
            for (unsigned int i = 0; i < more; i++)
                if (!rb_read_script(rcp, rcp_size, &pos, rb_script_count + i)) goto bad_file;
            rb_script_count = total;
        }
        RB_NEED(4);
        more = *(unsigned int *)(rcp + pos); pos += 4;
        if (outputs + more > 100000) goto bad_file;
        DWORD *grown_pos = realloc(out_pos, (outputs + more ? outputs + more : 1) * sizeof *out_pos);
        if (!grown_pos) goto bad_file;
        out_pos = grown_pos;
        for (unsigned int o = 0; o < more; o++) {
            out_pos[outputs + o] = pos;
            if (!rb_skip_output(rcp, rcp_size, &pos)) goto bad_file;
        }
        outputs += more;
        RB_NEED(4);
        unsigned int sets = *(unsigned int *)(rcp + pos); pos += 4;
        int best_n = 0;
        for (unsigned int k = 0; k < sets; k++) {
            RB_NEED(1);
            const unsigned char *ids = rcp + pos;
            pos += 1;
            for (unsigned int i = 0; i < ids[0]; i++) { RB_NEED(1); RB_NEED(1u + rcp[pos]); pos += 1 + rcp[pos]; }
            RB_NEED(4);
            unsigned int cn = *(unsigned int *)(rcp + pos); pos += 4;
            RB_NEED(4ull * cn);
            const unsigned int *c = (const unsigned int *)(rcp + pos); pos += 4 * cn;
            RB_NEED(4);
            unsigned int mn = *(unsigned int *)(rcp + pos); pos += 4;
            RB_NEED(4ull * mn);
            const unsigned int *m = (const unsigned int *)(rcp + pos); pos += 4 * mn;
            for (unsigned int i = 0; i < cn; i++) if (c[i] >= count) goto bad_file;
            for (unsigned int i = 0; i < mn; i++) if (m[i] >= outputs) goto bad_file;
            int n;
            if (rb_set_launched(ids, &n) && n > best_n && n <= 7) {
                best_n = n; chosen = rb_chosen_set = (int)k; check = c; check_n = cn; make = m; make_n = mn;
                rb_use_set(ids);
            }
        }
    }
    if (chosen < 0) {                                             // Thrawn's Revenge alone: the plain part
        rb_use_set(NULL);
        log_line("rebuild: recipes for Thrawn's Revenge alone");
        check = NULL; check_n = plain_count;
        make = NULL; make_n = plain_outputs;
    } else {
        snprintf(line, sizeof line, "rebuild: recipes for the submods in the launch options (%s%s%s)", rb_set[0],
                 rb_set_count > 1 ? " + " : "", rb_set_count > 1 ? rb_set[1] : "");
        log_line(line);
    }
    for (unsigned int i = 0; i < count; i++) {                    // the sources under their roots
        char rel[MAX_PATH];
        strcpy(rel, src[i].path);
        if (!rb_root_path(src[i].path, src[i].root, rel)) goto bad_file;
    }

    // Up to date? (the stamp holds the fingerprint; every output must still be there)
    unsigned int print = rb_fingerprint(rcp, rcp_size, src, check, check_n, chosen);
    snprintf(path, MAX_PATH, "%s\\Rebuild.stamp", rb_mod);
    DWORD stamp_size = 0;
    unsigned char *stamp = read_whole(path, &stamp_size);
    int fresh = stamp && stamp_size == 4 && *(unsigned int *)stamp == print;
    free(stamp);

    // the sources must be the files the recipes were made from; if not, the old rebuilt files go too
    int remove_only = 0, text_changed = 0;
    for (unsigned int c = 0; c < check_n; c++) {
        unsigned int i = check ? check[c] : c;
        if (src[i].root == 2) continue;
        WIN32_FILE_ATTRIBUTE_DATA a;
        int found = GetFileAttributesExA(src[i].path, GetFileExInfoStandard, &a);
        if (found && !a.nFileSizeHigh && a.nFileSizeLow != src[i].size && rb_is_text(src[i].path)) {
            if (!text_changed) {
                snprintf(line, sizeof line, "rebuild: %s is %lu bytes, not %lu (changed by another tool); "
                         "the mod's texts follow it", src[i].path, (unsigned long)a.nFileSizeLow,
                         (unsigned long)src[i].size);
                log_line(line);
            }
            text_changed = 1;
            continue;
        }
        if (!found || a.nFileSizeLow != src[i].size || a.nFileSizeHigh) {
            snprintf(rebuild_status, sizeof rebuild_status,
                     "this Thrawn's Revenge version does not match the mod (%s); the mod is off until it is updated",
                     strrchr(src[i].path, '\\') + 1);
            log_line(rebuild_status);
            char line[MAX_PATH + 120];
            if (GetFileAttributesExA(src[i].path, GetFileExInfoStandard, &a))
                snprintf(line, sizeof line, "rebuild: %s is %lu bytes; the recipes want %lu", src[i].path,
                         (unsigned long)a.nFileSizeLow, (unsigned long)src[i].size);
            else
                snprintf(line, sizeof line, "rebuild: %s is missing; the recipes want %lu bytes", src[i].path,
                         (unsigned long)src[i].size);
            log_line(line);
            remove_only = 1;
            fresh = 0;
            break;
        }
    }

    written = calloc(make_n ? make_n : 1, sizeof *written);
    all_out = calloc(make_n ? make_n : 1, sizeof *all_out);
    DWORD started = GetTickCount();
    DWORD cap = 0;
    for (unsigned int o = 0; o < make_n; o++) {
        pos = out_pos[make ? make[o] : o];
        RB_NEED(2);
        unsigned short n = *(unsigned short *)(rcp + pos); pos += 2;
        RB_NEED(n + 12u);
        char rel[MAX_PATH], out_path[MAX_PATH];
        if (n >= MAX_PATH) goto bad_file;
        memcpy(rel, rcp + pos, n); rel[n] = 0; pos += n;
        DWORD size = *(DWORD *)(rcp + pos), crc = *(DWORD *)(rcp + pos + 4), steps = *(DWORD *)(rcp + pos + 8);
        pos += 12;
        snprintf(out_path, MAX_PATH, "%s\\%s", rb_mod, rel);
        all_out[all_n++] = _strdup(rel);
        if (!remove_only) rb_check_overlap(rel);
        if (remove_only) {
            DeleteFileA(out_path);
            continue;
        }
        if (fresh) {                                                // skip the steps; only check the file is there
            WIN32_FILE_ATTRIBUTE_DATA a;
            if (!GetFileAttributesExA(out_path, GetFileExInfoStandard, &a) || (a.nFileSizeLow != size && !text_changed))
                fresh = 0;
        }
        if (!rb_grow(&buf, &cap, size ? size : 1)) goto bad_file;
        DWORD at = 0;
        int from_text = 0;                                          // made by a TEXT or GEN step
        for (DWORD k = 0; k < steps; k++) {
            RB_NEED(1);
            unsigned char kind = rcp[pos++];
            if (kind == 0) {
                RB_NEED(4);
                DWORD len = *(DWORD *)(rcp + pos); pos += 4;
                RB_NEED(len);
                if (at + len > size && !(text_changed && rb_grow(&buf, &cap, (unsigned long long)at + len))) goto bad_file;
                if (!fresh) memcpy(buf + at, rcp + pos, len);
                pos += len; at += len;
            } else if (kind == 1) {
                RB_NEED(10);
                unsigned short s = *(unsigned short *)(rcp + pos);
                DWORD off = *(DWORD *)(rcp + pos + 2), len = *(DWORD *)(rcp + pos + 6);
                pos += 10;
                if (s >= count) goto bad_file;
                if (at + len > size && !(text_changed && rb_grow(&buf, &cap, (unsigned long long)at + len))) goto bad_file;
                if (!fresh && !rb_copy(&src[s], off, len, buf + at)) {
                    snprintf(rebuild_status, sizeof rebuild_status, "could not read %s", src[s].path);
                    goto failed;
                }
                at += len;
            } else if (kind == 2) {
                RB_NEED(6);
                unsigned short s = *(unsigned short *)(rcp + pos), flags = *(unsigned short *)(rcp + pos + 2);
                unsigned short join_len = *(unsigned short *)(rcp + pos + 4);
                pos += 6;
                RB_NEED(join_len + 2u);
                const unsigned char *join = rcp + pos; pos += join_len;
                unsigned short end_len = *(unsigned short *)(rcp + pos); pos += 2;
                RB_NEED(end_len + 2u);
                const unsigned char *end = rcp + pos; pos += end_len;
                unsigned short key_count = *(unsigned short *)(rcp + pos); pos += 2;
                const unsigned char *keys = rcp + pos;
                for (unsigned int i = 0; i < key_count; i++) { RB_NEED(1); RB_NEED(1u + rcp[pos]); pos += 1 + rcp[pos]; }
                if (s >= count) goto bad_file;
                if (fresh) continue;                                // its length is unknown: checked by size only
                from_text = 1;
                rb_texts *t = rb_load_texts(&src[s]);
                long put = t ? rb_text_step(t, flags, join, join_len, end, end_len, keys, key_count,
                                            buf + at, (text_changed ? cap : size) - at) : -1;
                while (put < 0 && t && text_changed && rb_grow(&buf, &cap, cap * 2ull))
                    put = rb_text_step(t, flags, join, join_len, end, end_len, keys, key_count, buf + at, cap - at);
                if (put < 0) {
                    snprintf(rebuild_status, sizeof rebuild_status,
                             "this Thrawn's Revenge version does not match the mod (%s); the mod is off until it is updated",
                             rel);
                    goto failed;
                }
                at += (DWORD)put;
            } else if (kind == 3) {
                RB_NEED(2);
                unsigned short sc = *(unsigned short *)(rcp + pos); pos += 2;
                if (sc >= rb_script_count) goto bad_file;
                if (fresh) continue;
                from_text = 1;
                rb_gen_start();
                char name[256], err[200];
                if (rb_script_name_len[sc] >= sizeof name) goto bad_file;
                memcpy(name, rb_script_name[sc], rb_script_name_len[sc]); name[rb_script_name_len[sc]] = 0;
                unsigned char *made; size_t made_len;
                int ok = rbgen_output(name, rel, &made, &made_len, err, sizeof err);
                if (ok && at + made_len > size && text_changed) ok = rb_grow(&buf, &cap, (unsigned long long)at + made_len);
                else if (ok && at + made_len > size) ok = 0;
                if (!ok) {
                    if (made) { rb_save_mismatch(rel, made, made_len, size, crc); free(made); } else log_line(err);
                    snprintf(rebuild_status, sizeof rebuild_status,
                             "this Thrawn's Revenge version does not match the mod (%s); the mod is off until it is updated",
                             rel);
                    goto failed;
                }
                memcpy(buf + at, made, made_len);
                at += (DWORD)made_len;
                free(made);
            } else if (kind == 4) {
                RB_NEED(6);
                unsigned short sc = *(unsigned short *)(rcp + pos);
                unsigned int icons = *(unsigned int *)(rcp + pos + 2);
                pos += 6;
                if (sc >= rb_script_count) goto bad_file;
                char script[256], icon[256], err[200];
                if (rb_script_name_len[sc] >= sizeof script) goto bad_file;
                memcpy(script, rb_script_name[sc], rb_script_name_len[sc]); script[rb_script_name_len[sc]] = 0;
                for (unsigned int i = 0; i < icons; i++) {
                    RB_NEED(1);
                    unsigned int len = rcp[pos];
                    RB_NEED(9u + len);
                    memcpy(icon, rcp + pos + 1, len); icon[len] = 0;
                    int x = *(int *)(rcp + pos + 1 + len), y = *(int *)(rcp + pos + 5 + len);
                    pos += 9 + len;
                    if (fresh) continue;
                    rb_gen_start();
                    if (at != size || !rbgen_paint(script, icon, buf, size, x, y, err, sizeof err)) {
                        if (at == size) log_line(err);
                        snprintf(rebuild_status, sizeof rebuild_status,
                                 "this Thrawn's Revenge version does not match the mod (%s); the mod is off until it is updated",
                                 rel);
                        goto failed;
                    }
                }
            } else goto bad_file;
        }
        if (fresh) continue;
        if (text_changed && from_text) size = at;                  // follows the player's text: no stored crc
        else if (at != size || crc32_update(0, buf, size) != crc) {
            rb_save_mismatch(rel, buf, at, size, crc);
            snprintf(rebuild_status, sizeof rebuild_status,
                     "this Thrawn's Revenge version does not match the mod (%s); the mod is off until it is updated",
                     rel);
            goto failed;
        }
        if (!rb_write(out_path, buf, size)) {
            snprintf(rebuild_status, sizeof rebuild_status,
                     "could not write into the mod's folder (%s); the mod is off", rel);
            goto failed;
        }
        written[done++] = _strdup(out_path);
    }
    rb_manifest(all_out, remove_only ? 0 : all_n);
    if (remove_only) {
        DeleteFileA(path);
        goto finish;
    }
    if (done) {
        HANDLE f = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, 0, NULL);   // path = the stamp
        if (f != INVALID_HANDLE_VALUE) { DWORD put; WriteFile(f, &print, 4, &put, NULL); CloseHandle(f); }
        snprintf(line, sizeof line, "rebuild: %u files in %lu ms", done, (unsigned long)(GetTickCount() - started));
        log_line(line);
    }
    goto finish;

bad_file:
    snprintf(rebuild_status, sizeof rebuild_status, "the mod's Rebuild.rcp is damaged; please re-subscribe");
failed:
    // all or nothing: a half rebuilt mod would mix two versions of Thrawn's Revenge
    log_line(rebuild_status);
    for (unsigned int i = 0; i < done; i++) { DeleteFileA(written[i]); }
    snprintf(path, MAX_PATH, "%s\\Rebuild.stamp", rb_mod);
    DeleteFileA(path);
finish:
    if (rb_gen_started) rbgen_close();
    rb_gen_started = 0;
    if (rb_gen_texts.texts) {
        rb_texts *t = rb_gen_texts.texts;
        free(t->slot); free(t->value); free(t->value_len); free(t->key); free(t->key_len); free(t->data); free(t);
        rb_gen_texts.texts = NULL;
    }
    free(rb_script_name); free(rb_script_src); free(rb_script_name_len); free(rb_script_size);
    rb_script_name = NULL; rb_script_src = NULL; rb_script_name_len = rb_script_size = NULL; rb_script_count = 0;
    for (unsigned int i = 0; i < count; i++) {
        if (src[i].handle) CloseHandle(src[i].handle);
        rb_texts *t = src[i].texts;
        if (t) { free(t->slot); free(t->value); free(t->value_len); free(t->key); free(t->key_len); free(t->data); free(t); }
    }
    if (written) for (unsigned int i = 0; i < done; i++) free(written[i]);
    free(written);
    free(out_pos);
    if (all_out) for (unsigned int i = 0; i < all_n; i++) free(all_out[i]);
    free(all_out);
    free(buf);
    free(src);
    free(rcp);
}

// Shown once the game is up (a message box from DllMain would block the loader).
static char rebuild_update_note[200];      // the mod ships a newer POWRPROF.dll than this one

// Steam never updates the game folder, so players copy each new POWRPROF.dll by hand. This only reads the copy in
// the mod's folder and tells the player when it is newer. Nothing is written.
static DWORD rb_pe_stamp(const unsigned char *d, DWORD n) {
    if (n < 0x200 || d[0] != 'M' || d[1] != 'Z') return 0;
    DWORD pe = *(const DWORD *)(d + 0x3c);
    if (pe > n - 24 || memcmp(d + pe, "PE\0\0", 4) != 0 || *(const unsigned short *)(d + pe + 4) != 0x8664) return 0;
    return *(const DWORD *)(d + pe + 8);
}

static void rb_check_version(void) {
    if (!rb_own_id[0] || !rb_workshop[0]) return;
    HMODULE self = NULL;
    if (!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            (LPCSTR)(void *)rb_check_version, &self))
        return;
    const IMAGE_DOS_HEADER *dos = (const IMAGE_DOS_HEADER *)self;
    DWORD mine = ((const IMAGE_NT_HEADERS *)((const unsigned char *)self + dos->e_lfanew))->FileHeader.TimeDateStamp;
    char shipped[MAX_PATH];
    snprintf(shipped, MAX_PATH, "%s\\%s\\POWRPROF.dll", rb_workshop, rb_own_id);
    DWORD n = 0;
    unsigned char *d = read_whole(shipped, &n);
    if (!d) return;
    if (rb_pe_stamp(d, n) > mine) {
        log_line("engine hook: the mod's POWRPROF.dll is newer than this one");
        snprintf(rebuild_update_note, sizeof rebuild_update_note,
                 "Statecraft has a newer POWRPROF.dll. Please copy it from the mod's folder into the "
                 "game's corruption folder, replacing the old one, then restart the game.");
    }
    free(d);
}

static DWORD WINAPI rebuild_notice(LPVOID unused) {
    (void)unused;
    Sleep(4000);
    // an outdated POWRPROF.dll first: it is the likely cause of a failed rebuild
    const char *text = rebuild_update_note[0] ? rebuild_update_note : rebuild_status[0] ? rebuild_status
                                                                                        : rebuild_warning;
    MessageBoxA(NULL, text, "Statecraft", MB_OK | MB_ICONWARNING | MB_SETFOREGROUND);
    return 0;
}

static void rebuild_at_start(void) {
    // the generators' text functions (Lua's upper(), %w...) follow the C library's locale: plain "C" on this thread
    // while they run, whatever the process uses, so every PC makes the same files
    int per_thread = _configthreadlocale(_ENABLE_PER_THREAD_LOCALE);
    char *was = setlocale(LC_ALL, NULL);
    char saved[200];
    snprintf(saved, sizeof saved, "%s", was ? was : "C");
    setlocale(LC_ALL, "C");
    run_rebuild();
    setlocale(LC_ALL, saved);
    _configthreadlocale(per_thread);
    rb_check_version();
    if (rebuild_status[0] || rebuild_warning[0] || rebuild_update_note[0])
        CreateThread(NULL, 0, rebuild_notice, NULL, 0, NULL);
}
