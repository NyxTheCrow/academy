extends Node
## Headless test runner. Run with:
##     godot --headless tests/TestRunner.tscn
## Exits 0 if all pass, 1 otherwise — CI gates on it.

var _passed := 0
var _failed := 0

func _ready() -> void:
	await get_tree().process_frame

	_test_time_minutes()
	_test_calendar()
	_test_sleep()
	_test_apply_effects_tags()
	_test_merge_effects()
	_test_requirements()
	_test_locations_and_movement()
	_test_tag_gated_actions()
	_test_combat_action_filter()
	_test_event_firing()
	_test_save_load_roundtrip()
	_test_data_loaded()
	_test_stats_and_menus()
	_test_needs()
	_test_npc_students()
	_test_descriptors()
	_test_lexicon()
	_test_save_slots()
	_test_data_overrides()
	_test_modes_and_director()

	print("\n==== %d passed, %d failed ====" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)

func _eq(a, b, label: String) -> void:
	_check(a == b, "%s  (got %s, expected %s)" % [label, str(a), str(b)])

func _action_ids() -> Array:
	var ids := []
	for a in GameState.available_actions():
		ids.append(a.get("id", ""))
	return ids

# --- Tests ------------------------------------------------------------------
func _test_time_minutes() -> void:
	print("[time (minutes)]")
	GameState.reset()
	_eq(GameState.minutes_of_day, GameState.START_MINUTES, "starts at 07:00")
	_eq(GameState.time_string(), "07:00", "time string")
	_eq(GameState.location, "room", "starts in room")
	GameState.advance_time(30)
	_eq(GameState.time_string(), "07:30", "30 min later")
	GameState.reset()
	GameState.advance_time(GameState.DAY_MINUTES)
	_eq(GameState.day_name(), "Tuesday", "a full day -> next day")
	_eq(GameState.time_string(), "07:00", "same time next day")
	GameState.reset()
	GameState.advance_time(GameState.DAY_MINUTES * 7)
	_eq(GameState.day_count, 7, "7 days -> day_count 7")
	_eq(GameState.day_name(), "Monday", "7 days -> Monday again")

func _test_calendar() -> void:
	print("[calendar hierarchy]")
	GameState.reset()
	_eq(GameState.day_count, 0, "starts at day 0")
	_eq(GameState.weekday_index(), 0, "day 0 is Monday")
	_eq(GameState.week_of_month(), 0, "day 0 week-of-month 0")
	GameState.advance_time(GameState.DAY_MINUTES * GameState.DAYS_PER_MONTH)  # +1 month
	_eq(GameState.month_of_trimester(), 1, "a month later -> month index 1")
	GameState.reset()
	GameState.advance_time(GameState.DAY_MINUTES * GameState.DAYS_PER_TRIMESTER)  # +1 trimester
	_eq(GameState.trimester_of_year(), 1, "a trimester later -> trimester index 1")
	GameState.reset()
	GameState.advance_time(GameState.DAY_MINUTES * GameState.DAYS_PER_YEAR)  # +1 year
	_eq(GameState.year_index(), 1, "a year later -> year index 1")

func _test_sleep() -> void:
	print("[sleep]")
	GameState.reset()
	GameState.advance_time(600)  # 17:00
	GameState.energy = 10
	GameState.sleep()
	_eq(GameState.time_string(), "07:00", "sleep wakes at 07:00")
	_eq(GameState.day_name(), "Tuesday", "sleep advances a day")
	_eq(GameState.energy, GameState.max_energy, "sleep restores energy")

func _test_apply_effects_tags() -> void:
	print("[apply_effects + tags]")
	GameState.reset()
	GameState.apply_effects({"stats": {"focus": -5}, "energy": -10, "tags": ["dressed"], "flags": {"met": true}})
	_eq(GameState.stats["focus"], 95, "stat changed (100 - 5)")
	_eq(GameState.energy, 90, "energy subtracted")
	_check(GameState.has_tag("dressed"), "tag added")
	_check(GameState.flags.get("met", false), "flag set")
	GameState.apply_effects({"remove_tags": ["dressed"]})
	_check(not GameState.has_tag("dressed"), "tag removed")

func _test_merge_effects() -> void:
	print("[merge_effects]")
	var into := {"stats": {"magic": 2}}
	GameState.merge_effects(into, {"stats": {"magic": 3}, "tags": ["a"], "flags": {"x": true}})
	_eq(into["stats"]["magic"], 5, "merged stat")
	_check("a" in into["tags"], "merged tag")
	_check(into["flags"]["x"], "merged flag")

func _test_requirements() -> void:
	print("[requirement_met]")
	GameState.reset()  # Monday 07:00
	_check(GameState.requirement_met({}, [], {}, 100), "empty requirement passes")
	_check(GameState.requirement_met({"tags": ["a"]}, ["a", "b"], {}, 100), "has required tag")
	_check(not GameState.requirement_met({"tags": ["c"]}, ["a"], {}, 100), "missing required tag fails")
	_check(not GameState.requirement_met({"without_tags": ["a"]}, ["a"], {}, 100), "forbidden tag fails")
	_check(not GameState.requirement_met({"time_after": "09:00"}, [], {}, 100), "before window fails at 07:00")
	GameState.advance_time(180)  # 10:00
	_check(GameState.requirement_met({"time_after": "09:00", "time_before": "12:00"}, [], {}, 100), "inside window passes at 10:00")
	_check(not GameState.requirement_met({"min_energy": 50}, [], {}, 10), "min_energy fails")

func _test_locations_and_movement() -> void:
	print("[locations + movement]")
	GameState.reset()  # room
	_check("study_room" in _action_ids(), "room offers study")
	_check("go_corridor_a" in _action_ids(), "room offers movement to corridor A")
	_check(not ("attend_lecture" in _action_ids()), "lecture not offered in the room")
	GameState.set_location("corridor_a")
	_eq(GameState.location, "corridor_a", "moved to corridor A")
	_check("go_classroom" in _action_ids(), "corridor A connects to classroom")

func _test_tag_gated_actions() -> void:
	print("[tag-gated actions]")
	GameState.reset()
	GameState.set_location("classroom")
	GameState.advance_time(180)  # 10:00, a weekday
	_check(not ("attend_lecture" in _action_ids()), "lecture hidden without 'dressed' tag")
	GameState.add_tag("dressed")
	_check("attend_lecture" in _action_ids(), "lecture available once dressed (time+tags met)")
	# Duel gate
	GameState.set_location("dueling_room")
	_check(not ("duel_cassius" in _action_ids()), "duel hidden without 'can_duel'")
	GameState.add_tag("can_duel")
	_check("duel_cassius" in _action_ids(), "duel available with 'can_duel'")

func _test_combat_action_filter() -> void:
	print("[combat action tag filter]")
	var basic := _combat_ids([])
	_check("move" in basic and "strike" in basic, "move + strike available to all")
	_check(not ("fire_wall" in basic), "fire_wall hidden without pyromancer")
	var pyro := _combat_ids(["pyromancer"])
	_check("fire_wall" in pyro, "fire_wall available with pyromancer")
	_check("brace" in _combat_ids(["duelist"]), "brace available with duelist")

func _combat_ids(tags: Array) -> Array:
	var ids := []
	for act in GameData.combat_actions:
		if GameState.requirement_met(act.get("requires", {}), tags, {}, 100):
			ids.append(act.get("id", ""))
	return ids

func _test_event_firing() -> void:
	print("[event firing]")
	GameState.reset()
	GameState.apply_effects({"flags": {"attended_lecture": true}})
	GameState.advance_time(5)
	_check(GameState.flags.get("noticed_by_professor", false), "attending a lecture fires the event")
	_check(GameState.has_tag("can_duel"), "event grants a tag")

func _test_save_load_roundtrip() -> void:
	print("[save/load]")
	GameState.reset()
	Students.reset()
	GameState.player_name = "Tester"
	GameState.dev_mode = true
	GameState.set_location("classroom")
	GameState.add_tag("pyromancer")
	GameState.toggle_favorite("elara")
	GameState.add_item("charm")
	GameState.needs["hunger"] = 42
	GameState.advance_time(GameState.DAY_MINUTES * 3 + 120)
	GameState.apply_effects({"stats": {"focus": -7}})
	var path := "user://test_save.json"
	GameState.save_game(path)
	var snap_min := GameState.minutes_of_day
	var snap_day := GameState.day_count
	var snap_focus := int(GameState.stats["focus"])
	var snap_hunger := int(GameState.needs["hunger"])
	GameState.reset()
	GameState.player_name = "Wiped"
	GameState.load_game(path)
	_eq(GameState.player_name, "Tester", "loaded name")
	_eq(GameState.location, "classroom", "loaded location")
	_check(GameState.has_tag("pyromancer"), "loaded tag")
	_eq(int(GameState.stats["focus"]), snap_focus, "loaded focus")
	_eq(int(GameState.needs["hunger"]), snap_hunger, "loaded need")
	_eq(GameState.minutes_of_day, snap_min, "loaded time")
	_eq(GameState.day_count, snap_day, "loaded day_count")
	_check(GameState.is_favorite("elara"), "loaded favourite")
	_check(GameState.has_item("charm"), "loaded inventory item")
	_eq(Students.npcs.size(), 4, "loaded NPCs")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _test_needs() -> void:
	print("[needs]")
	GameState.reset()
	_eq(GameState.needs.keys().size(), 6, "six needs")
	_eq(GameState.need_descriptor("hunger", 90), "Full", "hunger 90 -> Full")
	_eq(GameState.need_descriptor("hunger", 5), "Starving", "hunger 5 -> Starving")
	_eq(GameState.need_descriptor("bladder", 5), "Desperate", "bladder 5 -> Desperate")
	var before := int(GameState.needs["hunger"])
	GameState.advance_time(600)  # a long stretch drifts needs down
	_check(int(GameState.needs["hunger"]) < before, "hunger drifts down over time")
	GameState.apply_effects({"needs": {"hunger": 100}})
	_eq(int(GameState.needs["hunger"]), 100, "eating restores hunger (clamped)")

func _test_data_loaded() -> void:
	print("[data]")
	_eq(GameData.locations.size(), 8, "8 locations")
	_check(GameData.combat_actions.size() >= 3, "combat actions loaded")
	_eq(GameData.students.size(), 4, "4 students")
	_check(GameData.backgrounds.size() >= 3, "backgrounds loaded")
	_check(GameData.spells.size() >= 3, "spells loaded")
	_check(GameData.items.size() >= 2, "items loaded")
	_check(GameData.schedule.size() >= 2, "schedule loaded")
	_check(GameData.tags_registry.size() >= 5, "tags registry loaded")

func _test_stats_and_menus() -> void:
	print("[stats + menus state]")
	GameState.reset()
	_eq(GameState.stats.keys().size(), 1, "only one stat now")
	_check(GameState.stats.has("focus"), "the stat is focus")
	_eq(GameState.focus_descriptor(100), "Sharp", "focus 100 -> Sharp")
	_eq(GameState.focus_descriptor(10), "Burnt out", "focus 10 -> Burnt out")
	# Favourites
	GameState.toggle_favorite("elara")
	_check(GameState.is_favorite("elara"), "favourite toggled on")
	GameState.toggle_favorite("elara")
	_check(not GameState.is_favorite("elara"), "favourite toggled off")
	# Inventory
	_check(GameState.has_item("textbook"), "starts with a textbook")
	GameState.add_item("charm")
	_check(GameState.has_item("charm"), "item added")
	GameState.remove_item("charm")
	_check(not GameState.has_item("charm"), "item removed")

func _test_npc_students() -> void:
	print("[npc students]")
	GameState.reset()
	Students.reset()
	_eq(Students.npcs.size(), 4, "four NPCs")
	_check(Students.npcs[0].has("location") and Students.npcs[0].has("tags"), "NPCs have location + tags")
	GameState.advance_time(30)
	var acted := false
	for npc in Students.npcs:
		if npc["current_action"] != "Waiting":
			acted = true
	_check(acted, "NPCs act when time advances")

func _test_descriptors() -> void:
	print("[descriptors (numberless)]")
	GameState.reset()
	GameState.dev_mode = false
	_check(not GameState.show_numbers(), "player mode hides numbers")
	GameState.dev_mode = true
	_check(GameState.show_numbers(), "dev mode shows numbers")
	_eq(GameState.stat_descriptor(0), "Untrained", "stat 0 -> Untrained")
	_eq(GameState.stat_descriptor(20), "Skilled", "stat 20 -> Skilled")
	_eq(GameState.hp_descriptor(10, 10), "Unhurt", "full HP -> Unhurt")
	_eq(GameState.hp_descriptor(1, 10), "Near death", "1/10 HP -> Near death")
	_eq(GameState.relationship_descriptor(0), "Stranger", "0 bond -> Stranger")
	GameState.energy = 90
	_eq(GameState.energy_descriptor(), "Fresh", "90 energy -> Fresh")
	GameState.energy = 5
	_eq(GameState.energy_descriptor(), "Exhausted", "5 energy -> Exhausted")

func _test_lexicon() -> void:
	print("[lexicon]")
	_check(Lexicon.all().size() >= 10, "lexicon entries loaded")
	_check(not Lexicon.lookup("focus").is_empty(), "lookup by term")
	_check(not Lexicon.lookup("bandwidth").is_empty(), "lookup by alias")
	_eq(Lexicon.search("").size(), Lexicon.all().size(), "empty query returns all")
	_check(Lexicon.search("fire").size() >= 1, "search finds Fire Wall")
	_check(Lexicon.search("zzqqxx").is_empty(), "no matches -> empty")
	_check(Lexicon.define("Focus") != "", "define returns text")

func _test_save_slots() -> void:
	print("[save slots]")
	GameState.reset()
	GameState.player_name = "Slotter"
	GameState.delete_slot(3)
	_check(not GameState.slot_info(3).get("exists", false), "slot 3 empty initially")
	GameState.save_slot(3)
	var info := GameState.slot_info(3)
	_check(info.get("exists", false), "slot 3 exists after save")
	_eq(info.get("name", ""), "Slotter", "slot metadata carries the name")
	GameState.player_name = "Someone Else"
	GameState.load_slot(3)
	_eq(GameState.player_name, "Slotter", "load_slot restores state")
	GameState.delete_slot(3)
	_check(not GameState.slot_info(3).get("exists", false), "slot 3 deleted")

func _test_data_overrides() -> void:
	print("[data overrides]")
	var orig := GameData.combat_actions.size()
	GameData.write_override("combat_actions.json", "[]")
	_check(GameData.has_override("combat_actions.json"), "override written")
	GameData.reload()
	_eq(GameData.combat_actions.size(), 0, "override applied on reload")
	GameData.clear_override("combat_actions.json")
	_check(not GameData.has_override("combat_actions.json"), "override cleared")
	GameData.reload()
	_eq(GameData.combat_actions.size(), orig, "original restored after revert")
	# write_project (res:// is writable when running from a directory project)
	var werr := GameData.write_project("editor_tmp_test.json", "[1, 2, 3]")
	_check(werr == "", "write_project succeeds (or reports read-only)")
	if werr == "":
		_check(FileAccess.file_exists("res://data/editor_tmp_test.json"), "project file written")
		DirAccess.remove_absolute(ProjectSettings.globalize_path("res://data/editor_tmp_test.json"))

func _test_modes_and_director() -> void:
	print("[modes + director]")
	_check(Director != null, "Director autoload loaded")
	for path in [
		"res://scenes/modes/MainMenuMode.tscn",
		"res://scenes/modes/CharCreationMode.tscn",
		"res://scenes/modes/AcademyMode.tscn",
		"res://scenes/modes/DialogueMode.tscn",
		"res://scenes/modes/CombatMode.tscn",
		"res://scenes/modes/LexiconMode.tscn",
		"res://scenes/modes/CharacterSheetMode.tscn",
		"res://scenes/modes/ScheduleMode.tscn",
		"res://scenes/modes/PeopleMode.tscn",
		"res://scenes/modes/SpellsMode.tscn",
		"res://scenes/modes/InventoryMode.tscn",
		"res://scenes/modes/SaveLoadMode.tscn",
		"res://scenes/modes/EditorMode.tscn",
	]:
		var fname: String = str(path).get_file()
		var packed: PackedScene = load(path)
		if packed == null:
			_check(false, "loads %s" % fname)
			continue
		var m: Node = packed.instantiate()
		_check(m != null and m.has_method("enter"), "%s script attached" % fname)
		if m != null:
			m.free()
