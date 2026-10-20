class_name DraftRevisionLog
extends RefCounted
## The named revisions of a drawing: a history you keep, not a stack you walk.
##
## Undo is a stack: it answers "what did I just do", and it forgets the answer as soon as a new edit
## is made. A revision is a *record* - a message, who made it, when, and the drawing as it stood - so
## that the interesting history survives: what was sent, what changed after the client saw it, and
## what the difference between those two drawings was. That is the question a designer actually gets
## asked, and undo cannot answer it.
##
## ## Why snapshots, and why that is not expensive
##
## A revision stores the drawing's own `to_dict()` - a whole snapshot - rather than a delta. The
## project already decided this way once, in `undo_stack.gd`, and for the same reason: a delta needs a
## correct inverse for every edit, and a subtly wrong inverse corrupts a drawing in a way nobody can
## see. A revision is captured on a person's command rather than on every keystroke, so there are a
## handful of them and each is a small JSON object; the cost is nothing next to being wrong.
##
## ## What the diff is and is not
##
## `diff()` compares two revisions by **entity id**, which is the property that makes it possible at
## all: `document.add()` assigns an id and `document.replace()` keeps it, so a shape that was widened
## is the *same* shape afterwards. What it does not do is say what changed *inside* an entity - "this
## bed got wider" is a human sentence about geometry, and a diff's job is to point at the bed so a
## person can look at it.
##
## Both sides are compared **after a JSON round trip**. A snapshot taken in memory carries integer
## keys and integer lengths, and the same snapshot read back from a file carries strings and floats,
## so comparing a saved revision against the live drawing without that would report every shape in the
## drawing as changed - the same trap the round-trip notes in this project describe.

## What a revision record holds. One list, so the writer, the reader and the diff cannot disagree
## about what a revision is.
const FIELDS: Array[String] = ["message", "author", "when", "snapshot"]

## How many revisions a drawing keeps. A cap rather than a limit of the format: a log that grows
## without bound is a file nobody prunes, and the oldest revision of a garden is the least interesting
## one in it. What falls off the end is counted, so the log can say it is not the whole story.
const LIMIT := 50

## What a revision with no message is called. A revision nobody explained is still a revision, and a
## blank line in a list reads as a fault.
const NO_MESSAGE := "no message"

var _records: Array[Dictionary] = []
## How many revisions were dropped off the oldest end. Kept because "this is all of it" and "this is
## the last fifty" are different claims and only one of them is true.
var dropped: int = 0


static func make() -> DraftRevisionLog:
	return DraftRevisionLog.new()


## Who is at the keyboard, as far as the machine knows. There is no account in this app and no signed-in
## user, so the operating system's own answer is the only honest one - and it is worth having at all
## because a history that cannot say *who* is a list of timestamps.
##
## Empty when the environment says nothing, which the log treats as an anonymous revision rather than
## inventing a name.
static func system_author() -> String:
	for name: String in ["USERNAME", "USER", "LOGNAME"]:
		var who := OS.get_environment(name).strip_edges()
		if not who.is_empty():
			return who
	return ""


# --- keeping a revision ---------------------------------------------------------------


## Record the drawing as it stands, and return the record: what was captured, how many shapes it has,
## and which revision it is. The snapshot is taken by the caller - `document.to_dict()` - because this
## class knows nothing about documents and can therefore be tested without one.
##
## The parameter is not called `snapshot`, nor the local below `record`: either would shadow a method
## of this class, which is a warning in this project rather than a style note.
func capture(state: Dictionary, message: String, author: String = "") -> Dictionary:
	var stored: Dictionary = {
		"message": message.strip_edges() if not message.strip_edges().is_empty() else NO_MESSAGE,
		"author": author.strip_edges(),
		"when": Time.get_datetime_string_from_system(false, true),
		# Through JSON, so a snapshot held in memory and one read back from a file are the *same*
		# snapshot to `diff()`. Without this a revision compared with itself would look changed.
		"snapshot": _plain(state),
	}
	_records.append(stored)
	while _records.size() > LIMIT:
		_records.remove_at(0)
		dropped += 1
	return record_at(_records.size() - 1)


## One snapshot as the file format would hold it: numbers as floats and keys as strings, which is what
## makes two snapshots comparable whichever way they arrived.
##
## The parameter is not called `snapshot`: this class has a method of that name, and a local that shadows
## one is a warning in this project rather than a style note.
static func _plain(state: Dictionary) -> Dictionary:
	var text := JSON.stringify(state)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else state


# --- reading the log ------------------------------------------------------------------


func count() -> int:
	return _records.size()


## A stored revision, as it is kept: the message, who, when, and the drawing itself. Private, because
## the snapshot is not something the rest of the program should reach for by accident - `snapshot()`
## hands out a copy and `record_at()` a description.
func _revision(index: int) -> Dictionary:
	return _records[index] if is_valid(index) else {}


func is_valid(index: int) -> bool:
	return index >= 0 and index < _records.size()


## A revision as anything listing them needs it: what it says, who made it, when, and how big the
## drawing was. Counted from the snapshot rather than stored, so the number cannot go stale.
func record_at(index: int) -> Dictionary:
	if not is_valid(index):
		return {}
	var stored: Dictionary = _records[index]
	var state: Dictionary = stored.get("snapshot", {})
	var entities: Dictionary = state.get("entities", {})
	return {
		"index": index,
		"message": String(stored["message"]),
		"author": String(stored["author"]),
		"when": String(stored["when"]),
		"shapes": entities.size(),
	}


func messages() -> Array[String]:
	var out: Array[String] = []
	for index in _records.size():
		out.append(String(_records[index]["message"]))
	return out


## One revision described the way a history reads: the message first, because that is what a person
## looks for, then who and when, then how big the drawing was.
func describe(index: int) -> String:
	var row: Dictionary = record_at(index)
	if row.is_empty():
		return ""
	var words := "rev %d  %s" % [index + 1, String(row["message"])]
	if not String(row["author"]).is_empty():
		words += "  (%s, %s)" % [String(row["author"]), String(row["when"])]
	else:
		words += "  (%s)" % String(row["when"])
	words += "  %d shapes" % int(row["shapes"])
	return words


## The drawing as that revision held it, ready for `DraftDocument.from_dict`. A copy, so a caller that
## restores it cannot alter the revision it came from.
func snapshot(index: int) -> Dictionary:
	if not is_valid(index):
		return {}
	var stored: Dictionary = _records[index]
	var state: Variant = stored.get("snapshot", {})
	return (state as Dictionary).duplicate(true) if state is Dictionary else {}


func clear() -> void:
	_records.clear()
	dropped = 0


# --- comparing two of them ------------------------------------------------------------


## What changed between two revisions, by entity id.
##
## The three lists are ids rather than records, and a caller that wants to say what a shape *is* looks
## it up in the revision it was found in: a diff that carried copies of the geometry would be a third
## copy of the drawing.
func diff(from_index: int, to_index: int) -> Dictionary:
	if not is_valid(from_index) or not is_valid(to_index):
		return {
			"ok": false, "reason": "there is no such revision",
			"added": [], "changed": [], "removed": [], "same": false,
		}
	var before: Dictionary = _plain(snapshot(from_index))
	var after: Dictionary = _plain(snapshot(to_index))
	return compare(before, after)


## The comparison itself, on two drawing states. Pure, so it can be tested against hand-written
## states as well as against two revisions of a real drawing.
static func compare(before: Dictionary, after: Dictionary) -> Dictionary:
	var old: Dictionary = _entities_of(before)
	var new: Dictionary = _entities_of(after)
	var added: Array[int] = []
	var changed: Array[int] = []
	var removed: Array[int] = []
	for key: Variant in new:
		var id: int = int(key)
		if not old.has(id):
			added.append(id)
		elif old[id] != new[key]:
			changed.append(id)
		old.erase(id)
	for key: Variant in old:
		removed.append(int(key))
	added.sort()
	changed.sort()
	removed.sort()
	return {
		"ok": true,
		"reason": "",
		"added": added,
		"changed": changed,
		"removed": removed,
		"same": added.is_empty() and changed.is_empty() and removed.is_empty(),
	}


## A drawing's shapes keyed by their id, whatever the ids arrived as. The document stores them as a
## JSON object, so an id is a string on the way in and an `int` in the rest of the program.
static func _entities_of(state: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var entities: Variant = state.get("entities", {})
	if not entities is Dictionary:
		return out
	for key: Variant in entities:
		out[int(key)] = entities[key]
	return out


## The difference in words, the way a designer would be told it.
static func describe_diff(changes: Dictionary) -> String:
	if not bool(changes.get("ok", false)):
		return String(changes.get("reason", "the two revisions cannot be compared"))
	if bool(changes.get("same", false)):
		return "the drawing is the same in both revisions"
	var parts: Array[String] = []
	for pair: Array in [
		["added", "added"], ["changed", "changed"], ["removed", "removed"],
	]:
		var ids: Array = changes[pair[0]]
		if not ids.is_empty():
			parts.append("%d %s" % [ids.size(), String(pair[1])])
	# The ids are named, because "the drawing changed" is not something anybody can act on.
	var words := ", ".join(parts)
	var named: Array[String] = []
	for key: String in ["added", "changed", "removed"]:
		var ids: Array = changes[key]
		if ids.is_empty():
			continue
		var listed: Array[String] = []
		for id: Variant in ids.slice(0, 6):
			listed.append("#%d" % int(id))
		if ids.size() > 6:
			listed.append("and %d more" % (ids.size() - 6))
		named.append("%s: %s" % [key, ", ".join(listed)])
	return "%s  (%s)" % [words, "; ".join(named)]


# --- what a file keeps ----------------------------------------------------------------


func to_dict() -> Dictionary:
	var rows: Array = []
	for stored: Dictionary in _records:
		var kept: Dictionary = {}
		for field: String in FIELDS:
			kept[field] = stored[field]
		rows.append(kept)
	return {"version": 1, "dropped": dropped, "records": rows}


## Read a history back. Anything it cannot understand is dropped rather than refused: a history is worth
## having, and a damaged record is not a reason to lose the nine around it.
##
## The local is not called `log`: that is a built-in function, and one of the names this project treats as
## taken.
static func from_dict(data: Variant) -> DraftRevisionLog:
	var history := DraftRevisionLog.new()
	if not (data is Dictionary) or not (data.get("records") is Array):
		return history
	history.dropped = int((data as Dictionary).get("dropped", 0))
	for entry: Variant in data["records"]:
		if not (entry is Dictionary):
			continue
		var entry_record: Dictionary = entry
		# A record with no *drawing* in it is not a revision of an empty drawing, it is a damaged
		# record: keeping it would invent a revision that restores nothing, and a restore that wipes
		# the drawing is the one outcome a history must never have.
		if not entry_record.has("snapshot") or not (entry_record["snapshot"] is Dictionary):
			continue
		var state: Variant = entry_record["snapshot"]
		history._records.append({
			"message": String(entry_record.get("message", NO_MESSAGE)),
			"author": String(entry_record.get("author", "")),
			"when": String(entry_record.get("when", "")),
			"snapshot": state,
		})
	return history