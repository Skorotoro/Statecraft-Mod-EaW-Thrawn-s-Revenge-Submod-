// --- Image functions for the data generators ----------------------------------------------------
// The generators (rbgen.c) draw some of the mod's icons from Thrawn's Revenge's own art on the player's
// PC. The mod's build draws the same icons with Pillow; this is Pillow's own imaging core (libImaging,
// tools/pillow_imaging) driven the way Pillow's Python layer drives it, so both give the same pixels.
// Each function's comment names the Pillow call it stands for. Images are Lua userdata.
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "Imaging.h"
#include "Bcn.h"
#include "lua.h"
#include "lauxlib.h"
#include "rbimage.h"

// libImaging expects these from Pillow's Python module
void *ImagingError_MemoryError(void) { return NULL; }
void *ImagingError_Mismatch(void) { return NULL; }
void *ImagingError_ModeError(void) { return NULL; }
void *ImagingError_ValueError(const char *message) { (void)message; return NULL; }
void ImagingError_Clear(void) {}
void ImagingSectionEnter(ImagingSectionCookie *cookie) { (void)cookie; }
void ImagingSectionLeave(ImagingSectionCookie *cookie) { (void)cookie; }

#define IMG "rbgen.image"

typedef struct {
    Imaging im;
    int tga_rle, tga_orientation;        // how an opened TGA was stored (Pillow keeps this in im.info)
    int id_len;
    unsigned char id[255];
} image_ud;

static image_ud *push(lua_State *L, Imaging im) {
    if (!im) luaL_error(L, "image operation failed");
    image_ud *u = lua_newuserdatauv(L, sizeof *u, 0);
    memset(u, 0, sizeof *u);
    u->im = im;
    u->tga_orientation = -1;
    luaL_setmetatable(L, IMG);
    return u;
}

static image_ud *check_ud(lua_State *L, int i) { return luaL_checkudata(L, i, IMG); }
static Imaging check(lua_State *L, int i) {
    image_ud *u = check_ud(L, i);
    if (!u->im) luaL_error(L, "image already freed");
    return u->im;
}

static int img_gc(lua_State *L) {
    image_ud *u = luaL_checkudata(L, 1, IMG);
    if (u->im) ImagingDelete(u->im);
    u->im = NULL;
    return 0;
}

// a copy that keeps the TGA storage info, as Pillow's Image._new copies im.info
static image_ud *push_like(lua_State *L, Imaging im, image_ud *from) {
    image_ud *u = push(L, im);
    if (from) {
        u->tga_rle = from->tga_rle; u->tga_orientation = from->tga_orientation;
        u->id_len = from->id_len; memcpy(u->id, from->id, from->id_len);
    }
    return u;
}

static void ink_of(lua_State *L, Imaging im, int first, UINT8 ink[4]) {
    int n = im->bands;
    memset(ink, 0, 4);
    for (int k = 0; k < 4; k++) ink[k] = (UINT8)luaL_optinteger(L, first + k, k == 3 ? 255 : 0);
    if (n == 1) { ink[1] = ink[2] = 0; ink[3] = 0; }
}

// Image.new(mode, (w, h), color)
static int l_new(lua_State *L) {
    const char *mode = luaL_checkstring(L, 1);
    int w = (int)luaL_checkinteger(L, 2), h = (int)luaL_checkinteger(L, 3);
    Imaging im = ImagingNewDirty(mode, w, h);
    if (!im) return luaL_error(L, "bad image mode %s", mode);
    UINT8 ink[4] = {0, 0, 0, 0};                   // no colour: Pillow's default 0 (black, transparent)
    if (!lua_isnoneornil(L, 4)) {
        ink_of(L, im, 4, ink);
        if (im->bands == 1) ink[0] = (UINT8)luaL_checkinteger(L, 4);
    }
    if (!strcmp(mode, "RGB")) ink[3] = 255;       // Pillow stores RGB with a full fourth byte
    ImagingFill(im, ink);
    push(L, im);
    return 1;
}

// Image.frombytes(mode, (w, h), data): RGBA, RGB or L, packed rows top to bottom
static int l_frombytes(lua_State *L) {
    const char *mode = luaL_checkstring(L, 1);
    int w = (int)luaL_checkinteger(L, 2), h = (int)luaL_checkinteger(L, 3);
    size_t n;
    const unsigned char *d = (const unsigned char *)luaL_checklstring(L, 4, &n);
    int px = !strcmp(mode, "RGBA") ? 4 : !strcmp(mode, "RGB") ? 3 : !strcmp(mode, "L") ? 1 : 0;
    if (!px) return luaL_error(L, "frombytes: mode %s", mode);
    if (n < (size_t)w * h * px) return luaL_error(L, "frombytes: not enough data");
    Imaging im = ImagingNewDirty(mode, w, h);
    for (int y = 0; y < h; y++) {
        UINT8 *row = (UINT8 *)im->image[y];
        const unsigned char *s = d + (size_t)y * w * px;
        if (px == 1) memcpy(row, s, w);
        else for (int x = 0; x < w; x++) {
            row[4 * x] = s[px * x]; row[4 * x + 1] = s[px * x + 1]; row[4 * x + 2] = s[px * x + 2];
            row[4 * x + 3] = px == 4 ? s[4 * x + 3] : 255;
        }
    }
    push(L, im);
    return 1;
}

// Image.getpixel((x, y)) -> its bands (1 for one band images, else r, g, b, a; RGB with a = 255)
static int l_pixel(lua_State *L) {
    Imaging im = check(L, 1);
    int x = (int)luaL_checkinteger(L, 2), y = (int)luaL_checkinteger(L, 3);
    if (x < 0 || y < 0 || x >= im->xsize || y >= im->ysize) return luaL_error(L, "pixel out of range");
    if (im->bands == 1) { lua_pushinteger(L, ((UINT8 *)im->image[y])[x]); return 1; }
    const UINT8 *p = (UINT8 *)im->image[y] + 4 * x;
    for (int i = 0; i < 4; i++) lua_pushinteger(L, p[i]);
    return 4;
}

// Image.tobytes()
static int l_tobytes(lua_State *L) {
    Imaging im = check(L, 1);
    int px = im->bands == 1 ? 1 : im->bands == 3 ? 3 : 4;
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    for (int y = 0; y < im->ysize; y++) {
        UINT8 *row = (UINT8 *)im->image[y];
        if (px == 4 || px == 1) luaL_addlstring(&b, (const char *)row, (size_t)im->xsize * px);
        else for (int x = 0; x < im->xsize; x++) luaL_addlstring(&b, (const char *)row + 4 * x, 3);
    }
    luaL_pushresult(&b);
    return 1;
}

// Image.frombytes(data) in place (same mode and size; the image keeps its info)
static int l_set_bytes(lua_State *L) {
    Imaging im = check(L, 1);
    size_t n;
    const unsigned char *d = (const unsigned char *)luaL_checklstring(L, 2, &n);
    int px = im->bands == 1 ? 1 : im->bands == 3 ? 3 : 4;
    if (n < (size_t)im->xsize * im->ysize * px) return luaL_error(L, "set_bytes: not enough data");
    for (int y = 0; y < im->ysize; y++) {
        UINT8 *row = (UINT8 *)im->image[y];
        const unsigned char *s = d + (size_t)y * im->xsize * px;
        if (px != 3) memcpy(row, s, (size_t)im->xsize * px);
        else for (int x = 0; x < im->xsize; x++) {
            row[4 * x] = s[3 * x]; row[4 * x + 1] = s[3 * x + 1]; row[4 * x + 2] = s[3 * x + 2]; row[4 * x + 3] = 255;
        }
    }
    return 0;
}

static int l_size(lua_State *L) {
    Imaging im = check(L, 1);
    lua_pushinteger(L, im->xsize);
    lua_pushinteger(L, im->ysize);
    return 2;
}

static int l_mode(lua_State *L) { lua_pushstring(L, check(L, 1)->mode); return 1; }

static int l_copy(lua_State *L) {
    image_ud *u = check_ud(L, 1);
    push_like(L, ImagingCopy(check(L, 1)), u);
    return 1;
}

// Image.convert(mode)
static int l_convert(lua_State *L) {
    image_ud *u = check_ud(L, 1);
    Imaging im = check(L, 1);
    const char *mode = luaL_checkstring(L, 2);
    if (!strcmp(im->mode, mode)) { push_like(L, ImagingCopy(im), u); return 1; }
    push_like(L, ImagingConvert(im, mode, NULL, 0), u);
    return 1;
}

static int filter_of(const char *name) {
    if (!strcmp(name, "nearest")) return IMAGING_TRANSFORM_NEAREST;
    if (!strcmp(name, "box")) return IMAGING_TRANSFORM_BOX;
    if (!strcmp(name, "bilinear")) return IMAGING_TRANSFORM_BILINEAR;
    if (!strcmp(name, "hamming")) return IMAGING_TRANSFORM_HAMMING;
    if (!strcmp(name, "bicubic")) return IMAGING_TRANSFORM_BICUBIC;
    if (!strcmp(name, "lanczos")) return IMAGING_TRANSFORM_LANCZOS;
    return -1;
}

static Imaging resize(Imaging im, int w, int h, int filter) {
    if (im->xsize == w && im->ysize == h) return ImagingCopy(im);
    float box[4] = {0, 0, (float)im->xsize, (float)im->ysize};
    if ((!strcmp(im->mode, "RGBA") || !strcmp(im->mode, "LA")) && filter != IMAGING_TRANSFORM_NEAREST) {
        // Pillow resizes these with premultiplied alpha
        const char *pre = !strcmp(im->mode, "RGBA") ? "RGBa" : "La";
        Imaging a = ImagingConvert(im, pre, NULL, 0);
        Imaging b = a ? resize(a, w, h, filter) : NULL;
        Imaging c = b ? ImagingConvert(b, im->mode, NULL, 0) : NULL;
        if (a) ImagingDelete(a);
        if (b) ImagingDelete(b);
        return c;
    }
    return ImagingResample(im, w, h, filter, box);
}

// Image.resize((w, h), filter)
static int l_resize(lua_State *L) {
    image_ud *u = check_ud(L, 1);
    Imaging im = check(L, 1);
    int w = (int)luaL_checkinteger(L, 2), h = (int)luaL_checkinteger(L, 3);
    int filter = filter_of(luaL_optstring(L, 4, "bicubic"));
    if (filter < 0) return luaL_error(L, "resize: unknown filter");
    push_like(L, resize(im, w, h, filter), u);
    return 1;
}

// Image.crop((x0, y0, x1, y1))
static int l_crop(lua_State *L) {
    image_ud *u = check_ud(L, 1);
    Imaging im = check(L, 1);
    push_like(L, ImagingCrop(im, (int)luaL_checkinteger(L, 2), (int)luaL_checkinteger(L, 3),
                             (int)luaL_checkinteger(L, 4), (int)luaL_checkinteger(L, 5)), u);
    return 1;
}

// Image.paste(src, (x, y), mask) in place; src converted to the target's mode like Pillow does
static void paste(lua_State *L, Imaging dst, Imaging src, int x, int y, Imaging mask) {
    Imaging tmp = NULL;
    if (strcmp(dst->mode, src->mode)) {
        if (strcmp(dst->mode, "RGB") || (strcmp(src->mode, "LA") && strcmp(src->mode, "RGBA") && strcmp(src->mode, "RGBa")))
            src = tmp = ImagingConvert(src, dst->mode, NULL, 0);
    }
    int w = src->xsize, h = src->ysize;
    int r = ImagingPaste(dst, src, mask, x, y, x + w, y + h);
    if (tmp) ImagingDelete(tmp);
    if (r < 0) luaL_error(L, "paste failed");
}

static int l_paste(lua_State *L) {
    Imaging dst = check(L, 1), src = check(L, 2);
    Imaging mask = lua_isnoneornil(L, 5) ? NULL : check(L, 5);
    paste(L, dst, src, (int)luaL_checkinteger(L, 3), (int)luaL_checkinteger(L, 4), mask);
    return 0;
}

// Image.paste(color, (x0, y0, x1, y1), mask)
static int l_fill(lua_State *L) {
    Imaging dst = check(L, 1);
    UINT8 ink[4];
    ink_of(L, dst, 2, ink);
    if (dst->bands == 1) ink[0] = (UINT8)luaL_checkinteger(L, 2);
    Imaging mask = lua_isnoneornil(L, 10) ? NULL : check(L, 10);
    if (ImagingFill2(dst, ink, mask, (int)luaL_checkinteger(L, 6), (int)luaL_checkinteger(L, 7),
                     (int)luaL_checkinteger(L, 8), (int)luaL_checkinteger(L, 9)) < 0)
        return luaL_error(L, "fill failed");
    return 0;
}

// Image.alpha_composite(src, dest=(x, y)) in place
static int l_alpha_composite(lua_State *L) {
    Imaging dst = check(L, 1), src = check(L, 2);
    int x = (int)luaL_optinteger(L, 3, 0), y = (int)luaL_optinteger(L, 4, 0);
    int whole = x == 0 && y == 0 && src->xsize == dst->xsize && src->ysize == dst->ysize;
    Imaging background = whole ? dst : ImagingCrop(dst, x, y, x + src->xsize, y + src->ysize);
    Imaging result = background ? ImagingAlphaComposite(background, src) : NULL;
    if (!whole && background) ImagingDelete(background);
    if (!result) return luaL_error(L, "alpha_composite failed");
    paste(L, dst, result, x, y, NULL);
    ImagingDelete(result);
    return 0;
}

// Image.alpha_composite(a, b) (a new image)
static int l_composite2(lua_State *L) {
    push(L, ImagingAlphaComposite(check(L, 1), check(L, 2)));
    return 1;
}

// Image.split()
static int l_split(lua_State *L) {
    Imaging im = check(L, 1);
    for (int b = 0; b < im->bands; b++) push(L, ImagingGetBand(im, b));
    return im->bands;
}

// Image.merge(mode, bands)
static int l_merge(lua_State *L) {
    const char *mode = luaL_checkstring(L, 1);
    luaL_checktype(L, 2, LUA_TTABLE);
    Imaging bands[4] = {NULL, NULL, NULL, NULL};
    int n = (int)luaL_len(L, 2);
    for (int i = 0; i < n && i < 4; i++) {
        lua_geti(L, 2, i + 1);
        bands[i] = check(L, -1);
        lua_pop(L, 1);
    }
    push(L, ImagingMerge(mode, bands));
    return 1;
}

// Image.putalpha(band or value) in place (RGBA / LA images)
static int l_putalpha(lua_State *L) {
    Imaging im = check(L, 1);
    int band = im->bands == 2 ? 1 : 3;
    if (lua_isinteger(L, 2)) ImagingFillBand(im, band, (int)lua_tointeger(L, 2));
    else ImagingPutBand(im, check(L, 2), band);
    return 0;
}

// Image.point(lut): lut is a string of 256 bytes per band
static int l_point(lua_State *L) {
    image_ud *u = check_ud(L, 1);
    Imaging im = check(L, 1);
    size_t n;
    const char *lut = luaL_checklstring(L, 2, &n);
    if (n < (size_t)256 * im->bands) return luaL_error(L, "point: lut too short");
    push_like(L, ImagingPoint(im, NULL, lut), u);
    return 1;
}

// Image.blend(a, b, alpha)
static int l_blend(lua_State *L) {
    push(L, ImagingBlend(check(L, 1), check(L, 2), (float)luaL_checknumber(L, 3)));
    return 1;
}

// ImageChops.multiply(a, b)
static int l_multiply(lua_State *L) {
    push(L, ImagingChopMultiply(check(L, 1), check(L, 2)));
    return 1;
}

// Image.filter(GaussianBlur(radius))
static int l_gaussian(lua_State *L) {
    image_ud *u = check_ud(L, 1);
    Imaging im = check(L, 1);
    float r = (float)luaL_checknumber(L, 2);
    if (r == 0) { push_like(L, ImagingCopy(im), u); return 1; }
    Imaging out = ImagingNewDirty(im->mode, im->xsize, im->ysize);
    if (!out || !ImagingGaussianBlur(out, im, r, r, 3)) { if (out) ImagingDelete(out); return luaL_error(L, "blur failed"); }
    push_like(L, out, u);
    return 1;
}

// Image.filter(RankFilter(size, rank)), e.g. MinFilter(3) = rank 0; one band images
static int l_rankfilter(lua_State *L) {
    Imaging im = check(L, 1);
    int size = (int)luaL_checkinteger(L, 2), rank = (int)luaL_checkinteger(L, 3);
    if (im->bands != 1) return luaL_error(L, "rankfilter: one band images only");
    Imaging big = ImagingExpand(im, size / 2, size / 2);
    Imaging out = big ? ImagingRankFilter(big, size, rank) : NULL;
    if (big) ImagingDelete(big);
    push(L, out);
    return 1;
}

// Image.getbbox() -> x0, y0, x1, y1 or nil
static int l_getbbox(lua_State *L) {
    int bbox[4];
    if (!ImagingGetBBox(check(L, 1), bbox, 1)) { lua_pushnil(L); return 1; }
    for (int i = 0; i < 4; i++) lua_pushinteger(L, bbox[i]);
    return 4;
}

// Image.histogram() -> {counts} (256 per band)
static int l_histogram(lua_State *L) {
    Imaging im = check(L, 1);
    ImagingHistogram h = ImagingGetHistogram(im, NULL, NULL);
    if (!h) return luaL_error(L, "histogram failed");
    lua_createtable(L, 256 * h->bands, 0);
    for (int i = 0; i < 256 * h->bands; i++) {
        lua_pushinteger(L, h->histogram[i]);
        lua_rawseti(L, -2, i + 1);
    }
    ImagingHistogramDelete(h);
    return 1;
}

// Image.transpose(FLIP_LEFT_RIGHT)
static int l_flip(lua_State *L) {
    image_ud *u = check_ud(L, 1);
    Imaging im = check(L, 1);
    Imaging out = ImagingNewDirty(im->mode, im->xsize, im->ysize);
    if (!out || !ImagingFlipLeftRight(out, im)) return luaL_error(L, "flip failed");
    push_like(L, out, u);
    return 1;
}

// --- reading -------------------------------------------------------------------------------------

static unsigned short u16(const unsigned char *p) { return (unsigned short)(p[0] | p[1] << 8); }
static unsigned int u32(const unsigned char *p) { return p[0] | p[1] << 8 | p[2] << 16 | (unsigned int)p[3] << 24; }

// one row of TGA pixels (BGR, BGRA or L) into an image row
static void tga_row(Imaging im, int y, const unsigned char *s, int depth) {
    UINT8 *row = (UINT8 *)im->image[y];
    int w = im->xsize;
    if (depth == 8) { memcpy(row, s, w); return; }
    for (int x = 0; x < w; x++) {
        row[4 * x] = s[x * (depth / 8) + 2];
        row[4 * x + 1] = s[x * (depth / 8) + 1];
        row[4 * x + 2] = s[x * (depth / 8)];
        row[4 * x + 3] = depth == 32 ? s[4 * x + 3] : 255;
    }
}

// TgaImagePlugin: types 2/10 (24, 32 bits) and 3/11 (8 bits grey)
static int open_tga(lua_State *L, const unsigned char *d, size_t n) {
    if (n < 18) return luaL_error(L, "not a TGA file");
    int id_len = d[0], cmap = d[1], type = d[2], depth = d[16], flags = d[17];
    int w = u16(d + 12), h = u16(d + 14);
    if (cmap || w <= 0 || h <= 0) return luaL_error(L, "unsupported TGA file");
    const char *mode;
    if ((type == 2 || type == 10) && (depth == 24 || depth == 32)) mode = depth == 24 ? "RGB" : "RGBA";
    else if ((type == 3 || type == 11) && depth == 8) mode = "L";
    else return luaL_error(L, "unsupported TGA type %d depth %d", type, depth);
    int orientation = flags & 0x30;
    if (orientation == 0x10 || orientation == 0x30) return luaL_error(L, "unsupported TGA orientation");
    int top_down = orientation == 0x20;
    Imaging im = ImagingNewDirty(mode, w, h);
    size_t pos = 18 + id_len, bpp = depth / 8, row_bytes = (size_t)w * bpp;
    unsigned char *line = malloc(row_bytes);
    size_t at = 0;
    int y = 0;
    while (y < h) {
        if (type & 8) {
            if (pos >= n) break;
            int c = d[pos++], count = (c & 0x7f) + 1;
            for (int k = 0; k < count; k++) {
                if (c & 0x80) { if (pos + bpp > n) goto short_file; memcpy(line + at, d + pos, bpp); }
                else { if (pos + bpp > n) goto short_file; memcpy(line + at, d + pos, bpp); pos += bpp; }
                at += bpp;
                if (at == row_bytes) {
                    tga_row(im, top_down ? y : h - 1 - y, line, depth);
                    at = 0;
                    if (++y >= h) break;
                }
            }
            if (c & 0x80) pos += bpp;
        } else {
            if (pos + row_bytes > n) goto short_file;
            tga_row(im, top_down ? y : h - 1 - y, d + pos, depth);
            pos += row_bytes;
            y++;
        }
    }
    free(line);
    image_ud *u = push(L, im);
    u->tga_rle = (type & 8) != 0;
    u->tga_orientation = top_down ? 1 : -1;
    u->id_len = id_len;
    memcpy(u->id, d + 18, id_len);
    return 1;
short_file:
    free(line);
    ImagingDelete(im);
    return luaL_error(L, "TGA file too short");
}

// DdsImagePlugin: DXT1/3/5 (Pillow's BCn decoder) and uncompressed RGB(A) with bit masks
static int open_dds(lua_State *L, const unsigned char *d, size_t n) {
    if (n < 128 || u32(d + 4) != 124) return luaL_error(L, "unsupported DDS file");
    int h = (int)u32(d + 12), w = (int)u32(d + 16);
    unsigned int pfflags = u32(d + 80), bitcount = u32(d + 88);
    const unsigned char *fourcc = d + 84;
    if (pfflags & 0x40) {                                     // DDPF_RGB
        int alpha = (pfflags & 0x1) != 0, count = alpha ? 4 : 3;
        unsigned int masks[4], offset[4], total[4];
        for (int i = 0; i < count; i++) {
            masks[i] = u32(d + 92 + 4 * i);
            offset[i] = 0;
            if (masks[i]) while ((masks[i] >> (offset[i] + 1)) << (offset[i] + 1) == masks[i]) offset[i]++;
            total[i] = masks[i] >> offset[i];
        }
        Imaging im = ImagingNewDirty(alpha ? "RGBA" : "RGB", w, h);
        size_t pos = 128, bytes = bitcount / 8;
        for (int y = 0; y < h; y++) {
            UINT8 *row = (UINT8 *)im->image[y];
            for (int x = 0; x < w; x++) {
                if (pos + bytes > n) { ImagingDelete(im); return luaL_error(L, "DDS file too short"); }
                unsigned long long v = 0;
                for (size_t k = 0; k < bytes; k++) v |= (unsigned long long)d[pos + k] << (8 * k);
                pos += bytes;
                for (int i = 0; i < 4; i++) {
                    if (i < count) row[4 * x + i] = (UINT8)(int)(((double)((v & masks[i]) >> offset[i]) / total[i]) * 255);
                    else row[4 * x + i] = 255;
                }
            }
        }
        push(L, im);
        return 1;
    }
    int N;
    const char *format;
    if (!memcmp(fourcc, "DXT1", 4)) { N = 1; format = "DXT1"; }
    else if (!memcmp(fourcc, "DXT3", 4)) { N = 2; format = "DXT3"; }
    else if (!memcmp(fourcc, "DXT5", 4)) { N = 3; format = "DXT5"; }
    else return luaL_error(L, "unsupported DDS pixel format");
    Imaging im = ImagingNewDirty("RGBA", w, h);
    struct ImagingCodecStateInstance state;
    BCNSTATE context;
    memset(&state, 0, sizeof state);
    memset(&context, 0, sizeof context);
    context.pixel_format = (char *)format;
    state.state = N;
    state.xsize = w; state.ysize = h;
    state.context = &context;
    ImagingBcnDecode(im, &state, (UINT8 *)d + 128, (Py_ssize_t)(n - 128));
    push(L, im);
    return 1;
}

// A texture to read single pixels from (Image.getpixel on Image.open(data).convert("RGB") / RGBA): a DXT1/3/5 DDS
// decodes only the 4x4 blocks asked for (same decoder, same pixels as a full decode); anything else is opened.
#define SAMPLER "rbgen.sampler"
static int l_open(lua_State *L);
typedef struct {
    unsigned char *data;                 // the DDS file
    size_t n;
    int w, h, N, bw;                     // size, BCn kind, blocks per row
    UINT8 **block;                       // decoded blocks (16 RGBA pixels), made when first read
    Imaging tmp;                         // a 4x4 image to decode one block into
} sampler_ud;

static int sampler_gc(lua_State *L) {
    sampler_ud *s = luaL_checkudata(L, 1, SAMPLER);
    if (s->block) {
        for (int i = 0; i < ((s->w + 3) / 4) * ((s->h + 3) / 4); i++) free(s->block[i]);
        free(s->block);
    }
    if (s->tmp) ImagingDelete(s->tmp);
    free(s->data);
    memset(s, 0, sizeof *s);
    return 0;
}

static int l_sampler(lua_State *L) {
    size_t n;
    const unsigned char *d = (const unsigned char *)luaL_checklstring(L, 1, &n);
    int N = 0;
    if (n >= 128 && !memcmp(d, "DDS ", 4) && u32(d + 4) == 124 && !(u32(d + 80) & 0x40)) {
        if (!memcmp(d + 84, "DXT1", 4)) N = 1;
        else if (!memcmp(d + 84, "DXT3", 4)) N = 2;
        else if (!memcmp(d + 84, "DXT5", 4)) N = 3;
    }
    if (!N) {                                                   // not block compressed: the image, as RGB(A)
        l_open(L);
        Imaging im = check(L, -1);
        if (strcmp(im->mode, "RGB") && strcmp(im->mode, "RGBA")) push(L, ImagingConvert(im, "RGB", NULL, 0));
        return 1;
    }
    sampler_ud *s = lua_newuserdatauv(L, sizeof *s, 0);
    memset(s, 0, sizeof *s);
    luaL_setmetatable(L, SAMPLER);
    s->h = (int)u32(d + 12); s->w = (int)u32(d + 16); s->N = N;
    s->bw = (s->w + 3) / 4;
    s->data = malloc(n); memcpy(s->data, d, n); s->n = n;
    s->block = calloc((size_t)s->bw * ((s->h + 3) / 4), sizeof *s->block);
    s->tmp = ImagingNewDirty("RGBA", 4, 4);
    return 1;
}

static int l_sample(lua_State *L) {
    if (!luaL_testudata(L, 1, SAMPLER)) return l_pixel(L);
    sampler_ud *s = luaL_checkudata(L, 1, SAMPLER);
    int x = (int)luaL_checkinteger(L, 2), y = (int)luaL_checkinteger(L, 3);
    if (x < 0 || y < 0 || x >= s->w || y >= s->h) return luaL_error(L, "pixel out of range");
    int b = (y / 4) * s->bw + x / 4;
    if (!s->block[b]) {
        size_t size = s->N == 1 ? 8 : 16, at = 128 + (size_t)b * size;
        if (at + size > s->n) return luaL_error(L, "DDS file too short");
        struct ImagingCodecStateInstance state;
        BCNSTATE context;
        memset(&state, 0, sizeof state);
        memset(&context, 0, sizeof context);
        context.pixel_format = (char *)(s->N == 1 ? "DXT1" : s->N == 2 ? "DXT3" : "DXT5");
        state.state = s->N;
        state.xsize = 4; state.ysize = 4;
        state.context = &context;
        ImagingBcnDecode(s->tmp, &state, s->data + at, (Py_ssize_t)size);
        s->block[b] = malloc(64);
        for (int r = 0; r < 4; r++) memcpy(s->block[b] + 16 * r, s->tmp->image[r], 16);
    }
    const UINT8 *p = s->block[b] + 16 * (y % 4) + 4 * (x % 4);
    for (int i = 0; i < 4; i++) lua_pushinteger(L, p[i]);
    return 4;
}

static int l_sampler_size(lua_State *L) {
    if (!luaL_testudata(L, 1, SAMPLER)) return l_size(L);
    sampler_ud *s = luaL_checkudata(L, 1, SAMPLER);
    lua_pushinteger(L, s->w);
    lua_pushinteger(L, s->h);
    return 2;
}

// Image.open(data); .load()
static int l_open(lua_State *L) {
    size_t n;
    const unsigned char *d = (const unsigned char *)luaL_checklstring(L, 1, &n);
    if (n >= 4 && !memcmp(d, "DDS ", 4)) return open_dds(L, d, n);
    return open_tga(L, d, n);
}

// a region of a 32-bit BMP (Thrawn's command bar atlas) as RGBA
static int l_from_bmp(lua_State *L) {
    size_t n;
    const unsigned char *d = (const unsigned char *)luaL_checklstring(L, 1, &n);
    int x0 = (int)luaL_checkinteger(L, 2), y0 = (int)luaL_checkinteger(L, 3);
    int w = (int)luaL_checkinteger(L, 4), h = (int)luaL_checkinteger(L, 5);
    int bw, bh;
    size_t start = 54;
    if (n >= 18 && !(d[0] == 'B' && d[1] == 'M')) {
        // a submod may ship a real TGA under that name (uncompressed, 32-bit): the same pixels, rows as stored
        if (d[1] != 0 || d[2] != 2 || d[16] != 32) return luaL_error(L, "command bar atlas: unsupported TGA");
        start = 18 + d[0];
        bw = u16(d + 12);
        bh = (d[17] & 0x20) ? -(int)u16(d + 14) : (int)u16(d + 14);
    } else {
        if (n < 54) return luaL_error(L, "not a BMP");
        bw = (int)u32(d + 18); bh = (int)u32(d + 22);
    }
    int rows = bh < 0 ? -bh : bh;
    if (x0 < 0 || y0 < 0 || x0 + w > bw || y0 + h > rows || start + (size_t)bw * rows * 4 > n)
        return luaL_error(L, "BMP region out of range");
    Imaging im = ImagingNewDirty("RGBA", w, h);
    for (int y = 0; y < h; y++) {
        int sy = bh > 0 ? rows - 1 - (y0 + y) : y0 + y;
        const unsigned char *s = d + start + ((size_t)sy * bw + x0) * 4;
        UINT8 *row = (UINT8 *)im->image[y];
        for (int x = 0; x < w; x++) {
            row[4 * x] = s[4 * x + 2]; row[4 * x + 1] = s[4 * x + 1]; row[4 * x + 2] = s[4 * x]; row[4 * x + 3] = s[4 * x + 3];
        }
    }
    push(L, im);
    return 1;
}

// --- writing -------------------------------------------------------------------------------------

static void pack_bgra(UINT8 *out, const UINT8 *in, int pixels) {
    for (int i = 0; i < pixels; i++) {
        out[4 * i] = in[4 * i + 2]; out[4 * i + 1] = in[4 * i + 1]; out[4 * i + 2] = in[4 * i]; out[4 * i + 3] = in[4 * i + 3];
    }
}

// Image.save(..., "TGA") of an RGBA image, keeping the source's RLE/orientation/id like Pillow (im.info)
static int l_tga(lua_State *L) {
    image_ud *u = check_ud(L, 1);
    Imaging im = check(L, 1);
    if (strcmp(im->mode, "RGBA")) return luaL_error(L, "tga: RGBA images only");
    int rle = lua_isnoneornil(L, 2) ? u->tga_rle : lua_toboolean(L, 2);
    int orientation = u->tga_orientation;
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    unsigned char head[18] = {0};
    head[0] = (unsigned char)u->id_len;
    head[2] = rle ? 10 : 2;
    head[12] = im->xsize & 0xff; head[13] = im->xsize >> 8;
    head[14] = im->ysize & 0xff; head[15] = im->ysize >> 8;
    head[16] = 32;
    head[17] = 8 | (orientation > 0 ? 0x20 : 0);
    luaL_addlstring(&b, (const char *)head, 18);
    luaL_addlstring(&b, (const char *)u->id, u->id_len);
    if (!rle) {
        UINT8 *line = malloc((size_t)im->xsize * 4);
        for (int k = 0; k < im->ysize; k++) {
            int y = orientation > 0 ? k : im->ysize - 1 - k;
            pack_bgra(line, (UINT8 *)im->image[y], im->xsize);
            luaL_addlstring(&b, (const char *)line, (size_t)im->xsize * 4);
        }
        free(line);
    } else {
        struct ImagingCodecStateInstance state;
        memset(&state, 0, sizeof state);
        state.xsize = im->xsize; state.ysize = im->ysize;
        state.bits = 32;
        state.bytes = im->xsize * 4;
        state.ystep = orientation > 0 ? 1 : -1;
        state.shuffle = (ImagingShuffler)pack_bgra;
        state.buffer = malloc((size_t)state.bytes);
        UINT8 *out = malloc(65536);
        for (;;) {
            int got = ImagingTgaRleEncode(im, &state, out, 65536);
            if (got > 0) luaL_addlstring(&b, (const char *)out, got);
            if (state.errcode == IMAGING_CODEC_END || got <= 0) break;
        }
        free(out);
        free(state.buffer);
    }
    static const char footer[26] = {0, 0, 0, 0, 0, 0, 0, 0, 'T', 'R', 'U', 'E', 'V', 'I', 'S', 'I', 'O', 'N', '-',
                                    'X', 'F', 'I', 'L', 'E', '.', 0};
    luaL_addlstring(&b, footer, 26);
    luaL_pushresult(&b);
    return 1;
}

// paint an RGBA image into a 32-bit BMP held in buf (the atlas), at (x, y) from the top left
void rbimage_paint_bmp(unsigned char *buf, size_t n, void *image, int x0, int y0) {
    Imaging im = ((image_ud *)image)->im;
    if (!im || n < 54 || strcmp(im->mode, "RGBA")) return;
    int bw = (int)u32(buf + 18), bh = (int)u32(buf + 22), rows = bh < 0 ? -bh : bh;
    for (int y = 0; y < im->ysize; y++) {
        int ty = y0 + y;
        if (ty < 0 || ty >= rows) continue;
        int sy = bh > 0 ? rows - 1 - ty : ty;
        for (int x = 0; x < im->xsize; x++) {
            int tx = x0 + x;
            if (tx < 0 || tx >= bw) continue;
            size_t at = 54 + ((size_t)sy * bw + tx) * 4;
            if (at + 4 > n) continue;
            const UINT8 *p = (UINT8 *)im->image[y] + 4 * x;
            buf[at] = p[2]; buf[at + 1] = p[1]; buf[at + 2] = p[0]; buf[at + 3] = p[3];
        }
    }
}

// an image's size and RGBA pixels (malloc'd, rows top to bottom), for tests
int rbimage_rgba(void *image, int *w, int *h, unsigned char **out) {
    Imaging im = ((image_ud *)image)->im;
    Imaging rgba = strcmp(im->mode, "RGBA") ? ImagingConvert(im, "RGBA", NULL, 0) : im;
    if (!rgba) return 0;
    *w = rgba->xsize; *h = rgba->ysize;
    *out = malloc((size_t)rgba->xsize * rgba->ysize * 4);
    for (int y = 0; y < rgba->ysize; y++) memcpy(*out + (size_t)y * rgba->xsize * 4, rgba->image[y], (size_t)rgba->xsize * 4);
    if (rgba != im) ImagingDelete(rgba);
    return 1;
}

void *rbimage_check(lua_State *L, int index) { return luaL_testudata(L, index, IMG); }

static const luaL_Reg fns[] = {
    {"img_new", l_new}, {"img_frombytes", l_frombytes}, {"img_bytes", l_tobytes}, {"img_set_bytes", l_set_bytes}, {"img_pixel", l_pixel}, {"img_size", l_size},
    {"img_mode", l_mode}, {"img_copy", l_copy}, {"img_convert", l_convert}, {"img_resize", l_resize},
    {"img_crop", l_crop}, {"img_paste", l_paste}, {"img_fill", l_fill}, {"img_alpha_composite", l_alpha_composite},
    {"img_composite", l_composite2}, {"img_split", l_split}, {"img_merge", l_merge}, {"img_putalpha", l_putalpha},
    {"img_point", l_point}, {"img_blend", l_blend}, {"img_multiply", l_multiply}, {"img_gaussian", l_gaussian},
    {"img_rankfilter", l_rankfilter}, {"img_getbbox", l_getbbox}, {"img_histogram", l_histogram},
    {"img_flip", l_flip}, {"img_open", l_open}, {"img_sampler", l_sampler}, {"img_sample", l_sample},
    {"img_sampler_size", l_sampler_size}, {"img_from_bmp", l_from_bmp}, {"img_tga", l_tga}, {NULL, NULL}};

// adds the image functions to the table on top of the stack
void rbimage_register(lua_State *L) {
    if (luaL_newmetatable(L, IMG)) {
        lua_pushcfunction(L, img_gc);
        lua_setfield(L, -2, "__gc");
    }
    lua_pop(L, 1);
    if (luaL_newmetatable(L, SAMPLER)) {
        lua_pushcfunction(L, sampler_gc);
        lua_setfield(L, -2, "__gc");
    }
    lua_pop(L, 1);
    luaL_setfuncs(L, fns, 0);
}
