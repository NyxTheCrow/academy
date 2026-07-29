extends "res://scripts/GameMode.gd"
## SchemaEditorMode — a data editor whose forms are generated from ContentSchema.
##
## The old EditorMode made you hand-edit a whole JSON file as raw text. This one
## reads the schema and renders a proper form per entry: dropdowns for references
## (pick a location from a list, not by typing its id), structured rows for
## skill/effect maps, and a dedicated variant editor for graded-reveal
## descriptions. Because it is fully schema-driven, adding a new content type or
## field to ContentSchema makes it editable here with ZERO new UI code — which is
## exactly what makes adding spells / places / characters / traits / conversations
## easy.
##
## Layout:  [ type list ] [ entry list + New/Dup/Del ] [ auto-generated form ]
## Save writes a user:// override for the type's file; Validate runs the schema
## linter over the working copy and lists any dangling refs / bad keys inline.

const ContentC := preload("res://core/Content.gd")
const SchemaC := preload("res://core/ContentSchema.gd")
const ValidatorC := preload("res://core/ContentValidator.gd")

var _content: Content = null      # Content instance (loaded from content/)
var _schema: Dictionary = {}
var _working: Dictionary = {}     # type -> collection (isolated edit copy)
var _type := ""
var _entry: Dictionary = {}       # reference into the working collection
var _key := ""                    # dict-collection key (or the array entry's id)
var _standalone := false

var type_list: VBoxContainer
var entry_list: VBoxContainer
var form_box: VBoxContainer
var header: Label
var status: RichTextLabel

func enter(context: Dictionary) -> void:
	_standalone = context.get("standalone", false)
	_content = ContentC.new()
	_content.load_all()
	_schema = SchemaC.all()
	for t in _schema:
		_working[t] = _dup(_content.collection(t))
	_build_ui()
	_rebuild_type_list()
	if not _schema.is_empty():
		_select_type(_schema.keys()[0])

func _dup(v: Variant) -> Variant:
	if v is Dictionary: return (v as Dictionary).duplicate(true)
	if v is Array: return (v as Array).duplicate(true)
	return v

# --- UI scaffold ------------------------------------------------------------
func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	var title := Label.new()
	title.text = "Content Editor  (schema-driven)"
	title.add_theme_font_size_override("font_size", 22)
	top.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var validate_btn := Button.new()
	validate_btn.text = "Validate all"
	validate_btn.pressed.connect(_on_validate_all)
	top.add_child(validate_btn)
	var close := Button.new()
	close.text = "Return to Main Menu" if _standalone else "Close"
	close.pressed.connect(func(): finished.emit({}))
	top.add_child(close)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)

	body.add_child(_scroll_col(160, func(c): type_list = c))
	body.add_child(_scroll_col(220, func(c): entry_list = c))

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	header = Label.new()
	header.add_theme_font_size_override("font_size", 18)
	right.add_child(header)
	var form_scroll := ScrollContainer.new()
	form_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(form_scroll)
	form_box = VBoxContainer.new()
	form_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_box.add_theme_constant_override("separation", 10)
	form_scroll.add_child(form_box)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	right.add_child(actions)
	actions.add_child(_btn("Save file (override)", _on_save))
	actions.add_child(_btn("Write to project", _on_write_project))
	actions.add_child(_btn("Revert file", _on_revert))
	status = RichTextLabel.new()
	status.bbcode_enabled = true
	status.fit_content = true
	status.custom_minimum_size = Vector2(0, 48)
	right.add_child(status)

func _scroll_col(width: int, bind: Callable) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.custom_minimum_size = Vector2(width, 0)
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	s.add_child(col)
	bind.call(col)
	return s

func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b

# --- Type + entry lists -----------------------------------------------------
func _rebuild_type_list() -> void:
	for c in type_list.get_children():
		c.queue_free()
	for t in _schema:
		var b := Button.new()
		b.text = str(_schema[t].get("label", t))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_select_type.bind(t))
		type_list.add_child(b)

func _is_single() -> bool:
	return str(_schema.get(_type, {}).get("collection", "")) == "single"

func _select_type(t: String) -> void:
	_type = t
	_entry = {}
	_key = ""
	_rebuild_entry_list()
	_clear_form()
	if _is_single():
		_select_entry("(settings)")
	else:
		_set_status("[color=gray]%d entries. Pick one, or add a new %s.[/color]" % [_entry_ids().size(), t])

func _entry_ids() -> Array:
	if _is_single():
		return ["(settings)"]
	var col = _working.get(_type, null)
	if col is Dictionary:
		return col.keys()
	if col is Array:
		var out: Array = []
		for e in col:
			out.append(str(e.get("id", "?")))
		return out
	return []

func _rebuild_entry_list() -> void:
	for c in entry_list.get_children():
		c.queue_free()
	# A single-object type (tuning) has no roster — just its one settings entry.
	if not _is_single():
		var bar := HBoxContainer.new()
		bar.add_theme_constant_override("separation", 4)
		bar.add_child(_btn("+ New", _on_new_entry))
		bar.add_child(_btn("Dup", _on_duplicate))
		bar.add_child(_btn("Del", _on_delete))
		entry_list.add_child(bar)
		entry_list.add_child(HSeparator.new())
	for eid in _entry_ids():
		var b := Button.new()
		b.text = eid
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.pressed.connect(_select_entry.bind(str(eid)))
		entry_list.add_child(b)

func _select_entry(eid: String) -> void:
	if _is_single():
		_key = eid
		_entry = _working[_type]
		_build_form()
		return
	var col = _working.get(_type, null)
	if col is Dictionary:
		_key = eid
		_entry = col[eid]
	elif col is Array:
		for e in col:
			if str(e.get("id", "")) == eid:
				_entry = e
				_key = eid
				break
	_build_form()

# --- The schema-driven form -------------------------------------------------
func _clear_form() -> void:
	for c in form_box.get_children():
		c.queue_free()
	header.text = ""

func _build_form() -> void:
	_clear_form()
	if _entry.is_empty() and not (_working[_type] is Dictionary and _working[_type].has(_key)):
		return
	header.text = "%s  ·  %s" % [str(_schema[_type].get("label", _type)), _key]
	for field in _schema[_type].get("fields", []):
		form_box.add_child(_field_row(field))

func _field_row(field: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var lbl := Label.new()
	lbl.text = str(field.get("label", field["key"])) + ("" if not field.get("optional", false) else "  (optional)")
	lbl.add_theme_color_override("font_color", Color(0.72, 0.78, 0.9))
	row.add_child(lbl)
	row.add_child(_widget(field))
	return row

## Build the editing widget for one field, bound to _entry[field.key].
func _widget(field: Dictionary) -> Control:
	var key: String = field["key"]
	var t: String = field["type"]
	var val: Variant = _entry.get(key, null)
	match t:
		"text":
			return _line_edit(str(val) if val != null else "", func(s): _entry[key] = s)
		"multiline":
			return _text_edit(str(val) if val != null else "", func(s): _entry[key] = s, 60)
		"int", "float":
			return _num_edit(float(val) if val != null else 0.0, t == "int", func(n): _entry[key] = n)
		"bool":
			return _check(bool(val) if val != null else false, func(b): _entry[key] = b)
		"enum":
			return _option(field.get("options", []), str(val) if val != null else "", func(s): _entry[key] = s)
		"ref":
			var ids := _content.ids(field["ref"]).duplicate()
			ids.insert(0, "")
			return _option(ids, str(val) if val != null else "", func(s): _entry[key] = s)
		"tag_list", "string_list":
			return _string_list(val if val is Array else [], func(a): _entry[key] = a)
		"ref_list":
			return _ref_list(val if val is Array else [], field["ref"], func(a): _entry[key] = a)
		"map_num":
			return _map_num(val if val is Dictionary else {}, field.get("key_ref", ""), func(d): _entry[key] = d)
		"descriptions":
			return _descriptions(val, func(a): _entry[key] = a)
		"requirements", "trigger", "effects", "list", "object":
			return _json_block(val, field, func(v): _entry[key] = v)
	return _line_edit(str(val), func(s): _entry[key] = s)

# --- Primitive widgets ------------------------------------------------------
func _line_edit(text: String, on_change: Callable) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.text_changed.connect(func(s): on_change.call(s))
	return e

func _text_edit(text: String, on_change: Callable, h: int) -> TextEdit:
	var e := TextEdit.new()
	e.text = text
	e.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	e.custom_minimum_size = Vector2(0, h)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.text_changed.connect(func(): on_change.call(e.text))
	return e

func _num_edit(value: float, is_int: bool, on_change: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = -100000
	s.max_value = 100000
	s.step = 1 if is_int else 0.01
	s.value = value
	s.value_changed.connect(func(n): on_change.call(int(n) if is_int else n))
	return s

func _check(value: bool, on_change: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.button_pressed = value
	c.toggled.connect(func(b): on_change.call(b))
	return c

func _option(options: Array, value: String, on_change: Callable) -> OptionButton:
	var o := OptionButton.new()
	var sel := 0
	for i in options.size():
		o.add_item(str(options[i]) if str(options[i]) != "" else "(none)")
		if str(options[i]) == value:
			sel = i
	o.selected = sel
	o.item_selected.connect(func(i): on_change.call(str(options[i])))
	return o

# --- List widgets -----------------------------------------------------------
func _string_list(items: Array, on_change: Callable) -> Control:
	var data: Array = items.duplicate()
	var box := VBoxContainer.new()
	var rebuild := func(): pass
	rebuild = func():
		for c in box.get_children():
			c.queue_free()
		for i in data.size():
			var idx := i
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 4)
			var le := LineEdit.new()
			le.text = str(data[idx])
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			le.text_changed.connect(func(s): data[idx] = s; on_change.call(data))
			h.add_child(le)
			h.add_child(_btn("−", func(): data.remove_at(idx); on_change.call(data); rebuild.call()))
			box.add_child(h)
		box.add_child(_btn("+ add", func(): data.append(""); on_change.call(data); rebuild.call()))
	rebuild.call()
	return box

func _ref_list(items: Array, ref_type: String, on_change: Callable) -> Control:
	var data: Array = items.duplicate()
	var ids := _content.ids(ref_type).duplicate()
	ids.insert(0, "")
	var box := VBoxContainer.new()
	var rebuild := func(): pass
	rebuild = func():
		for c in box.get_children():
			c.queue_free()
		for i in data.size():
			var idx := i
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 4)
			h.add_child(_option(ids, str(data[idx]), func(s): data[idx] = s; on_change.call(data)))
			h.add_child(_btn("−", func(): data.remove_at(idx); on_change.call(data); rebuild.call()))
			box.add_child(h)
		box.add_child(_btn("+ add", func(): data.append(ids[0] if ids.size() > 0 else ""); on_change.call(data); rebuild.call()))
	rebuild.call()
	return box

func _map_num(m: Dictionary, key_ref: String, on_change: Callable) -> Control:
	var data: Dictionary = m.duplicate()
	var ids: Array = _content.ids(key_ref).duplicate() if key_ref != "" else []
	var box := VBoxContainer.new()
	var rebuild := func(): pass
	rebuild = func():
		for c in box.get_children():
			c.queue_free()
		for k in data.keys():
			var kk := str(k)
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 4)
			if key_ref != "":
				var opts := ids.duplicate()
				if not (kk in opts):
					opts.insert(0, kk)
				h.add_child(_option(opts, kk, func(s):
					var val = data[kk]; data.erase(kk); data[s] = val; on_change.call(data); rebuild.call()))
			else:
				var le := LineEdit.new()
				le.text = kk
				le.custom_minimum_size = Vector2(120, 0)
				le.text_submitted.connect(func(s):
					var val = data[kk]; data.erase(kk); data[s] = val; on_change.call(data); rebuild.call())
				h.add_child(le)
			var sb := SpinBox.new()
			sb.min_value = -100000; sb.max_value = 100000; sb.step = 0.05
			sb.value = float(data[kk])
			sb.value_changed.connect(func(n): data[kk] = n; on_change.call(data))
			h.add_child(sb)
			h.add_child(_btn("−", func(): data.erase(kk); on_change.call(data); rebuild.call()))
			box.add_child(h)
		var add_key: String = (ids[0] if ids.size() > 0 else "new_key")
		box.add_child(_btn("+ add", func():
			var nk := add_key
			var n := 2
			while data.has(nk):
				nk = "%s_%d" % [add_key, n]; n += 1
			data[nk] = 0.0; on_change.call(data); rebuild.call()))
	rebuild.call()
	return box

# --- Graded-reveal (descriptions) editor ------------------------------------
## Each variant is edited as { text, requires }. Higher-skill variants go first;
## a variant with empty requires is the fallback and belongs last.
func _descriptions(value: Variant, on_change: Callable) -> Control:
	var data: Array = _norm_variants(value)
	var box := VBoxContainer.new()
	var rebuild := func(): pass
	rebuild = func():
		for c in box.get_children():
			c.queue_free()
		for i in data.size():
			var idx := i
			var panel := PanelContainer.new()
			var pv := VBoxContainer.new()
			pv.add_theme_constant_override("separation", 3)
			var mc := MarginContainer.new()
			for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
				mc.add_theme_constant_override(side, 6)
			mc.add_child(pv)
			panel.add_child(mc)
			var head := HBoxContainer.new()
			var tag := Label.new()
			tag.text = "Variant %d%s" % [idx + 1, "  (fallback)" if (data[idx].get("requires", {}) as Dictionary).is_empty() else ""]
			tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			head.add_child(tag)
			head.add_child(_btn("▲", func(): _swap(data, idx, idx - 1); on_change.call(_out_variants(data)); rebuild.call()))
			head.add_child(_btn("▼", func(): _swap(data, idx, idx + 1); on_change.call(_out_variants(data)); rebuild.call()))
			head.add_child(_btn("−", func(): data.remove_at(idx); on_change.call(_out_variants(data)); rebuild.call()))
			pv.add_child(head)
			pv.add_child(_text_edit(str(data[idx].get("text", "")), func(s): data[idx]["text"] = s; on_change.call(_out_variants(data)), 54))
			var rq := Label.new()
			rq.text = "shown when (requirements JSON, {} = always):"
			rq.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
			pv.add_child(rq)
			pv.add_child(_json_line(data[idx].get("requires", {}), func(v): data[idx]["requires"] = v; on_change.call(_out_variants(data))))
			box.add_child(panel)
		box.add_child(_btn("+ add variant", func(): data.append({"text": "", "requires": {}}); on_change.call(_out_variants(data)); rebuild.call()))
	rebuild.call()
	return box

func _norm_variants(value: Variant) -> Array:
	var out: Array = []
	var list: Array = value if value is Array else ([value] if value != null else [])
	for v in list:
		if v is String:
			out.append({"text": v, "requires": {}})
		elif v is Dictionary:
			out.append({"text": str(v.get("text", "")), "requires": v.get("requires", {})})
	return out

## Serialize variant editors back to content shape: drop empty-requires down to a
## bare string is tempting, but keeping {text, requires} is simplest and validates.
func _out_variants(data: Array) -> Array:
	var out: Array = []
	for v in data:
		if (v.get("requires", {}) as Dictionary).is_empty():
			out.append({"text": str(v.get("text", ""))})
		else:
			out.append({"text": str(v.get("text", "")), "requires": v["requires"]})
	return out

func _swap(a: Array, i: int, j: int) -> void:
	if i < 0 or j < 0 or i >= a.size() or j >= a.size():
		return
	var tmp = a[i]; a[i] = a[j]; a[j] = tmp

# --- JSON block editor (requirements / effects / nested lists) --------------
## A focused JSON editor for the structured composite fields, with a live parse
## check and a palette of valid keys to insert. Validated again on Save.
func _json_block(value: Variant, field: Dictionary, on_change: Callable) -> Control:
	var box := VBoxContainer.new()
	var hint := Label.new()
	hint.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	hint.text = _keys_hint(field["type"])
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var te := _text_edit(JSON.stringify(value if value != null else _blank_for(field), "\t"), func(_s): pass, 90)
	var err := Label.new()
	err.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	te.text_changed.connect(func():
		var parsed: Variant = JSON.parse_string(te.text)
		if parsed == null and te.text.strip_edges() != "":
			err.text = "  invalid JSON"
		else:
			err.text = ""
			on_change.call(parsed if parsed != null else _blank_for(field)))
	box.add_child(te)
	box.add_child(err)
	return box

func _json_line(value: Variant, on_change: Callable) -> Control:
	var le := LineEdit.new()
	le.text = JSON.stringify(value if value != null else {})
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_changed.connect(func(s):
		var parsed: Variant = JSON.parse_string(s)
		if parsed is Dictionary:
			on_change.call(parsed))
	return le

func _keys_hint(t: String) -> String:
	match t:
		"requirements": return "keys: " + ", ".join(PackedStringArray(SchemaC.REQUIREMENT_KEYS))
		"trigger": return "keys: " + ", ".join(PackedStringArray(SchemaC.TRIGGER_KEYS))
		"effects": return "keys: " + ", ".join(PackedStringArray(SchemaC.EFFECT_KEYS))
	return "structured JSON"

func _blank_for(field: Dictionary) -> Variant:
	return [] if field["type"] == "list" else {}

# --- New / duplicate / delete ----------------------------------------------
func _default_entry() -> Dictionary:
	var e := {}
	for field in _schema[_type].get("fields", []):
		if field.get("optional", false):
			continue
		match field["type"]:
			"int", "float": e[field["key"]] = 0
			"bool": e[field["key"]] = false
			"tag_list", "string_list", "ref_list", "list": e[field["key"]] = []
			"map_num", "requirements", "trigger", "effects", "object": e[field["key"]] = {}
			"descriptions": e[field["key"]] = [{"text": ""}]
			"enum": e[field["key"]] = str((field.get("options", [""]) as Array)[0])
			_: e[field["key"]] = ""
	return e

func _fresh_id(base: String) -> String:
	var existing := _entry_ids()
	if not (base in existing):
		return base
	var n := 2
	while ("%s_%d" % [base, n]) in existing:
		n += 1
	return "%s_%d" % [base, n]

func _on_new_entry() -> void:
	if _is_single():
		return
	var e := _default_entry()
	var nid := _fresh_id("new_" + _type.trim_suffix("s"))
	var col = _working[_type]
	if col is Dictionary:
		col[nid] = e
	elif col is Array:
		e["id"] = nid
		col.append(e)
	_rebuild_entry_list()
	_select_entry(nid)
	_set_status("[color=lightgreen]Added %s. Edit, then Save.[/color]" % nid)

func _on_duplicate() -> void:
	if _is_single() or _entry.is_empty():
		return
	var clone: Dictionary = _entry.duplicate(true)
	var nid := _fresh_id(_key + "_copy")
	var col = _working[_type]
	if col is Dictionary:
		col[nid] = clone
	elif col is Array:
		clone["id"] = nid
		col.append(clone)
	_rebuild_entry_list()
	_select_entry(nid)

func _on_delete() -> void:
	if _is_single() or _key == "":
		return
	var col = _working[_type]
	if col is Dictionary:
		col.erase(_key)
	elif col is Array:
		for i in col.size():
			if str(col[i].get("id", "")) == _key:
				col.remove_at(i)
				break
	_entry = {}
	_key = ""
	_rebuild_entry_list()
	_clear_form()

# --- Save / validate --------------------------------------------------------
func _file_for_type() -> String:
	return str(_schema[_type].get("file", _type + ".json"))

func _on_save() -> void:
	var issues := _validate_type()
	var text := JSON.stringify(_working[_type], "\t")
	var werr := _content.write_override(_file_for_type(), text)
	if werr != "":
		_set_status("[color=salmon]Save failed: %s[/color]" % werr)
		return
	_content.load_all()   # refresh refs so pickers see new ids
	if issues.is_empty():
		_set_status("[color=lightgreen]Saved %s (override).[/color]" % _file_for_type())
	else:
		_set_status("[color=orange]Saved with %d validation issue(s):[/color]\n%s" % [issues.size(), "\n".join(issues)])

func _on_write_project() -> void:
	var text := JSON.stringify(_working[_type], "\t")
	var werr := _content.write_project(_file_for_type(), text)
	if werr != "":
		_set_status("[color=salmon]%s[/color]" % werr)
		return
	_content.clear_override(_file_for_type())
	_content.load_all()
	_set_status("[color=lightgreen]Wrote res://content/%s.[/color]" % _file_for_type())

func _on_revert() -> void:
	_content.clear_override(_file_for_type())
	_content.load_all()
	_working[_type] = _dup(_content.collection(_type))
	_rebuild_entry_list()
	_clear_form()
	_set_status("[color=gray]Reverted %s to the res:// original.[/color]" % _file_for_type())

## Validate just the working copy of the current type (temporarily swapped in so
## cross-references resolve against the edited data).
func _validate_type() -> Array:
	var backup = _content.tables.get(_type, null)
	_content.tables[_type] = _working[_type]
	var issues := ValidatorC.validate(_content, {_type: _schema[_type]})
	_content.tables[_type] = backup
	return issues

func _on_validate_all() -> void:
	var probe := ContentC.new()
	probe.load_all()
	for t in _working:
		probe.tables[t] = _working[t]
	probe._bind_handles()
	var issues := ValidatorC.validate(probe, _schema)
	if issues.is_empty():
		_set_status("[color=lightgreen]All content validates cleanly.[/color]")
	else:
		_set_status("[color=orange]%d issue(s):[/color]\n%s" % [issues.size(), "\n".join(issues)])

func _set_status(bb: String) -> void:
	if status != null:
		status.text = bb
