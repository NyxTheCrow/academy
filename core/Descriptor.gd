extends RefCounted
class_name Descriptor
## Descriptor — the numberless surface, in ONE place.
##
## Design pillar (design/01): player mode shows words, not numbers. In the old
## build the number→word logic lived as scattered static methods AND was re-branched
## with `if dev_mode` at every call site. Here every "render this number as a word"
## lives together, and `value(...)` does the dev-mode branch once so a UI never
## repeats it. Callers ask for a display string and get a word (player) or the raw
## number (dev) — nothing else decides.
##
## This is presentation only. Graded-reveal PROSE (a fact rendered at N clarity
## levels) is a different, content-authored thing and lives in core/Descriptions.gd.

# --- Skills (the stat tree): Untrained → Master -----------------------------
static func skill(v: float) -> String:
	if v <= 1: return "Untrained"
	elif v <= 4: return "Novice"
	elif v <= 9: return "Apprentice"
	elif v <= 15: return "Adept"
	elif v <= 24: return "Skilled"
	return "Master"

# --- Relationships: Stranger → Inseparable ----------------------------------
static func relationship(v: int) -> String:
	if v <= 0: return "Stranger"
	elif v <= 3: return "Acquaintance"
	elif v <= 7: return "Friend"
	elif v <= 12: return "Close"
	return "Inseparable"

# --- HP (combat): Unhurt → Near death ---------------------------------------
static func hp(cur: int, maxhp: int) -> String:
	if cur >= maxhp: return "Unhurt"
	var f := float(cur) / float(maxi(1, maxhp))
	if f >= 0.7: return "Grazed"
	elif f >= 0.4: return "Wounded"
	elif f >= 0.15: return "Bloodied"
	return "Near death"

# --- Resources: energy / focus / mana (0..100) ------------------------------
static func resource(id: String, v: float) -> String:
	match id:
		"energy":
			if v >= 80: return "Fresh"
			elif v >= 55: return "Rested"
			elif v >= 30: return "Tired"
			elif v >= 10: return "Drowsy"
			return "Exhausted"
		"focus":
			if v >= 85: return "Sharp"
			elif v >= 60: return "Clear"
			elif v >= 35: return "Foggy"
			elif v >= 15: return "Frazzled"
			return "Burnt out"
		"mana":
			if v >= 85: return "Brimming"
			elif v >= 60: return "Ample"
			elif v >= 35: return "Low"
			elif v >= 15: return "Nearly spent"
			return "Empty"
	return str(int(v))

# --- Needs (0..100), higher = better/fuller ---------------------------------
static func need(id: String, v: float) -> String:
	match id:
		"hunger":
			if v >= 85: return "Full"
			elif v >= 60: return "Satisfied"
			elif v >= 35: return "Peckish"
			elif v >= 15: return "Hungry"
			return "Starving"
		"thirst":
			if v >= 85: return "Slaked"
			elif v >= 60: return "Fine"
			elif v >= 35: return "Thirsty"
			elif v >= 15: return "Parched"
			return "Dry as dust"
		"bladder":
			if v >= 80: return "Empty"
			elif v >= 55: return "Comfortable"
			elif v >= 30: return "Need to go"
			elif v >= 12: return "Bursting"
			return "Desperate"
		"hygiene":
			if v >= 85: return "Fresh"
			elif v >= 60: return "Clean"
			elif v >= 35: return "Grubby"
			elif v >= 15: return "Filthy"
			return "Reeking"
		"calm":
			if v >= 85: return "Serene"
			elif v >= 60: return "Composed"
			elif v >= 40: return "Tense"
			elif v >= 20: return "Anxious"
			return "Panicked"
	return str(int(v))

# --- The one dev-mode branch ------------------------------------------------
## Render an actor stat for display. `kind` is "skill" | "need" | "resource" |
## "relationship". In dev mode returns the number; otherwise the word.
static func value(dev: bool, kind: String, id: String, v: float) -> String:
	if dev:
		return "%.2f" % v if kind == "skill" else str(int(v))
	match kind:
		"skill": return skill(v)
		"need": return need(id, v)
		"resource": return resource(id, v)
		"relationship": return relationship(int(v))
	return str(int(v))
