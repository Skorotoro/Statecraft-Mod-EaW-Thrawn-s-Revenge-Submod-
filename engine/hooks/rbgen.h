// Data generators for the start-up rebuild (rbgen.c)
#include <stddef.h>

typedef struct {
    const char *roots[2];                        // 0 = Thrawn's Revenge Data, 1 = the game folder
    const char *layers[8];                       // root 0 as a stack of Data folders, highest first (other submods
    int layer_count;                             // over Thrawn's): a file is read from the first that has it; 0 = roots[0]
    // English text of a key (UTF-16, n characters); 0 if there is none
    int (*text)(const char *key, unsigned int len, const unsigned short **value, unsigned int *n);
    // the i-th key of that text file (file order); 0 past the last
    int (*text_key)(unsigned int i, const char **key, unsigned int *len);
    // a generator script's source by name ("data/<name>": a data blob); NULL if there is none
    const char *(*script)(const char *name, unsigned int *size);
} rbgen_host;

int rbgen_open(const rbgen_host *host);
// the file `output` made by the script `script`; malloc'd into *data. 0 (and err) on failure
int rbgen_output(const char *script, const char *output, unsigned char **data, size_t *len, char *err, size_t err_len);
// paints the image icons[icon] of the script `script` into a 32-bit BMP (buf, n bytes) at (x, y)
int rbgen_paint(const char *script, const char *icon, unsigned char *buf, size_t n, int x, int y, char *err, size_t err_len);
// every output and icon a script made (tests)
int rbgen_each(const char *script, void (*fn)(const char *, const char *, size_t, void *, void *), void *ctx);
void rbgen_close(void);
