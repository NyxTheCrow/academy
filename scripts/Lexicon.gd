extends Node
## Lexicon — the searchable term/keyword glossary (autoload).
##
## Loads data/lexicon.json and provides search/lookup used by the Lexicon
## screen and by hover tooltips across the UI.

var entries: Array = []

func _ready() -> void:
	reload()

func reload() -> void:
	var path := GameData.src_path("lexicon.json")  # override-aware
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Array:
			entries = parsed
	print("[Lexicon] %d entries" % entries.size())

func all() -> Array:
	return entries

## Case-insensitive filter over term, aliases, category, and definition.
func search(query: String) -> Array:
	var q := query.strip_edges().to_lower()
	if q == "":
		return entries
	var out: Array = []
	for e in entries:
		if _matches(e, q):
			out.append(e)
	return out

func _matches(e: Dictionary, q: String) -> bool:
	if q in str(e.get("term", "")).to_lower():
		return true
	if q in str(e.get("category", "")).to_lower():
		return true
	if q in str(e.get("definition", "")).to_lower():
		return true
	for a in e.get("aliases", []):
		if q in str(a).to_lower():
			return true
	return false

## Find one entry by exact term or alias (case-insensitive).
func lookup(key: String) -> Dictionary:
	var k := key.strip_edges().to_lower()
	for e in entries:
		if str(e.get("term", "")).to_lower() == k:
			return e
		for a in e.get("aliases", []):
			if str(a).to_lower() == k:
				return e
	return {}

## A short "Term — definition" string for a tooltip, or "" if unknown.
func define(key: String) -> String:
	var e := lookup(key)
	if e.is_empty():
		return ""
	return "%s — %s" % [e.get("term", ""), e.get("definition", "")]
