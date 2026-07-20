extends Node
## Headless test runner for the spine. Run with:
##     godot --headless tests/TestRunner.tscn
## Exits with code 0 if all tests pass, 1 otherwise — so CI can gate on it.
##
## Runs as a normal scene so the GameData / GameState / Director autoloads are
## all present, then exercises the pure game logic (no rendering required).

var _passed := 0
var _failed := 0

func _ready() -> void:
	await get_tree().process_frame  # let autoloads finish _ready

	_test_clock_rollover()
	_test_semester_rollover()
	_test_apply_effects()
	_test_merge_effects()
	_test_event_firing()
	_test_activity_availability()
	_test_save_load_roundtrip()
	_test_modes_and_director()

	print("\n==== %d passed, %d failed ====" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# --- Assertions -------------------------------------------------------------
func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)

func _eq(a, b, label: String) -> void:
	_check(a == b, "%s  (got %s, expected %s)" % [label, str(a), str(b)])

# --- Tests ------------------------------------------------------------------
func _test_clock_rollover() -> void:
	print("[clock rollover]")
	GameState.reset()
	_eq(GameState.slot_name(), "Morning", "starts on Morning")
	_eq(GameState.day_name(), "Monday", "starts on Monday")
	for i in 3:
		GameState.advance_time()
	_eq(GameState.day_name(), "Tuesday", "3 slots -> next day")
	_eq(GameState.slot_name(), "Morning", "3 slots -> back to Morning")
	GameState.reset()
	for i in 21:
		GameState.advance_time()
	_eq(GameState.week, 2, "21 slots (7 days) -> week 2")
	_eq(GameState.day_name(), "Monday", "21 slots -> Monday again")

func _test_semester_rollover() -> void:
	print("[semester rollover]")
	GameState.reset()
	for i in 3 * 7 * 4:  # 4 weeks
		GameState.advance_time()
	_eq(GameState.semester, 2, "4 weeks -> semester 2")
	_eq(GameState.week, 1, "semester rolls week back to 1")

func _test_apply_effects() -> void:
	print("[apply_effects]")
	GameState.reset()
	GameState.apply_effects({"stats": {"magic": 5}, "energy": -10, "relationships": {"elara": 2}, "flags": {"met": true}})
	_eq(GameState.stats["magic"], 5, "stat added")
	_eq(GameState.energy, 90, "energy subtracted")
	_eq(GameState.relationships["elara"], 2, "relationship added")
	_eq(GameState.flags.get("met", false), true, "flag set")
	GameState.apply_effects({"energy": -1000})
	_eq(GameState.energy, 0, "energy clamps at 0")
	GameState.apply_effects({"energy": 1000})
	_eq(GameState.energy, GameState.max_energy, "energy clamps at max")

func _test_merge_effects() -> void:
	print("[merge_effects]")
	var into := {"stats": {"magic": 2}}
	GameState.merge_effects(into, {"stats": {"magic": 3, "combat": 1}, "flags": {"x": true}})
	_eq(into["stats"]["magic"], 5, "merged additive stat")
	_eq(into["stats"]["combat"], 1, "merged new stat")
	_eq(into["flags"]["x"], true, "merged flag")

func _test_event_firing() -> void:
	print("[event firing]")
	GameState.reset()
	GameState.apply_effects({"stats": {"magic": 15}})
	GameState.advance_time()  # events are checked on advance
	_eq(GameState.flags.get("noticed_by_professor", false), true, "magic>=15 fires 'noticed' event")
	_check(GameState.fired_events.has("noticed_by_professor"), "event recorded as fired")
	# Should not fire twice: clear the flag, advance again, stays cleared.
	GameState.flags.erase("noticed_by_professor")
	GameState.advance_time()
	_check(not GameState.flags.has("noticed_by_professor"), "once-only event does not re-fire")

func _test_activity_availability() -> void:
	print("[activity availability]")
	GameState.reset()  # Monday, Morning
	var ids := []
	for a in GameState.available_activities():
		ids.append(a.get("id", ""))
	_check("class_magic" in ids, "Magic Theory available Monday morning")
	_check(not ("spar_cassius" in ids), "Wed/Sat combat NOT available Monday morning")
	_check(not ("advanced_seminar" in ids), "flag-gated seminar hidden without flag")

func _test_save_load_roundtrip() -> void:
	print("[save/load roundtrip]")
	GameState.reset()
	GameState.apply_effects({"stats": {"magic": 9, "combat": 4}, "flags": {"beat_cassius": true}})
	for i in 5:
		GameState.advance_time()
	var path := "user://test_save.json"
	GameState.save_game(path)
	var snap_week := GameState.week
	var snap_slot := GameState.slot_index
	GameState.reset()
	_eq(GameState.stats["magic"], 0, "reset clears state")
	GameState.load_game(path)
	_eq(GameState.stats["magic"], 9, "loaded magic")
	_eq(GameState.stats["combat"], 4, "loaded combat")
	_eq(GameState.flags.get("beat_cassius", false), true, "loaded flag")
	_eq(GameState.week, snap_week, "loaded week")
	_eq(GameState.slot_index, snap_slot, "loaded slot")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _test_modes_and_director() -> void:
	# Guards the class of bug where a mode script or the Director autoload fails
	# to compile — which the pure-logic tests above would otherwise miss.
	print("[modes + director]")
	_check(Director != null, "Director autoload loaded")
	_check(Director.has_method("run_mode"), "Director has run_mode()")
	for path in [
		"res://scenes/modes/AcademyMode.tscn",
		"res://scenes/modes/DialogueMode.tscn",
		"res://scenes/modes/CombatMode.tscn",
	]:
		var fname: String = str(path).get_file()
		var packed: PackedScene = load(path)
		if packed == null:
			_check(false, "loads %s" % fname)
			continue
		var m: Node = packed.instantiate()
		# A parse error would leave the root without its script -> no enter().
		_check(m != null and m.has_method("enter"), "%s script attached (enter())" % fname)
		_check(m != null and m.has_signal("finished"), "%s has finished signal" % fname)
		if m != null:
			m.free()
