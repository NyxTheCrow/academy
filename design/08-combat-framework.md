# 08 — Combat Framework (timeline / action-reaction)

Synthesised from Nyx's action-reaction combat discussion. This is the **rough
framework prototype**, deliberately the "tiny toy" the design conversation
recommended building before any of the ambitious layers.

## The model

Not real-time, not classic turn-based. It is **discrete-tick WEGO**: time is a
stream of ticks; both sides queue actions that span several ticks; the world
advances through them like a roguelike advances turns.

Core pieces (all implemented in `scripts/combat/TickEngine.gd`):

- **Ticks.** Actions have duration, not instant resolution.
- **Phases.** Every action runs `startup -> commit point -> active (resolve) ->
  recovery`. Before the commit point a plan can be interrupted; after it, the
  action must resolve. This is what stops infinite counter-chains: committing to
  the wrong response is a real, punishable mistake.
- **Reactions are just actions.** "Reacting" is queuing a new action after
  seeing new information. There is no special reaction verb.
- **Readiness.** A small pool (regenerates while idle) is the concrete resource
  that stops a unit from reacting perfectly to everything. Block the ray and you
  may not have the readiness for the follow-up.
- **Deterministic, lethal.** Attacks that connect resolve for known effect — no
  accuracy roll. Survivability is layered: a **directional ward** absorbs one
  hit from the side it faces; otherwise the unit goes down.
- **Hex geometry decides what's possible.** The board is a hex grid (axial
  coordinates, six neighbours). Which dodges, flanks and escapes exist is a
  function of position. A ray is dangerous because of the geometry you are
  trapped in, not a hit chance.
- **A simple, honest enemy.** It can aim at your **projected destination** (where
  your queued move is taking you), so "it predicted my move and put a ray there"
  actually happens — no cheating, just reading your committed plan.

## What is intentionally NOT here yet

Per the doc's build order, these come later and are **not** in the prototype:
hidden spell identity, layered "what is this spell" knowledge checks, illusions,
feints, companions, and sophisticated AI. First we answer: *is predicting,
committing, interrupting and forcing movement fun with full information?*

## Where it lives

- Engine (pure logic, headless-testable): `scripts/combat/TickEngine.gd`
- Editable action kit: `data/tick_actions.json` (ray, dodge, stride, ward, rune,
  burst, hold) — every number editable in the in-game Data Editor.
- Playable front-end: `scenes/modes/TickCombatMode.gd` (numbers visible; a bare
  grid + timeline log). Reachable from the Dueling Room -> "Timeline spar".
- Tests: `_test_tick_combat()` in `tests/TestRunner.gd` pin the framework rules
  deterministically (ray lethality, dodge, commit lock, readiness gate,
  directional ward, projected-destination aim, rune trigger, full AI duel).

## Open questions (for later)

- Initiative: the player currently plans first each round, then the enemy
  responds. Should idle stand-offs let the enemy press instead?
- How much survivability (wards/injury tiers) before lethality stops feeling
  like a knowledge check?
- How is a spell's identity/effect concealed without becoming a wiki lookup?
