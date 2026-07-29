extends RefCounted
class_name SaveManager
## SaveManager — save slots over a World. The old build hand-enumerated every
## GameState field in save_game/load_game (and reached sideways into the Students
## autoload). Here a World already knows how to serialize itself (to_dict /
## from_dict over its clock + actors + fired ledger), so a save is just that dict
## plus a small header — and any new actor field is saved automatically.
##
## Files live in user://core_saves/. slot_info() reads only the header, so the
## save menu can list slots without loading a whole world.

const DIR := "user://core_saves/"
const VERSION := 1

static func slot_path(slot: int) -> String:
	return "%sslot_%d.json" % [DIR, slot]

static func save(world, slot: int) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var data := {
		"version": VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"player_name": world.player.name if world.player else "?",
		"label": "%s · %s" % [world.player.name if world.player else "?", world.clock.date_string()],
		"world": world.to_dict(),
	}
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("[SaveManager] could not open %s" % slot_path(slot))
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true

static func load_into(world, slot: int) -> bool:
	var p := slot_path(slot)
	if not FileAccess.file_exists(p):
		return false
	var f := FileAccess.open(p, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_error("[SaveManager] corrupt save: %s" % p)
		return false
	world.from_dict((parsed as Dictionary).get("world", {}))
	return true

## Header only (no world rebuild): { exists, name, label, saved_at }.
static func slot_info(slot: int) -> Dictionary:
	var p := slot_path(slot)
	if not FileAccess.file_exists(p):
		return {"exists": false}
	var f := FileAccess.open(p, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return {"exists": true, "name": "(corrupt)", "label": "", "saved_at": 0.0}
	var d: Dictionary = parsed
	return {
		"exists": true,
		"name": str(d.get("player_name", "?")),
		"label": str(d.get("label", "")),
		"saved_at": float(d.get("saved_at", 0.0)),
	}

static func delete(slot: int) -> void:
	var p := slot_path(slot)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
