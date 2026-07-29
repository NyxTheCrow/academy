extends RefCounted
class_name Clock
## Clock — a pure calendar/time value object.
##
## This is the whole of "TIME" as a first-class state, extracted from the old
## GameState god-object. It holds only the current instant (an absolute day
## count plus minutes into the day) and the calendar shape; it has NO knowledge
## of needs, events, NPCs, or side effects. Advancing time here does nothing but
## roll the numbers over — the simulation layer (World) decides what a tick means.
##
## All display strings ("Monday, Morning", "Trimester 2 · Week 3") derive from
## day_count, so there is one source of truth for the date.

const DEFAULT_CONFIG := {
	"start_minutes": 420,          # 07:00
	"day_minutes": 1440,
	"days": ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
	"weeks_per_month": 4,
	"months_per_trimester": 3,
	"trimesters_per_year": 3,
	"school_days_per_week": 5,
}

var config: Dictionary = DEFAULT_CONFIG.duplicate(true)
var day_count: int = 0
var minutes_of_day: int = 420

func _init(cfg: Dictionary = {}, start_day: int = 0, start_minute: int = -1) -> void:
	for k in cfg:
		config[k] = cfg[k]
	day_count = start_day
	minutes_of_day = start_minute if start_minute >= 0 else int(config["start_minutes"])

# --- Config accessors -------------------------------------------------------
func _c(key: String, fallback: Variant) -> Variant:
	return config.get(key, fallback)

func day_minutes() -> int: return int(_c("day_minutes", 1440))
func days() -> Array: return _c("days", DEFAULT_CONFIG["days"])
func weeks_per_month() -> int: return maxi(1, int(_c("weeks_per_month", 4)))
func months_per_trimester() -> int: return maxi(1, int(_c("months_per_trimester", 3)))
func trimesters_per_year() -> int: return maxi(1, int(_c("trimesters_per_year", 3)))
func school_days_per_week() -> int: return int(_c("school_days_per_week", 5))
func days_per_month() -> int: return weeks_per_month() * 7
func days_per_trimester() -> int: return days_per_month() * months_per_trimester()
func days_per_year() -> int: return days_per_trimester() * trimesters_per_year()

# --- Advancing (the ONLY mutators) ------------------------------------------
## Add minutes; returns how many whole days rolled over (so the caller can run
## per-day logic like refilling resources). No other side effects.
func advance(mins: int) -> int:
	minutes_of_day += maxi(0, mins)
	var rolled := 0
	var dm := day_minutes()
	while minutes_of_day >= dm:
		minutes_of_day -= dm
		day_count += 1
		rolled += 1
	return rolled

## Minutes until the next occurrence of `hhmm` today or tomorrow (used by sleep()
## and "wait until" helpers). Always returns a positive delta.
func minutes_until(hhmm: String) -> int:
	var target := hm(hhmm)
	if target > minutes_of_day:
		return target - minutes_of_day
	return (day_minutes() - minutes_of_day) + target

# --- Derived date (display-only) --------------------------------------------
func weekday_index() -> int: return day_count % 7
func day_name() -> String: return str(days()[weekday_index()])
func is_school_day() -> bool: return weekday_index() < school_days_per_week()
func week_of_year() -> int: return day_count / 7
func week_of_month() -> int: return (day_count / 7) % weeks_per_month()
func month_of_trimester() -> int: return (day_count / days_per_month()) % months_per_trimester()
func trimester_of_year() -> int: return (day_count / days_per_trimester()) % trimesters_per_year()
func year_index() -> int: return day_count / days_per_year()

func time_string() -> String:
	return "%02d:%02d" % [minutes_of_day / 60, minutes_of_day % 60]

func date_string() -> String:
	return "Trimester %d · Month %d · Week %d · %s · %s" % [
		trimester_of_year() + 1, month_of_trimester() + 1,
		week_of_month() + 1, day_name(), time_string()]

# --- Parsing ----------------------------------------------------------------
## "09:30" -> 570. Tolerant of a bare hour ("9") and of ints already in minutes.
static func hm(v: Variant) -> int:
	if v is int or v is float:
		return int(v)
	var parts: PackedStringArray = str(v).split(":")
	var h := int(parts[0]) if parts.size() > 0 else 0
	var m := int(parts[1]) if parts.size() > 1 else 0
	return h * 60 + m

# --- Serialization ----------------------------------------------------------
func to_dict() -> Dictionary:
	return {"day_count": day_count, "minutes_of_day": minutes_of_day}

func from_dict(d: Dictionary) -> void:
	day_count = int(d.get("day_count", 0))
	minutes_of_day = int(d.get("minutes_of_day", config["start_minutes"]))
