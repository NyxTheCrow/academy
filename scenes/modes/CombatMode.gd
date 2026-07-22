extends "res://scripts/GameMode.gd"
## CombatMode — tactical grid combat.
##
## Actions come from a shared data list (data/combat_actions.json); the player's
## available actions are those whose tag requirements they meet (request #4).
## Each action has a `kind` that drives its behaviour: move / melee / wall /
## self. Basic move + strike carry no requirements, so everyone has them; Fire
## Wall needs "pyromancer", Brace needs "duelist", etc.

const GRID_W := 6
const GRID_H := 5
const CELL := 64

var _units: Array = []
var _player: Dictionary = {}
var _reward: Dictionary = {}
var _penalty: Dictionary = {}
var _hazards: Array = []          # {pos, dmg, ttl}
var _actions: Array = []          # player's tag-filtered combat actions
var _pending: Dictionary = {}     # currently selected targeted action
var _player_turn := true
var _has_moved := false
var _has_acted := false
var _finished := false

var _cells: Array = []
var info_label: Label
var log_box: RichTextLabel
var end_turn_btn: Button
var _ability_bar: HBoxContainer

func enter(context: Dictionary) -> void:
	var enc := GameData.get_encounter(str(context.get("encounter_id", "")))
	_reward = enc.get("reward", {"effects": {"needs": {"calm": 5}}})
	_penalty = enc.get("penalty", {"effects": {"energy": -30}})
	# Filter the shared action list by the player's tags.
	_actions.clear()
	for act in GameData.combat_actions:
		if GameState.requirement_met(act.get("requires", {}), GameState.tags, GameState.stats, GameState.energy):
			_actions.append(act)
	_build_ui(enc.get("name", "Battle"))
	_spawn_units(enc)
	_redraw()
	_log("A battle begins! Pick an action, then a target.")

func _spawn_units(enc: Dictionary) -> void:
	_units.clear()
	# Player toughness/attack: a base plus small bonuses from martial tags.
	var hp: int = 22
	var atk: int = 5
	if GameState.has_tag("duelist"):
		atk += 2
	if GameState.has_tag("pyromancer"):
		atk += 1
	_player = {
		"name": GameState.player_name, "team": "player", "glyph": "@",
		"max_hp": hp, "hp": hp, "atk": atk, "pos": Vector2i(0, GRID_H / 2),
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
	var log_scroll := ScrollContainer.new()
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(log_scroll)
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.fit_content = true
	log_box.scroll_following = true
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(log_box)

	# Ability bar built from the player's tag-filtered actions.
	_ability_bar = HBoxContainer.new()
	_ability_bar.add_theme_constant_override("separation", 8)
	v.add_child(_ability_bar)
	for act in _actions:
		var ab := Button.new()
		ab.text = act.get("name", "?")
		var def := Lexicon.define(str(act.get("name", "")))
		ab.tooltip_text = def if def != "" else str(act.get("description", ""))
		ab.pressed.connect(_on_ability.bind(act))
		ab.set_meta("action_id", act.get("id", ""))
		_ability_bar.add_child(ab)
	end_turn_btn = Button.new()
	end_turn_btn.text = "End Turn"
	end_turn_btn.pressed.connect(_end_player_turn)
	_ability_bar.add_child(end_turn_btn)

# --- Helpers ----------------------------------------------------------------
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

func _dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _pending_kind() -> String:
	return str(_pending.get("kind", "")) if not _pending.is_empty() else ""

func _reachable(to: Vector2i, rng: int) -> bool:
	return _dist(_player["pos"], to) <= rng and _unit_at(to).is_empty()

# --- Rendering --------------------------------------------------------------
func _redraw() -> void:
	var kind := _pending_kind()
	for y in GRID_H:
		for x in GRID_W:
			var b: Button = _cells[y * GRID_W + x]
			var pos := Vector2i(x, y)
			var u := _unit_at(pos)
			var hz := _hazard_at(pos)
			b.modulate = Color.WHITE
			if not u.is_empty():
				b.text = u["glyph"]
				b.modulate = (Color(0.7, 1.0, 0.7) if u["team"] == "player" else Color(1.0, 0.7, 0.7))
			elif not hz.is_empty():
				b.text = "#"
				b.modulate = Color(1.0, 0.55, 0.2)
			else:
				b.text = ""
			# Targeting highlights.
			if _player_turn and not _pending.is_empty():
				if kind == "move" and u.is_empty() and hz.is_empty() and _reachable(pos, int(_pending.get("range", 3))):
					b.modulate = Color(0.6, 0.9, 1.0)
				elif kind == "melee" and not u.is_empty() and u["team"] == "enemy" and _dist(_player["pos"], pos) <= int(_pending.get("range", 1)):
					b.modulate = Color(1.0, 0.85, 0.4)
				elif kind == "wall" and u.is_empty():
					b.modulate = Color(1.0, 0.8, 0.4)

	var s := ""
	for u in _units:
		if GameState.dev_mode:
			s += "%s  HP %d/%d\n" % [u["name"], u["hp"], u["max_hp"]]
		else:
			s += "%s  —  %s\n" % [u["name"], GameState.hp_descriptor(int(u["hp"]), int(u["max_hp"]))]
	if not _hazards.is_empty():
		if GameState.dev_mode:
			s += "\nFire Walls: %d" % _hazards.size()
			for hz in _hazards:
				s += "  [%s ttl%d]" % [str(hz["pos"]), hz["ttl"]]
		else:
			s += "\nFlames linger on the field."
	s += "\n\n" + ("Your turn" if _player_turn else "Enemy turn")
	if _player_turn:
		if not _pending.is_empty():
			s += "\n→ %s: pick a target." % _pending.get("name", "")
		else:
			s += "\n(moved: %s, acted: %s)" % [str(_has_moved), str(_has_acted)]
	info_label.text = s
	_refresh_ability_bar()

func _refresh_ability_bar() -> void:
	for ab in _ability_bar.get_children():
		if not (ab is Button) or not ab.has_meta("action_id"):
			continue
		var id: String = str(ab.get_meta("action_id"))
		var act := _find_action(id)
		var is_move: bool = act.get("kind", "") == "move"
		ab.disabled = (not _player_turn) or (_has_moved if is_move else _has_acted)
	end_turn_btn.disabled = not _player_turn

func _find_action(id: String) -> Dictionary:
	for a in _actions:
		if a.get("id", "") == id:
			return a
	return {}

func _log(text: String) -> void:
	log_box.append_text(text + "\n")

# --- Player actions ---------------------------------------------------------
func _on_ability(act: Dictionary) -> void:
	if not _player_turn or _finished:
		return
	var kind: String = act.get("kind", "")
	if kind == "self":
		_resolve_self(act)
		return
	# Toggle targeting for this action.
	_pending = act if _pending.get("id", "") != act.get("id", "") else {}
	_redraw()

func _resolve_self(act: Dictionary) -> void:
	if _has_acted:
		return
	if act.has("heal"):
		_player["hp"] = mini(int(_player["max_hp"]), int(_player["hp"]) + int(act["heal"]))
		if GameState.dev_mode:
			_log("You %s, recovering %d HP." % [str(act.get("name", "brace")).to_lower(), int(act["heal"])])
		else:
			_log("You steady yourself.")
	_has_acted = true
	_pending = {}
	_after_action()

func _on_cell_pressed(index: int) -> void:
	if not _player_turn or _finished or _pending.is_empty():
		return
	var pos := Vector2i(index % GRID_W, index / GRID_W)
	match _pending_kind():
		"move":
			if not _has_moved and _reachable(pos, int(_pending.get("range", 3))):
				_move_unit(_player, pos)
				_has_moved = true
				_pending = {}
				_after_action()
		"melee":
			var target := _unit_at(pos)
			if not _has_acted and not target.is_empty() and target["team"] == "enemy" and _dist(_player["pos"], pos) <= int(_pending.get("range", 1)):
				_attack(_player, target)
				_has_acted = true
				_pending = {}
				_after_action()
		"wall":
			if not _has_acted and _unit_at(pos).is_empty():
				_place_wall(pos, _pending)
				_has_acted = true
				_pending = {}
				_after_action()

func _place_wall(center: Vector2i, act: Dictionary) -> void:
	var length: int = int(act.get("length", 3))
	var dmg: int = int(act.get("dmg", 6))
	var ttl: int = int(act.get("ttl", 3))
	var half := length / 2
	var placed := 0
	for dy in range(-half, length - half):
		var p := Vector2i(center.x, center.y + dy)
		if p.y >= 0 and p.y < GRID_H and _hazard_at(p).is_empty():
			_hazards.append({"pos": p, "dmg": dmg, "ttl": ttl})
			placed += 1
	if GameState.dev_mode:
		_log("You raise a wall of flame (%d tiles)." % placed)
	else:
		_log("You raise a wall of flame.")

func _move_unit(u: Dictionary, newpos: Vector2i) -> void:
	u["pos"] = newpos
	var hz := _hazard_at(newpos)
	if not hz.is_empty():
		_damage(u, int(hz["dmg"]), "the flames")

func _attack(attacker: Dictionary, defender: Dictionary) -> void:
	_damage(defender, maxi(1, int(attacker["atk"]) - randi_range(0, 2)), attacker["name"])

func _damage(target: Dictionary, amount: int, source: String) -> void:
	target["hp"] = int(target["hp"]) - amount
	if GameState.dev_mode:
		_log("%s takes [color=orange]%d[/color] from %s." % [target["name"], amount, source])
	elif source == "the flames":
		_log("The flames scorch %s." % target["name"])
	else:
		_log("%s strikes %s." % [source, target["name"]])
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
	var hz := _hazard_at(_player["pos"])
	if not hz.is_empty():
		_damage(_player, int(hz["dmg"]), "the flames")
		if _check_end():
			return
	_pending = {}
	_player_turn = false
	_redraw()
	_enemy_turn()

func _enemy_turn() -> void:
	for u in _units.duplicate():
		if u["team"] != "enemy" or not _units.has(u):
			continue
		var steps: int = int(u.get("move", 3))
		while steps > 0 and _dist(u["pos"], _player["pos"]) > 1:
			var next := _step_toward(u["pos"], _player["pos"])
			if next == u["pos"]:
				break
			_move_unit(u, next)
			if not _units.has(u):
				break
			steps -= 1
		if not _units.has(u):
			continue
		if _dist(u["pos"], _player["pos"]) <= 1:
			_attack(u, _player)
			if _check_end():
				return
		if not _units.has(u):
			continue
		var hz := _hazard_at(u["pos"])
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
	_refresh_ability_bar()
	await get_tree().create_timer(1.2).timeout
	finished.emit(result)
