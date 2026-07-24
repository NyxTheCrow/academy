extends "res://scripts/GameMode.gd"
## AcademyMode — the exploration / location view and base mode.
##
## Player mode shows no numbers: energy, stats, and bonds appear as words
## (Fresh / Adept / Friend). Dev mode shows the raw numbers. Hoverable "chips"
## (stat names, tags) surface a lexicon definition on hover and open the
## searchable Lexicon on click.

var header_label: Label
var date_label: Label
var stats_box: VBoxContainer
var tags_title: Label
var tags_flow: HFlowContainer
var relations_label: Label
var students_label: RichTextLabel
var place_label: Label
var place_desc: Label
var log_box: RichTextLabel
var action_container: VBoxContainer
var editor_btn: Button

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

	# --- Sidebar (scrollable) ---
	var sidebar_scroll := ScrollContainer.new()
	sidebar_scroll.custom_minimum_size = Vector2(330, 0)
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
	sidebar.add_child(_title("Condition"))
	stats_box = VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 2)
	sidebar.add_child(stats_box)

	tags_title = _title("Tags")
	sidebar.add_child(tags_title)
	tags_flow = HFlowContainer.new()
	sidebar.add_child(tags_flow)

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
	sidebar.add_child(_title("Menus"))
	for m in [["Character", "character"], ["Schedule", "schedule"], ["Other People", "people"],
			["Spells", "spells"], ["Inventory", "inventory"], ["Lexicon", "lexicon"], ["Saves", "saves"]]:
		var mb := Button.new()
		mb.text = m[0]
		mb.pressed.connect(_open_menu.bind(m[1]))
		sidebar.add_child(mb)

	# Dev-only data editor.
	editor_btn = Button.new()
	editor_btn.text = "Data Editor (dev)"
	editor_btn.pressed.connect(_open_menu.bind("editor"))
	sidebar.add_child(editor_btn)

	var menu_btn := Button.new()
	menu_btn.text = "Return to Main Menu"
	menu_btn.pressed.connect(func(): finished.emit({"action": "main_menu"}))
	sidebar.add_child(menu_btn)

	# --- Main column ---
	var main_v := VBoxContainer.new()
	main_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_v.add_theme_constant_override("separation", 10)
	root_h.add_child(main_v)

	place_label = Label.new()
	place_label.add_theme_font_size_override("font_size", 24)
	place_label.mouse_filter = Control.MOUSE_FILTER_STOP
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

# --- A hoverable term chip: tooltip = lexicon definition, click = open it ----
func _hover_chip(key: String, display: String) -> Button:
	var b := Button.new()
	b.text = display
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var def := Lexicon.define(key)
	if def != "":
		b.tooltip_text = def
	b.pressed.connect(_open_lexicon.bind(key))
	return b

func _open_lexicon(focus := "") -> void:
	await Director.run_mode("lexicon", {"focus": focus})

func _open_menu(mode: String) -> void:
	await Director.run_mode(mode, {})

func _refresh() -> void:
	if date_label == null:
		return
	header_label.text = GameState.player_name + ("   [DEV]" if GameState.dev_mode else "")
	# The clock/date is legible in both modes (numbers here are fine).
	date_label.text = GameState.date_string()
	if editor_btn != null:
		editor_btn.visible = GameState.dev_mode

	var loc := GameState.current_location()
	place_label.text = str(loc.get("name", GameState.location))
	place_label.tooltip_text = Lexicon.define(str(loc.get("name", "")))
	place_desc.text = str(loc.get("description", ""))

	_rebuild_stats()
	_rebuild_tags()
	_rebuild_relations()
	_refresh_students()
	_rebuild_actions()

func _rebuild_stats() -> void:
	for c in stats_box.get_children():
		c.queue_free()
	stats_box.add_child(_stat_row("Energy", "Energy",
		GameState.energy_descriptor(), "%d / %d" % [GameState.energy, GameState.max_energy]))
	for k in GameState.stats:
		if GameState.is_aptitude(str(k)):
			continue  # aptitude stats are hidden from the player (and the UI) entirely
		var v := int(GameState.stats[k])
		stats_box.add_child(_stat_row(str(k), str(k).capitalize(),
			GameState.stat_word(str(k)), str(v)))
	# Visible self-assessed needs (words in player mode, numbers in dev).
	for nk in ["hunger", "thirst", "bladder", "hygiene", "calm", "mana"]:
		var nv := int(GameState.needs.get(nk, 0))
		var label: String = "Mana" if nk == "mana" else str(nk).capitalize()
		stats_box.add_child(_stat_row(nk, label, GameState.need_descriptor(nk, nv), str(nv)))

func _stat_row(key: String, label: String, descriptor: String, number: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var chip := _hover_chip(key, label)
	chip.custom_minimum_size = Vector2(120, 0)
	h.add_child(chip)
	var val := Label.new()
	val.text = number if GameState.dev_mode else descriptor
	h.add_child(val)
	return h

func _rebuild_tags() -> void:
	# Tags are hidden from the player; only dev mode sees them.
	var show_tags := GameState.dev_mode
	tags_title.visible = show_tags
	tags_flow.visible = show_tags
	for c in tags_flow.get_children():
		c.queue_free()
	if not show_tags:
		return
	if GameState.tags.is_empty():
		var l := Label.new()
		l.text = "(none)"
		tags_flow.add_child(l)
		return
	for t in GameState.tags:
		tags_flow.add_child(_hover_chip(str(t), str(t)))

func _rebuild_relations() -> void:
	if GameState.relationships.is_empty():
		relations_label.text = "(no bonds yet)"
		return
	var r := ""
	for npc in GameState.relationships:
		var v := int(GameState.relationships[npc])
		var shown := str(v) if GameState.dev_mode else GameState.relationship_descriptor(v)
		r += "%s:  %s\n" % [str(npc).capitalize(), shown]
	relations_label.text = r

func _refresh_students() -> void:
	var out := ""
	for npc in Students.npcs:
		var here := "  [color=lightgreen](here)[/color]" if npc["location"] == GameState.location else ""
		out += "[b]%s[/b] @ %s%s\n    [color=gray]%s[/color]\n" % [
			npc["name"], Students.location_name(npc["location"]), here, npc["current_action"]]
		if GameState.dev_mode:
			var st: Dictionary = npc["stats"]
			out += "    [color=dimgray]focus %d · tags: %s[/color]\n" % [
				int(st.get("focus", 0)), ", ".join(PackedStringArray(npc["tags"]))]
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
	# Time cost is a small number, but it's a clock reading rather than a hidden
	# stat, so it stays visible in both modes (the design keeps time legible).
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
	elif a.has("tactical"):
		var rest: Dictionary = await Director.run_mode("tickcombat", {"config": a.get("tactical", {})})
		GameState.apply_effects(a.get("effects", {}))
		GameState.apply_effects(rest.get("effects", {}))
		GameState.advance_time(dur)
	elif a.get("wait_for_class", false):
		GameState.wait_for_class()
	elif a.get("sleep", false):
		GameState.sleep()
	elif a.has("goto"):
		GameState.set_location(str(a["goto"]))
		GameState.advance_time(dur)
	else:
		GameState.apply_effects(a.get("effects", {}))
		GameState.advance_time(dur)
		GameState.message.emit("You spend a while: %s." % a.get("name", "…"))

func _on_message(text: String) -> void:
	if log_box != null:
		log_box.append_text(text + "\n")
