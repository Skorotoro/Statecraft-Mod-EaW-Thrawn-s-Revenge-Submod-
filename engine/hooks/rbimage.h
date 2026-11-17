// Image functions for the data generators (rbimage.c)
#include <stddef.h>
#include "lua.h"

void rbimage_register(lua_State *L);
void *rbimage_check(lua_State *L, int index);
void rbimage_paint_bmp(unsigned char *buf, size_t n, void *image, int x, int y);
int rbimage_rgba(void *image, int *w, int *h, unsigned char **out);
