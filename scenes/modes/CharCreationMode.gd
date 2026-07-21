extends "res://scripts/GameMode.gd"
## CharCreationMode — the new-game setup screen.
##
## Collects a name, a data-driven background (which grants starting morale and
## tags), and the dev/normal display choice, then writes them into GameState
## and hands off to the academy.

var _name_edit: LineEdit
var _bg_option: OptionButton
var _bg_desc: Label
var _dev_check: CheckBox

func enter(_context: Dictionary) -> void:
	_build_ui()
	_refresh()

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
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	margin.add_child(v)

	var title := Label.new()
	title.text = "Enrolment"
	title.add_theme_font_size_override("font_size", 26)
	v.add_child(title)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	var name_lbl := Label.new()
	name_lbl.text = "Name:"
	name_lbl.custom_minimum_size = Vector2(110, 0)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Student"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_lbl)
	name_row.add_child(_name_edit)
	v.add_child(name_row)

	v.add_child(HSeparator.new())
	var bg_lbl := Label.new()
	bg_lbl.text = "Background:"
	v.add_child(bg_lbl)
	_bg_option = OptionButton.new()
	for i in GameData.backgrounds.size():
		_bg_option.add_item(GameData.backgrounds[i].get("name", "Background"), i)
	_bg_option.item_selected.connect(func(_i): _refresh())
	v.add_child(_bg_option)
	_bg_desc = Label.new()
	_bg_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bg_desc.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	v.add_child(_bg_desc)

	v.add_child(HSeparator.new())
	_dev_check = CheckBox.new()
	_dev_check.text = "Developer mode (show numbers and all data)"
	v.add_child(_dev_check)

	var begin := Button.new()
	begin.text = "Begin the Year  ▸"
	begin.pressed.connect(_on_begin)
	v.add_child(begin)

func _refresh() -> void:
	if GameData.backgrounds.size() > 0:
		var idx: int = maxi(0, _bg_option.get_selected_id())
		_bg_desc.text = GameData.backgrounds[idx].get("description", "")

func _on_begin() -> void:
	GameState.reset()
	var chosen_name := _name_edit.text.strip_edges()
	GameState.player_name = chosen_name if chosen_name != "" else "Student"
	GameState.dev_mode = _dev_check.button_pressed
	if GameData.backgrounds.size() > 0:
		var idx: int = maxi(0, _bg_option.get_selected_id())
		GameState.apply_effects(GameData.backgrounds[idx].get("effects", {}))
	Students.reset()
	finished.emit({})
