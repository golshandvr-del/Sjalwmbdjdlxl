# Frontier mod — design notes (T006)

`mods/frontier/` is the first total-conversion content mod for Project Nexus. It
is enabled by default and adds a complete playable game on top of the engine:
a multi-tier tech tree, twelve units across six roles, twelve buildings including
defensive towers and walls, a second spendable resource (energy), and three
scenarios with hand-authored natural maps.

The engine features this mod relies on (prerequisites, production from any
building, forest terrain, ASCII maps, `hq_type`, scenario `rules`, defensive
buildings) are general and data-driven — see DEC-018 in `docs/ai/DECISIONS.md`.
Nothing in the engine special-cases the `frontier` mod.

## Faction

Every id is prefixed `fr_`. The scenario `rules.faction_prefix` value (`"fr_"`)
keeps the AI and the HUD inside the faction: a full-tree AI never picks a vanilla
`outpost` or `soldier`, and a vanilla scenario (no `rules` section) never picks
`fr_` content — that is what keeps the vanilla golden hashes unchanged (check A2).

## Resources

- `resource_basic` (displayed "Gold"): the main currency. Produced by the
  citadel and the lumber mill.
- `resource_energy` (displayed "Energy"): the advanced currency. Produced only by
  the power well and spent by the magic/siege/air units (mage, priest, ballista,
  catapult, paladin, wyvern).

## Building tree (prerequisite depth ≥ 4)

```
fr_citadel (HQ, tier 0)
├── fr_barracks      (tier 1)  -> militia, spearman, archer
├── fr_lumber_mill   (tier 1)  -> gold income
├── fr_watchtower    (tier 1)  -> defensive (attack_damage 12, range 4)
└── fr_wall          (tier 1)  -> cheap, tough, counts_for_survival: false

fr_lumber_mill
└── fr_power_well    (tier 2)  -> energy income

fr_barracks
├── fr_stable        (tier 2)  -> rider, lancer
└── fr_academy       (tier 3, also needs fr_power_well) -> mage, priest

fr_academy
├── fr_workshop      (tier 4)  -> catapult, ballista
└── (with fr_stable) fr_sanctum (tier 4) -> paladin

fr_workshop + fr_watchtower
└── fr_cannon_tower  (tier 5)  -> strong defensive (attack_damage 30, range 6)

fr_sanctum + fr_workshop
└── fr_dragon_roost  (tier 5)  -> wyvern
```

The longest building chain is `fr_citadel → fr_barracks → fr_academy →
fr_workshop → fr_dragon_roost` (depth 4); the cannon tower reaches depth 5 via
`fr_citadel → fr_watchtower → fr_cannon_tower` plus the workshop branch.

## Tech tree (`mods/frontier/data/tech/frontier_tech.json`)

```
fr_tech_woodcraft ──┬── fr_tech_arcane_study ──┐
                    │        (needs fr_academy)│
                    └── fr_tech_elite_guard     │
                         (needs fr_barracks)     │
fr_tech_fletching ────── fr_tech_siege_engineering ──┤
                    (needs fr_workshop)               │
fr_tech_lancer_training ── fr_tech_holy_order ────────┤
   (needs fr_stable)        (needs fr_sanctum)        │
fr_tech_fortifications ── fr_tech_advanced_logistics │
   (needs fr_watchtower)     (needs fr_power_well)    │
                                                       └── fr_tech_dragon_taming
                                                            (needs fr_dragon_roost)
```

Ten `fr_tech_*` nodes, three levels deep. Six of them require a completed
building (`requires_buildings`); the rest are gated only by other techs. Each has
a gold cost, a `research_time_ticks`, and a real effect (`unit_stat_add` or
`veterancy_bonus`).

## Units

| Unit | Category | Cost | Build (t) | HP | Dmg | Range | Vision | Speed | Value/cost |
|---|---|---|---|---|---|---|---|---|---|
| `fr_scout` | scout | 25 gold | 72 | 55 | 4 | 1 | 9 | 3 | 8.80 |
| `fr_militia` | infantry | 30 gold | 75 | 70 | 6 | 1 | 5 | 4 | 14.00 |
| `fr_priest` | magic | 45 gold + 15 energy | 82 | 90 | 8 | 2 | 7 | 2 | 15.00 |
| `fr_archer` | ranged | 50 gold | 85 | 65 | 12 | 3 | 6 | 2 | 23.40 |
| `fr_spearman` | infantry | 45 gold | 82 | 120 | 9 | 1 | 4 | 2 | 24.00 |
| `fr_rider` | cavalry | 70 gold | 95 | 140 | 14 | 1 | 5 | 3 | 28.00 |
| `fr_paladin` | cavalry | 120 gold + 20 energy | 120 | 220 | 18 | 1 | 6 | 2 | 28.29 |
| `fr_mage` | magic | 40 gold + 30 energy | 80 | 60 | 24 | 3 | 6 | 2 | 30.86 |
| `fr_wyvern` | air | 90 gold + 60 energy | 105 | 160 | 26 | 2 | 8 | 4 | 34.67 |
| `fr_lancer` | cavalry | 90 gold | 105 | 170 | 20 | 1 | 5 | 2 | 37.78 |
| `fr_ballista` | siege | 55 gold + 35 energy | 87 | 85 | 26 | 5 | 6 | 1 | 49.11 |
| `fr_catapult` | siege | 60 gold + 40 energy | 90 | 100 | 34 | 4 | 5 | 1 | 59.50 |

Roles: six categories (infantry, ranged, cavalry, siege, magic, air) plus the
scout. Six units spend energy. Three units are tech-gated: `fr_lancer`
(`fr_tech_lancer_training`), `fr_paladin` (`fr_tech_holy_order`), `fr_wyvern`
(`fr_tech_dragon_taming`). No unit strictly dominates another (check B24) and
every value-per-cost sits within 0.25x–4x of the median (check B25).

## Scenarios

The maps are produced by `tools/mapgen/frontier_mapgen.py` (Python 3, stdlib only,
deterministic seeded fractal value noise — no stamps). Running that script rewrites
the three `map.rows` grids byte-for-byte, so the committed maps are reproducible.

- `fr_river_valley` — 2 players (owner 0 human, owner 1 `smart` AI), 64×32 ASCII
  map: a **real winding river** that crosses the whole map (centreline sways more
  than 6 tiles, mean width 2–6) and is broken by **three land fords** so armies can
  cross; forest groves and rocky outcrops. Forest 15.5 %, water 7.1 %, rock 12.1 %
  (12 forest clusters, all distinct shapes). Both citadels sit on opposite banks.
- `fr_four_realms` — 4-player FFA, 80×48 ASCII map, one citadel in each corner
  region. One quadrant is generated organically and mirrored, then de-symmetrised,
  so it is 4-fold fair but the clusters are irregular. Forest 13.9 %, water 7.0 %,
  rock 8.0 % (21 forest clusters, all distinct shapes).
- `fr_border_siege` — 2 players, 64×32 ASCII map with a **central rock ridge with
  three passes** plus forest flanks (different layout from every other map, ≥ 25 %
  of tiles differ). Pre-placed watchtowers and walls (a tutorial in defensive
  play). Forest 15.0 %, rock 15.2 %, no water.

All three set `hq_type: "fr_citadel"` and
`rules: { full_ai: true, pop_cap: 45, faction_prefix: "fr_" }`.

## Full-tree AI

When `rules.full_ai` is true, the strategic AI (`strategic_ai` + `ai_commander`)
plays the whole tree via the pure, deterministic `FullTreeOrderUtil`:
it researches the cheapest reachable tech, builds the next reachable building in
tree order (economy → production → defense), and keeps a rotating unit queue on
its production buildings so the army is a real mix.

Each personality plays the tree differently, driven by the data table
`FullTreeOrderUtil.PERSONALITY_PLAN` (see DEC-019): a building-priority list, a
build-avoid list, a unit-mix preference and an attack-army threshold. `economic`
builds lumber mill/power well first and favours late units; `aggressive` builds
barracks/stable early, skips static defenses (watchtower/wall) and pushes earliest;
`defensive` (the 4th personality) fortifies first and masses the largest army.

Full-tree AIs hold their all-in until `FULL_TREE_MIN_ATTACK_TICK`, so a duel is a
build-up that reaches the late buildings and units rather than a rush. Without
`full_ai` the AI behaves exactly as before (vanilla golden hashes lock this).
