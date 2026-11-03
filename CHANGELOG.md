# Changelog

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
