# PunyAuras

A heavily trimmed-down WeakAuras for the World of Warcraft 1.12.1 client and
Unreal Azeroth.

## License and credits

PunyAuras is free software, licensed under the GNU General Public License
version 2 (see `LICENSE`).

It is derived from [WeakAuras](https://github.com/WeakAuras/WeakAuras2) by
the WeakAuras Team, also GPLv2. The options window follows the layout of
WeakAuras' own options window; the aura data model, the region types (icon,
progress bar, text, texture, progress texture, model, group, dynamic group)
and their options, the sub-region texts, the conditions, the chat message
actions, the text placeholders, the texture picker, the aura trigger, the
weapon enchant, health and power triggers, the spell, item and player info
triggers (cooldowns, items, experience, reputation, money, forms, talents,
location, pet, conditions), the load conditions, and the aura export and
import (transmission table, uids, import naming) are ports of WeakAuras'
own. The export string's format is PunyAuras' own, not WeakAuras'. These
textures are taken from WeakAuras unchanged:

| File | WeakAuras original |
|---|---|
| `Media/Textures/PunyAurasNewAura.tga` | `WeakAuras/Media/Textures/newaura.tga` |
| `Media/Textures/PunyAurasImport.tga` | `WeakAuras/Media/Textures/importsmall.tga` |
| `Media/Textures/PunyAurasMoveUp.tga` | `WeakAuras/Media/Textures/moveup.tga` |
| `Media/Textures/PunyAurasMoveDown.tga` | `WeakAuras/Media/Textures/movedown.tga` |

`Media/Textures/PunyAurasGroup.tga` and `PunyAurasDynamicGroup.tga` redraw
WeakAuras' default group and dynamic group icons
(`WeakAurasOptions/RegionOptions/Group.lua`, `DynamicGroup.lua`) as
textures.

The textures in `Media/Textures/Auras/` are WeakAuras' own, re-encoded
(same pixels, RGBA TGA) and renamed with a `PunyAuras` prefix:
`PunyAurasAura<n>.tga` is `WeakAuras/PowerAurasMedia/Auras/Aura<n>.tga`
(the Power Auras textures WeakAuras ships), and the others
(`PunyAurasCircle_*`, `PunyAurasSquare_*`, `PunyAurasRing_*`,
`PunyAurasTriangle45`, `PunyAurasSquare_Border_5px`) are the shapes of
the same names (`square_border_5px` in lower case) in
`WeakAuras/Media/Textures/`.
