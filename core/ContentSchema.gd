extends RefCounted
class_name ContentSchema
## ContentSchema — the single source of truth for what content exists and what
## shape each piece has. This is the keystone of the "easy editor" you asked for:
## the editor renders forms FROM this schema (no per-type UI code), the validator
## checks data AGAINST it (bad content fails CI), and it doubles as the data-model
## documentation. Add a field here → it appears in the editor and gets validated.
## Add a whole new content type here → it becomes editable, with zero UI code.
##
## Field `type`s the editor and validator understand:
##   text · multiline · int · float · bool
##   tag_list · string_list
##   ref(<type>) · ref_list(<type>)          — a picker over another type's ids
##   map_num(<key_ref?>)                      — { id: number }, keys optionally ref-checked
##   requirements · effects                   — the shared predicate / mutation blocks
##   descriptions                             — a graded-reveal variant list
##   enum(options) · list(item fields) · object(fields)

# Every key the shared blocks accept — used by the editor's sub-forms and by the
# validator to reject typos like "requries" or "efects".
const REQUIREMENT_KEYS := [
	"tags", "without_tags", "traits", "without_traits",
	"min_skills", "max_skills", "min_needs", "max_needs",
	"min_resources", "max_resources", "flags", "relationships",
	"has_items", "at_location", "location", "time_after", "time_before", "days",
]
const EFFECT_KEYS := [
	"skills", "needs", "resources", "energy", "focus", "mana",
	"relationships", "flags", "tags", "remove_tags",
	"traits", "remove_traits", "add_items", "remove_items",
]
# A trigger is a requirement block plus calendar keys (evaluated against the clock).
const TRIGGER_KEYS := [
	"week", "date", "day",
	"tags", "without_tags", "traits", "without_traits",
	"min_skills", "max_skills", "min_needs", "max_needs",
	"min_resources", "max_resources", "flags", "relationships",
	"has_items", "at_location", "location", "time_after", "time_before", "days",
]

static func all() -> Dictionary:
	return {
		"skills": {
			"label": "Skills (stat tree)", "file": "skills.json", "collection": "array", "id_field": "id",
			"fields": [
				{"key": "id", "label": "ID", "type": "text"},
				{"key": "name", "label": "Name", "type": "text"},
				{"key": "parent", "label": "Parent skill", "type": "ref", "ref": "skills", "optional": true},
				{"key": "hidden", "label": "Hidden from player", "type": "bool", "optional": true},
				{"key": "description", "label": "Description", "type": "multiline", "optional": true},
			],
		},
		"needs": {
			"label": "Needs", "file": "needs.json", "collection": "array", "id_field": "id",
			"fields": [
				{"key": "id", "label": "ID", "type": "text"},
				{"key": "name", "label": "Name", "type": "text"},
				{"key": "start", "label": "Start value", "type": "float", "optional": true},
				{"key": "decay_per_min", "label": "Drift / minute", "type": "float", "optional": true},
				{"key": "baseline", "label": "Baseline (eases toward)", "type": "float", "optional": true},
				{"key": "description", "label": "Description", "type": "multiline", "optional": true},
			],
		},
		"resources": {
			"label": "Resources", "file": "resources.json", "collection": "array", "id_field": "id",
			"fields": [
				{"key": "id", "label": "ID", "type": "text"},
				{"key": "name", "label": "Name", "type": "text"},
				{"key": "max", "label": "Maximum", "type": "float", "optional": true},
				{"key": "start", "label": "Start value", "type": "float", "optional": true},
				{"key": "regen_per_min", "label": "Regen / minute", "type": "float", "optional": true},
				{"key": "daily_refill", "label": "Refill each morning", "type": "bool", "optional": true},
				{"key": "description", "label": "Description", "type": "multiline", "optional": true},
			],
		},
		"traits": {
			"label": "Character traits", "file": "traits.json", "collection": "array", "id_field": "id",
			"fields": [
				{"key": "id", "label": "ID", "type": "text"},
				{"key": "name", "label": "Name", "type": "text"},
				{"key": "description", "label": "Description", "type": "multiline", "optional": true},
				{"key": "grants_tags", "label": "Grants tags", "type": "tag_list", "optional": true},
				{"key": "learn_rates", "label": "Learns faster (skill → ×mult)", "type": "map_num", "key_ref": "skills", "optional": true},
			],
		},
		"actors": {
			"label": "Characters (actors)", "file": "actors.json", "collection": "dict",
			"fields": [
				{"key": "name", "label": "Name", "type": "text"},
				{"key": "kind", "label": "Kind", "type": "enum", "options": ["student", "faculty", "player"]},
				{"key": "is_player", "label": "Is the player", "type": "bool", "optional": true},
				{"key": "location", "label": "Starts at", "type": "ref", "ref": "locations"},
				{"key": "tags", "label": "Tags", "type": "tag_list", "optional": true},
				{"key": "traits", "label": "Traits", "type": "ref_list", "ref": "traits", "optional": true},
				{"key": "skills", "label": "Skill overrides", "type": "map_num", "key_ref": "skills", "optional": true},
				{"key": "needs", "label": "Need overrides", "type": "map_num", "key_ref": "needs", "optional": true},
				{"key": "resources", "label": "Resource overrides", "type": "map_num", "key_ref": "resources", "optional": true},
				{"key": "weights", "label": "AI interaction weights", "type": "map_num", "key_ref": "interactions", "optional": true},
			],
		},
		"locations": {
			"label": "Locations (places only)", "file": "locations.json", "collection": "dict",
			"fields": [
				{"key": "name", "label": "Name", "type": "text"},
				{"key": "description", "label": "Description (graded)", "type": "descriptions"},
				{"key": "connections", "label": "Connects to", "type": "ref_list", "ref": "locations", "optional": true},
				{"key": "tags", "label": "Location tags", "type": "tag_list", "optional": true},
			],
		},
		"interactions": {
			"label": "Interactions (what you can do)", "file": "interactions.json", "collection": "dict",
			"fields": [
				{"key": "name", "label": "Button label", "type": "text"},
				{"key": "where", "label": "Available at", "type": "ref_list", "ref": "locations", "optional": true},
				{"key": "where_tags", "label": "…or at any location tagged", "type": "tag_list", "optional": true},
				{"key": "duration", "label": "Minutes", "type": "int", "optional": true},
				{"key": "requires", "label": "Requirements", "type": "requirements", "optional": true},
				{"key": "effects", "label": "Effects", "type": "effects", "optional": true},
				{"key": "learn_skill", "label": "Teaches skill", "type": "ref", "ref": "skills", "optional": true},
				{"key": "learn_mode", "label": "Learn mode", "type": "enum", "options": ["focus", "attend"], "optional": true},
				{"key": "goto", "label": "Moves you to", "type": "ref", "ref": "locations", "optional": true},
				{"key": "dialogue", "label": "Opens conversation", "type": "ref", "ref": "conversations", "optional": true},
				{"key": "description", "label": "On-take description (graded)", "type": "descriptions", "optional": true},
			],
		},
		"schedule": {
			"label": "Timetable (recurring events)", "file": "schedule.json", "collection": "array", "id_field": "id",
			"fields": [
				{"key": "id", "label": "ID", "type": "text"},
				{"key": "name", "label": "Name", "type": "text"},
				{"key": "kind", "label": "Kind", "type": "enum", "options": ["class", "meal", "curfew", "event"]},
				{"key": "room", "label": "Room", "type": "ref", "ref": "locations", "optional": true},
				{"key": "skill", "label": "Teaches skill", "type": "ref", "ref": "skills", "optional": true},
				{"key": "teacher", "label": "Teacher (actor)", "type": "ref", "ref": "actors", "optional": true},
				{"key": "days", "label": "Days", "type": "string_list"},
				{"key": "start", "label": "Start (HH:MM)", "type": "text"},
				{"key": "end", "label": "End (HH:MM)", "type": "text"},
				{"key": "description", "label": "Session description (graded)", "type": "descriptions", "optional": true},
				{"key": "effects", "label": "Per-session effects", "type": "effects", "optional": true},
			],
		},
		"occurrences": {
			"label": "One-time events / sub-events", "file": "occurrences.json", "collection": "array", "id_field": "id",
			"fields": [
				{"key": "id", "label": "ID", "type": "text"},
				{"key": "attach_to", "label": "Sub-event of (recurring id)", "type": "ref", "ref": "schedule", "optional": true},
				{"key": "once", "label": "Fire once", "type": "bool", "optional": true},
				{"key": "trigger", "label": "Trigger", "type": "trigger", "optional": true},
				{"key": "description", "label": "Description (graded)", "type": "descriptions", "optional": true},
				{"key": "effects", "label": "Effects", "type": "effects", "optional": true},
			],
		},
		"spells": {
			"label": "Spells", "file": "spells.json", "collection": "array", "id_field": "id",
			"fields": [
				{"key": "id", "label": "ID", "type": "text"},
				{"key": "name", "label": "Name", "type": "text"},
				{"key": "element", "label": "Element", "type": "text", "optional": true},
				{"key": "requires", "label": "Requirements", "type": "requirements", "optional": true},
				{"key": "description", "label": "Description (graded)", "type": "descriptions", "optional": true},
			],
		},
		"items": {
			"label": "Items", "file": "items.json", "collection": "dict",
			"fields": [
				{"key": "name", "label": "Name", "type": "text"},
				{"key": "description", "label": "Description", "type": "multiline", "optional": true},
				{"key": "use", "label": "Effects on use", "type": "effects", "optional": true},
				{"key": "consumable", "label": "Consumed on use", "type": "bool", "optional": true},
			],
		},
		"conversations": {
			"label": "Conversations (branching)", "file": "conversations.json", "collection": "dict",
			"fields": [
				{"key": "lines", "label": "Nodes", "type": "list", "item": [
					{"key": "speaker", "label": "Speaker", "type": "text", "optional": true},
					{"key": "text", "label": "Text (graded)", "type": "descriptions", "optional": true},
					{"key": "label", "label": "Jump label", "type": "text", "optional": true},
					{"key": "choices", "label": "Choices", "type": "list", "item": [
						{"key": "text", "label": "Choice text", "type": "text"},
						{"key": "requires", "label": "Shown when", "type": "requirements", "optional": true},
						{"key": "effects", "label": "Effects", "type": "effects", "optional": true},
						{"key": "goto", "label": "Go to label", "type": "text", "optional": true},
					], "optional": true},
				]},
			],
		},
	}
