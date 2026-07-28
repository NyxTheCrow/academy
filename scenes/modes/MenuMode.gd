extends "res://scripts/GameMode.gd"
## MenuMode — shared scaffold for the simple full-screen menus (Character,
## Schedule, People, Spells, Inventory). Subclasses override _menu_title() and
## _populate(); call _repopulate() to rebuild after an interactive change.

var content: VBoxContainer
var mode_context := {}

func enter(context: Dictionary) -> void:
	mode_context = context
	_scaffold(_menu_title())
	_repopulate()

func _menu_title() -> String:
	return "Menu"

func _populate() -> void:
	pass

func _repopulate() -> void:
	for c in content.get_children():
		c.queue_free()
	_populate()

func _scaffold(title: String) -> void:
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
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 24)
	top.add_child(t)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): finished.emit({}))
	top.add_child(close)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)

# --- Small builders for subclasses ------------------------------------------
func _h(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	return l

func _kv(key: String, value: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var k := Label.new()
	k.text = key
	k.custom_minimum_size = Vector2(150, 0)
	k.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	h.add_child(k)
	var val := Label.new()
	val.text = value
	val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(val)
	return h

## Render a character's full aptitude stat sheet into `content`: Focus, then
## every registry stat indented by its parent/substat hierarchy (class levels
## included). Shared by the player's character sheet and the NPC detail page so
## the MC and the NPCs carry — and grow — on exactly the same sheet.
func _stat_sheet(stats: Dictionary) -> void:
	content.add_child(_kv("Focus", str(int(stats.get("focus", 0)))))
	for entry in GameData.stats_registry:
		var sid := str(entry.get("id", ""))
		if sid == "":
			continue
		var nm := str(entry.get("name", sid))
		var indent: String = "      " if str(entry.get("parent", "")) != "" else ""
		content.add_child(_kv(indent + nm, "%.2f" % float(stats.get(sid, 0))))

func _rich(bbcode: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.text = bbcode
	return r
