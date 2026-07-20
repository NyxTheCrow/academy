extends Control
## GameMode — base class for every top-level "screen"/state in the game:
## AcademyMode (planning UI), DialogueMode (VN), CombatMode (tactical).
##
## The Director pushes modes onto a stack and shows only the top one. A mode
## does its thing, then emits `finished(result)` where `result` is a
## dictionary — typically { "effects": {...}, ... } — that the caller feeds
## back into GameState. This shared contract is what lets the three states
## stay fully decoupled from one another.
##
## Modes extend this by path (`extends "res://scripts/GameMode.gd"`) rather than
## via a `class_name`, so nothing depends on the global class registry being
## populated — which it isn't yet when autoloads compile on a clean import.

## Emit when the mode is done. `result` flows back to whoever ran the mode.
signal finished(result: Dictionary)

## Called once right after the mode is added to the tree, with its context.
func enter(_context: Dictionary) -> void:
	pass

## Called when a mode that was covering this one closes and this becomes top.
func on_resumed() -> void:
	pass
