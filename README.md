# Statecraft (Diplomacy, Espionage, Faction Reworks) [Submod TR 3.51]

Source code for Statecraft, my submod for Thrawn's Revenge 3.5 (Empire at War: Forces of Corruption).
The mod itself is on the Steam Workshop.

## What's here

- `engine/` - source for `POWRPROF.dll`, the DLL the mod needs. `hooks/enginehook.c` is the engine hook,
  `hooks/rebuild.c` and the `rb*` files put the mod's files together on your PC.
- `generators/` - Lua scripts the DLL runs to build files from your own Thrawn's Revenge install.
- `mod/` - the mod's scripts and XML, as released.

`engine/tools/` is unmodified third-party code (MinHook, Lua 5.5, Pillow's imaging core, minimp3).

## The DLL

The game loads `POWRPROF.dll` from its own folder. Mine passes the real Windows call through and adds what the
mod needs: Lua `math`, script data in saves, clicks on the mod's windows, allied fleets in battles,
reinforcements, hyperlane colours and a few engine fixes.

- Does nothing unless Statecraft is in the launch options.
- Patches nothing if your StarWarsG.exe isn't the version it was made for.
- Only writes to the mod's own folder. No network access, no self-updates.
- To remove it, delete `POWRPROF.dll` from the `corruption` folder.

The mod ships no Thrawn's Revenge files. `Data\Rebuild.rcp` holds recipes that build them from your own install
on first start, and the DLL checks the results before the mod uses them.

## Build it yourself

The build is reproducible, so you can check the DLL in the mod is this code:

1. Install [WinLibs](https://winlibs.com) GCC 16.2.0 (x86_64, UCRT, POSIX threads, r1) and Git for Windows.
2. Run `bash build.sh` in `engine/`.
3. Compare `certutil -hashfile engine/hooks/POWRPROF_release.dll SHA256` with the hash at the end of the mod's
   README.txt.

`hooks/POWRPROF.dll` is my test build (extra logging and test commands) and never ships.

## License

My code is GPL-3.0 (`LICENSE`). Third-party code keeps its own license: MinHook (BSD 2-Clause), Lua (MIT),
Pillow (MIT-CMU), minimp3 (CC0).
