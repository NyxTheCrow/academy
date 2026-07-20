extends Control
## GameMode — base class for every top-level "screen"/state in the game:
## AcademyMode (planning UI), DialogueMode (VN), CombatMode (tactical).
##
## The Director pushes modes onto a stack and shows only the top one. A mode
## does its thing, then emits `finished(result)` where `result` is a
## dictionary — typically { "effects": {...}, ... } — that the caller feeds
## back into GameState. This shared contract is what lets the three states
## stay fully decoupled from one another.
class_name GameMode

## Emit when the mode is done. `result` flows back to whoever ran the mode.
signal finished(result: Dictionary)

## Called once right after the mode is added to the tree, with its context.
func enter(_context: Dictionary) -> void:
	pass

## Called when a mode that was covering this one closes and this becomes top.
func on_resumed() -> void:
	pass
