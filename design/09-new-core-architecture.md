# 09 · New Core Architecture (the clean base)

This is the restructured foundation the project is being rebuilt onto. It lives
in **`core/`** (pure logic) and **`content/`** (data), alongside — not yet
replacing — the legacy prototype in `scripts/`, `scenes/`, `data/`. Both are
covered by headless tests (`tests/TestRunner.tscn` = legacy, wired earlier;
`tests/CoreTestRunner.tscn` = this core), and CI runs both.

It exists to fix the structural flaws catalogued during the codebase review:
a `GameState` god-object, a forked player/NPC model, effect/requirement logic
duplicated three ways, locations that owned their events, and a raw-text data
editor. Each principle below maps to a decision you asked for.

## Principles → modules

### 1. The player and NPCs are ONE thing — `core/Actor.gd` [DONE]
There is a single `Actor` class. The player is just an actor with
`is_player == true`. An actor is defined entirely by numbers + labels:
`skills` (float competencies), `needs` (0–100), `resources` (energy/focus/mana),
`tags`, `traits`, `relationships`, `flags`, `inventory`. **All** behaviour —
applying effects, checking requirements, learning — delegates to the same shared
statics, so the simulation treats every character identically. Tests assert the
player and an NPC apply the same effect and evaluate the same requirement to
byte-identical results.

### 2. One rule, one implementation
- `core/Effects.gd` — the single mutation path (`apply` + `merge`). Preserves
  floats, clamps needs/resources, handles every category. Kills the old 3-way
  fork where NPCs silently dropped needs/flags/relationships.
- `core/Requirements.gd` — the single predicate evaluator, for actions, events,
  dialogue choices **and** stat-gated description variants. Optional world clock,
  so a pure stat gate needs no time context.
- `core/Clock.gd` — TIME as a pure value object (calendar math only, no side
  effects), extracted from the god-object.

### 3. Locations are just places — `content/locations.json` [DONE]
A location has a name, a (graded) description, `connections`, and `tags`. It no
longer owns a list of activities. **What you can do** lives in
`content/interactions.json`; each interaction declares `where` (location ids)
and/or `where_tags` (any location tagged so). Places and doings are now
independent axes.

### 4. Recurring events with one-time sub-events — `core/Events.gd` [DONE]
Two kinds, cleanly separated:
- **Recurring** (`content/schedule.json`): the class/meal/curfew *skeleton* —
  cadence + location + base description/effects. Every session shares it.
- **One-time occurrences** (`content/occurrences.json`): fire-once beats. An
  occurrence with `attach_to: "<recurring id>"` becomes a **one-time sub-event
  hosted inside a session** of that recurring event — "the day the professor
  calls on you". `Events.resolve_session()` returns the skeleton *unless* a
  pending attached sub-event matches this session, in which case its description
  overrides and its effects merge on top, then it's consumed. That is exactly
  "every class isn't the same": a shared base with one-off inserts.

### 5. Descriptions vary by stats — `core/Descriptions.gd` [DONE]
Graded reveal is a first-class primitive, not a bespoke method. A description is
an ordered list of variants, each with a `requires` block; `resolve(variants,
actor)` returns the first the actor meets (author sharp/high-skill variants
first, a bare fallback last). Used by locations, interactions, sessions, spells,
occurrences, and dialogue lines. Example shipped in content: the Aetherics
mana-sensing session and the `mana_sense` spell read as fuzzy → sharpening →
precise by `self_mana_awareness`.

### 6. Characters defined by stats + traits [DONE]
`content/skills.json` (the stat tree), `content/needs.json`,
`content/resources.json`. `content/traits.json` holds character traits that
**modify** behaviour: a trait can `grant_tags` and set `learn_rates`
(`{skill: ×mult}`). `Actor.learn(skill, amount)` scales by the actor's folded
learn-rate — so "this character learns shaping faster" is data, and it is the
same single learning path for the player and NPCs.

### 7. Keep tick combat, hex-based [KEPT]
The deterministic WEGO hex engine (`scripts/combat/TickEngine.gd`) is unchanged
and stays the combat direction. It already has no god-object dependency; it will
consume `Actor`s when combat is migrated onto the core.

## The keystone: a schema → editor → validator loop

`core/ContentSchema.gd` is the **single source of truth** for what content
exists and what shape each piece has. Field types include the domain composites:
`ref`/`ref_list` (pick another entry by id), `map_num` (skill→number),
`requirements`/`trigger`/`effects`, and `descriptions` (graded-reveal variants).

From that one schema:
- **`scenes/modes/SchemaEditorMode.gd`** renders a form per entry automatically —
  dropdowns for references, structured rows for skill/effect maps, a dedicated
  variant editor for graded descriptions. Adding a field to the schema, or a
  whole new content type, makes it editable with **zero new UI code**. Reachable
  from the main menu as "Content Editor (new)". Save writes a `user://` override
  (or writes straight to `content/` from the editor).
- **`core/ContentValidator.gd`** lints all content against the schema: dangling
  references, unknown requirement/effect keys, malformed description blocks. A
  headless test runs it on shipped content, so bad data fails CI.

Numeric tuning is editable too: per-need **decay rates** are fields on the needs
type, and the **class-learning rates** (skill gained per week) live in a
single-object `tuning` type — both edited with number spinners in the same
schema-driven editor, no raw-JSON required.

## Status

| Piece | State |
|-------|-------|
| Actor (unified PC/NPC) | Built + tested |
| Effects / Requirements / Descriptions / Clock | Built + tested |
| Locations ⟂ Interactions | Built (data + schema) |
| Recurring + one-time sub-events | Built + tested |
| Traits / learn-faster | Built + tested |
| Schema + schema-driven editor + validator | Built + smoke-tested |
| Editable numeric tuning (need decay, learning rates) | Built + tested |
| Seed content (validates clean) | Built |
| **Runtime `World`/`Sim` loop on the core** (`core/World.gd`) | Built + tested — advances the clock, drifts needs/resources, refills daily, runs unified NPC turns, resolves class learning + recurring/one-time events, save/load |
| **Game UI — Academy screen on the core** (`scenes/modes/CoreAcademyMode.gd`) | Built + smoke-tested — reads the player `Actor`/`World`, graded location prose, Descriptor words (dev = numbers via F2), action list from `available_interactions`, taking an action drives the world. Reached via "New Game (core)". |
| **Numberless surface** (`core/Descriptor.gd`) | Built + tested — number→word in one place, one dev-mode branch |
| **Save/load over `Actor`s** (`core/SaveManager.gd`) | Built + tested — slots over `World.to_dict`, header-only `slot_info` |
| **The live runtime handle** (`core/Game.gd` autoload) | Built — one `Content` + one `World` the modes read |
| **Other menus (character/schedule/people/spells/inventory/lexicon) on the core** | Not yet — still legacy on `GameState` |
| **VN dialogue on the core** | Not yet — `content/conversations.json` exists; `CoreAcademyMode` stubs the launch |
| **Combat consuming `Actor`s** | Not yet |

The legacy prototype still runs (reachable via the "(legacy)" menu entries) and
its 244 tests still pass; the core suite is now 114. Migration is incremental:
re-point the remaining modes at the `World`, one screen at a time, deleting the
`GameState`/`Students` halves as they're replaced.
