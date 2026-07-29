extends "res://scripts/GameMode.gd"
## CoreSavesMode — save/load slots for the new core, backed by SaveManager over
## Game.world. `load_only` context (from the main menu) hides the Save buttons.

const SaveManagerC := preload("res://core/SaveManager.gd")
const SLOTS := 6

var _load_only := false
var content_box: VBoxContainer

func enter(context: Dictionary) -> void:
	_load_only = context.get("load_only", false)
	_build_ui()
	_repopulate()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)
	var top := HBoxContainer.new()
	var t := Label.new()
	t.text = "Saves (core)"
	t.add_theme_font_size_override("font_size", 24)
	top.add_child(t)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): finished.emit({}))
	top.add_child(close)
	v.add_child(top)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	content_box = VBoxContainer.new()
	content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_box.add_theme_constant_override("separation", 8)
	scroll.add_child(content_box)

func _repopulate() -> void:
	for c in content_box.get_children():
		c.queue_free()
	for slot in range(1, SLOTS + 1):
		content_box.add_child(_slot_row(slot))

func _slot_row(slot: int) -> HBoxContainer:
	var info: Dictionary = SaveManagerC.slot_info(slot)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if info.get("exists", false):
		lbl.text = "[b]Slot %d[/b]  %s\n[color=gray]%s[/color]" % [slot, info.get("name", "?"), info.get("label", "")]
	else:
		lbl.text = "[b]Slot %d[/b]  [color=dimgray](empty)[/color]" % slot
	row.add_child(lbl)
	if not _load_only:
		var save_btn := Button.new()
		save_btn.text = "Save"
		save_btn.pressed.connect(_on_save.bind(slot))
		row.add_child(save_btn)
	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.disabled = not info.get("exists", false)
	load_btn.pressed.connect(_on_load.bind(slot))
	row.add_child(load_btn)
	var del_btn := Button.new()
	del_btn.text = "Delete"
	del_btn.disabled = not info.get("exists", false)
	del_btn.pressed.connect(_on_delete.bind(slot))
	row.add_child(del_btn)
	return row

func _on_save(slot: int) -> void:
	SaveManagerC.save(Game.world, slot)
	_repopulate()

func _on_load(slot: int) -> void:
	Game.ensure_world()
	if SaveManagerC.load_into(Game.world, slot):
		Game.world.state_changed.emit()
		finished.emit({"loaded": true})

func _on_delete(slot: int) -> void:
	SaveManagerC.delete(slot)
	_repopulate()
