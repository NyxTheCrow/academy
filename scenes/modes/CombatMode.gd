extends "res://scripts/GameMode.gd"
## CombatMode — the tactical-combat spine.
##
## Turn-based grid fight: units with HP/attack, a player turn (one move + one
## action), a simple enemy AI, hazard tiles (Fire Wall), and win/lose. The
## player unit derives from GameState stats; the outcome returns as a result
## dictionary through the same `effects` boundary as everything else.

const GRID_W := 6
const GRID_H := 5
const CELL := 64
const FIREWALL_DMG := 6
const FIREWALL_TTL := 3  # rounds the wall persists

var _units: Array = []          # {name, team, hp, max_hp, atk, move, pos, glyph}
var _player: Dictionary = {}
var _reward: Dictionary = {}
var _penalty: Dictionary = {}
var _hazards: Array = []        # {pos: Vector2i, dmg: int, ttl: int}
var _player_turn := true
var _has_moved := false
var _has_acted := false
var _targeting := ""            # "" or "firewall"
var _finished := false

var _cells: Array = []          # Button grid, index = y * GRID_W + x
var info_label: Label
var log_box: RichTextLabel
var end_turn_btn: Button
var firewall_btn: Button

func enter(context: Dictionary) -> void:
	var enc := GameData.get_encounter(str(context.get("encounter_id", "")))
	_reward = enc.get("reward", {"effects": {"stats": {"combat": 2}}})
	_penalty = enc.get("penalty", {"effects": {"energy": -30}})
	_build_ui(enc.get("name", "Battle"))
	_spawn_units(enc)
	_redraw()
	_log("A battle begins! Move, then attack an adjacent foe — or raise a Fire Wall.")

# --- Setup ------------------------------------------------------------------
func _spawn_units(enc: Dictionary) -> void:
	_units.clear()
	var combat_stat: int = int(GameState.stats.get("combat", 0))
	var magic_stat: int = int(GameState.stats.get("magic", 0))
	_player = {
		"name": GameState.player_name, "team": "player", "glyph": "@",
		"max_hp": 20 + combat_stat * 2, "hp": 20 + combat_stat * 2,
		"atk": 4 + combat_stat + int(magic_stat / 2.0), "move": 3,
		"pos": Vector2i(0, GRID_H / 2),
	}
	_units.append(_player)

	var enemies: Array = enc.get("enemies", [{"name": "Rival", "hp": 22, "atk": 5, "move": 3}])
	var slot := 0
	for e in enemies:
		_units.append({
			"name": e.get("name", "Foe"), "team": "enemy", "glyph": "E",
			"max_hp": int(e.get("hp", 20)), "hp": int(e.get("hp", 20)),
			"atk": int(e.get("atk", 5)), "move": int(e.get("move", 3)),
			"pos": Vector2i(GRID_W - 1, clampi(1 + slot, 0, GRID_H - 1)),
		})
		slot += 2

# --- UI ---------------------------------------------------------------------
func _build_ui(title: String) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)

	var title_lbl := Label.new()
	title_lbl.text = "⚔  %s" % title
	title_lbl.add_theme_font_size_override("font_size", 22)
	v.add_child(title_lbl)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)

	var grid := GridContainer.new()
	grid.columns = GRID_W
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	h.add_child(grid)
	_cells.clear()
	for i in GRID_W * GRID_H:
		var b := Button.new()
		b.custom_minimum_size = Vector2(CELL, CELL)
		b.add_theme_font_size_override("font_size", 28)
		b.pressed.connect(_on_cell_pressed.bind(i))
		grid.add_child(b)
		_cells.append(b)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(300, 0)
	side.add_theme_constant_override("separation", 10)
	h.add_child(side)

	info_label = Label.new()
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(info_label)

	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(log_box)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	v.add_child(actions)
	firewall_btn = Button.new()
	firewall_btn.text = "Fire Wall (%d dmg)" % FIREWALL_DMG
	firewall_btn.tooltip_text = "Raise a 3-tile wall of flame. Damages any unit that moves onto it or ends its turn on it."
	firewall_btn.pressed.connect(_on_firewall)
	actions.add_child(firewall_btn)
	end_turn_btn = Button.new()
	end_turn_btn.text = "End Turn"
	end_turn_btn.pressed.connect(_end_player_turn)
	actions.add_child(end_turn_btn)

# --- Rendering --------------------------------------------------------------
func _unit_at(pos: Vector2i) -> Dictionary:
	for u in _units:
		if u["pos"] == pos:
			return u
	return {}

func _hazard_at(pos: Vector2i) -> Dictionary:
	for hz in _hazards:
		if hz["pos"] == pos:
			return hz
	return {}

func _redraw() -> void:
	for y in GRID_H:
		for x in GRID_W:
			var b: Button = _cells[y * GRID_W + x]
			var pos := Vector2i(x, y)
			var u := _unit_at(pos)
			var hz := _hazard_at(pos)
			if not u.is_empty():
				b.text = u["glyph"]
				b.modulate = (Color(0.7, 1.0, 0.7) if u["team"] == "player" else Color(1.0, 0.7, 0.7))
			elif not hz.is_empty():
				b.text = "#"
				b.modulate = Color(1.0, 0.55, 0.2)
			else:
				b.text = ""
				b.modulate = Color.WHITE
				if _targeting == "firewall":
					b.modulate = Color(1.0, 0.8, 0.4)
				elif _player_turn and not _has_moved and _reachable(_player["pos"], pos, _player["move"]):
					b.modulate = Color(0.6, 0.9, 1.0)

	var s := ""
	for u in _units:
		s += "%s  HP %d/%d  ATK %d\n" % [u["name"], u["hp"], u["max_hp"], u["atk"]]
	if not _hazards.is_empty():
		s += "\nFire Walls: %d tile(s)" % _hazards.size()
		if GameState.dev_mode:
			for hz in _hazards:
				s += "\n  [dev] %s ttl=%d" % [str(hz["pos"]), hz["ttl"]]
	s += "\n\n" + ("Your turn" if _player_turn else "Enemy turn")
	if _player_turn:
		if _targeting == "firewall":
			s += "\n→ Click a tile to place the wall."
		else:
			s += "  (moved: %s, acted: %s)" % [str(_has_moved), str(_has_acted)]
	info_label.text = s
	end_turn_btn.disabled = not _player_turn
	firewall_btn.disabled = not _player_turn or _has_acted

# --- Rules ------------------------------------------------------------------
func _log(text: String) -> void:
	log_box.append_text(text + "\n")

func _dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _reachable(from: Vector2i, to: Vector2i, move: int) -> bool:
	return _dist(from, to) <= move and _unit_at(to).is_empty()

func _on_cell_pressed(index: int) -> void:
	if not _player_turn or _finished:
		return
	var pos := Vector2i(index % GRID_W, index / GRID_W)

	if _targeting == "firewall":
		_place_firewall(pos)
		return

	var target := _unit_at(pos)
	if not target.is_empty() and target["team"] == "enemy":
		if not _has_acted and _dist(_player["pos"], pos) <= 1:
			_attack(_player, target)
			_has_acted = true
			_after_action()
		else:
			_log("[color=gray]Too far to strike — move adjacent first.[/color]")
		return

	if target.is_empty() and not _has_moved and _reachable(_player["pos"], pos, _player["move"]):
		_move_unit(_player, pos)
		_has_moved = true
		if not _check_end():
			_redraw()

func _on_firewall() -> void:
	if not _player_turn or _has_acted:
		return
	_targeting = "firewall" if _targeting == "" else ""
	_redraw()

func _place_firewall(center: Vector2i) -> void:
	# A vertical, 3-tile-long wall centred on the clicked tile.
	var placed := 0
	for dy in [-1, 0, 1]:
		var p := Vector2i(center.x, center.y + dy)
		if p.y < 0 or p.y >= GRID_H:
			continue
		if _hazard_at(p).is_empty():
			_hazards.append({"pos": p, "dmg": FIREWALL_DMG, "ttl": FIREWALL_TTL})
			placed += 1
	_log("You raise a wall of flame (%d tiles)." % placed)
	_targeting = ""
	_has_acted = true
	_after_action()

func _move_unit(u: Dictionary, newpos: Vector2i) -> void:
	u["pos"] = newpos
	var hz := _hazard_at(newpos)
	if not hz.is_empty():
		_damage(u, int(hz["dmg"]), "the flames")

func _attack(attacker: Dictionary, defender: Dictionary) -> void:
	_damage(defender, maxi(1, int(attacker["atk"]) - randi_range(0, 2)), attacker["name"])

func _damage(target: Dictionary, amount: int, source: String) -> void:
	target["hp"] = int(target["hp"]) - amount
	_log("%s takes [color=orange]%d[/color] from %s." % [target["name"], amount, source])
	if target["hp"] <= 0:
		_log("[color=yellow]%s is defeated![/color]" % target["name"])
		_units.erase(target)

func _after_action() -> void:
	if _check_end():
		return
	_redraw()
	if _has_moved and _has_acted:
		_end_player_turn()

func _end_player_turn() -> void:
	if _finished:
		return
	# "End your turn on it": the wall bites the player if they finish standing in it.
	var hz := _hazard_at(_player["pos"])
	if not hz.is_empty():
		_damage(_player, int(hz["dmg"]), "the flames")
		if _check_end():
			return
	_targeting = ""
	_player_turn = false
	_redraw()
	_enemy_turn()

func _enemy_turn() -> void:
	for u in _units.duplicate():
		if u["team"] != "enemy" or not _units.has(u):
			continue
		var steps: int = int(u["move"])
		while steps > 0 and _dist(u["pos"], _player["pos"]) > 1:
			var next := _step_toward(u["pos"], _player["pos"])
			if next == u["pos"]:
				break
			_move_unit(u, next)
			if not _units.has(u):
				break  # walked into flames and died
			steps -= 1
		if not _units.has(u):
			continue
		if _dist(u["pos"], _player["pos"]) <= 1:
			_attack(u, _player)
			if _check_end():
				return
		# Enemy ends its turn standing in flames.
		var hz := _hazard_at(u["pos"])
		if not _units.has(u):
			continue
		if not hz.is_empty():
			_damage(u, int(hz["dmg"]), "the flames")
			if _check_end():
				return

	_tick_hazards()
	_player_turn = true
	_has_moved = false
	_has_acted = false
	_redraw()

func _tick_hazards() -> void:
	var kept: Array = []
	for hz in _hazards:
		hz["ttl"] = int(hz["ttl"]) - 1
		if hz["ttl"] > 0:
			kept.append(hz)
	if kept.size() != _hazards.size():
		_log("[color=gray]Some flames burn out.[/color]")
	_hazards = kept

func _step_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var next := from
	if from.x != to.x:
		next.x += signi(to.x - from.x)
	elif from.y != to.y:
		next.y += signi(to.y - from.y)
	if not _unit_at(next).is_empty():
		return from
	return next

func _check_end() -> bool:
	if _player["hp"] <= 0:
		_log("[color=salmon]You have fallen...[/color]")
		var r := _penalty.duplicate(true)
		r["outcome"] = "lose"
		_finish(r)
		return true
	for u in _units:
		if u["team"] == "enemy":
			return false
	_log("[color=lightgreen]Victory![/color]")
	var r2 := _reward.duplicate(true)
	r2["outcome"] = "win"
	_finish(r2)
	return true

func _finish(result: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	end_turn_btn.disabled = true
	firewall_btn.disabled = true
	await get_tree().create_timer(1.2).timeout
	finished.emit(result)
