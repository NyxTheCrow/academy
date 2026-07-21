# 03 · Skills & Magic

## Skills: many small booleans, not few big numbers

Core idea (qhaqx): **reduce the "numeral" feel by bloating the number of
skills** — lots of granular, largely **yes/no competencies** instead of a
handful of aggregate stats. Rather than "Magic: 42," you have a wide tree of
tiny nodes:

- *Do you know Firebolt?* (y/n)
- *Do you know its stabilization component?* (y/n)
- *Mana-sense tier 1 / 2 / 3* (small steps)
- *Can you recognize evocation glyphs?* (y/n)

This makes competence **legible as fiction** ("you know these spells; you don't
know those") instead of as a bar, and it plays directly into the numberless
surface: knowing-or-not is easy to phrase in prose.

> This is the same substrate as the prototype's **tags** — see `07`. Per-spell
> and per-skill booleans are exactly what tags are for.

## Spellcasting as a small procedure

- Spells have **components**. You can **partially fail** — botch a specific
  component — rather than a single all-or-nothing roll.
- Partial outcomes get **visual + textual feedback** (the flame guttered, the
  ward held but frayed, a rune smeared). Casting is a little scene, not a dice
  throw. This is a major source of the "charm" and of granular skill expression.

## Randomness, bounded by skill [DECIDED in principle]

Yes to randomness — but **scaled to competence**:

- **When you suck, outcomes are very random.** When you're skilled, randomness
  shrinks toward **minimal influence**.
- Never a pure coinflip for a master; never boringly deterministic for a novice.
- Sketch: `outcome = base(skill) + noise`, where `|noise| ∝ (1 − competence)`,
  clamped to sane bounds. (Numbers TBD.)

Counter-concern (qhaqx): randomness can frustrate. Answers: the variance is
**legible in-fiction** (a novice *feels* unsure; the prose says so), it **shrinks
fast** with skill, and **divination** (see `01`) can narrow the forecast. It
should respect skill/level, "within bounds."

## Progression & gating

- Learning is gated by **mental bandwidth** (`02`) — you can't cram infinitely.
- Component skills are **prerequisites** for full spells — a tree of tiny nodes,
  bottom-up.
