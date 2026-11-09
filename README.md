# Discord Rich Presence for Dragon's Dogma 2

Shows what your Arisen is doing in your Discord status, live from the game:

```
Playing Dragon's Dogma 2
Aldric · Warfarer · Lv. 108
Checkpoint Rest Town                         <- what you're doing (rotates)
14:50 elapsed
[cover art, hover: "Rook (Mage) · Brant (Fighter) · Ayla (Thief)"]
[small activity icon, hover: "Checkpoint Rest Town · 22:30 · Downpour"]
```

What you're doing, most telling first: fallen, `Climbing: Ox`, combat, knocked down, an affliction
(`Burning`, `Poisoned`, `Petrified`...), carrying / grappling / gliding, and otherwise a rotation of the quest set
as destination, the place and the in-game day (`Day 103`), with a flavour line when none of them is known.
In combat the line rotates between `Fighting: Griffin`, your HP (`♥ 82%`) and your condition (knocked down or
an affliction), starting with the enemy. Hovering the cover art lists your pawns and their vocations. The small
icon shows the time of day (sun or moon), or that you are climbing a monster or have fallen.

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

