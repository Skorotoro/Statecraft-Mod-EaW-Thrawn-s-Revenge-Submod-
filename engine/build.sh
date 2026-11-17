#!/bin/bash
# Builds hooks/POWRPROF.dll (the engine hook) and tools/rebuild_test/test.exe (the start-up rebuild, run
# outside the game). Close the game first; copy POWRPROF.dll into the game's corruption folder after.
set -e
cd "$(dirname "$0")"
# The release's build time (BUILD_TIME, seconds since 1970) goes into the DLL instead of the current time, so the
# same source built with the same compiler (WinLibs GCC 16.2.0 UCRT POSIX r1) gives a byte-identical POWRPROF.dll.
[ -n "$SOURCE_DATE_EPOCH" ] || export SOURCE_DATE_EPOCH=$(tr -dc '0-9' < BUILD_TIME)
PI=tools/pillow_imaging
LUA=$(ls tools/lua-5.5.0/src/*.c | grep -vE '/luac?\.c$')
IMG="$PI/Storage.c $PI/Access.c $PI/Bands.c $PI/Copy.c $PI/Crop.c $PI/Fill.c $PI/GetBBox.c $PI/Geometry.c
     $PI/Palette.c $PI/Convert.c $PI/ConvertYCbCr.c $PI/Resample.c $PI/AlphaComposite.c $PI/Paste.c $PI/BoxBlur.c
     $PI/RankFilter.c $PI/Blend.c $PI/Point.c $PI/Chops.c $PI/Histo.c $PI/Filter.c $PI/BcnDecode.c
     $PI/TgaRleEncode.c $PI/Arrow.c"
FLAGS="-O2 -Wno-format-truncation -Dl_strcoll=strcmp -Ihooks -I$PI -Itools/lua-5.5.0/src -Itools/minhook/include -Itools/minimp3"
# the libraries are built quietly (their own warnings); our files with -Wall
mkdir -p build/obj
for f in $LUA $IMG; do
    o=build/obj/$(basename "$f" .c).o
    [ "$o" -nt "$f" ] || gcc $FLAGS -w -c "$f" -o "$o"
done
gcc $FLAGS -Wall -c hooks/rbgen.c -o build/obj/rbgen.o
gcc $FLAGS -Wall -c hooks/rbimage.c -o build/obj/rbimage.o
gcc $FLAGS -w -c hooks/rbaudio.c -o build/obj/rbaudio.o
# the same MP3 decoder for the mod's build (gen_host.py loads it), so both decode alike
gcc $FLAGS -w -shared -static -s -DRBAUDIO_EXPORT -o build/gen_audio.dll hooks/rbaudio.c
LIBS="build/obj/*.o"
if [ "$1" != "test" ]; then
    gcc $FLAGS -shared -static -s -Wall -o hooks/POWRPROF.dll hooks/enginehook.c $LIBS tools/minhook/src/hook.c \
        tools/minhook/src/buffer.c tools/minhook/src/trampoline.c tools/minhook/src/hde/hde64.c -luser32
    echo "built hooks/POWRPROF.dll"
    # the players' copy (Workshop package): no test command channel, no diagnostic thread dump
    gcc $FLAGS -DRELEASE_BUILD -shared -static -s -Wall -o hooks/POWRPROF_release.dll hooks/enginehook.c $LIBS         tools/minhook/src/hook.c tools/minhook/src/buffer.c tools/minhook/src/trampoline.c         tools/minhook/src/hde/hde64.c -luser32
    echo "built hooks/POWRPROF_release.dll"
fi
gcc $FLAGS -Wno-unused-function -o tools/rebuild_test/test.exe tools/rebuild_test/test.c $LIBS
echo "built tools/rebuild_test/test.exe"
