# Magical Academy — Spine Prototype (Godot 4)

A prototype of the **core architecture** for a time-management academy sim:
a canonical calendar/clock, data-driven content, a **mode/state machine** that
switches between the game's three screens, save/load, and a headless test suite.

The game's distinct states each have a mode, and the base architecture is set
up so content can go in:

| Mode | Script | What it is |
|------|--------|-----------|
| **CharCreation** | `scenes/modes/CharCreationMode.gd` | New-game setup: name, stats, background, dev toggle |
| **Academy** | `scenes/modes/AcademyMode.gd` | The planning UI — clock, stats, activities, NPCs |
| **Dialogue** | `scenes/modes/DialogueMode.gd` | VN scene — speaker, portrait, branching choices |
| **Combat** | `scenes/modes/CombatMode.gd` | Tactical turn-based grid fight (with Fire Wall) |

> From the design chats: **the clock is the backbone, the game state is the
> nervous system, and the Director is the switchboard between screens.**

## Core systems

- **Hourly clock** — the day runs 08:00–22:00; activities have a `duration`
  (hours) and are gated by `hours` / `hour_range`. The clock lives in
  `GameState` and only moves through `advance_time(hours)`.
- **Character creation** runs first: pick a name, spend a few stat points,
  choose a data-driven background (`data/backgrounds.json`), and toggle dev
  mode. It writes straight into `GameState`, then the academy boots.
- **Dev vs normal display** — `GameState.dev_mode`. Dev reveals all data
  (skill-check dice math, NPC stats). Normal hides it. Toggle with **F2** or
  the debug panel; chosen at character creation.
- **Four NPC students** (`Students` autoload, `data/students.json`) share the
  player's stats, hours, and action list. Every hour each one picks an action
  by a weighted random roll (their own bias) and grows their own stats. Shown
  in the Academy sidebar — names + current action in normal mode, full stats
  in dev mode. Saved and loaded with the game.
- **Fire Wall** (combat) — an ability that raises a 3-tile hazard zone; any
  unit that moves onto it or ends its turn on it takes damage. Lasts a few
  rounds.

## Run it

1. Install **Godot 4.2+** (standard build, no C#) from <https://godotengine.org>.
2. Project manager → **Import** → pick this folder's `project.godot`.
3. Press **F5**. Main scene is `scenes/Root.tscn`.

## Bug-testing tools

Three ways to test, in increasing automation:

- **In-game debug overlay** — press **F3** while playing. Shows live state
  (clock, stats, bonds, flags) and gives dev buttons: bump stats, skip a day,
  refill energy, save/load, reset, and **force-launch a Dialogue or Combat
  scene** so you can exercise those modes without grinding to their triggers.
- **Headless test suite** — no editor, no GPU needed:
  ```bash
  godot --headless tests/TestRunner.tscn
  ```
  Exits non-zero on failure. Covers clock/semester rollover, `apply_effects`,
  event firing (fire-once semantics), activity gating, and a save/load
  round-trip.
- **CI** — `.github/workflows/tests.yml` runs that same suite on every push,
  so a logic regression fails the build automatically.

## The mode/state machine

`Director` (autoload) owns a **stack of modes**; only the top is visible. The
Academy is the persistent base. Sub-modes are launched and awaited:

```gdscript
# from AcademyMode, when an activity triggers combat:
var result: Dictionary = await Director.run_mode("combat", {"encounter_id": "duel_rival"})
GameState.apply_effects(result.get("effects", {}))
GameState.advance_time()
```

Every mode extends `GameMode` and hands back a `result` dictionary via its
`finished` signal. That single contract is what keeps the three screens fully
decoupled — Dialogue and Combat never touch each other or the calendar; they
just resolve and return an `effects` bundle.

```
Root.tscn ─ registers the Director's host, boots Academy, layers DebugOverlay
  └─ ModeHost
       ├─ AcademyMode      (base, always at bottom of the stack)
       ├─ DialogueMode     (pushed over Academy, popped on finish)
       └─ CombatMode       (pushed over Academy, popped on finish)
```

## The spine (unchanged, still the core)

Two rules keep the whole game coherent; everything routes through them:

1. **The clock only moves through `GameState.advance_time()`.**
2. **State only mutates through `GameState.apply_effects(effects)`.**

Effects are one shape everywhere:
`{"stats": {...}, "energy": N, "relationships": {...}, "flags": {...}}`.
Activities, events, dialogue choices, and combat rewards all emit it.

## Files

```
project.godot              Autoloads: GameData -> GameState -> Director
scripts/
  GameData.gd              CONTENT layer — loads the JSON tables
  GameState.gd             THE SPINE — clock, state, effects, events, save/load
  Director.gd              MODE MACHINE — the stack of screens
  GameMode.gd              Base class for all three modes (class_name GameMode)
scenes/
  Root.tscn / .gd          Main scene; wires Director + debug overlay
  DebugOverlay.tscn / .gd  F3 bug-testing panel (floats above every mode)
  modes/
    AcademyMode.tscn / .gd
    DialogueMode.tscn / .gd
    CombatMode.tscn / .gd
data/
  activities.json          Activities (some trigger dialogue/combat)
  events.json              Date/stat/flag-triggered story beats
  dialogue.json            VN scenes (lines, labels, branching choices)
  encounters.json          Combat encounters (enemies, reward, penalty)
tests/
  TestRunner.tscn / .gd    Headless spine tests
.github/workflows/tests.yml  CI: runs the suite on push
```

## Try the full loop

1. **Attend Magic Theory** a few mornings → at `magic` 15 an event fires and
   sets a flag → **Advanced Arcana Seminar** unlocks on Saturdays.
   *(activity → stat → event → flag → new activity)*
2. **Spend the Evening with Elara** `[scene]` → the VN mode; your choice can
   branch and sets bonds/flags.
3. **Duel Cassius** `[fight]` (Wed/Sat afternoons) → the tactical combat mode;
   win to gain combat and set a flag, lose and pay energy.

All three write results back through the same `apply_effects` boundary.

## Authoring content (no code)

- **Activity** → append to `data/activities.json`. Add `"dialogue": "scene_id"`
  or `"combat": "encounter_id"` to make it launch a mode instead of resolving
  instantly.
- **Dialogue** → add a scene to `data/dialogue.json`: a list of
  `{speaker,text}` lines, `{label}` jump targets, and `{choices:[...]}` where a
  choice has `effects` and an optional `goto` label.
- **Encounter** → add to `data/encounters.json`: `enemies` plus `reward` /
  `penalty` effect bundles.

## Status

- [x] Canonical clock (semester → week → day → 3 slots)
- [x] Data-driven activities with availability + requirement gating
- [x] Resolution: flat effects **and** dice skill checks
- [x] Event system (date / stat / flag triggers, fire-once)
- [x] **Mode/state machine** with Academy / Dialogue / Combat spines
- [x] **VN dialogue** engine (branching choices, labels)
- [x] **Tactical combat** spine (grid, move + attack, enemy AI, win/lose)
- [x] **Save / load** (JSON to `user://`)
- [x] **Debug overlay** + **headless test suite** + **CI**
- [ ] Deeper combat (terrain, abilities, statuses, a party)
- [ ] Portrait/background art in dialogue (placeholders for now)
- [ ] Multiple save slots / main menu

_Authored without a Godot binary in the build environment, so it hasn't been
run through the editor here — the environment's proxy blocks the Godot
download. JSON is validated and GDScript is consistent-tab Godot 4.2 syntax;
the CI job (or a local run) is the real check. If the first import surfaces
anything, it'll be small — tell me the error and I'll fix it fast._
