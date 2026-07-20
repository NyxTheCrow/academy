# Magical Academy — Spine Prototype (Godot 4)

A prototype of the **core game-state spine** for a time-management academy sim:
a canonical calendar/clock, data-driven activities that compete for time slots,
a resolution system (flat effects + dice-based skill checks), a story flag/event
system, and a clickable UI. No combat yet — this is the skeleton everything
else hangs off.

> This is the "spine" from the design conversation: **the clock is the backbone,
> the game state is the nervous system.** Nail these two and the rest is content
> plugged into them.

## Run it

1. Install **Godot 4.2+** (standard build, no C# needed) from <https://godotengine.org>.
2. Open the Godot project manager → **Import** → select this folder's `project.godot`.
3. Press **F5** (Play). `scenes/Main.tscn` is the main scene.

You'll get a plannable week: pick an activity for each Morning / Afternoon /
Evening slot, watch stats and energy change, and see events fire as you cross
thresholds or reach certain dates.

## What to try (the loop is already interesting)

- **Attend Magic Theory** a few mornings until your `magic` hits 15 → an event
  fires ("Professor Vane has noticed your talent") which sets a flag → a new
  hidden activity, **Advanced Arcana Seminar**, unlocks on Saturday mornings.
  That's the full loop: *activity → stat → event → flag → new activity.*
- **Study in the Library** / **Practice Spells** are **skill checks** — the
  outcome is `stat + d6` vs a difficulty, with different effects on success/fail.
- Energy gates activities and refills each morning; **Rest** tops it up mid-day.

## Architecture

```
project.godot          Autoloads GameData then GameState (order matters).
scripts/
  GameData.gd          CONTENT layer. Loads the JSON tables. No game logic.
  GameState.gd         THE SPINE. Owns the clock + all player state.
data/
  activities.json      Every activity, as data. Author here, not in code.
  events.json          Every triggered event/story beat, as data.
scenes/
  Main.tscn / Main.gd  UI shell. Reads GameState, calls it, redraws on signals.
```

Two rules keep the whole game coherent, and everything routes through them:

1. **The clock only moves through `GameState.advance_time()`.**
2. **State only mutates through `GameState.apply_effects(effects)`.**

Because activities, events, and (later) combat all speak the same `effects`
dictionary (`{"stats": {...}, "energy": N, "relationships": {...}, "flags": {...}}`),
adding new systems doesn't mean new mutation paths — they just emit effects.

## Authoring content (no code)

Add an activity by appending to `data/activities.json`:

```json
{
  "id": "meditate",
  "name": "Meditate in the Grove",
  "description": "Quiet focus. Restores energy and nudges knowledge.",
  "slots": ["Evening"],
  "days": ["Saturday", "Sunday"],
  "requirements": { "min_energy": 0 },
  "effects": { "stats": { "knowledge": 1 }, "energy": 15 }
}
```

Supported fields: `days`, `slots` (availability gates), `requirements`
(`min_energy`, `min_stats`, `flags`), and either flat `effects` or a
`skill_check` (`stat`, `difficulty`, `success`, `failure`).

Events (`data/events.json`) share the same `effects` shape and trigger on any
mix of `semester` / `week` / `day` / `slot` / `min_stats` / `flags`.

## Where tactical combat plugs in (next milestone)

Combat is a **separate scene/module**, not part of the spine — this is what
keeps the risky part isolated:

1. An activity or event sets an intent, e.g. `"combat": "duel_rival"` (or emits
   a signal). The spine stays combat-agnostic.
2. `Main` (or a small router) instances a `Combat.tscn`, handing it the
   relevant slice of `GameState` (your stats, learned spells, party).
3. The combat scene runs the tactical turn-based fight on its own grid.
4. On resolution it returns **one `effects` dictionary** back through
   `GameState.apply_effects(...)` — rewards, injuries, flags — then
   `advance_time()`. Combat writes to state exactly like any activity does.

Keeping combat behind that `effects` boundary means you can build and balance
the tactical layer in isolation without ever touching the calendar spine.

## Status

- [x] Canonical clock (semester → week → day → 3 slots)
- [x] Data-driven activities with availability + requirement gating
- [x] Resolution: flat effects **and** dice skill checks
- [x] Relationships, energy economy, story flags
- [x] Event system (date / stat / flag triggers, once-only)
- [x] Clickable planning UI (clock, stats, journal, activity buttons)
- [ ] Save/load (serialize the GameState fields — deliberately kept flat for this)
- [ ] VN-style dialogue scenes for events
- [ ] Tactical combat module

_Note: authored without a Godot binary available in the build environment, so it
hasn't been run through the editor here. JSON validated; GDScript is Godot 4.2
syntax. If the first import surfaces anything, it'll be trivial to fix._
