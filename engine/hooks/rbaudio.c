// --- MP3 decoding for the data generators -------------------------------------------------------
// The Diplomacy window's Mon Mothma lines are the base game's campaign speech (MP3s in EnglishSpeech.meg);
// the engine's sound events play WAVs, so the generators decode them on the player's PC. minimp3 (CC0,
// tools/minimp3), without SIMD so every PC and the mod's build (gen_audio.dll, the same file) get the same
// samples.
#define MINIMP3_IMPLEMENTATION
#define MINIMP3_NO_SIMD
#include <stdlib.h>
#include <string.h>
#include "minimp3.h"

#ifdef RBAUDIO_EXPORT
#define RBAUDIO_API __declspec(dllexport)
#else
#define RBAUDIO_API
#endif

// the whole file as 16-bit samples (channels interleaved); *pcm is malloc'd (free with rbaudio_free)
RBAUDIO_API int rbaudio_mp3(const unsigned char *data, size_t n, short **pcm, size_t *samples, int *channels,
                            int *rate) {
    mp3dec_t dec;
    mp3dec_frame_info_t info;
    short frame[MINIMP3_MAX_SAMPLES_PER_FRAME];
    size_t cap = 0, have = 0, pos = 0;
    short *out = NULL;
    *channels = 0;
    *rate = 0;
    mp3dec_init(&dec);
    while (pos < n) {
        int got = mp3dec_decode_frame(&dec, data + pos, (int)(n - pos > 0x7fffffff ? 0x7fffffff : n - pos), frame, &info);
        if (!info.frame_bytes) break;
        pos += info.frame_bytes;
        if (got <= 0) continue;
        if (!*channels) { *channels = info.channels; *rate = info.hz; }
        size_t add = (size_t)got * info.channels;
        if (have + add > cap) {
            cap = (have + add) * 2;
            short *more = realloc(out, cap * sizeof *out);
            if (!more) { free(out); return 0; }
            out = more;
        }
        memcpy(out + have, frame, add * sizeof *out);
        have += add;
    }
    *pcm = out;
    *samples = have;
    return out != NULL;
}

RBAUDIO_API void rbaudio_free(short *pcm) { free(pcm); }
