# Project Nexus

A **modular, open-source, cross-platform top-down 2D strategy game** built on a
**Central Brain (Nexus)** architecture. All gameplay modules communicate through
an **Event Bus** and share a single **World State**, making the game highly
moddable, extensible, deterministic, and ready for local + online multiplayer.

- **Engine:** Godot 4.x (GDScript core; C++/GDExtension only for hot paths later)
- **Genre:** Hybrid RTS + Turn-based via an "Active Pause" mechanic
- **Visual roadmap:** simple (Mindustry-style) -> detailed (MOWAS-style)
- **Platform priority:** Android -> iOS -> Windows/macOS/Linux

> **Code Language Policy:** the entire codebase is English-only. See
> [`docs/CODE_POLICY.md`](docs/CODE_POLICY.md). Non-English text is permitted
> **only** inside `localization/` files, referenced through English keys.

---

## Roadmap target: v0.6.0 (READ THIS FIRST)

The authoritative plan lives in **[`docs/STRUCTURE.md`](docs/STRUCTURE.md)** (the
single source of truth for architecture, known bugs, the ordered v0.6.0
requirements `R#`, and the executable phase plan `P0`..`P8`). For a fast
"where in the code" lookup, see **[`docs/CODE_MAP.md`](docs/CODE_MAP.md)**.

> **Status note (v0.6.0, phase `P9-FIX`):** the v0.6.0 effort is code-complete
> and **CI is now green**. The critical gameplay bugs (resource runaway, units
> spawning on the HQ, movement not working, no zoom/pan, weak visuals) are fixed,
> and the match-setup menu, save/load, export/import, LAN multiplayer with auto
> mod-sync, control groups, minimap, portrait/landscape layout, HQ/flag
> placement, and the fully-rewritten Mod Editor UI (tree / multi-part / graphic
> upload / object editor) are all wired. The P9 QA pass found 11 issues; **all 11
> (plus one sibling finding) have since been fixed** (the standalone bug report was
> retired in commit 7dc53a6; its history lives in `docs/STRUCTURE.md`).
>
> Latest headless run (Godot 4.7.2, also enforced by GitHub Actions CI):
> - **Tests:** `Total: 4544 | Passed: 4544 | Failed: 0 | Skipped: 0 | Exit: 0` ✅
> - **CODE_POLICY linter:** `246 files scanned | No violations | Exit: 0` ✅
> - **Smoke:** scene smoke `failures=0`, game smoke `failures=0`, exported pack boots.
>
> See `docs/STRUCTURE.md` sections 3 (bugs), 4 (requirements), 5-8 (phases), and
> `docs/ai/PROJECT_STATE.md` for the current verified state.

> **Android fix rounds (MA + MB) — COMPLETE.** After the v0.6.0 QA pass, the
> user reported two rounds of Android-specific bugs, tracked in
> [`docs/PLAN_ANDROID_FIXES.md`](docs/PLAN_ANDROID_FIXES.md) (round 1, `MA1`..`MA7`,
> 11 bugs) and [`docs/PLAN_ANDROID_FIXES_V2.md`](docs/PLAN_ANDROID_FIXES_V2.md)
> (round 2, `MB1`..`MB10`, 29 bugs). **Both rounds are fully fixed** (own-unit
> control, pause destination markers, fog-aware minimap, setup labels + solo AI
> team grouping + corner settings gear, Android BACK-key routing,
> orientation/auto-scale/responsive GUI redesign, deep multiplayer-lobby rework
> (ready round-trip, bots visible to joiners, re-join teardown, read-only client
> view), host-IP display + LAN auto-scan, Map Editor rebuild, Mod Editor
> 3-part/image-ratio validation + `user://` build stability, LAN-no-TLS policy +
> RGBA8 image normalization, and a global loading overlay). A handful of items
> can only be *finally* confirmed on a physical Android build — those are listed
> under "نیازمندِ تأییدِ روی دستگاهِ اندروید" at the bottom of
> `docs/PLAN_ANDROID_FIXES_V2.md`.

> **Feature round (MC) + AI/Stat re-architecture round (MD).** Round 3
> ([`docs/plan_android_fix_v3.md`](docs/plan_android_fix_v3.md), phases
> `MC1`..`MC14`, 18 requests) added deep gameplay, dynamic diplomacy, the 35-knob
> AI personality vector, and the builder tools. Round 4
> ([`docs/plan_android_fix_v4.md`](docs/plan_android_fix_v4.md), phases
> `MD1`..`MD14`) is a **foundational re-architecture** implementing an expert AI's
> two-part design: (1) **stats as data assets** (not hard-coded) with a fixed
> engine-side **Capability layer** they map onto via `affects`, and (2) a
> **multi-layer deterministic AI decision pipeline** — `Raw Stats -> Derived
> Metrics/Capabilities -> Role Inference -> Personality Weights + Policy ->
> Context -> Utility Scoring -> Staged Action Selection -> Learning`. All decision
> math is fixed-point (`SCALE=1000`) for lockstep safety. See that plan for the
> full phase breakdown, the expert-opinion critique, and the determinism rules.
>
> **Status:** Round 4 (`MD1`..`MD14`) is **code-complete**. The AI now selects
> units/buildings by data-driven *capability* utility (no more hard-coded
> `"soldier"`), a mod's new Free stat is understood with **zero engine code**
> (proven by the `test_md14_*` round-trip tests), and the whole decision path is
> fixed-point so dynamic stats never break lockstep. The end-to-end data-flow
> diagram lives in [`docs/CODE_MAP.md`](docs/CODE_MAP.md) section 2.5, and the
> architecture summary in [`docs/STRUCTURE.md`](docs/STRUCTURE.md) section 1.2.

---

## Architecture -- The Central Brain ("Nexus")

The Nexus has **no gameplay of its own**; it is a pure coordinator. Core
components (all in `core/`):

| Component | File | Responsibility |
|---|---|---|
| **Nexus** | `core/nexus.gd` | Autoload singleton; wires everything and drives the tick loop |
| **Event Bus** | `core/event_bus.gd` | Decoupled publish/subscribe communication |
| **World State** | `core/world_state.gd` | Single source of truth (serializable sections) |
| **Module Registry** | `core/module_registry.gd` | Module lifecycle (init/tick/event/shutdown) |
| **Sim Clock** | `core/sim_clock.gd` | Deterministic tick clock + Active Pause |
| **Command Queue** | `core/command_queue.gd` | Player/AI commands (lockstep basis) |
| **Data Loader** | `core/data_loader.gd` | Data-driven content loading (JSON + mods) |
| **Save System** | `core/save_system.gd` | Serialize/restore the whole game to JSON |
| **IModule** | `core/i_module.gd` | The standard module contract |

**Golden rule:** no module references another module directly. Everything goes
through `Nexus.event_bus` and `Nexus.world_state`.

---

## How to Run (Godot 4.x)

> This repository is a real Godot project. Open it in the Godot Editor; the
> sandbox that generated it does not run Godot itself.

1. Install **Godot 4.7+** (verified with 4.7.2).
2. Open `project.godot` in the Godot Editor.
3. Press **Play** (F5). The main scene is now `scenes/main_menu.tscn` -- the
   **Main Menu / Lobby** (Phase 5). From it you can:
   - **Single Player (Desktop)** -> `scenes/game_desktop.tscn` (keyboard + mouse).
   - **Single Player (Mobile)** -> `scenes/game_main.tscn` (touch UI).
   - **Host Game** / **Join Game** -> an online lockstep match over ENet
     (`NetworkSession` + `EnetTransport`; same deterministic core as local play).
   - **Language** -> switch the entire UI between English and Persian live.
4. In the **playable skirmish** (Phase 1 core + Phase 2 strategic depth):
   - Select friendly (blue) units, move them, and command your HQ.
   - **Mobile UI:** tap a unit to select (tap more to build a squad), tap ground
     to move; on-screen buttons for Build/Research/Upgrade/Fuse/Pause/Speed/Style.
   - **Desktop UI:** left-click / drag-box to select (Shift to add), right-click to
     move, WASD/arrows to pan, mouse-wheel to zoom; hotkeys
     Space=Pause, B=Build, R=Research, U=Upgrade, F=Fuse, Tab=Speed, V=Style,
     L=Language.
   - **Research** starts the next affordable tech; **Upgrade HQ** levels it up;
     **Fuse Hero** merges a selected squad into a powerful Hero.
   - **Pause** = Active Pause (you can still queue commands), **Speed** cycles
     1x/2x/4x. **Style** flips the simple/detailed render look.
   - **Fog of war** hides unscouted ground and enemy units until you explore.
   - A deterministic **AI opponent** (red) builds and attacks.
   - Destroy the enemy HQ to win; lose yours and it's game over.
5. To inspect the core instead, set the main scene to `scenes/debug_main.tscn`
   (the Phase 0 Debug Console: registered modules, live tick, event log, and
   Pause/Step/Save/Load buttons).

### Tooling: the English-only CODE_POLICY linter (Phase 5)

```bash
godot --headless --path . --script res://tools/check_code_policy.gd
```
Exit code `0` = clean, `1` = a non-ASCII character was found outside the allowed
`localization/` files. This is the same check CI runs (`.github/workflows/ci.yml`).

### Running the unit + integration tests (headless)

```bash
godot --headless --path . --script res://tests/test_runner.gd
```
Exit code `0` = all tests passed, `1` = some failed. Current suite: **4544
checks in 610 test functions** (Godot 4.7.2; the phase notes below keep their
historical counts) covering EventBus, ModuleRegistry, SimClock, CommandQueue, WorldState,
PathService, Map, Economy, Combat, Units movement, the AI commander, the
victory rule, and full deterministic battle replays (human-vs-AI and AI-vs-AI),
**the full Phase 2 strategic layer** (tech-tree research + prerequisites +
effects, building construction + upgrade trees, logistics/caravan supply, fog of
war visibility, difficulty presets (+ custom presets that survive save/load),
hero fusion recipes, veterancy promotion, and a deterministic Phase 2
integration replay), **and the full Phase 3 layer**: the deterministic
`StateHasher` checksum, the strategic (macro) AI brain (expand / research /
upgrade / mass-then-push + determinism), lockstep multiplayer (tick gating,
command injection, desync detection, and a two-peer loopback match that ends on
identical world hashes), and the data-driven mod pipeline (discover / load-order
/ merge / enable-disable), **and the full Phase 4 layer**: both render styles
drawing against a headless recording canvas, the detailed style as a drop-in for
the simple one, runtime style switching proven cosmetic-only (world hash
unchanged), the `EnetTransport` interface matching `LoopbackTransport`, two peers
staying in sync over a swapped (non-loopback) transport, and `NetworkSession`
deterministic seeding + session start.

Note on running headless: the test runner relies on Godot's global class
registry. If you run a fresh checkout and see `Could not find base class
"IModule"`, open the project in the editor once (or run `godot --headless
--editor --quit`) so Godot writes `.godot/global_script_class_cache.cfg`, then
re-run the command above.

> **Current CI status: GREEN.** GitHub Actions (`.github/workflows/ci.yml`, Godot
> 4.7.2) runs six gates: lint, tests (`Total: 4544 | Passed: 4544 | Failed: 0`),
> scene smoke, game smoke, clean-tree check and exported-pack boot. Gate details:
> `AGENTS.md` section 4.

---

## Project Status

### Phase 0 -- Foundation [DONE] COMPLETE
The project skeleton and the central brain, with a Test Module proving the
architecture. See the structure document and `docs/` for the full roadmap.

- [x] 0.1 Empty Godot project (`project.godot`)
- [x] 0.2 Full folder structure with `.gitkeep`
- [x] 0.3 Git repo + Godot `.gitignore` + initial commit
- [x] 0.4 `docs/CODE_POLICY.md` added and referenced here
- [x] 0.5 `IModule` contract (`core/i_module.gd`)
- [x] 0.6 `EventBus` (publish/subscribe)
- [x] 0.7 `ModuleRegistry`
- [x] 0.8 `WorldState`
- [x] 0.9 `SimClock` (tick-based + active pause)
- [x] 0.10 `Nexus` wiring everything together (+ `CommandQueue`, `SaveSystem`)
- [x] 0.11 Minimal `DataLoader` (JSON)
- [x] 0.12 `TestModule` proving the architecture
- [x] 0.13 Debug scene with on-screen event log
- [x] 0.14 Unit tests for EventBus, ModuleRegistry, SimClock (+ more)

### Phase 1 -- Playable Core (Mindustry-style) [DONE] COMPLETE
A fully playable single-player skirmish with simple graphics.

- [x] 1.1 `Map` module: grid stored in `WorldState`
- [x] 1.2 Deterministic A* pathfinding (`core/path_service.gd`)
- [x] 1.3 `Units` data definitions (`data/units/*.json`)
- [x] 1.4 `Units` module: spawn, deterministic per-tick movement
- [x] 1.5 Unit selection + move command (via `CommandQueue`)
- [x] 1.6 `Buildings` module + HQ placement
- [x] 1.7 `Economy` module: resources + production tick
- [x] 1.8 `Combat` module: damage resolution + death events
- [x] 1.9 `RenderAdapter` (reads `WorldState`, never writes)
- [x] 1.10 `style_simple`: flat-shape Mindustry-style renderer
- [x] 1.11 Mobile UI: touch select / move / build
- [x] 1.12 **Active Pause** wired into the UI
- [x] 1.13 Data-driven skirmish scenario (`data/scenarios/skirmish_basic.json`)
- [x] 1.14 Integration test: deterministic battle from a fixed seed

### Bonus (Phase 3 head-start) -- a real opponent + win/lose [DONE]
So the skirmish is actually winnable end-to-end:

- [x] `AiCommanderModule` (`modules/ai_commander/`): deterministic AI that
  produces soldiers and marches idle units at the nearest enemy. Difficulty
  presets: `easy` / `normal` / `hard` (set per player in the scenario).
- [x] `VictoryModule` (`modules/victory/`): elimination + victory/draw
  detection, emitting `match.over`; the HUD shows a Victory/Defeat overlay
  with a **Play Again** button.

All core + Phase 1 + AI/victory tests pass headlessly.

### Phase 2 -- Strategic Depth [DONE] COMPLETE
The strategic layer that turns the skirmish into a real game of decisions. Every
system is data-driven, event-bus-only, deterministic, and tested headlessly.

- [x] 2.1 `TechTree` module (`modules/tech_tree/`): per-player research with
  resource cost + timed progress, driven by `research_tech` commands
- [x] 2.2 Tech **prerequisites** + **effects** (e.g. `improved_weapons` buffs
  living units *and* future spawns; `advanced_optics` needs `improved_armor`)
- [x] 2.3 `Buildings` construction sites (cost charged, timed build, no
  production until complete)
- [x] 2.4 **Building upgrade tree** (`upgrade_building`): paid + timed level-ups
  raising max health and production; concurrent upgrades rejected
- [x] 2.5 `Logistics` module (`modules/economy/logistics_module.gd`): caravan
  supply routes between a player's command buildings
- [x] 2.6 `FogOfWar` module (`modules/fog_of_war/`): per-viewer visible/explored
  tile tracking from unit + building vision
- [x] 2.7 Fog wired into the `RenderAdapter` (local player is the viewer; enemy
  units stay hidden until scouted, explored-but-unseen tiles are dimmed)
- [x] 2.8 `Difficulty` module (`modules/difficulty/`) reading
  `data/difficulty_presets/*.json` (easy / normal / hard)
- [x] 2.9 Difficulty drives AI cadence + resource multipliers via the scenario
- [x] 2.10 **Custom difficulty presets** definable at runtime
- [x] 2.11 Custom selection + definitions **survive save/load** (serialize)
- [x] 2.12 `HeroFusion` module (`modules/hero_fusion/`) reading
  `data/tech/*` hero recipes
- [x] 2.13 `fuse_units` command: a matching squad is consumed and reborn as one
  Hero (with starting veterancy), emitting `hero_fusion.completed`
- [x] 2.14 **Veterancy**: units gain ranks from kills (Combat module), raising
  their stats as they survive
- [x] 2.15 Phase 2 **HUD controls**: Research / Upgrade HQ / Fuse Hero buttons,
  squad-building tap selection, and a tech-count readout
- [x] 2.16 Phase 2 **localization keys** for all new UI / unit / building / tech
  / difficulty / recipe labels (`localization/en.json`)
- [x] 2.17 **Core fix:** commands are now delivered exactly once via the Event
  Bus (removed a double-dispatch that double-spent resources / duplicated
  spawns / stacked tech effects)
- [x] 2.18 Scenario loader wires difficulty + registers human fog viewers

All **97** core + Phase 1 + Phase 2 tests pass headlessly and the full Phase 2
match replay is bit-for-bit deterministic.

### Phase 3 -- Smart AI & Multiplayer [DONE] COMPLETE
The intelligence + connectivity layer. A high-level AI brain, deterministic
lockstep netcode for local **and** online multiplayer, and a real mod pipeline.
Every piece is event-bus-only, fully deterministic, and tested headlessly.

- [x] 3.1 `StrategicAiModule` (`modules/ai_commander/strategic_ai_module.gd`):
  a **macro** planning brain that sits ABOVE the tactical `AiCommander`. Per
  controlled player, on fixed tick boundaries, it runs a prioritized plan --
  **research** the next useful tech, **expand** with outposts up to a cap,
  **upgrade** the HQ when rich, and (the key behaviour) **mass an army then
  commit to a coordinated all-in push**, switching its posture between `build`
  and `attack`. Opt in per scenario player with `"smart": true` and an optional
  `"personality"` (`economic` / `balanced` / `aggressive`). Uses **no real RNG**
  (sorted keys + tick-derived decisions only) so it stays lockstep-safe.
- [x] 3.2 `StateHasher` (`core/state_hasher.gd`): a **stable, insertion-order-
  independent** FNV-1a checksum of the `WorldState`, the cornerstone of desync
  detection. Per-peer/local sections (e.g. `lockstep`) are excluded so two
  in-sync peers never falsely diverge.
- [x] 3.3 `LockstepModule` (`modules/multiplayer/lockstep_module.gd`): classic
  **scheduled-turn lockstep** on top of the existing Command Queue. Commands
  issued on tick `T` execute on `T + input_delay` on every peer; a tick is only
  simulated once **all** peers have confirmed it (`can_simulate_tick`), and
  peers periodically exchange world checksums so a desync is surfaced
  immediately as a `lockstep.desync` event. Same seed + same commands => same
  world on every machine -- tiny bandwidth (commands only).
- [x] 3.4 `LoopbackTransport` (`modules/multiplayer/loopback_transport.gd`): a
  transport adapter that wires several lockstep peers together **in process**.
  This is literally the production transport for **local** multiplayer
  (hot-seat / split control) and the test harness for replays. An **online**
  transport (Godot `MultiplayerAPI` / ENet) implements the same two
  `broadcast_*` methods, so local and online share 100% of the deterministic
  core.
- [x] 3.5 Bootstrap registers `strategic_ai` (before the tactical commander) and
  `multiplayer` (inert in single-player); the scenario loader activates the
  strategic brain for `"smart"` AI players.
- [x] 3.6 `ModLoader` (`core/mod_loader.gd`): the data-driven **mod pipeline**.
  Scans `mods/`, reads each `mod.json` manifest, resolves a **deterministic
  load order** from `load_after` (stable topological sort, ties by id),
  honours `enabled`, and **merges** each mod's JSON into the base catalogs
  (last-writer-wins, identical on every machine -> still lockstep-safe). The
  shipped `mods/example_mod` adds a `heavy_soldier` unit to demonstrate it.
- [x] 3.7 Bootstrap applies mods after the base catalogs (`load_catalogs` ->
  `load_mods`) and records the loaded mod ids in `WorldState`.

All **138** tests (97 prior + the new Phase 3 suite) pass headlessly; the
strategic-AI run is bit-for-bit deterministic and two lockstep peers exchanging
only commands end on identical world hashes with no desync.

### Phase 4 -- Visual Upgrade & Online Transport [DONE] COMPLETE
The polish + connectivity layer. A richer **detailed (MOWAS-style)** render
style slotting in behind the existing `RenderAdapter`, and a concrete
**ENet / `MultiplayerAPI`** online transport implementing the exact same
interface as `LoopbackTransport`, so the deterministic lockstep core goes online
**without a single line of game logic changing**. A second display language
(`fa`) is added to exercise the localization pipeline end-to-end.

- [x] 4.1 `StyleDetailed` (`render/style_detailed/style_detailed.gd`): a
  richer presentation strategy with the **identical duck-typed interface** as
  `StyleSimple` (`draw_tile` / `draw_building` / `draw_unit` / `owner_color`).
  It adds a subtle textured ground checkerboard, beveled/shaded buildings with
  **level pips**, rounded unit bodies with an **outline + selection ring**,
  **veterancy rank pips**, a **move-order line** to the unit's target, and a
  three-zone (green/amber/red) **health bar**. Pure cosmetics -- it never reads
  or writes simulation state.
- [x] 4.2 `RenderAdapter` **style switching**: `set_style("simple"|"detailed")`
  and `toggle_style()` swap the active style at runtime with **zero** changes to
  any game logic (the whole point of Logic/Render Separation). A **Style** HUD
  button (`ui/mobile/game_hud.gd` + `scenes/game_main.tscn`) flips the look live.
- [x] 4.3 `EnetTransport` (`modules/multiplayer/enet_transport.gd`): the concrete
  **online** transport built on Godot's `ENetMultiplayerPeer` / `MultiplayerAPI`.
  It exposes the **same** `broadcast_turn` / `broadcast_checksum` contract the
  lockstep core already consumes from `LoopbackTransport`, plus `host` / `join` /
  `close` / `peer_ids` / `local_peer_id` / `is_host`. Turn + checksum packets are
  delivered to every peer except the author, so the deterministic core runs
  online unchanged -- same seed + same commands => identical world on every
  machine, commands-only bandwidth.
- [x] 4.4 `NetworkSession` (`modules/multiplayer/network_session.gd`): a tiny,
  UI-facing coordinator that turns "host a match" / "join a match" into a running
  lockstep session. The host decides the seed + peer set and auto-starts once the
  lobby fills; a joining client begins its session on connect. It owns the
  transport but only ever calls the **transport-agnostic** surface, so any
  conforming transport (including a test stub) is a drop-in.
- [x] 4.5 `localization/fa.json`: a full Persian translation of every UI / unit /
  building / tech / scenario key, proving the **localization pipeline** is truly
  data-driven and language-agnostic (the only place non-English text is allowed).
- [x] 4.6 New UI/net **localization keys** (`ui.game.style*`, `ui.net.*`) added to
  `en.json` (and mirrored in `fa.json`).

All **176** tests (138 prior + the new Phase 4 suite) pass headlessly. The
Phase 4 suite proves: both render styles emit drawing primitives against a
headless recording canvas; the detailed style is a method-for-method drop-in for
the simple one; runtime style switching **never mutates the world hash**
(cosmetic-only); `EnetTransport` is interface-compatible with `LoopbackTransport`;
two lockstep peers stay **bit-for-bit in sync over a swapped (non-loopback)
transport** with no desync; and `NetworkSession.begin_session()` seeds the world
deterministically and starts lockstep across the agreed peer set.

### Phase 5 -- Tooling, Desktop UI & Export [DONE] COMPLETE
The developer experience and shippable build layer:
- [x] 5.1 **CI/lint check** enforcing the English-only `CODE_POLICY`
  (`tools/check_code_policy.gd`): scans every source file, exempts only
  `localization/`, reports `file:line:col` of any non-ASCII character, and exits
  non-zero on a violation. Wired into `.github/workflows/ci.yml` as a gate that
  runs alongside the headless test suite on every push / pull request.
- [x] 5.2 **Localization service** (`core/localization.gd`): a data-driven
  English-key -> display-text resolver that loads every `localization/*.json`,
  switches locale at runtime, falls back to the key when a string is missing,
  and cycles locales deterministically (English <-> Persian).
- [x] 5.3 **Desktop (keyboard/mouse) HUD** (`ui/desktop/desktop_hud.gd` +
  `scenes/game_desktop.tscn`): WASD/arrow camera pan, mouse-wheel zoom, left-click
  and drag-box selection (Shift to add), right-click to move, and hotkeys
  (Space/B/R/U/F/Tab/V/L) -- all routed through the same command pipeline as the
  mobile HUD.
- [x] 5.4 **Main menu / lobby** (`ui/shared/main_menu.gd` +
  `scenes/main_menu.tscn`): launches single-player desktop or mobile, hosts or
  joins an online lockstep match via `NetworkSession` (host/join), switches
  language live, and quits. It is now the project's main scene.
- [x] 5.5 **Per-platform export presets** (`export_presets.cfg`): Android first
  (priority platform), then Linux/X11, Windows Desktop, and macOS.
- [x] 5.6 New UI/menu **localization keys** (`ui.menu.*`, `ui.net.connecting`,
  `ui.game.language`, `ui.game.desktop_hint`) added to `en.json` and mirrored in
  `fa.json`; a test now asserts the two locale key sets stay in sync.

All **207** tests (176 prior + the new Phase 5 suite) pass headlessly. The
Phase 5 suite proves: the Localization service loads/falls-back/switches/cycles
correctly and every English key has a Persian translation; the CODE_POLICY
enforcement logic detects non-ASCII, exempts `localization/`, and the committed
repository is clean under a real scan; and the new desktop/menu scenes, export
presets, linter, and CI workflow all ship.

### Phase 6 -- Content, Balance & Release Hardening [WIP] IN PROGRESS
> Note: the v0.6.0 roadmap (phases `P0`..`P9-FIX` in `docs/STRUCTURE.md`) has
> since superseded and completed most of the "still planned" items below
> (settings, options, more content, the community mod editor, and Android/desktop
> release builds via `export_presets.cfg`). This section is kept for history; the
> authoritative, up-to-date status is `docs/STRUCTURE.md` section 5.

Building on the shippable base. Done so far:
- [x] 6.1 **Persisted settings service** (`core/game_settings.gd`): a validated,
  durable preferences store (locale, render style, default difficulty, camera
  zoom, SFX/music toggles) backed by the `ui_prefs` WorldState section and
  written to `user://nexus_settings.json` (separate from match saves, so it
  survives across matches and launches and works on every export platform).
  Every setter validates against an allow-list / range; unknown or out-of-range
  values fall back to the documented default, so a corrupt or hand-edited file
  can never push the game into an invalid state.
- [x] 6.2 **In-game Options/Settings screen** (`ui/shared/options_menu.gd` +
  `scenes/options_menu.tscn`), reachable from the main menu via a new **Options**
  button. It edits every persisted setting live, fully localized (English /
  Persian), with a **Reset** to defaults and a **Back** that saves and returns.
  The main menu now loads persisted settings on launch (so it opens in the saved
  language) and new `ui.options.*` keys ship in both locale files.

Still planned for Phase 6:
- [ ] 6.3 More scenarios + unit/tech content (data-driven, via `data/`).
- [ ] 6.4 AI difficulty tuning + balance pass.
- [ ] 6.5 A community **mod editor** under `tools/`.
- [ ] 6.6 Packaged **Android + desktop release builds** driven by
  `export_presets.cfg`.

### Roadmap Phase A -- Make the Game Visible & Understandable [DONE] COMPLETE
The presentation fix described in the structure document (the APK showed a tiny
square in the corner). This phase touches ONLY the render/UI layer -- the
deterministic core is untouched.

- [x] A.1 `RenderAdapter.fit_map_to_viewport(viewport_size)`: computes zoom +
  camera offset so the WHOLE map fits on screen with a margin (the fix for the
  tiny-map bug), replacing the fixed 24px tiling that left big maps off-screen.
- [x] A.2 Both HUDs (`ui/mobile/game_hud.gd` + `ui/desktop/desktop_hud.gd`) call
  `fit_map_to_viewport` on start before biasing toward the local HQ.
- [x] A.3 Re-fit on `get_viewport().size_changed` (device rotation / resize).
- [x] A.4 `StyleSimple` readability pass: bigger units + a dark ownership ring
  for instant friend/foe reading.
- [x] A.5 Localized tooltips on every mobile HUD button (`ui.game.tip.*`).
- [x] A.6 A short **onboarding overlay** at match start ("blue is you / tap to
  move / destroy the red HQ"), localized in `en` + `fa`.
- [ ] A.7 Manual Android debug build verification (requires Godot + Android SDK
  on a developer machine; see `docs/RELEASE.md`).

### Roadmap Phase B -- Data-Driven Visual Layer ("Play-Dough") [DONE] COMPLETE
The cosmetic layer that reads look from JSON, the foundation of the Mod Editor.
**No visual field affects the deterministic world hash** (proven by tests).

- [x] B.1 Optional `"visual"` block (`shape` / `color` / `texture` /
  `size_scale` / `outline`) added to every base `data/units/*.json` and
  `data/buildings/*.json`.
- [x] B.2 `TextureService` (`core/texture_service.gd`): a lazy, cached,
  multi-root `texture_id -> Texture2D` resolver with a safe placeholder fallback.
- [x] B.3 `RenderAdapter` resolves each entity's `visual` block from the catalog
  (read-only) and hands it to the style -- WorldState never mutated.
- [x] B.4 `StyleSprite` (`render/style_sprite/style_sprite.gd`): a texture-driven
  style with the SAME duck-typed interface as simple/detailed; the **Style**
  button now cycles simple -> detailed -> sprite.
- [x] B.5 Base textures generated under `assets/textures/` (ground/wall/water/
  soldier/scout/tank/hero/hq/barracks/outpost).
- [x] B.6 The **play-dough proof**: `mods/playdough_demo` shows the SAME building
  schema becoming a Wall (high HP, no attack) or a Turret (attack_range +
  texture) purely from JSON. Documented in `docs/MODDING.md`.
- [x] B.7 Headless regression tests: visual schema present, TextureService
  cache/fallback, StyleSprite interface + texture drawing, sprite style switch,
  and **style/visual swaps never change the world hash**.

The suite is now **244** tests (228 prior + the new Phase A/B suite). See
`docs/STRUCTURE.md` for the full phase map.

### Roadmap Phase C -- Storage Service & Portable `.nexpack` Packages [DONE] COMPLETE
The portable-content plumbing the Mod Editor (Phase D) is built on. Every piece
is pure infrastructure: it never touches WorldState or the deterministic hash (a
storage path is not gameplay).

- [x] C.1 `StorageService` (`core/storage_service.gd`): a single, configurable
  content root (default `user://content/`, writable on every export target). It
  normalises paths, creates the root on demand, resolves a bare pack id to a
  `.nexpack` path, and lists installed packs in a deterministic sorted order. A
  blank/invalid path falls back to the documented default (never unusable).
- [x] C.2 `content_path` in `core/game_settings.gd` + an Options row: a validated
  setter/getter (a blank value is rejected and leaves state intact), surfaced as
  a "Content Folder" cycle button in `ui/shared/options_menu.gd`, localized via
  `ui.options.content_path` in both locales.
- [x] C.3 `.nexpack` format (`core/pack_format.gd`): the SINGLE source of truth
  for the in-ZIP layout (`manifest.json` + `data/` + `textures/`), identical to
  an unpacked `mods/<id>/` folder, plus `validate_manifest` / `provided_data_paths`.
- [x] C.4 `PackReader` (`core/pack_reader.gd`): opens a `.nexpack` with Godot's
  `ZIPReader` and reads the manifest / JSON / bytes **on demand without extracting
  the whole archive**; `read_catalogs()` groups entries by catalog -> id exactly
  as `DataLoader` consumes them; safe against a corrupt ZIP or bad manifest.
- [x] C.5 ModLoader pack pipeline (`ModLoader.load_packs()`): discovers every
  `.nexpack` under the content root, applies the SAME deterministic topological
  load order as folder mods, merges their catalogs into the DataLoader, and
  extracts each pack's textures into a per-pack cache root handed to the
  TextureService -- so a `.nexpack` and a `mods/<id>/` folder are interchangeable.
- [x] C.6 `PackWriter` (`core/pack_writer.gd`): the Mod Editor's save engine,
  built on `ZIPPacker`. `write_from_dir()` packs an existing mod folder;
  `write_from_data()` packs an in-memory manifest + content map. Entries are
  written in a stable sorted order (deterministic archive); an invalid manifest
  is refused before anything is written.
- [x] C.7 Round-trip tests: six headless `test_phase_c_*` tests covering the
  StorageService root/resolve, the Settings `content_path`, format validation, a
  full write->read round-trip (binary texture byte-for-byte), loading a pack into
  the catalogs through ModLoader, and the Options key in both locales.

### Roadmap Phase D -- Graphical Mod Editor (core) [DONE] COMPLETE
The content-authoring tool. Following the project's golden rule, ALL authoring
logic lives in a headless-tested model (`tools/mod_project.gd`); the editor scene
(`ui/shared/mod_editor.gd` + `scenes/mod_editor.tscn`) is a thin view on top.

- [x] D.1 Editor scene + skeleton: a localized layout with a header (mod id /
  name), a side panel (Units/Buildings tabs, an entity list, Add/Remove), a
  detail panel (health + cost sliders, a cosmetic colour button), and a footer
  (New / Save / Back + a status line). Reachable from a new **Mod Editor** button
  on the main menu (`ui.menu.mod_editor`, en + fa).
- [x] D.2 Project lifecycle (`ModProject.new_project` / `open_pack`): "New"
  starts an empty project with a default manifest; `open_pack` re-reads an
  existing `.nexpack` via `PackReader` and, on any failure, leaves the
  in-progress project UNCHANGED (a bad file never destroys work).
- [x] D.3 Unit Editor with the `visual` block: add/remove units via a
  `default_unit` factory (valid stats, round body, default colour); edit health,
  cost, and the cosmetic `visual.color` live.
- [x] D.4 Building Editor -- the play-dough realisation: the same editing surface
  over the buildings catalog (`default_building`), proving one schema becomes
  different entities purely by changing `stats`/`visual`.
- [x] D.5 Texture management at the model level
  (`add_texture`/`remove_texture`/`has_texture`) using the canonical
  `textures/<name>.png` entry path the pack format + TextureService understand;
  bytes are bundled verbatim.
- [x] D.7 Save + validation: `ModProject.validate()` checks the whole project
  (manifest + non-empty + each entity has `stats`) and `save_pack()` REFUSES an
  invalid project before writing (never produces a broken pack);
  `build_manifest()` rebuilds `provides` deterministically from the live content.
- [x] D play-test proof (basis for D.8): a test saves an editor pack into the
  content root and loads it back through the SAME `ModLoader` the game uses,
  confirming an edited unit lands in the catalog -- i.e. a saved mod is
  immediately play-testable.

The one-click in-editor Play-test launch (D.8) is now delivered as part of
Phase E (the Map Editor's **Play-test** button reuses the same one-shot scenario
selection). Still optional for Phase D: a live preview panel (D.6, reusing the
RenderAdapter + StyleSprite from Phase B).

The suite is now **251** tests (244 prior + the new Phase D suite: project
new/edit, id normalisation, empty-project rejection, save->reopen round-trip,
load-into-catalogs via ModLoader, byte-for-byte texture round-trip, and editor
key localization in both locales).

### Roadmap Phase E -- Graphical Map / Scenario Editor [DONE] COMPLETE
The second authoring tool: build a whole playable **custom game** (a map + entity
placements + match rules + a simple tech tree) and bundle it into a single
`.nexpack` that the game lists and launches. Same golden rule as Phase D -- ALL
authoring logic lives in a headless-tested model (`tools/scenario_project.gd`),
and the editor scene (`ui/shared/map_editor.gd` + `ui/shared/tile_grid.gd` +
`scenes/map_editor.tscn`) is a thin view on top.

- [x] E.1 Grid map editor: a `TileGrid` control draws the current map + entities
  and emits `cell_clicked(x, y)`; the model owns the grid (width/height/walls).
- [x] E.2 Brush tools: single-cell paint/erase, rectangle **Fill** (corner-order
  agnostic, clamped to bounds), **Border** ring, **Clear**, and **Resize** that
  prunes any wall/entity that falls off a shrunk grid (never holds off-map data).
- [x] E.3 Entity placement (HQ / Unit) with an exclusive-cell rule: placing first
  clears any wall and removes any existing entity on that cell, so a cell is
  always unambiguous; `remove_entity_at` + `entity_at` round it out.
- [x] E.4 Scenario / match rules: players (owner / human / per-player difficulty /
  start resources), random `seed`, and the difficulty preset, all on the
  scenario top-level the `ScenarioLoader` already consumes.
- [x] E.5 Simple tech tree: author `tech` nodes (`default_tech` factory) with
  prerequisites; `validate()` flags a node that requires an unknown tech.
- [x] E.6 Bundle a whole "custom game": `ModProject` gained `scenarios` + `tech`
  catalogs, so a single `.nexpack` ships units + buildings + scenarios + tech.
  No pack-format change was needed -- the format (Phase C) already supported
  arbitrary catalogs via `provides`.
- [x] E.7 Content listing in the main menu: a new **Custom Games** scene
  (`ui/shared/custom_games.gd` + `scenes/custom_games.tscn`) lists every
  installed scenario (shipped or from a `.nexpack`) via
  `ScenarioLoader.list_scenarios` and launches it with
  `load_scenario_from_catalog`. A new **Map Editor** button reaches the editor.
  `GameBootstrap.setup_skirmish` now honours a one-shot `playtest_scenario`
  selection (consumed after use), powering both Custom Games and Play-test.

New Phase E tests (`test_phase_e_*`) cover: a fresh scenario is playable;
paint/fill/border/resize; exclusive-cell entity placement; byte-stable scenario
round-trip; validation (missing HQ / too few players / dangling tech
prerequisite); the simple tech tree; a scenario surviving the `.nexpack`
round-trip; an authored scenario actually loading + simulating through the real
module stack; catalog listing + load-by-id; and editor key localization (en+fa).

(Earlier milestone: the Phase 6 settings tests prove the service returns valid
defaults; setters reject bad values without corrupting current state; settings
survive a disk round-trip; corrupt/partial files fall back safely; reset restores
defaults; every options key is translated in both locales; and the Options
scene/service ship.)

### Roadmap Phase E2-E6 -- Advanced Modular Mod Editor [DONE] COMPLETE
The deep upgrade of the editor: a **tree-organised** catalogue of units,
buildings and a brand-new **objects** catalog, each with a layered **pixel
graphic**, a dynamic **attribute** picker driven by a stat registry,
single/multi-part bodies with a compatibility matrix, an **upgrade** tab (hard
+15% size cap), a **train/build** tab, and a **sea + coastline** map editor.
The full design lives in `docs/Nexus_ModEditor_Plan_fa.md`.

Golden rule (same as Phase B): only `logical_size` (in tiles) is simulation
data; every pixel size, image, colour and the auto-drawn coastline is **cosmetic
only** and can never affect the deterministic hash.

- [x] **E2 Shared infrastructure**
  - `tools/stat_registry.gd` -- single source of truth for every editable stat
    (`needs_value` / `applies_to` / `group`) plus the multi-part **compatibility
    matrix** (`compatible` / `conflicts`): two parts may not share a stat group
    (defense excepted, for buildings).
  - `tools/graphic_model.gd` -- the `graphic{mode,logical_size,parts}` model,
    the layer rule (`px(layer3) <= px(layer2) <= px(layer1)`), and **headless PNG
    validation** (signature + IHDR dimensions, 16x16 .. 512x512, PNG-only).
  - `tools/mod_project.gd` -- tree API (`add_child` / `add_sibling` /
    `rename_node` / `build_tree` / `set_parent`) over editor-only metadata
    (`editor.parent_id` / `tree_order`), plus `add_texture_validated` +
    `unique_texture_name`.
- [x] **E3 Unit Editor** -- single + multi-part units (`default_multipart_unit`),
  per-part stats with conflict checking, `fusable` flag (multi-part only), an
  `upgrade` block validated against the +15% base-layer cap, and a `buildable`
  (trained-from) descriptor.
- [x] **E4 Building Editor** -- multi-part buildings where **every part must
  carry health + armor** and is independently destructible
  (`default_multipart_building`, `validate_building`).
- [x] **E5 Object Editor** -- a new `objects` catalog: decorative or
  **extractable** map objects (`default_object`, `set_object`,
  `validate_object`); an extractable object must declare `yields{material,rate}`;
  placement is land / sea / both. Objects round-trip in `.nexpack` like every
  other catalog.
- [x] **E6 Map Editor + coastline** -- a `sea` terrain token alongside
  land/wall in `tools/scenario_project.gd` (painted, resized, round-tripped),
  `place_object` to drop map objects on the grid, and **render-only** coastline
  bitmasks in `tools/coast_autotile.gd` that never mutate logical data.

New tests (`test_phase_e2_*` .. `test_phase_e6_*` +
`test_phase_e2e6_editor_keys_localized_in_all_locales`) cover: stat groups +
compatibility; the layer-size rule; PNG validation (accept/reject by
format+size); tree build/rename/re-parent round-trip; texture validation + unique
naming; single/multi-part unit validity + fusable rule; multi-part stat-group
conflict rejection; the +15% upgrade cap; the building hp+armor rule;
multi-part building `.nexpack` round-trip; extractable vs decorative objects +
object round-trip; sea paint + round-trip; object placement + round-trip;
coastline being cosmetic-only (emission byte-identical before/after); and full
en+fa localization of every new editor key.

> Status: model + validation + headless tests are complete. Wiring the final
> Godot UI widgets (image upload, tree view, attribute pickers) sits on top of
> these models and is finished/verified during the user's debug pass.

---

## Repository Layout

See the design document for the full tree. Top-level folders:

```
core/         Central brain (Nexus) and its components
                (+ state_hasher.gd, mod_loader.gd for Phase 3;
                 localization.gd for Phase 5; game_settings.gd for Phase 6;
                 texture_service.gd for roadmap Phase B;
                 storage_service.gd + pack_format.gd + pack_reader.gd +
                 pack_writer.gd for roadmap Phase C)
modules/      Independent gameplay modules:
                map/ units/ buildings/ economy/ (+logistics) combat/
                ai_commander/ (+strategic_ai_module) victory/ tech_tree/
                fog_of_war/ difficulty/ hero_fusion/ multiplayer/ test_module
ui/           User interface (mobile / desktop / shared)
render/       Swappable render styles behind a RenderAdapter (fog-aware):
                style_simple/ (Mindustry-style) + style_detailed/ (MOWAS-style)
                + style_sprite/ (texture-driven, roadmap Phase B)
assets/       Base art shipped with the game (textures/ for the sprite style)
data/         Data-driven content (JSON): units, buildings (now incl. a cosmetic
                "visual" block), tech, scenarios, difficulty_presets, hero recipes
localization/ Translated display text (only place non-English is allowed)
mods/         Community mods (example_mod: a heavy_soldier unit;
                playdough_demo: a Wall + Turret from one building schema)
platforms/    Per-platform export settings
tests/        Unit / integration tests (Phase E + E2-E6 suites added)
tools/        Tooling (check_code_policy.gd linter; mod_project.gd +
                scenario_project.gd authoring models; stat_registry.gd +
                graphic_model.gd + coast_autotile.gd for the advanced Mod
                Editor, roadmap Phase E2-E6)
docs/         Documentation (incl. CODE_POLICY.md, STRUCTURE.md,
                Nexus_ModEditor_Plan_fa.md)
scenes/       Godot scenes (main_menu + options_menu + game_desktop +
                game_main + mod_editor + map_editor + custom_games + debug)
.github/      CI workflow (CODE_POLICY lint + headless test gate)
```

## License

Intended to be open-source (MIT) per the design document.
