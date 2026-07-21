# 07 · Mapping to the Current Build

Orientation only — **not a to-do list, and no code changes implied here.** Just
where each design idea stands against what the prototype already has, so it's
clear what's substrate vs. what's net-new when you next pick something up.

## Already there (substrate the ideas can build on)

| Idea | In the build |
|------|--------------|
| Numberless surface + dev/transparency mode | **Built** — player mode shows words; F2 / dev shows numbers |
| Time as a core state (minute-resolution) | **Built** — `advance_time(minutes)`, day/week/semester |
| Location as a core state (no map) | **Built** — rooms + connections, movement is a timed action |
| Per-thing booleans for skills/spells (`03`) | **Built as tags** — `tags` + `requirement_met()` are exactly "y/n on individual things" |
| Backgrounds gate lots of checks (`05`) | **Built (seed)** — creation picks a background that grants tags |
| Information surfacing (`01`) | **Partial** — the Lexicon/hover system surfaces meaning on demand |
| A qualitative mood stat | **Built** — `morale`, shown as words |
| Menus (character / schedule / people / spells / inventory) | **Built** |
| Tactical combat with tag-gated actions | **Built** |

## Net-new (design patterns not yet in code)

| Idea | Status |
|------|--------|
| **Graded reveal** — one fact rendered at N clarity levels by skill (`01`) | Not yet — the key new *content pattern* for numberless charm |
| **Divination / outcome forecasting** (`01`) | Not yet |
| **Grades & teacher comments** as feedback (`01`) | Not yet |
| **Bandwidth / burnout**, **mana/aura**, **sanity**, **injury** (`02`) | Not yet — new resource channels |
| **Spell components / partial failure** (`03`) | Not yet |
| **Skill-scaled bounded randomness** (`03`) | Not yet |
| **Class-mobility arc, fake descent, student union** (`04`,`05`) | Not yet — needs event/branch content |

## The one pattern worth prototyping first (when the time comes)

**Graded reveal.** It's the smallest thing that would demonstrate the whole
thesis: take one hidden value (say, your mana), and render it as fuzzy →
sharpening → precise text depending on a "mana-sense" skill. If that *feels*
charming in a five-minute slice, the numberless direction is validated; if it
feels like a worse stat bar, that's a cheap, early signal. (Design note only —
build it when you choose to, not because this file says so.)
