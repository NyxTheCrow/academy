extends RefCounted
class_name ContentValidator
## ContentValidator — checks loaded content against the ContentSchema and returns
## a list of human-readable issues (empty == clean). A headless test runs this on
## the shipped content, so a dangling reference ("this interaction is available at
## a location that doesn't exist"), a typo'd requirement key, or a skill effect
## that names a non-existent skill FAILS CI instead of silently breaking a save.
##
## It is deliberately a linter, not a straitjacket: it flags dangling references,
## unknown requirement/effect keys, and malformed graded-reveal blocks — the
## mistakes that are easy to make by hand and expensive to debug at runtime.

static func validate(content, schema: Dictionary) -> Array:
	var issues: Array = []
	for type in schema:
		var spec: Dictionary = schema[type]
		var col = content.collection(type)
		var entries := _entries(col)
		for pair in entries:
			var eid: String = pair[0]
			var entry: Dictionary = pair[1]
			var where := "%s/%s" % [type, eid]
			for field in spec.get("fields", []):
				_check_field(content, entry.get(field["key"], null), field, where, issues)
	return issues

## Normalise a dict collection (id->entry) or array collection (entries with id)
## into a list of [id, entry] pairs.
static func _entries(col) -> Array:
	var out: Array = []
	if col is Dictionary:
		for k in col:
			if col[k] is Dictionary:
				out.append([str(k), col[k]])
	elif col is Array:
		for e in col:
			if e is Dictionary:
				out.append([str(e.get("id", "?")), e])
	return out

static func _check_field(content, value, field: Dictionary, where: String, issues: Array) -> void:
	if value == null:
		if not bool(field.get("optional", false)):
			issues.append("%s: missing required field '%s'" % [where, field["key"]])
		return
	var t: String = field["type"]
	var loc := "%s.%s" % [where, field["key"]]
	match t:
		"ref":
			_check_ref(content, value, field["ref"], loc, issues)
		"ref_list":
			if value is Array:
				for v in value:
					_check_ref(content, v, field["ref"], loc, issues)
			else:
				issues.append("%s: expected a list of %s refs" % [loc, field["ref"]])
		"map_num":
			if value is Dictionary:
				if field.has("key_ref"):
					for k in value:
						_check_ref(content, k, field["key_ref"], loc, issues)
			else:
				issues.append("%s: expected a {id: number} map" % loc)
		"requirements":
			_check_predicate(content, value, ContentSchema.REQUIREMENT_KEYS, loc, issues, false)
		"trigger":
			_check_predicate(content, value, ContentSchema.TRIGGER_KEYS, loc, issues, false)
		"effects":
			_check_predicate(content, value, ContentSchema.EFFECT_KEYS, loc, issues, true)
		"descriptions":
			_check_descriptions(content, value, loc, issues)
		"list":
			if value is Array:
				for i in value.size():
					if value[i] is Dictionary:
						for sub in field.get("item", []):
							_check_field(content, value[i].get(sub["key"], null), sub, "%s[%d]" % [loc, i], issues)
			else:
				issues.append("%s: expected a list" % loc)
		"int", "float":
			if not (value is int or value is float):
				issues.append("%s: expected a number, got %s" % [loc, type_string(typeof(value))])
		"bool":
			if not (value is bool):
				issues.append("%s: expected true/false" % loc)
		_:
			pass  # text/multiline/tag_list/string_list/enum: lenient

static func _check_ref(content, id, ref_type: String, loc: String, issues: Array) -> void:
	if str(id) == "":
		return
	if not (str(id) in content.ids(ref_type)):
		issues.append("%s: '%s' is not a valid %s id" % [loc, str(id), ref_type])

## Validate a requirements/effects block: top-level keys must be known, and the
## skill/need/resource sub-maps must reference real ids.
static func _check_predicate(content, block, allowed: Array, loc: String, issues: Array, is_effect: bool) -> void:
	if not (block is Dictionary):
		issues.append("%s: expected an object" % loc)
		return
	for k in block:
		if not (str(k) in allowed):
			issues.append("%s: unknown key '%s'" % [loc, str(k)])
			continue
		var ref_type := ""
		match str(k):
			"min_skills", "max_skills", "skills": ref_type = "skills"
			"min_needs", "max_needs", "needs": ref_type = "needs"
			"min_resources", "max_resources", "resources": ref_type = "resources"
			"traits", "without_traits": ref_type = "traits"
		if ref_type != "" and block[k] is Dictionary:
			for sub in block[k]:
				_check_ref(content, sub, ref_type, "%s.%s" % [loc, k], issues)
		elif ref_type == "traits" and block[k] is Array:
			for v in block[k]:
				_check_ref(content, v, "traits", "%s.%s" % [loc, k], issues)

static func _check_descriptions(content, value, loc: String, issues: Array) -> void:
	var variants: Array = value if value is Array else [value]
	for i in variants.size():
		var v = variants[i]
		if v is String:
			continue
		if v is Dictionary:
			if not v.has("text"):
				issues.append("%s[%d]: description variant has no 'text'" % [loc, i])
			if v.has("requires"):
				_check_predicate(content, v["requires"], ContentSchema.REQUIREMENT_KEYS, "%s[%d].requires" % [loc, i], issues, false)
		else:
			issues.append("%s[%d]: description variant must be a string or {text, requires?}" % [loc, i])
