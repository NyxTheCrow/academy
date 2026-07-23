extends "res://scenes/modes/MenuMode.gd"
## Schedule — a calendar you can zoom from a single day out to the whole year.
## Recurring entries (data/schedule.json) repeat by weekday.

var _zoom := "week"  # day | week | month | trimester | year

func _menu_title() -> String:
	return "Schedule"

func _populate() -> void:
	_add_zoom_bar()
	var g := GameState
	content.add_child(_rich("[color=gray]Year %d · Trimester %d · Month %d · Week %d · Today is %s, %s[/color]" % [
		g.year_index() + 1, g.trimester_of_year() + 1, g.month_of_trimester() + 1,
		g.week_of_month() + 1, g.day_name(), g.time_string()]))
	content.add_child(HSeparator.new())
	match _zoom:
		"day": _view_day()
		"week": _view_week()
		"month": _view_month()
		"trimester": _view_trimester()
		"year": _view_year()

func _add_zoom_bar() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	for level in ["day", "week", "month", "trimester", "year"]:
		var b := Button.new()
		b.text = level.capitalize()
		b.disabled = (level == _zoom)
		b.pressed.connect(_set_zoom.bind(level))
		bar.add_child(b)
	content.add_child(bar)

func _set_zoom(level: String) -> void:
	_zoom = level
	_repopulate()

# --- Data helper ------------------------------------------------------------
func _events_for(weekday: String) -> Array:
	var out: Array = []
	for e in GameData.schedule:
		var days: Array = e.get("days", [])
		if (weekday in days) or ("Every day" in days):
			out.append(e)
	return out

# --- Views ------------------------------------------------------------------
func _view_day() -> void:
	var wd := GameState.day_name()
	content.add_child(_h("%s" % wd))
	var events := _events_for(wd)
	if events.is_empty():
		content.add_child(_kv("", "Nothing scheduled today."))
		return
	for e in events:
		content.add_child(_rich("[b]%s[/b]  ·  %s" % [e.get("name", "?"), e.get("time", "")]))
		content.add_child(_kv("   Where", str(e.get("location", "—"))))
		if e.has("teacher"):
			content.add_child(_kv("   Teacher", str(e["teacher"])))
		if e.has("note"):
			content.add_child(_kv("   Note", str(e["note"])))
		content.add_child(HSeparator.new())

func _view_week() -> void:
	content.add_child(_h("This Week"))
	var week_start := GameState.day_count - GameState.weekday_index()
	for i in 7:
		var wd: String = GameState.DAYS[i]
		var is_today: bool = (week_start + i) == GameState.day_count
		var head := "[b]%s[/b]" % wd
		if is_today:
			head = "[color=lightgreen]● %s (today)[/color]" % wd
		var events := _events_for(wd)
		var summary := ", ".join(PackedStringArray(events.map(func(e): return str(e.get("name", ""))))) if not events.is_empty() else "—"
		content.add_child(_rich("%s\n[color=gray]    %s[/color]" % [head, summary]))

func _view_month() -> void:
	content.add_child(_h("This Month (4 weeks)"))
	var month_start := GameState.day_count - (GameState.day_count % GameState.DAYS_PER_MONTH)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	# weekday headers
	for d in 7:
		var hd := Label.new()
		hd.text = GameState.DAYS[d].substr(0, 3)
		hd.custom_minimum_size = Vector2(64, 0)
		hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(hd)
	for w in GameState.WEEKS_PER_MONTH:
		for d in 7:
			var abs_day := month_start + w * 7 + d
			var cell := Button.new()
			cell.flat = true
			cell.focus_mode = Control.FOCUS_NONE
			cell.custom_minimum_size = Vector2(64, 44)
			var num := w * 7 + d + 1
			var has_events := not _events_for(GameState.DAYS[d]).is_empty()
			cell.text = "%d%s" % [num, "  •" if has_events else ""]
			if abs_day == GameState.day_count:
				cell.modulate = Color(0.5, 1.0, 0.5)
			elif has_events:
				cell.modulate = Color(1.0, 0.85, 0.5)
			if has_events:
				cell.tooltip_text = ", ".join(PackedStringArray(_events_for(GameState.DAYS[d]).map(func(e): return str(e.get("name", "")))))
			grid.add_child(cell)
	content.add_child(grid)

func _view_trimester() -> void:
	content.add_child(_h("This Trimester (3 months)"))
	for m in GameState.MONTHS_PER_TRIMESTER:
		var is_now: bool = m == GameState.month_of_trimester()
		var label := "Month %d  (weeks %d–%d)" % [m + 1, m * 4 + 1, m * 4 + 4]
		if is_now:
			label = "[color=lightgreen]● %s (current)[/color]" % label
		content.add_child(_rich("[b]%s[/b]" % label))

func _view_year() -> void:
	content.add_child(_h("This Year (3 trimesters)"))
	for t in GameState.TRIMESTERS_PER_YEAR:
		var is_now: bool = t == GameState.trimester_of_year()
		var label := "Trimester %d  (months %d–%d)" % [t + 1, t * 3 + 1, t * 3 + 3]
		if is_now:
			label = "[color=lightgreen]● %s (current)[/color]" % label
		content.add_child(_rich("[b]%s[/b]" % label))
