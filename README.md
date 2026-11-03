# Discord Rich Presence for Dragon's Dogma 2

Shows what your Arisen is doing in your Discord status, live from the game:

```
Playing Dragon's Dogma 2
Aldric · Warfarer · Lv. 108
Checkpoint Rest Town · Pawn: Rook (4 of 4)   <- place · what you're doing
14:50 elapsed
[cover art + small activity icon, hover: "Checkpoint Rest Town · 22:30 · Downpour"]
```

What you're doing, most telling first: fallen, knocked down, `Climbing: Ox`, `Fighting: Griffin`,
an affliction (`Burning`, `Poisoned`, `Petrified`...), carrying / grappling / gliding, and otherwise a rotation of
your main pawn, the quest set as destination and a flavour line. The small icon shows the time of day
(sun or moon), or that you are climbing a monster or have fallen.

Starts and stops with the game. No external program, no Python. Requires REFramework.

## Requirements

- [REFramework](https://www.nexusmods.com/dragonsdogma2/mods/8) (tested with 1.5.9.1)
- The Discord **desktop** app running on the same PC, with activity sharing turned on
  (User Settings → Activity Privacy)


## Building from source

The DLL is plain C (Windows API and the C runtime only, one export) and is built with
[Zig 0.13](https://ziglang.org/download/), a self-contained C compiler:

```
./build.ps1 -Zig C:\path\to\zig.exe -Release
```

Sources: `plugin/DiscordPresence.c` (plugin), `plugin/DiscordPresence.rc` (file version info),
`DiscordPresence.lua` (game side), `modinfo.ini`, `build.ps1`.

## License

[MIT](LICENSE) © 2026 JustS73. The cover art shown in Discord is not part of this repository.

