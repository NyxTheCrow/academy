extends Node
## Headless tests for the new core/ foundation. Independent of the legacy
## autoloads — every core module is pure and preloaded here directly.
##   godot --headless tests/CoreTestRunner.tscn
## Exits 0 if all pass, 1 otherwise.

const ClockC := preload("res://core/Clock.gd")
const ActorC := preload("res://core/Actor.gd")
const EffectsC := preload("res://core/Effects.gd")
const RequirementsC := preload("res://core/Requirements.gd")
const DescriptionsC := preload("res://core/Descriptions.gd")
const EventsC := preload("res://core/Events.gd")
const ContentC := preload("res://core/Content.gd")
const SchemaC := preload("res://core/ContentSchema.gd")
const ValidatorC := preload("res://core/ContentValidator.gd")
const WorldC := preload("res://core/World.gd")
const DescriptorC := preload("res://core/Descriptor.gd")
const SaveManagerC := preload("res://core/SaveManager.gd")

var _passed := 0
var _failed := 0

func _ready() -> void:
	_test_clock()
	_test_actor_effects()
	_test_requirements()
	_test_descriptions_graded_reveal()
	_test_actor_unification()
	_test_learning_and_traits()
	_test_events_recurring_and_occurrences()
	_test_content_loads()
	_test_schema_and_validation()
	_test_editor_smoke()
	_test_world_time_and_drift()
	_test_world_interactions_and_learning()
	_test_world_npc_attendance()
	_test_world_occurrences()
	_test_world_save_load()
	_test_descriptors()
	_test_save_manager()
	_test_core_academy_smoke()
	print("\n==== core: %d passed, %d failed ====" % [_passed, _failed])
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

func _approx(a: float, b: float, label: String) -> void:
	_check(abs(a - b) < 0.0001, "%s  (got %s, expected %s)" % [label, str(a), str(b)])

# --- Actor factory for tests ------------------------------------------------
func _mk(id: String) -> Actor:
	var a: Actor = ActorC.new()
	a.id = id
	a.name = id.capitalize()
	a.resource_max = {"energy": 100.0, "focus": 100.0, "mana": 100.0}
	a.resources = {"energy": 100.0, "focus": 100.0, "mana": 100.0}
	a.needs = {"hunger": 75.0, "calm": 50.0}
	a.skills = {"shaping": 0.0, "history": 0.0}
	a.tags = ["student"]
	return a

# --- Tests ------------------------------------------------------------------
func _test_clock() -> void:
	print("[clock]")
	var c: Clock = ClockC.new()
	_eq(c.minutes_of_day, 420, "starts at 07:00")
	_eq(c.time_string(), "07:00", "time string")
	_eq(c.advance(30), 0, "30 min: no day rollover")
	_eq(c.time_string(), "07:30", "07:30 after 30 min")
	_eq(c.advance(1440), 1, "a full day rolls once")
	_eq(c.day_name(), "Tuesday", "day rolled to Tuesday")
	_eq(c.advance(1440 * 6), 6, "six more days -> six rollovers")
	_eq(c.day_name(), "Monday", "back to Monday after 7 days")
	_eq(ClockC.hm("09:30"), 570, "hm parses HH:MM")
	# Calendar hierarchy
	var c2: Clock = ClockC.new()
	c2.advance(1440 * c2.days_per_year())
	_eq(c2.year_index(), 1, "a year later -> year index 1")
	_eq(c2.minutes_until("07:00"), 1440, "minutes_until wraps to tomorrow")

func _test_actor_effects() -> void:
	print("[effects — one path, all categories]")
	var a := _mk("p")
	a.apply({"needs": {"hunger": -10.5}, "energy": -20, "tags": ["dressed"],
		"flags": {"met": true}, "relationships": {"elara": 3}, "skills": {"shaping": 1.25}})
	_approx(a.get_need("hunger"), 64.5, "float need delta preserved (no int truncation)")
	_approx(a.get_resource("energy"), 80.0, "energy shorthand routed to resources")
	_check(a.has_tag("dressed"), "tag added")
	_check(a.flags.get("met", false), "flag set")
	_eq(int(a.relationships.get("elara", 0)), 3, "relationship added")
	_approx(a.get_skill("shaping"), 1.25, "fractional skill gain preserved")
	# Clamping
	a.apply({"needs": {"hunger": 999}, "energy": 999})
	_approx(a.get_need("hunger"), 100.0, "needs clamp at 100")
	_approx(a.get_resource("energy"), 100.0, "resources clamp at max")
	# merge preserves floats and folds categories
	var bundle := {}
	EffectsC.merge(bundle, {"skills": {"shaping": 0.5}})
	EffectsC.merge(bundle, {"skills": {"shaping": 0.25}, "tags": ["x"]})
	_approx(float(bundle["skills"]["shaping"]), 0.75, "merge accumulates floats")
	_check("x" in bundle["tags"], "merge folds list categories")

func _test_requirements() -> void:
	print("[requirements — one evaluator]")
	var a := _mk("p")
	a.tags = ["student", "enrolled"]
	a.skills = {"shaping": 5.0}
	a.location = "gardens"
	var world: Clock = ClockC.new()  # Monday 07:00
	_check(a.meets({}, world), "empty requirement passes")
	_check(a.meets({"tags": ["enrolled"]}, world), "has required tag")
	_check(not a.meets({"tags": ["faculty"]}, world), "missing tag fails")
	_check(not a.meets({"without_tags": ["student"]}, world), "forbidden tag fails")
	_check(a.meets({"min_skills": {"shaping": 3}}, world), "skill threshold met")
	_check(not a.meets({"min_skills": {"shaping": 9}}, world), "skill threshold unmet")
	_check(a.meets({"max_skills": {"shaping": 9}}, world), "max skill ok")
	_check(a.meets({"at_location": "gardens"}, world), "location gate (single)")
	_check(a.meets({"location": ["gardens", "dormitories"]}, world), "location gate (any-of)")
	_check(not a.meets({"time_after": "09:00"}, world), "time gate before window fails at 07:00")
	world.advance(180)  # 10:00
	_check(a.meets({"time_after": "09:00", "time_before": "12:00"}, world), "inside time window passes")
	_check(a.meets({"days": ["Monday"]}, world), "day gate matches")
	# Stat-only gate with no world (description variants use this)
	_check(a.meets({"min_skills": {"shaping": 3}}, null), "stat gate works without a world clock")

func _test_descriptions_graded_reveal() -> void:
	print("[descriptions — graded reveal]")
	# The mana-sensing exercise: three clarity levels by self_mana_awareness.
	var variants := [
		{"requires": {"min_skills": {"self_mana_awareness": 6}}, "text": "precise"},
		{"requires": {"min_skills": {"self_mana_awareness": 2}}, "text": "fuzzy"},
		{"text": "nothing"},
	]
	var a := _mk("p")
	a.skills = {"self_mana_awareness": 0.0}
	_eq(a.describe(variants), "nothing", "novice sees the fallback")
	a.skills["self_mana_awareness"] = 3.0
	_eq(a.describe(variants), "fuzzy", "some skill -> fuzzy band")
	a.skills["self_mana_awareness"] = 8.0
	_eq(a.describe(variants), "precise", "high skill -> precise reading")
	_eq(DescriptionsC.level_count(variants), 3, "three clarity levels")
	_eq(a.describe("a plain string"), "a plain string", "bare string resolves as-is")

func _test_actor_unification() -> void:
	print("[actor unification — PC and NPC are identical]")
	var pc := _mk("player"); pc.is_player = true
	var npc := _mk("elara")
	# The SAME effect + requirement + learning calls work on both, byte for byte.
	var fx := {"skills": {"history": 2.0}, "needs": {"calm": 5}}
	pc.apply(fx); npc.apply(fx)
	_eq(pc.get_skill("history"), npc.get_skill("history"), "PC and NPC apply effects identically")
	_eq(pc.meets({"min_skills": {"history": 2}}), npc.meets({"min_skills": {"history": 2}}),
		"PC and NPC evaluate requirements identically")
	# Round-trip through serialization (used by save/load AND the editor).
	var clone: Actor = ActorC.from_json(npc.to_dict())
	_eq(clone.get_skill("history"), npc.get_skill("history"), "actor survives to_dict/from_json")
	_eq(clone.tags, npc.tags, "tags survive round-trip")

func _test_learning_and_traits() -> void:
	print("[learning + traits (learn faster)]")
	var slow := _mk("slow")
	var fast := _mk("fast")
	fast.learn_rates = {"shaping": 2.0}   # a "Quick Study (Shaping)" trait folded in
	slow.learn("shaping", 0.5)
	fast.learn("shaping", 0.5)
	_approx(slow.get_skill("shaping"), 0.5, "default learn rate is 1.0x")
	_approx(fast.get_skill("shaping"), 1.0, "a trait doubles the learning rate")
	_check(fast.get_skill("shaping") > slow.get_skill("shaping"), "trait-holder learns faster from the same lesson")

func _test_events_recurring_and_occurrences() -> void:
	print("[events — recurring skeleton + one-time sub-events]")
	var actor := _mk("p")
	actor.tags = ["student", "enrolled"]
	var world: Clock = ClockC.new()  # Monday 07:00
	# A recurring class template.
	var law := {
		"id": "law", "kind": "class", "days": ["Monday", "Wednesday", "Friday"],
		"start": "09:00", "end": "11:00", "room": "main_academic_building", "skill": "modern_politics",
		"description": [{"text": "Magister Adler works through precedent."}],
	}
	# A one-time sub-event attached to that class on a specific week.
	var occ := [{
		"id": "adler_calls_on_you", "attach_to": "law", "once": true,
		"trigger": {"week": 0},
		"description": [{"text": "Adler fixes on you: 'Defend the claimant.'"}],
		"effects": {"skills": {"modern_politics": 1.0}, "flags": {"spoke_in_law": true}},
	}]
	# Is Law in session Monday 09:30?
	world.advance(150)  # 09:30
	_check(EventsC.in_session(law, world), "recurring class is in session at 09:30 Monday")
	_check(not EventsC.in_session(law, ClockC.new()), "not in session at 07:00")
	# Resolve this session: the base skeleton PLUS the pending one-time insert.
	var fired := {}
	var session := EventsC.resolve_session(law, [occ[0]], world, actor, fired)
	_check(session.get("one_time_id", "") == "adler_calls_on_you", "the one-time sub-event fires inside the class")
	_check("Defend the claimant" in str(session.get("description", "")), "one-time description overrides the skeleton")
	actor.apply(session.get("effects", {}))
	_check(actor.flags.get("spoke_in_law", false), "the one-time effect applied")
	# Consumed: next session on the same class falls back to the skeleton.
	var session2 := EventsC.resolve_session(law, [occ[0]], world, actor, fired)
	_eq(session2.get("one_time_id", ""), "", "a once sub-event does not fire twice")
	_check("precedent" in str(session2.get("description", "")), "later sessions show the recurring skeleton")

func _test_content_loads() -> void:
	print("[content loads]")
	var c = ContentC.new()
	c.load_all()
	_check(c.actors.size() >= 3, "actors loaded")
	_check(c.locations.size() >= 5, "locations loaded")
	_check(c.interactions.size() >= 3, "interactions loaded")
	_check(c.skills_registry.size() >= 10, "skill registry loaded")
	_check(c.build_actor("player") != null, "can build the player actor from its template")
	var elara = c.build_actor("elara")
	_check(elara != null and elara.skills.has("shaping"), "a built NPC carries the full skill sheet")

func _test_schema_and_validation() -> void:
	print("[schema + validation]")
	var schema := SchemaC.all()
	_check(schema.has("actors") and schema.has("interactions") and schema.has("descriptions_demo") == false,
		"schema defines the content types")
	_check(schema["actors"]["fields"].size() > 0, "actors type has fields")
	var c = ContentC.new()
	c.load_all()
	var issues := ValidatorC.validate(c, schema)
	for iss in issues:
		print("    ISSUE: %s" % iss)
	_eq(issues.size(), 0, "shipped content validates cleanly against the schema")
	# The numeric knobs must be editable: need-decay is a field on the needs type,
	# and class-learning rates live in the editable single-object tuning type.
	_check(schema.has("tuning") and str(schema["tuning"]["collection"]) == "single",
		"tuning is an editable single-object type")
	_check(c.tuning.get("learning", {}).has("focus_per_week"),
		"class learning rate (skill per week) is exposed and editable")
	var need_fields: Array = []
	for f in schema["needs"]["fields"]:
		need_fields.append(str(f["key"]))
	_check("decay_per_min" in need_fields, "need-decay is an editable field on each need")

func _test_editor_smoke() -> void:
	print("[schema editor — builds a form for every type]")
	var packed: PackedScene = load("res://scenes/modes/SchemaEditorMode.tscn")
	var ed = packed.instantiate()
	add_child(ed)
	ed.enter({})
	var schema := SchemaC.all()
	var built_all := true
	for t in schema:
		ed._select_type(t)
		var eids: Array = ed._entry_ids()
		if eids.is_empty():
			continue
		ed._select_entry(str(eids[0]))
		# A form was generated from the schema (one row per field) with no crash.
		if ed.form_box.get_child_count() == 0:
			built_all = false
			print("    (no form built for type %s)" % t)
	_check(built_all, "every content type renders an auto-generated form")
	# New-entry + per-type validation round-trips.
	ed._select_type("spells")
	var before: int = ed._entry_ids().size()
	ed._on_new_entry()
	_check(ed._entry_ids().size() == before + 1, "New entry adds a row to the working copy")
	_check(ed._validate_type() is Array, "per-type validation returns a list of issues")
	ed.free()

# --- World (runtime sim loop) -----------------------------------------------
func _new_world():
	var c = ContentC.new()
	c.load_all()
	var w = WorldC.new()
	w.setup(c)
	return w

func _test_world_time_and_drift() -> void:
	print("[world — clock, drift, daily refill]")
	var w = _new_world()
	_check(w.player != null and w.player.is_player, "world has a player actor")
	_check(w.actors.size() >= 3, "world builds the full roster")
	var hunger0: float = w.player.get_need("hunger")
	w.player.resources["energy"] = 40.0
	w.advance_time(600)  # a long stretch
	_check(w.player.get_need("hunger") < hunger0, "hunger drifts down over time")
	_eq(w.clock.time_string(), "17:00", "clock advanced 10h from 07:00")
	# Crossing the day boundary refills daily resources (energy/focus).
	w.advance_time(1000)  # into the next day
	_check(w.clock.day_count == 1, "a day rolled over")
	_eq(w.player.get_resource("energy"), 100.0, "energy refills on the new day")

func _test_world_interactions_and_learning() -> void:
	print("[world — interactions + class learning]")
	var w = _new_world()
	# In the dorm you can study and move; class actions are hidden.
	var ids := _iids(w.available_interactions(w.player))
	_check("study_room" in ids, "dorm offers study")
	_check("go_right_plaza" in ids, "dorm offers movement")
	_check(not ("focus_class" in ids), "in-class actions hidden outside a class")
	# Put the player in Law (Monday 09:00) and learn.
	w.player.location = "main_academic_building"
	w.clock.day_count = 0        # Monday
	w.clock.minutes_of_day = 540 # 09:00
	var class_ids := _iids(w.available_interactions(w.player))
	_check("focus_class" in class_ids, "in-class actions appear during a class")
	var before: float = w.player.get_skill("modern_politics")
	var focus := _find_iid(w, "focus_class")
	w.resolve_interaction(w.player, focus)
	_check(w.player.get_skill("modern_politics") > before, "focusing in Law raises modern_politics")
	# A full week of focusing lands near the tuned target (0.5).
	var w2 = _new_world()
	var law: Dictionary = {}
	for c in w2.content.schedule:
		if str(c.get("id", "")) == "law":
			law = c
	var per := w2.class_learn_amount(law, "focus", 20)
	var slots := 6  # 2h / 20min
	_approx(per * law["days"].size() * slots, 0.5, "a week of focusing ≈ 0.5 in the class skill")

func _test_world_npc_attendance() -> void:
	print("[world — NPCs attend on the same path]")
	var w = _new_world()
	w.clock.day_count = 0
	w.clock.minutes_of_day = 540  # 09:00 Monday, Law in session
	var elara = w.actor_by_id("elara")
	var before: float = elara.get_skill("modern_politics")
	# NPCs act inside the tick, through the very same interactions.
	w.advance_time(40)  # two 20-min ticks of class
	_check(elara.get_skill("modern_politics") > before, "an NPC accrues the class skill via the shared path")

func _test_world_occurrences() -> void:
	print("[world — one-time events + attached sub-events]")
	var w = _new_world()
	# Attached sub-event: Adler calls on you, once, in week 1.
	w.player.location = "main_academic_building"
	w.clock.day_count = 7        # Monday of week 1
	w.clock.minutes_of_day = 540 # 09:00 (Law is MWF)
	var res := w.resolve_interaction(w.player, _find_iid(w, "focus_class"))
	_eq(str(res.get("one_time_id", "")), "adler_calls_on_you", "the attached sub-event fires inside the class")
	_check(w.player.flags.get("spoke_in_law", false), "the sub-event's effect applied")
	# Free-standing occurrence: attending a lecture (sets attended_lecture) later
	# fires 'noticed_by_professor', granting can_duel.
	var w2 = _new_world()
	w2.player.location = "main_academic_building"
	w2.clock.day_count = 0
	w2.clock.minutes_of_day = 540
	w2.player_take(_find_iid(w2, "focus_class"))  # sets flag, then advance_time fires the occurrence
	_check(w2.player.has_tag("can_duel"), "a free-standing occurrence fires and grants a tag")

func _test_world_save_load() -> void:
	print("[world — save/load round-trip]")
	var w = _new_world()
	w.player.location = "gardens"
	w.player.apply({"skills": {"shaping": 3.5}, "tags": ["pyromancer"]})
	w.clock.day_count = 4
	w.clock.minutes_of_day = 812
	w.fired["some_event"] = true
	var snap := w.to_dict()
	var w2 = _new_world()
	w2.from_dict(snap)
	_eq(w2.player.location, "gardens", "location restored")
	_approx(w2.player.get_skill("shaping"), 3.5, "skill restored")
	_check(w2.player.has_tag("pyromancer"), "tag restored")
	_eq(w2.clock.day_count, 4, "clock day restored")
	_eq(w2.clock.minutes_of_day, 812, "clock minute restored")
	_check(w2.fired.get("some_event", false), "fired-event ledger restored")
	_eq(w2.actors.size(), w.actors.size(), "roster restored")

func _test_descriptors() -> void:
	print("[descriptors — numberless surface]")
	_eq(DescriptorC.skill(0), "Untrained", "skill 0 -> Untrained")
	_eq(DescriptorC.skill(20), "Skilled", "skill 20 -> Skilled")
	_eq(DescriptorC.resource("energy", 90), "Fresh", "energy 90 -> Fresh")
	_eq(DescriptorC.resource("focus", 10), "Burnt out", "focus 10 -> Burnt out")
	_eq(DescriptorC.resource("mana", 90), "Brimming", "mana 90 -> Brimming")
	_eq(DescriptorC.need("hunger", 5), "Starving", "hunger 5 -> Starving")
	_eq(DescriptorC.relationship(0), "Stranger", "bond 0 -> Stranger")
	# The one dev-mode branch: word in player mode, number in dev mode.
	_eq(DescriptorC.value(false, "resource", "energy", 90), "Fresh", "player mode shows the word")
	_eq(DescriptorC.value(true, "resource", "energy", 90), "90", "dev mode shows the number")
	_eq(DescriptorC.value(true, "skill", "shaping", 3.5), "3.50", "dev mode shows skill as a float")

func _test_save_manager() -> void:
	print("[save manager — slots over a World]")
	var w = _new_world()
	w.player.location = "gardens"
	w.player.apply({"skills": {"shaping": 2.5}, "tags": ["pyromancer"]})
	w.clock.day_count = 3
	w.clock.minutes_of_day = 615
	_check(SaveManagerC.save(w, 5), "save writes a slot")
	var info: Dictionary = SaveManagerC.slot_info(5)
	_check(info.get("exists", false), "slot header reads without a full load")
	_eq(str(info.get("name", "")), w.player.name, "header carries the player name")
	var w2 = _new_world()
	_check(SaveManagerC.load_into(w2, 5), "load succeeds")
	_eq(w2.player.location, "gardens", "loaded location")
	_approx(w2.player.get_skill("shaping"), 2.5, "loaded skill")
	_check(w2.player.has_tag("pyromancer"), "loaded tag")
	_eq(w2.clock.day_count, 3, "loaded clock day")
	_eq(w2.clock.minutes_of_day, 615, "loaded clock minute")
	SaveManagerC.delete(5)
	_check(not SaveManagerC.slot_info(5).get("exists", false), "slot deleted")

func _test_core_academy_smoke() -> void:
	print("[core academy — the UI runs on the World]")
	Game.boot()  # fresh world for the mode to read
	var packed: PackedScene = load("res://scenes/modes/CoreAcademyMode.tscn")
	var ac = packed.instantiate()
	add_child(ac)  # _ready builds the UI and binds to Game.world
	_check(ac.action_container.get_child_count() > 0, "the academy renders an action list from the World")
	# Taking an action drives the World: the clock advances by the action's duration.
	var study := _find_iid_w(Game.world, "study_room")
	_check(not study.is_empty(), "study is available in the dorm")
	var t0: String = Game.world.clock.time_string()
	ac._on_action(study)
	_check(Game.world.clock.time_string() != t0, "taking an action advances the world clock through the UI")
	ac.free()
	Game.boot()  # leave a clean world for anything after

func _find_iid_w(w, iid: String) -> Dictionary:
	for i in w.available_interactions(w.player):
		if str(i.get("id", "")) == iid:
			return i
	return {}

func _iids(interactions: Array) -> Array:
	var out: Array = []
	for i in interactions:
		out.append(str(i.get("id", "")))
	return out

func _find_iid(w, iid: String) -> Dictionary:
	for i in w.available_interactions(w.player):
		if str(i.get("id", "")) == iid:
			return i
	return {}
