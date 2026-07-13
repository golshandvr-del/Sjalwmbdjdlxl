# Modding Guide -- Project Nexus

Project Nexus is **data-driven**: units, buildings, tech, scenarios and now
their **visuals** are defined in JSON, not hardcoded. A mod is just a folder of
JSON (and optional textures) that **adds to** or **overrides** the base
catalogs. The engine never changes.

This document covers the **visual schema** (Phase B), the **"play-dough"
principle**, and how to ship a mod.

---

## 1. The visual schema (Phase B.1)

Every unit and building JSON may carry an **optional** `visual` block:

```json
"visual": {
  "shape": "circle|square|sprite",
  "color": "#4CB0F2",
  "texture": "textures/soldier.png",
  "size_scale": 1.0,
  "outline": true
}
```

| Field        | Meaning                                                                 |
|--------------|-------------------------------------------------------------------------|
| `shape`      | Fallback shape when no texture resolves (`circle`, `square`, `sprite`). |
| `color`      | Hex color: shape fill, and a tint for the texture. Falls back to owner color. |
| `texture`    | Relative path resolved by the `TextureService` (base `assets/` or a mod root). |
| `size_scale` | Multiplier on the drawn size (1.0 = one tile).                          |
| `outline`    | Whether to draw a contrast outline (style-dependent).                   |

**Golden rule (Design Philosophy #1):** the `visual` block is **cosmetic only**.
It is never read by the simulation and never affects the deterministic world
hash. Switching styles or editing a texture cannot desync a multiplayer match.
This is enforced by a headless regression test (`test_visual_*`).

The renderer has three interchangeable styles behind the `RenderAdapter`:
`simple` (flat shapes), `detailed` (shaded shapes), and `sprite` (textures from
the `visual` block, Phase B.4). The in-game **Style** button cycles them.

---

## 2. The "play-dough" principle (Phase B.6)

Because behaviour comes from **stats** and look comes from **visual**, the SAME
building schema becomes completely different things just by editing JSON:

| Want a...      | Set stats                                  | Set visual                         |
|----------------|--------------------------------------------|------------------------------------|
| **Wall**       | very high `health`, no `attack_*`          | `texture: wall_block.png`          |
| **Turret**     | `attack_damage` + `attack_range`           | `texture: turret.png`              |
| **Generator**  | `produces.resource_basic`                  | any texture                        |

The shipped `mods/playdough_demo` mod proves this: `raw_wall.json` (2000 HP, no
attack) and `raw_turret.json` (same schema + `attack_range: 5`) are both just
buildings with different numbers and textures. It is **disabled by default**
(`"enabled": false` in its `mod.json`); flip that to `true` to load it.

---

## 3. Anatomy of a mod

```
mods/<your_mod>/
  mod.json                       # manifest (see below)
  data/units/<id>.json           # added/overridden units
  data/buildings/<id>.json       # added/overridden buildings
  data/stats/<id>.json           # NEW (MD1): added/overridden stat definitions
  textures/<name>.png            # mod-supplied art (referenced by visual.texture)
```

### Defining a stat as data (MD1)

Stats are no longer hard-coded: each one is a small data record the engine merges
on top of its built-in Core stats. A mod can override a Core stat's metadata or
add a brand-new "Free" stat that the AI understands automatically (via `affects`,
see MD2) without any code change. A stat definition file looks like:

```json
{
  "id": "armor",
  "type": "int",
  "category": "defense",
  "min": 0,
  "max": 1000,
  "default": 0,
  "higher_is_better": true,
  "ai_importance": 0.7,
  "display_name_key": "stat.armor.name",
  "affects": { "survivability": 0.8, "holding_power": 0.5 }
}
```

| Field | Meaning |
|-------|---------|
| `id` | unique stat id (matches the key used in a unit/building `stats` dict) |
| `type` | `int` or `float` (floats are allowed on disk; the AI path uses fixed-point) |
| `category` | grouping label: `combat` / `defense` / `mobility` / `economy` / … |
| `min` / `max` / `default` | value bounds + fallback when a unit omits the stat |
| `higher_is_better` | direction of "good" (used by the AI valuation) |
| `ai_importance` | 0..1 hint of how much the AI should weigh this stat |
| `affects` | map `capability_id -> weight` binding the raw stat to AI capabilities |

The registry validates each definition (`validate_definition`) and rejects
unknown keys, `min > max`, a bad `type`, or a malformed `affects` map with a
human-readable reason for the mod editor. Core stats keep working even if you
ship no `data/stats/` folder at all.

`mod.json`:

```json
{
  "id": "your_mod",
  "name": "Your Mod",
  "version": "0.1.0",
  "author": "You",
  "enabled": true,
  "load_after": ["other_mod"],
  "provides": {
    "buildings": ["data/buildings/raw_wall.json"]
  }
}
```

The `ModLoader` discovers every mod, resolves a **deterministic load order**
from `load_after` (stable topological sort, ties by id), and **merges** each
mod's entries into the base catalogs (last-writer-wins). Same mod set on every
machine -> identical catalogs -> still lockstep-safe.

---

## 4. Where textures come from

The `TextureService` (Phase B.2) resolves `visual.texture` against an ordered
list of roots:

1. base game: `res://assets/textures/`
2. registered mod roots (added at load time; most-recent wins)

A missing texture resolves to a visible magenta/black placeholder instead of
crashing -- so a half-finished mod still runs.

> **Coming next (Phase C):** `.nexpack` -- a single ZIP (manifest + `data/` +
> `textures/`) that bundles a whole mod into one portable file, loaded directly
> without unpacking. Phase D adds a graphical in-game **Mod Editor** that writes
> these packs for you.

---

## 5. Advanced entities (Phase E2-E6 -- the modular editor)

The advanced Mod Editor authors richer entities. Everything below is **optional**:
an entity with only the Phase B `visual` block still works. The new blocks are
written by the editor, but you can hand-write them too.

### 5.1 The `graphic` block (layered pixel art)

```jsonc
"graphic": {
  "mode": "single",                 // "single" or "multi"
  "logical_size": { "w": 1, "h": 1 }, // TILES -- the ONLY field the sim reads
  "parts": [                          // 1..3 cosmetic layers, biggest first
    { "layer": 1, "px": { "w": 64, "h": 64 }, "texture": "textures/body.png" }
  ]
}
```

Rules (validated before save): PNG only, 16x16 .. 512x512; a higher layer can
never be larger than the layer beneath it. **Pixel sizes are cosmetic** -- only
`logical_size` affects collision / the deterministic hash.

### 5.2 Multi-part bodies + the compatibility matrix

A multi-part unit/building carries `part_stats[]` (one stats dict per layer). Two
parts may **not** share a stat *group* (combat / defense / mobility / economy /
vision) -- so one part is the weapon, another the engine, etc. Buildings are the
one exception: **every** building part must carry `health` + `armor`
(independently destructible). Only multi-part entities may set `"fusable": true`.

### 5.3 `upgrade` and `buildable`

```jsonc
"upgrade": {
  "trigger": { "type": "kill_count", "value": 50 },
  "effects": { "stat_add": {}, "stat_mul": {} },
  "visual_change": { "px": { "w": 68, "h": 68 } }  // capped at +15% of base layer
},
"buildable": { "from_building": "barracks", "cost": { "resource_basic": 50 },
               "materials": [], "required_tech": "" }
```

### 5.4 The `objects` catalog (map decorations + resource nodes)

A new catalog `data/objects/<id>.json`. A decorative object just needs a
`graphic` + `placement` (`land` / `sea` / `both`). An **extractable** resource
node must declare a yield:

```jsonc
{ "id": "iron_ore", "placement": "land", "extractable": true,
  "yields": { "material": "iron", "rate": 3 },
  "graphic": { "mode": "single", "logical_size": { "w": 1, "h": 1 }, "parts": [ ... ] } }
```

### 5.5 Sea + coastline on maps

A scenario map gains a `sea` cell list beside `walls`:

```jsonc
"map": { "width": 32, "height": 24, "walls": [...], "sea": [ [3,3], [4,4] ] }
```

The shoreline is **never stored** -- it is computed render-only from the sea map
(`tools/coast_autotile.gd`), so painting a coast cannot change the simulation.
Scenarios may also list placed objects: `"objects": [ { "object": "iron_ore",
"x": 6, "y": 6 } ]`.
