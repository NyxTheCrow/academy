extends "res://scripts/GameMode.gd"
## AcademyMode — the exploration / location view and base mode.
##
## Shows where you are (location + description), the time, your stats/tags, the
## other students and where they are, a journal, and the actions available here
## right now. Actions come from GameState.available_actions() — location actions
## whose tag/time requirements you meet, plus movement to connected locations.

var header_label: Label
var date_label: Label
var stats_label: Label
var tags_label: RichTextLabel
var relations_label: Label
var students_label: RichTextLabel
var place_label: Label
var place_desc: Label
var log_box: RichTextLabel
var action_container: VBoxContainer

func _ready() -> void:
	_build_ui()
	GameState.state_changed.connect(_refresh)
	GameState.message.connect(_on_message)
	_refresh()
	_on_message("[i]Another morning at the Academy. Where will you go, and what will you do?[/i]")

func on_resumed() -> void:
	_refresh()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.11, 0.16)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	add_child(margin)

	var root_h := HBoxContainer.new()
	root_h.add_theme_constant_override("separation", 18)
	margin.add_child(root_h)

	# --- Sidebar (scrollable): clock, stats, tags, relationships, students ---
	var sidebar_scroll := ScrollContainer.new()
	sidebar_scroll.custom_minimum_size = Vector2(320, 0)
	sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_h.add_child(sidebar_scroll)

	var sidebar := VBoxContainer.new()
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_constant_override("separation", 10)
	sidebar_scroll.add_child(sidebar)

	header_label = Label.new()
	header_label.add_theme_font_size_override("font_size", 20)
	sidebar.add_child(header_label)

	date_label = Label.new()
	date_label.add_theme_font_size_override("font_size", 16)
	date_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(date_label)

	sidebar.add_child(HSeparator.new())
	sidebar.add_child(_title("Stats"))
	stats_label = Label.new()
	sidebar.add_child(stats_label)

	sidebar.add_child(_title("Tags"))
	tags_label = RichTextLabel.new()
	tags_label.bbcode_enabled = true
	tags_label.fit_content = true
	tags_label.custom_minimum_size = Vector2(0, 24)
	sidebar.add_child(tags_label)

	sidebar.add_child(HSeparator.new())
	sidebar.add_child(_title("Relationships"))
	relations_label = Label.new()
	sidebar.add_child(relations_label)

	sidebar.add_child(HSeparator.new())
	sidebar.add_child(_title("Other Students"))
	students_label = RichTextLabel.new()
	students_label.bbcode_enabled = true
	students_label.fit_content = true
	students_label.custom_minimum_size = Vector2(0, 40)
	sidebar.add_child(students_label)

	sidebar.add_child(HSeparator.new())
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(func(): GameState.save_game())
	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.pressed.connect(func(): GameState.load_game())
	save_row.add_child(save_btn)
	save_row.add_child(load_btn)
	sidebar.add_child(save_row)

	# --- Main column: location, journal, actions ---
	var main_v := VBoxContainer.new()
	main_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_v.add_theme_constant_override("separation", 10)
	root_h.add_child(main_v)

	place_label = Label.new()
	place_label.add_theme_font_size_override("font_size", 24)
	main_v.add_child(place_label)
	place_desc = Label.new()
	place_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	place_desc.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	main_v.add_child(place_desc)

	main_v.add_child(_title("Journal"))
	log_box = RichTextLabel.new()
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.custom_minimum_size = Vector2(0, 120)
	log_box.bbcode_enabled = true
	log_box.scroll_active = true
	log_box.scroll_following = true
	main_v.add_child(log_box)

	main_v.add_child(_title("Actions"))
	var act_scroll := ScrollContainer.new()
	act_scroll.custom_minimum_size = Vector2(0, 190)
	act_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_v.add_child(act_scroll)
	action_container = VBoxContainer.new()
	action_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_container.add_theme_constant_override("separation", 6)
	act_scroll.add_child(action_container)

func _title(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = "— %s —" % text
	lbl.add_theme_font_size_override("font_size", 15)
	return lbl

func _refresh() -> void:
	if date_label == null:
		return
	header_label.text = GameState.player_name + ("   [DEV]" if GameState.dev_mode else "")
	date_label.text = GameState.date_string()

	var loc := GameState.current_location()
	place_label.text = str(loc.get("name", GameState.location))
	place_desc.text = str(loc.get("description", ""))

	var s := "Energy:  %d / %d\n\n" % [GameState.energy, GameState.max_energy]
	for k in GameState.stats:
		s += "%s:  %d\n" % [str(k).capitalize(), GameState.stats[k]]
	stats_label.text = s

	# Tags are always shown (they gate what you can do); dev mode just adds NPCs'.
	tags_label.text = "[color=gray]%s[/color]" % (", ".join(PackedStringArray(GameState.tags)) if not GameState.tags.is_empty() else "none")

	if GameState.relationships.is_empty():
		relations_label.text = "(no bonds yet)"
	else:
		var r := ""
		for npc in GameState.relationships:
			r += "%s:  %d\n" % [str(npc).capitalize(), GameState.relationships[npc]]
		relations_label.text = r

	_refresh_students()
	_rebuild_actions()

func _refresh_students() -> void:
	var out := ""
	for npc in Students.npcs:
		var here := "  [color=lightgreen](here)[/color]" if npc["location"] == GameState.location else ""
		out += "[b]%s[/b] @ %s%s\n    [color=gray]%s[/color]\n" % [
			npc["name"], Students.location_name(npc["location"]), here, npc["current_action"]]
		if GameState.dev_mode:
			var st: Dictionary = npc["stats"]
			out += "    [color=dimgray]MAG %d · CMB %d · KN %d · CHA %d · tags: %s[/color]\n" % [
				int(st.get("magic", 0)), int(st.get("combat", 0)), int(st.get("knowledge", 0)),
				int(st.get("charisma", 0)), ", ".join(PackedStringArray(npc["tags"]))]
	students_label.text = out

func _rebuild_actions() -> void:
	for c in action_container.get_children():
		c.queue_free()

	var actions := GameState.available_actions()
	if actions.is_empty():
		var lbl := Label.new()
		lbl.text = "(Nothing to do here.)"
		action_container.add_child(lbl)
		return

	for a in actions:
		var btn := Button.new()
		btn.text = _action_label(a)
		btn.tooltip_text = a.get("description", "")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.clip_text = true
		btn.pressed.connect(_on_action_pressed.bind(a))
		action_container.add_child(btn)

func _action_label(a: Dictionary) -> String:
	var label: String = a.get("name", "Action")
	if a.has("goto"):
		label = "→ " + label
	var dur := int(a.get("duration", 0))
	if dur > 0:
		label += "   (%d min)" % dur
	if a.has("dialogue"):
		label += "  [talk]"
	elif a.has("combat"):
		label += "  [fight]"
	return label

func _on_action_pressed(a: Dictionary) -> void:
	var dur := int(a.get("duration", GameState.WALK_MINUTES))
	if a.has("dialogue"):
		var res: Dictionary = await Director.run_mode("dialogue", {"scene_id": a["dialogue"]})
		GameState.apply_effects(a.get("effects", {}))
		GameState.apply_effects(res.get("effects", {}))
		GameState.advance_time(dur)
	elif a.has("combat"):
		var res2: Dictionary = await Director.run_mode("combat", {"encounter_id": a["combat"]})
		GameState.apply_effects(a.get("effects", {}))
		GameState.apply_effects(res2.get("effects", {}))
		GameState.advance_time(dur)
	elif a.get("sleep", false):
		GameState.sleep()
	elif a.has("goto"):
		GameState.set_location(str(a["goto"]))
		GameState.advance_time(dur)
	else:
		GameState.apply_effects(a.get("effects", {}))
		GameState.advance_time(dur)
		GameState.message.emit("You spend %d minutes: %s." % [dur, a.get("name", "…")])

func _on_message(text: String) -> void:
	if log_box != null:
		log_box.append_text(text + "\n")
