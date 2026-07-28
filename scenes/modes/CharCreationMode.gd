extends "res://scripts/GameMode.gd"
## CharCreationMode — a multi-step new-game wizard.
##
## Steps: background → difficulty (character points) → source of magic → sex →
## traits → life story → personality → finish (name, skip-intro, dev). Most
## steps are prototype stubs; the flow and the character-point budget are the
## point. On finish it seeds GameState and either drops you in your room on
## Monday (skip) or at the school gates on Sunday evening (full intro).

var _step := 0
var _choices := {}                  # step key -> chosen value
var _points := 100                  # budget, set by the difficulty step
var _final := {"name": "", "skip": false, "dev": false}

var _steps := [
	{"key": "background", "title": "Background", "kind": "select", "options": [
		{"label": "Commoner", "value": "commoner"},
		{"label": "Noble  (locked)", "value": "noble", "disabled": true}]},
	{"key": "difficulty", "title": "Difficulty — Character Points", "kind": "points",
		"blurb": "More points = a more advantaged character.", "options": [
		{"label": "50  — least advantaged", "value": 50},
		{"label": "75", "value": 75},
		{"label": "100", "value": 100},
		{"label": "125", "value": 125},
		{"label": "150 — most advantaged", "value": 150}]},
	{"key": "magic_source", "title": "Source of Magic", "kind": "select",
		"blurb": "Costs nothing for now.", "options": [
		{"label": "Magical Inheritance", "value": "inheritance"},
		{"label": "Bastardry", "value": "bastardry"},
		{"label": "Influence", "value": "influence"}]},
	{"key": "sex", "title": "Sex", "kind": "select", "options": [
		{"label": "Male", "value": "male"},
		{"label": "Female", "value": "female"}]},
	{"key": "traits", "title": "Traits", "kind": "placeholder",
		"blurb": "Magical / mental / physical traits. Negative traits grant character points; positive traits cost them. (No traits defined yet.)"},
	{"key": "life_story", "title": "Life Story", "kind": "placeholder",
		"blurb": "Pick a social class, then various positive/negative upbringing events. (No options defined yet.)"},
	{"key": "personality", "title": "Personality", "kind": "placeholder",
		"blurb": "Define your character's temperament. (No options defined yet.)"},
	{"key": "finish", "title": "Begin the Year", "kind": "finish"},
]

var title_label: Label
var step_content: VBoxContainer
var points_label: Label
var back_btn: Button
var next_btn: Button

func enter(_context: Dictionary) -> void:
	_apply_tuning()
	_build_ui()
	_render()

## Rebuild the difficulty step's point options from data/tuning.json
## ("char_creation.difficulty_points"), so the budget tiers are editable.
func _apply_tuning() -> void:
	var cc: Dictionary = GameData.tuning.get("char_creation", {}) if GameData.tuning is Dictionary else {}
	var pts: Array = cc.get("difficulty_points", [])
	if pts.is_empty():
		return
	var opts: Array = []
	for i in pts.size():
		var val := int(pts[i])
		var label := str(val)
		if i == 0:
			label += "  — least advantaged"
		elif i == pts.size() - 1:
			label += "  — most advantaged"
		opts.append({"label": label, "value": val})
	for step in _steps:
		if step.get("key", "") == "difficulty":
			step["options"] = opts
	_points = int(pts[pts.size() / 2])   # default budget = the middle tier

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.10, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 460)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)

	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 24)
	v.add_child(title_label)
	v.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	step_content = VBoxContainer.new()
	step_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	step_content.add_theme_constant_override("separation", 6)
	scroll.add_child(step_content)

	v.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	v.add_child(footer)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func(): finished.emit({"started": false}))
	footer.add_child(cancel_btn)
	points_label = Label.new()
	points_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.7))
	footer.add_child(points_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	back_btn = Button.new()
	back_btn.text = "◂ Back"
	back_btn.pressed.connect(_on_back)
	footer.add_child(back_btn)
	next_btn = Button.new()
	next_btn.pressed.connect(_on_next)
	footer.add_child(next_btn)

func _render() -> void:
	var step: Dictionary = _steps[_step]
	title_label.text = "%d/%d   %s" % [_step + 1, _steps.size(), step.get("title", "")]
	for c in step_content.get_children():
		c.queue_free()

	if step.has("blurb"):
		var b := Label.new()
		b.text = str(step["blurb"])
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
		step_content.add_child(b)

	match step.get("kind", ""):
		"select", "points":
			for opt in step.get("options", []):
				step_content.add_child(_option_button(step["key"], opt))
		"placeholder":
			var note := Label.new()
			note.text = "(prototype — nothing to choose here yet; continue)"
			note.add_theme_color_override("font_color", Color(0.6, 0.62, 0.68))
			step_content.add_child(note)
		"finish":
			_build_finish()

	points_label.text = ("Character points: %d" % _points) if _choices.has("difficulty") else ""
	back_btn.disabled = _step == 0
	next_btn.text = "Begin  ▸" if step.get("kind", "") == "finish" else "Next  ▸"

func _option_button(key: String, opt: Dictionary) -> Button:
	var b := Button.new()
	var label: String = opt.get("label", "?")
	if _choices.get(key, null) == opt.get("value"):
		label = "●  " + label
	b.text = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.disabled = opt.get("disabled", false)
	b.pressed.connect(_on_select.bind(key, opt))
	return b

func _build_finish() -> void:
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	var nl := Label.new()
	nl.text = "Name:"
	nl.custom_minimum_size = Vector2(110, 0)
	name_row.add_child(nl)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Student"
	name_edit.text = str(_final["name"])
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(t): _final["name"] = t)
	name_row.add_child(name_edit)
	step_content.add_child(name_row)

	var skip := CheckBox.new()
	skip.text = "Skip introduction (start Monday, in your room)"
	skip.button_pressed = bool(_final["skip"])
	skip.toggled.connect(func(v): _final["skip"] = v)
	step_content.add_child(skip)

	var dev := CheckBox.new()
	dev.text = "Developer mode (show numbers and all data)"
	dev.button_pressed = bool(_final["dev"])
	dev.toggled.connect(func(v): _final["dev"] = v)
	step_content.add_child(dev)

func _on_select(key: String, opt: Dictionary) -> void:
	_choices[key] = opt.get("value")
	if _steps[_step].get("kind", "") == "points":
		_points = int(opt.get("value"))
	_render()

func _on_back() -> void:
	if _step > 0:
		_step -= 1
		_render()

func _on_next() -> void:
	if _steps[_step].get("kind", "") == "finish":
		_begin()
	else:
		_step += 1
		_render()

func _begin() -> void:
	GameState.reset()
	var chosen_name: String = str(_final["name"]).strip_edges()
	GameState.player_name = chosen_name if chosen_name != "" else "Student"
	GameState.dev_mode = bool(_final["dev"])

	# Record choices as tags/flags (they don't do anything yet).
	GameState.flags["char_points"] = _points
	if _choices.has("background"):
		GameState.add_tag(str(_choices["background"]))
	if _choices.has("sex"):
		GameState.add_tag(str(_choices["sex"]))
	if _choices.has("magic_source"):
		GameState.add_tag("src_" + str(_choices["magic_source"]))

	if bool(_final["skip"]):
		# Straight into your room on Monday morning (reset defaults already do this).
		GameState.set_location("dormitories")
	else:
		# Sunday, 17:00, at the gates — the full introduction.
		GameState.day_count = 6          # Sunday
		GameState.minutes_of_day = 17 * 60
		GameState.set_location("school_gates")

	Students.reset()
	finished.emit({"started": true})
