class_name TimeEntry
extends RefCounted
## Hours worked on a job: a start, an end, a break, and the rate recorded **at entry** (spec §7.3).
##
## Never a running clock that owns the truth. A clock loses the truth every time the app closes, the
## phone dies, or the signal drops; an entry with a start and an end is a record that survives all
## three, and it is what a person signs at the end of a day.
##
## The loaded rate is **recorded**, like a line's price is frozen (§2.2): a raise next March must not
## reprice the hours worked last November, and a payroll revision must not silently restate a costed
## job.
##
## Minutes are stored **exactly**. Payroll may round to a quarter hour per a company setting, but the
## job cost report uses the exact minutes, because the labour genuinely took them.
##
## An entry is **pending** until an office user approves it, and a pending entry is excluded from
## actual cost with its total shown, so a report never reads low without saying why.

const MoneyScript := preload("res://scripts/biz/money.gd")

const MANUAL := 0
const CLOCK := 1
const IMPORT := 2

const SOURCE_NAMES := {MANUAL: "typed in", CLOCK: "clocked", IMPORT: "imported"}

## The longest break a shift can contain, in minutes: 24 hours. A "break" longer than a day is a
## data error, and averaging it away is how a nine-hour day becomes four.
const MAX_BREAK_MINUTES := 1440
## The longest shift this will accept, in minutes: 24 hours. Past that it is a mis-typed date, and a
## mis-typed date that gets costed is a job that looks over budget for no reason.
const MAX_SHIFT_MINUTES := 1440

var id: String = ""
var job: String = ""
var cost_code: StringName = &""
var crew_member: StringName = &""
## ISO-8601 UTC strings; the two together are the shift.
var started_at: String = ""
var ended_at: String = ""
var break_minutes: int = 0
## What this hour of this person's time cost, recorded when the entry was made.
var loaded_rate: Money = null
var source: int = MANUAL
var approved_by: String = ""
var note: String = ""
var photo: String = ""


func _init(entry_id: String = "") -> void:
	id = entry_id
	loaded_rate = MoneyScript.zero()


static func source_name(value: int) -> String:
	return String(SOURCE_NAMES.get(value, "typed in"))


func started_unix() -> int:
	return _unix(started_at)


func ended_unix() -> int:
	return _unix(ended_at)


## The minutes worked, break taken off. Zero when the timestamps cannot be read, because a negative or
## invented number is worse than none - the `problem()` below says what is wrong.
func minutes() -> int:
	var start := started_unix()
	var end := ended_unix()
	if start <= 0 or end <= 0:
		return 0
	return floori(float(end - start) / 60.0) - break_minutes


## What is wrong with this entry, in words, or empty when nothing is. A break longer than the shift,
## an end before the start, or an unreadable time is **refused or flagged, never averaged away**
## (§7.3).
func problem() -> String:
	var start := started_unix()
	var end := ended_unix()
	if start <= 0 or end <= 0:
		return "the start or the end is not a time"
	if end <= start:
		return "the entry ends before it starts"
	if break_minutes < 0:
		return "the break is negative"
	if break_minutes > MAX_BREAK_MINUTES:
		return "the break is longer than a day"
	var span := floori(float(end - start) / 60.0)
	if span > MAX_SHIFT_MINUTES:
		return "the shift is longer than a day"
	if break_minutes >= span:
		return "the break is longer than the shift"
	return ""


func is_valid() -> bool:
	return problem().is_empty()


func is_approved() -> bool:
	return not approved_by.strip_edges().is_empty()


## Approve an entry, so it may become cost. An entry that does not read is never approved; there is
## nothing to approve.
func approve(by: String) -> bool:
	if not is_valid() or by.strip_edges().is_empty():
		return false
	approved_by = by
	return true


## What this entry cost: the recorded rate for the exact minutes worked, rounded once (§7.3, §2.1).
## An unreadable rate stays unreadable, so a bad entry poisons the cost it feeds rather than reading
## as free labour.
func labour() -> Money:
	var rate := loaded_rate if loaded_rate != null else MoneyScript.invalid()
	if not rate.is_valid():
		return rate
	return MoneyScript.round_div(rate.cents * minutes(), 60, rate.currency)


## Whether two entries for the same person overlap in time. A person cannot be in two places at once,
## and an overlap is **flagged** rather than averaged.
func overlaps(other: TimeEntry) -> bool:
	if other == null or other.crew_member != crew_member:
		return false
	var a_start := started_unix()
	var a_end := ended_unix()
	var b_start := other.started_unix()
	var b_end := other.ended_unix()
	if a_start <= 0 or a_end <= 0 or b_start <= 0 or b_end <= 0:
		return false
	return a_start < b_end and b_start < a_end


func to_dict() -> Dictionary:
	return {
		"id": id,
		"job": job,
		"cost_code": String(cost_code),
		"crew_member": String(crew_member),
		"started_at": started_at,
		"ended_at": ended_at,
		"break_minutes": break_minutes,
		"loaded_rate": (loaded_rate if loaded_rate != null else MoneyScript.zero()).to_dict(),
		"source": source,
		"approved_by": approved_by,
		"note": note,
		"photo": photo,
	}


static func from_dict(data: Dictionary) -> TimeEntry:
	var entry: TimeEntry = EntryScript.new(String(data.get("id", "")))
	if entry.id.is_empty():
		return null
	entry.job = String(data.get("job", ""))
	entry.cost_code = StringName(data.get("cost_code", ""))
	entry.crew_member = StringName(data.get("crew_member", ""))
	entry.started_at = String(data.get("started_at", ""))
	entry.ended_at = String(data.get("ended_at", ""))
	entry.break_minutes = int(data.get("break_minutes", 0))
	entry.loaded_rate = MoneyScript.from_dict(data.get("loaded_rate", {}))
	entry.source = int(data.get("source", MANUAL))
	entry.approved_by = String(data.get("approved_by", ""))
	entry.note = String(data.get("note", ""))
	entry.photo = String(data.get("photo", ""))
	return entry


## Seconds since the epoch from an ISO-8601 string, or 0 when it cannot be read. A trailing `Z` is
## dropped, because Godot's parser wants the bare form.
static func _unix(iso: String) -> int:
	var text := iso.strip_edges()
	if text.is_empty():
		return 0
	if text.ends_with("Z"):
		text = text.substr(0, text.length() - 1)
	if not text.contains("T"):
		return 0
	return Time.get_unix_time_from_datetime_string(text)


const EntryScript := preload("res://scripts/biz/time_entry.gd")