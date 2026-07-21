extends Node
## Director — the mode/state machine (autoload).
##
## Owns which screen is active. Modes live on a stack; only the top is visible.
## The base mode (the Academy) is set once at startup and stays at the bottom.
## Sub-modes are launched with `await Director.run_mode(name, context)` which
## resolves to the mode's result dictionary once it emits `finished`.
##
## Modes are duck-typed here (referenced as plain Nodes) on purpose: an autoload
## is compiled before the global `class_name` registry is populated on a clean
## import, so referencing the `GameMode` type by name here would fail to parse.
## Every mode still provides enter()/on_resumed()/finished — we just call them
## dynamically.
##
## Usage from any mode:
##     var result: Dictionary = await Director.run_mode("combat", {"encounter_id": "duel_rival"})
##     GameState.apply_effects(result.get("effects", {}))

const MODE_SCENES := {
	"charcreation": "res://scenes/modes/CharCreationMode.tscn",
	"academy": "res://scenes/modes/AcademyMode.tscn",
	"dialogue": "res://scenes/modes/DialogueMode.tscn",
	"combat": "res://scenes/modes/CombatMode.tscn",
	"lexicon": "res://scenes/modes/LexiconMode.tscn",
	"character": "res://scenes/modes/CharacterSheetMode.tscn",
	"schedule": "res://scenes/modes/ScheduleMode.tscn",
	"people": "res://scenes/modes/PeopleMode.tscn",
	"spells": "res://scenes/modes/SpellsMode.tscn",
	"inventory": "res://scenes/modes/InventoryMode.tscn",
}

var _host: Node = null
var _stack: Array = []  # of mode nodes

## Called by Root to tell the Director where mode scenes should be parented.
func register_host(host: Node) -> void:
	_host = host

## Add the persistent base mode (the academy). Not awaited.
func set_base_mode(mode_name: String) -> void:
	var mode = _instance(mode_name)
	_host.add_child(mode)
	_stack.append(mode)
	_show_top()
	mode.enter({})

## Push a mode over the current top and await its result dictionary.
func run_mode(mode_name: String, context: Dictionary) -> Dictionary:
	if _host == null:
		push_error("[Director] no host registered")
		return {}
	if not _stack.is_empty():
		_stack.back().visible = false
	var mode = _instance(mode_name)
	_host.add_child(mode)
	_stack.append(mode)
	mode.visible = true
	mode.enter(context)
	var result: Variant = await mode.finished
	_stack.erase(mode)
	mode.queue_free()
	_show_top()
	return result if result is Dictionary else {}

## Name of the current top mode (handy for the debug overlay).
func current_mode() -> String:
	if _stack.is_empty():
		return ""
	return str(_stack.back().name)

func _show_top() -> void:
	for i in _stack.size():
		_stack[i].visible = (i == _stack.size() - 1)
	if not _stack.is_empty():
		var top = _stack.back()  # untyped: modes are duck-typed
		if top.has_method("on_resumed"):
			top.on_resumed()

# No return type hint on purpose: the result stays untyped (Variant) so callers
# can invoke the mode's enter()/finished dynamically without the GameMode type.
func _instance(mode_name: String):
	var packed: PackedScene = load(MODE_SCENES[mode_name])
	var mode: Node = packed.instantiate()
	if mode is Control:
		(mode as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
	return mode
