# Changelog

## Unreleased

- Out of combat the second line rotates between the tracked quest, the place and the in-game day
  (`Day {day}`); the flavour lines (`state_filler`, plus `state_night` at night) show only when none of these is known.
  The place is no longer put in front of the activity, where it rarely fit.
- The main pawn line (`Pawn: {pawn_name}`) is no longer in the rotation.
- Combat rotates `Fighting: {enemy}`, `♥ {hp_percent}%` and `{condition}` (knocked down, or the worst affliction,
  Drenched included), starting with the enemy each time a fight begins. Being knocked down no longer replaces combat.
- The cover art tooltip lists every party pawn with their vocation (`{party_pawns}`, entry format `pawn_entry`),
  main pawn first.
- A line that is too long is cut before its ` - ` (`Seafloor Shrine - Sacred Grounds` -> `Seafloor Shrine`).
- The party size (`(4 of 4)`) is off by default (`show_party`).
- Character names no longer carry the favorability suffix other mods add to the game's name lookup
  (` - Normal (477.0)`).
- English: `Soaked` is now `Drenched`, as in the game.
- New placeholders: `{party_pawns}`, `{condition}`. New text keys: `state_filler`, `combat_rotation`, `pawn_entry`.
- The config upgrades automatically (version 9); lines you edited are kept, `show_party` is turned off once.

## 2.0.0

- The second line shows where you are and what you're doing: `{place} · {activity}`.
- New activities: climbing a monster (with its name), knocked down, fallen, afflictions, carrying, grappling, gliding.
- Small icon on the cover art: day / night, climbing, fallen.
- Place, in-game time and weather in the icon tooltip.
- The place is dropped when you leave its area (and after `place_timeout_min` outside towns).
- Lines are shortened to fit Discord's profile card (`max_line_length`) instead of being cut off.
- New placeholders: `{place}`, `{activity}`, `{climb_target}`, `{status}`, `{weather}`.
- The config upgrades automatically from 1.x and keeps your edited lines.

## 1.0.1

- Plugin DLL rewritten in plain C: 27 KB instead of 230 KB, one export, file version info, and it starts
  only when REFramework initializes it. This avoids the Windows Defender false positive some users saw.

## 1.0.0

- Initial release.
