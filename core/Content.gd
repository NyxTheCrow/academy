extends RefCounted
class_name Content
## Content — the loader for the new content/ layer. Like the old GameData, but
## driven by the ContentSchema (so it always loads exactly the types the schema
## declares) and override-aware for the editor (user overrides win over res://).
##
## Its one piece of real logic is build_actor(): it turns an actor DEFINITION
## (sparse overrides in actors.json) into a full runtime Actor, filling in every
## registry skill/need/resource with defaults and folding traits into learn rates
## and granted tags. The player and every NPC are built by this same function.

const OVERRIDE_DIR := "user://content_overrides/"
const SRC_DIR := "res://content/"

var tables: Dictionary = {}   # schema type -> loaded collection (Dictionary or Array)

# Convenience handles (kept in sync with `tables`).
var skills_registry: Array = []
var needs_registry: Array = []
var resources_registry: Array = []
var traits: Dictionary = {}          # id -> trait def
var actors: Dictionary = {}
var locations: Dictionary = {}
var interactions: Dictionary = {}
var schedule: Array = []
var occurrences: Array = []
var spells: Array = []
var items: Dictionary = {}
var conversations: Dictionary = {}
var tuning: Dictionary = {}

func load_all() -> void:
	var schema := ContentSchema.all()
	for type in schema:
		var file: String = schema[type]["file"]
		var col: String = schema[type]["collection"]
		var parsed: Variant = _parse(_src_path(file))
		if col == "array":
			tables[type] = parsed if parsed is Array else []
		else:  # "dict" and "single" both load as a Dictionary
			tables[type] = parsed if parsed is Dictionary else {}
	_bind_handles()

func _bind_handles() -> void:
	skills_registry = tables.get("skills", [])
	needs_registry = tables.get("needs", [])
	resources_registry = tables.get("resources", [])
	# traits ship as an array; index by id for lookup.
	traits = {}
	for t in tables.get("traits", []):
		traits[str(t.get("id", ""))] = t
	actors = tables.get("actors", {})
	locations = tables.get("locations", {})
	interactions = tables.get("interactions", {})
	schedule = tables.get("schedule", [])
	occurrences = tables.get("occurrences", [])
	spells = tables.get("spells", [])
	items = tables.get("items", {})
	conversations = tables.get("conversations", {})
	tuning = tables.get("tuning", {})

# --- Generic access (for the validator + editor) ----------------------------
func collection(type: String) -> Variant:
	return tables.get(type, {})

## The set of valid ids for a type. Dict collections are keyed by id; array
## collections carry an "id" field on each entry.
func ids(type: String) -> Array:
	var c = tables.get(type, null)
	if c is Dictionary:
		return c.keys()
	if c is Array:
		var out: Array = []
		for e in c:
			if e is Dictionary and e.has("id"):
				out.append(str(e["id"]))
		return out
	return []

# --- The one actor factory (player and NPCs alike) --------------------------
func build_actor(aid: String) -> Actor:
	var def: Dictionary = actors.get(aid, {})
	if def.is_empty():
		return null
	var a := Actor.new()
	a.id = aid
	a.name = str(def.get("name", aid.capitalize()))
	a.kind = str(def.get("kind", "student"))
	a.is_player = bool(def.get("is_player", false))
	a.location = str(def.get("location", "dormitories"))
	a.tags = (def.get("tags", []) as Array).duplicate()
	a.traits = (def.get("traits", []) as Array).duplicate()
	a.weights = (def.get("weights", {}) as Dictionary).duplicate(true)
	a.relationships = (def.get("relationships", {}) as Dictionary).duplicate(true)

	# Full skill sheet: every registry skill defaults to 0, then overrides.
	a.skills = {}
	for s in skills_registry:
		a.skills[str(s.get("id", ""))] = 0.0
	for k in def.get("skills", {}):
		a.skills[str(k)] = float(def["skills"][k])

	# Needs default to each need's start value.
	a.needs = {}
	for n in needs_registry:
		a.needs[str(n.get("id", ""))] = float(n.get("start", 75.0))
	for k in def.get("needs", {}):
		a.needs[str(k)] = float(def["needs"][k])

	# Resources default to (start | max); track each max.
	a.resources = {}
	a.resource_max = {}
	for r in resources_registry:
		var rid := str(r.get("id", ""))
		var rmax := float(r.get("max", 100.0))
		a.resource_max[rid] = rmax
		a.resources[rid] = float(r.get("start", rmax))
	for k in def.get("resources", {}):
		a.resources[str(k)] = float(def["resources"][k])

	# Traits fold into learn rates + granted tags (the "learns X faster" hook).
	a.learn_rates = {}
	for tr in a.traits:
		var td: Dictionary = traits.get(str(tr), {})
		for sk in td.get("learn_rates", {}):
			a.learn_rates[str(sk)] = float(td["learn_rates"][sk])
		for tg in td.get("grants_tags", []):
			a.add_tag(str(tg))
	return a

# --- Override-aware IO (used by the Data Editor) ----------------------------
func _src_path(file: String) -> String:
	var o := OVERRIDE_DIR + file
	return o if FileAccess.file_exists(o) else SRC_DIR + file

func has_override(file: String) -> bool:
	return FileAccess.file_exists(OVERRIDE_DIR + file)

func read_source(file: String) -> String:
	var f := FileAccess.open(_src_path(file), FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t

func write_override(file: String, text: String) -> String:
	DirAccess.make_dir_recursive_absolute(OVERRIDE_DIR)
	var f := FileAccess.open(OVERRIDE_DIR + file, FileAccess.WRITE)
	if f == null:
		return "could not open override for writing"
	f.store_string(text)
	f.close()
	return ""

func clear_override(file: String) -> void:
	var p := OVERRIDE_DIR + file
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

func write_project(file: String, text: String) -> String:
	var f := FileAccess.open(SRC_DIR + file, FileAccess.WRITE)
	if f == null:
		return "res:// is read-only here (only works when running from the Godot editor)"
	f.store_string(text)
	f.close()
	return ""

func _parse(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("[Content] file not found: %s" % path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("[Content] failed to parse JSON: %s" % path)
	return parsed
