extends "res://scripts/GameMode.gd"
## SimulationMode — a ghost / observer mode. You don't play a character: you
## advance the clock and watch the NPC world roam, attend class, and learn at
## the weighted rates. Reachable from the main menu, beside the editor.

const LOC_ORDER := ["classroom", "corridor_a", "corridor_b", "room", "dueling_room",
	"school_gates", "courtyard", "amphitheater"]

var date_label: Label
var list_box: VBoxContainer

func enter(_context: Dictionary) -> void:
	_build_ui()
	GameState.state_changed.connect(_refresh)
	_refresh()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	var title := Label.new()
	title.text = "Simulation  (ghost)"
	title.add_theme_font_size_override("font_size", 22)
	top.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var back := Button.new()
	back.text = "Return to Main Menu"
	back.pressed.connect(func(): finished.emit({}))
	top.add_child(back)

	date_label = Label.new()
	date_label.add_theme_font_size_override("font_size", 16)
	v.add_child(date_label)

	var ctl := HBoxContainer.new()
	ctl.add_theme_constant_override("separation", 8)
	v.add_child(ctl)
	var step := Label.new()
	step.text = "Advance:"
	ctl.add_child(step)
	for pair in [["+20 min", 20], ["+1 hour", 60], ["+4 hours", 240], ["+1 day", 1440]]:
		var b := Button.new()
		b.text = str(pair[0])
		b.pressed.connect(_advance.bind(int(pair[1])))
		ctl.add_child(b)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 4)
	scroll.add_child(list_box)

func _advance(mins: int) -> void:
	GameState.advance_time(mins)   # drives the NPCs; state_changed -> _refresh

func _refresh() -> void:
	if date_label == null:
		return
	date_label.text = "Ghost view · " + GameState.date_string()
	for c in list_box.get_children():
		c.queue_free()

	var by_loc: Dictionary = {}
	for npc in Students.npcs:
		var l := str(npc["location"])
		if not by_loc.has(l):
			by_loc[l] = []
		by_loc[l].append(npc)

	var shown: Array = []
	for loc in LOC_ORDER:
		if by_loc.has(loc):
			_render_location(loc, by_loc[loc])
			shown.append(loc)
	for loc in by_loc:
		if not (loc in shown):
			_render_location(str(loc), by_loc[loc])

func _render_location(loc: String, npcs: Array) -> void:
	var cls := GameState.class_in_session(loc)
	var head := Students.location_name(loc) + ("  ·  [%s in session]" % str(cls.get("name", "")) if not cls.is_empty() else "")
	var h := Label.new()
	h.text = "— %s  (%d) —" % [head, npcs.size()]
	h.add_theme_font_size_override("font_size", 15)
	h.add_theme_color_override("font_color", Color(0.8, 0.82, 0.9))
	list_box.add_child(h)
	for npc in npcs:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.text = "  %s — %s%s" % [npc["name"], npc["current_action"], _learned(npc)]
		b.pressed.connect(_open.bind(str(npc["id"])))
		list_box.add_child(b)

## The class levels a character has accrued so far (aptitude stats above 0).
func _learned(npc: Dictionary) -> String:
	var parts: Array = []
	for k in npc["stats"]:
		if GameState.is_aptitude(str(k)):
			var val := float(npc["stats"][k])
			if val > 0.001:
				parts.append("%s %.2f" % [str(k), val])
	return ("    [" + ", ".join(PackedStringArray(parts)) + "]") if not parts.is_empty() else ""

func _open(id: String) -> void:
	await Director.run_mode("character_detail", {"npc_id": id})
	_refresh()
