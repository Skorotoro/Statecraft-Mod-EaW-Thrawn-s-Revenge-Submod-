// Runs the start-up rebuild outside the game:
//   test.exe <Thrawn's Data> <game folder> <mod Data> [launched submod ids, comma separated]
// or one data generator, writing its files and icons (raw RGBA: uint32 width, height, then pixels) to a folder:
//   test.exe --gen <Thrawn's Data> <game folder> <generators folder> <data folder> <script> <out folder>
#define REBUILD_TEST
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <wchar.h>
static void log_line(const char *text) { printf("%s\n", text); }
#include "../../hooks/rebuild.c"
#include "rbimage.h"

static char gen_dir[MAX_PATH], data_dir[MAX_PATH], out_dir[MAX_PATH];
static char *loaded[4096];
static int loaded_n;

static const char *test_script(const char *name, unsigned int *size) {
    char path[MAX_PATH];
    if (!strncmp(name, "data/", 5)) snprintf(path, MAX_PATH, "%s\\%s", data_dir, name + 5);
    else snprintf(path, MAX_PATH, "%s\\%s.lua", gen_dir, name);
    for (char *p = path; *p; p++) if (*p == '/') *p = '\\';
    DWORD n = 0;
    unsigned char *d = read_whole(path, &n);
    if (!d) return NULL;
    if (loaded_n < 4096) loaded[loaded_n++] = (char *)d;
    *size = n;
    return (const char *)d;
}

static void write_file(const char *rel, const char *data, size_t n) {
    char path[MAX_PATH];
    snprintf(path, MAX_PATH, "%s\\%s", out_dir, rel);
    for (char *p = path + strlen(out_dir) + 1; *p; p++)
        if (*p == '\\' || *p == '/') { char c = *p; *p = 0; CreateDirectoryA(path, NULL); *p = c; }
    FILE *f = fopen(path, "wb");
    if (f) { fwrite(data, 1, n, f); fclose(f); }
}

static int files, icons;
static void dump(const char *name, const char *data, size_t n, void *image, void *ctx) {
    (void)ctx;
    if (data) { write_file(name, data, n); files++; return; }
    if (!image) { printf("error: %s\n", name ? name : "?"); return; }
    int w, h;
    unsigned char *px;
    if (!rbimage_rgba(image, &w, &h, &px)) return;
    char rel[MAX_PATH];
    snprintf(rel, MAX_PATH, "icons\\%s.rgba", name);
    size_t size = 8 + (size_t)w * h * 4;
    char *buf = malloc(size);
    memcpy(buf, &w, 4); memcpy(buf + 4, &h, 4); memcpy(buf + 8, px, size - 8);
    write_file(rel, buf, size);
    free(buf); free(px);
    icons++;
}

int main(int argc, char **argv) {
    if (argc == 8 && !strcmp(argv[1], "--gen")) {
        strcpy(rb_tr, argv[2]); strcpy(rb_game, argv[3]);
        strcpy(gen_dir, argv[4]); strcpy(data_dir, argv[5]); strcpy(out_dir, argv[7]);
        CreateDirectoryA(out_dir, NULL);
        rb_gen_host.roots[0] = rb_tr; rb_gen_host.roots[1] = rb_game;
        rb_gen_host.text = rb_gen_text; rb_gen_host.text_key = rb_gen_text_key; rb_gen_host.script = test_script;
        snprintf(rb_gen_texts.path, MAX_PATH, "%s\\Text\\MasterTextFile_ENGLISH.dat", rb_tr);
        DWORD t = GetTickCount();
        rbgen_open(&rb_gen_host);
        int ok = rbgen_each(argv[6], dump, NULL);
        printf("%s: %d files, %d icons (%lu ms)\n", ok ? "ok" : "failed", files, icons,
               (unsigned long)(GetTickCount() - t));
        rbgen_close();
        return ok ? 0 : 1;
    }
    if (argc != 4 && argc != 5) { printf("usage: test <tr data> <game> <mod data> [submod ids, comma separated]\n"); return 2; }
    strcpy(rb_tr, argv[1]); strcpy(rb_game, argv[2]); strcpy(rb_mod, argv[3]);
    strcpy(rb_workshop, rb_tr);                                  // <workshop>\<id>\Data
    for (int up = 0; up < 2; up++) { char *s = strrchr(rb_workshop, '\\'); if (s) *s = 0; }
    if (argc == 5)
        for (char *id = strtok(argv[4], ","); id && rb_id_count < 16; id = strtok(NULL, ",")) strcpy(rb_ids[rb_id_count++], id);
    DWORD t = GetTickCount();
    run_rebuild();
    printf("status: '%s' (%lu ms)\n", rebuild_status, (unsigned long)(GetTickCount() - t));
    return rebuild_status[0] ? 1 : 0;
}
