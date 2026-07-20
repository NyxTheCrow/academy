extends Node
## Headless test runner for the spine. Run with:
##     godot --headless tests/TestRunner.tscn
## Exits 0 if all pass, 1 otherwise — CI gates on it.

var _passed := 0
var _failed := 0

func _ready() -> void:
	await get_tree().process_frame  # let autoloads finish _ready

	_test_clock_hourly()
	_test_semester_rollover()
	_test_apply_effects()
	_test_merge_effects()
	_test_event_firing()
	_test_activity_availability()
	_test_save_load_roundtrip()
	_test_data_loaded()
	_test_npc_students()
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
func _test_clock_hourly() -> void:
	print("[clock (hourly)]")
	GameState.reset()
	_eq(GameState.hour, GameState.DAY_START_HOUR, "starts at day-start hour")
	_eq(GameState.day_name(), "Monday", "starts on Monday")
	GameState.advance_time(1)
	_eq(GameState.hour, GameState.DAY_START_HOUR + 1, "one hour advances the clock")
	GameState.reset()
	var hours_per_day: int = GameState.DAY_END_HOUR - GameState.DAY_START_HOUR
	GameState.advance_time(hours_per_day)
	_eq(GameState.day_name(), "Tuesday", "a full day of hours -> next day")
	_eq(GameState.hour, GameState.DAY_START_HOUR, "day rolls back to start hour")
	GameState.reset()
	GameState.advance_time(hours_per_day * 7)
	_eq(GameState.week, 2, "7 days of hours -> week 2")
	_eq(GameState.day_name(), "Monday", "7 days -> Monday again")

func _test_semester_rollover() -> void:
	print("[semester rollover]")
	GameState.reset()
	var hours_per_week: int = (GameState.DAY_END_HOUR - GameState.DAY_START_HOUR) * 7
	GameState.advance_time(hours_per_week * GameState.WEEKS_PER_SEMESTER)
	_eq(GameState.semester, 2, "a full semester of hours -> semester 2")
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
	GameState.advance_time(1)
	_eq(GameState.flags.get("noticed_by_professor", false), true, "magic>=15 fires 'noticed' event")
	_check(GameState.fired_events.has("noticed_by_professor"), "event recorded as fired")
	GameState.flags.erase("noticed_by_professor")
	GameState.advance_time(1)
	_check(not GameState.flags.has("noticed_by_professor"), "once-only event does not re-fire")

func _test_activity_availability() -> void:
	print("[activity availability]")
	GameState.reset()  # Monday, 08:00
	_check("study_library" in _available_ids(), "Library available at 08:00 (hour_range)")
	_check(not ("class_magic" in _available_ids()), "Magic class NOT available at 08:00")
	GameState.advance_time(1)  # 09:00
	_check("class_magic" in _available_ids(), "Magic class available at 09:00")
	_check(not ("spar_cassius" in _available_ids()), "Wed/Sat combat NOT available Monday")
	_check(not ("advanced_seminar" in _available_ids()), "flag-gated seminar hidden without flag")

func _available_ids() -> Array:
	var ids := []
	for a in GameState.available_activities():
		ids.append(a.get("id", ""))
	return ids

func _test_save_load_roundtrip() -> void:
	print("[save/load roundtrip]")
	GameState.reset()
	Students.reset()
	GameState.player_name = "Tester"
	GameState.dev_mode = true
	GameState.apply_effects({"stats": {"magic": 9, "combat": 4}, "flags": {"beat_cassius": true}})
	GameState.advance_time(5)
	var path := "user://test_save.json"
	GameState.save_game(path)
	var snap_hour := GameState.hour
	# Scramble live state, then load it back.
	GameState.reset()
	GameState.player_name = "Wiped"
	GameState.dev_mode = false
	_eq(GameState.stats["magic"], 0, "reset clears state")
	GameState.load_game(path)
	_eq(GameState.player_name, "Tester", "loaded player name")
	_eq(GameState.dev_mode, true, "loaded dev flag")
	_eq(GameState.stats["magic"], 9, "loaded magic")
	_eq(GameState.hour, snap_hour, "loaded hour")
	_eq(Students.npcs.size(), 4, "loaded NPC roster")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _test_data_loaded() -> void:
	print("[data]")
	_eq(GameData.students.size(), 4, "4 student definitions loaded")
	_check(GameData.backgrounds.size() >= 3, "backgrounds loaded")
	_check(not GameData.get_encounter("duel_rival").is_empty(), "duel_rival encounter exists")

func _test_npc_students() -> void:
	print("[npc students]")
	GameState.reset()
	Students.reset()
	_eq(Students.npcs.size(), 4, "four NPCs spawned")
	_eq(GameState.dev_mode, false, "dev mode defaults off")
	GameState.advance_time(1)  # hour_ticked -> NPCs choose an action
	var acted := false
	for npc in Students.npcs:
		if npc["current_action"] != "Settling in":
			acted = true
	_check(acted, "NPCs pick an action on the hour tick")

func _test_modes_and_director() -> void:
	print("[modes + director]")
	_check(Director != null, "Director autoload loaded")
	_check(Director.has_method("run_mode"), "Director has run_mode()")
	for path in [
		"res://scenes/modes/CharCreationMode.tscn",
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
		_check(m != null and m.has_method("enter"), "%s script attached (enter())" % fname)
		_check(m != null and m.has_signal("finished"), "%s has finished signal" % fname)
		if m != null:
			m.free()
