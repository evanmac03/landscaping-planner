class_name Autosave
extends RefCounted
## A copy of a drawing kept in case the program stops without being asked.
##
## The problem is narrow. A program that is *closed* is a drawing that was saved, and a program that
## *stops* - a crash, a power cut, a machine that goes to sleep and never wakes up - is a drawing that
## is not. Everything else in this app is written when a person says so; this is the one file written
## without anybody asking, and that is why it lives apart from the drawings: a copy is not a drawing,
## it is what a drawing might have been.
##
## ## Where it lives, and why it is not a drawing
##
## `user://recovery`, one file per drawing *identity* - the file the drawing belongs to, or `untitled`
## for a drawing that has never been saved. Deliberately not in `user://drawings`, for the same reason
## the recent list is not: a Save dialog opens on that folder, and somebody's half-finished work
## sitting in the list of drawings they can open is worse than useless.
##
## ## The four rules
##
## * **A copy is only written when there is something to recover.** A drawing with nothing drawn on it
##   is refused rather than written: a copy of nothing, offered on the next launch, teaches a person
##   to click past the one that matters.
## * **A copy is cleared whenever the work stops being unsaved** - it was saved, a new drawing was
##   started, or another was opened. The file exists exactly while there is unsaved work.
## * **A copy of a drawing that is already on disk is not a rescue.** `still_wanted` compares the copy
##   with the file it belongs to, so a copy taken a moment before a Save is never offered back to
##   somebody as their own file.
## * **A copy is never put back without being asked**, and putting it back is an ordinary edit: the
##   drawing it replaces goes onto the undo history under a name that says what happened.

## Where the copies live. On `user://` for the same reason a drawing is: a copy belongs to the person
## who made it, not to the installation.
const DIR := "user://recovery"
const EXTENSION := ".json"
## The name a write goes through on its way to the real one, and the reason a copy cannot be read
## half-written: the same rename the drawings folder uses.
const TEMP_SUFFIX := ".writing"
## What a copy of a drawing with no file name is filed under. One slot per identity, and a drawing
## that has never been saved has one identity - `untitled`.
const UNTITLED := "untitled"
## How long a drawing has to have been worked on before another copy is kept. Half a minute is long
## enough that the file is not written on every keystroke and short enough that a crash costs a person
## about as much as a sentence of typing.
const INTERVAL := 30.0
## What a copy's file says it is. Read on the way in so that a file this program did not write is
## refused rather than restored as a drawing with no shapes in it.
const VERSION := 1


# --- where a copy lives -----------------------------------------------------------------


## Make sure the folder is there. Every write, read and listing needs it, and a listing needs it to
## exist in order to have nothing to list.
static func ensure_dir() -> bool:
	if DirAccess.open(DIR) == null and DirAccess.make_dir_recursive_absolute(DIR) != OK:
		return false
	return true


## The file a copy of this drawing goes in. The identity is the *name* of the drawing rather than its
## whole path, which is what the drawings folder and the revisions folder both do - and which means a
## drawing moved to another folder keeps the copy it had.
static func path_for(drawing_path: String = "") -> String:
	var called := DrawingStore.display_name(drawing_path)
	if called.is_empty():
		called = UNTITLED
	return DIR.path_join(DrawingStore.sanitise(called) + EXTENSION)


## Every copy on disk. What a listing of "work that might need rescuing" reads, and what a test peers
## through to check that nothing was left behind.
static func list() -> Array[String]:
	var out: Array[String] = []
	if not ensure_dir():
		return out
	var directory := DirAccess.open(DIR)
	if directory == null:
		return out
	for file_name in directory.get_files():
		# A temp file cannot be mistaken for a copy: `<name>.json.writing` does not end in the
		# extension.
		if file_name.ends_with(EXTENSION):
			out.append(DIR.path_join(file_name))
	return out


# --- keeping one ------------------------------------------------------------------------


## Whether it is time to keep another copy. Two things have to be true: the drawing has unsaved
## changes, and enough time has passed since the last copy that keeping one is not a chore the program
## does to itself every frame.
static func is_due(dirty: bool, since_last: float, interval: float = INTERVAL) -> bool:
	return dirty and since_last >= interval


## Whether a drawing state has anything in it worth keeping.
##
## A drawing with no shapes is not work somebody would be upset to lose, and offering it would be the
## offer that teaches a person to click past the offer that matters. Sheets, irrigation and lighting
## are read with the shapes rather than counted separately: they describe a garden, and a drawing with
## no garden in it yet is not one.
static func has_work(state: Dictionary) -> bool:
	var entities: Variant = state.get("entities", {})
	return entities is Dictionary and not (entities as Dictionary).is_empty()


## Keep a copy of a drawing. Returns `{"ok", "reason", "path", "when"}`.
##
## Through a temporary file and a rename, like every other write in this program, because the one
## failure a recovery feature must not have is a copy that is shorter than the work it was supposed to
## hold. The gesture serial travels with it: it is what says, later, that the copy is of *this*
## drawing rather than of one that happens to share its name.
static func write(
	state: Dictionary, drawing_path: String = "", project_name: String = "", serial: int = 0
) -> Dictionary:
	if state.is_empty():
		return _refused("there is no drawing to keep a copy of")
	if not has_work(state):
		return _refused("this drawing is empty, so there is nothing worth keeping")
	if not ensure_dir():
		return _refused("cannot open the recovery folder")
	var target: String = path_for(drawing_path)
	var temp: String = target + TEMP_SUFFIX
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return _refused("cannot write %s" % temp.get_file())
	# Not `when` and not `when_string`: the record is built first so that the sentence the caller gets
	# back carries the same moment that was written down.
	var kept: Dictionary = {
		"version": VERSION,
		"drawing_path": drawing_path,
		"project_name": project_name,
		"serial": maxi(serial, 0),
		"when": Time.get_datetime_string_from_system(false, true),
		"state": state,
	}
	file.store_string(JSON.stringify(kept, "  "))
	file.close()
	var error := DirAccess.rename_absolute(temp, target)
	if error != OK:
		DirAccess.remove_absolute(temp)
		return _refused("cannot put %s in place: %s" % [target.get_file(), error_string(error)])
	return {"ok": true, "reason": "", "path": target, "when": String(kept["when"])}


## Forget the copy of a drawing: what it held has been saved, or has been deliberately left behind.
##
## Clearing a copy that is not there is not a failure. It is the state this call exists to reach.
static func clear(drawing_path: String = "") -> bool:
	var target: String = path_for(drawing_path)
	if not FileAccess.file_exists(target):
		return true
	return DirAccess.remove_absolute(target) == OK


## Throw away every copy on disk. What a test does before it starts, so that one test cannot be the
## reason the next one fails. Counts what it removed.
static func clear_all() -> int:
	var removed := 0
	for target: String in list():
		if DirAccess.remove_absolute(target) == OK:
			removed += 1
	return removed


# --- reading one ------------------------------------------------------------------------


## Read a copy. Refuses a file that is not there, a file that is not JSON, JSON that is not an object,
## and an object that is not a copy - each with a sentence saying which, because "it did not open" is
## not something a person can act on.
static func read(path: String) -> Dictionary:
	if path.is_empty():
		return _refused("no copy was named")
	if not FileAccess.file_exists(path):
		return _refused("there is no copy called %s" % path.get_file())
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _refused("cannot read %s" % path.get_file())
	var text := file.get_as_text()
	file.close()
	# A reader rather than `JSON.parse_string`, which logs an engine error when it fails: the person is
	# already being told in a sentence what is wrong, and a console line nobody can act on is noise.
	var reader := JSON.new()
	if reader.parse(text) != OK:
		return _refused("%s is not readable: %s (line %d)" % [
			path.get_file(), reader.get_error_message(), reader.get_error_line()
		])
	if not (reader.data is Dictionary):
		return _refused("%s is not a copy of a drawing" % path.get_file())
	var data: Dictionary = reader.data
	if int(data.get("version", 0)) != VERSION or not (data.get("state") is Dictionary):
		return _refused("%s is not a copy of a drawing" % path.get_file())
	var state: Variant = data["state"]
	return {
		"ok": true,
		"reason": "",
		"path": path,
		"drawing_path": String(data.get("drawing_path", "")),
		"project_name": String(data.get("project_name", "")),
		"serial": int(data.get("serial", 0)),
		"when": String(data.get("when", "")),
		"state": state,
	}


static func _refused(reason: String) -> Dictionary:
	return {
		"ok": false, "reason": reason, "path": "",
		"drawing_path": "", "project_name": "", "serial": 0, "when": "", "state": {},
	}


## Is this copy still the only place something exists?
##
## A copy taken a moment before the drawing was saved is a copy of a file that is already on disk:
## offering it would be handing somebody their own file back and calling it a rescue. A copy of a
## drawing that has never been saved has no file to compare against at all, so it is always wanted -
## and so is a copy whose file has since been deleted, because then the copy is all there is.
##
## The comparison is the whole state, through JSON on *both* sides. That is the only way a snapshot
## held in memory and the same snapshot read back from a file compare equal: after a round trip every
## number is a float and every key is a string, on both sides equally.
static func still_wanted(copy: Dictionary) -> bool:
	var where := String(copy.get("drawing_path", ""))
	if where.is_empty():
		return true
	var saved: Dictionary = DrawingStore.read(where)
	if not bool(saved.get("ok", false)):
		return true
	var state: Variant = copy.get("state", {})
	var file_state: Variant = saved.get("data", {})
	if not (state is Dictionary) or not (file_state is Dictionary):
		return true
	return not same_state(state, file_state)


## Whether two drawing states are the same drawing. Both sides go through the file format, so a live
## snapshot and a snapshot read back from disk can be compared at all - comparing them directly reports
## every shape as changed, because one has integer keys and the other has strings.
static func same_state(left: Dictionary, right: Dictionary) -> bool:
	var one: Variant = JSON.parse_string(JSON.stringify(left))
	var other: Variant = JSON.parse_string(JSON.stringify(right))
	return one is Dictionary and other is Dictionary and one == other


## The newest copy that is still unsaved work, or an empty dictionary when there is none.
##
## Newest, because a person who stopped twice wants the work they had when they last stopped; and
## only copies that are `still_wanted`, so a leftover from a drawing that has since been saved is
## passed over rather than offered.
static func newest_wanted() -> Dictionary:
	var best: Dictionary = {}
	for path: String in list():
		var found: Dictionary = read(path)
		if not bool(found["ok"]) or not still_wanted(found):
			continue
		# The moment is written in ISO order, so comparing two of them as text is comparing them as
		# dates. A copy with no moment at all loses to one that has one rather than winning by default.
		if best.is_empty() or String(found["when"]) > String(best["when"]):
			best = found
	return best


# --- saying what one is ------------------------------------------------------------------


## The time of day a copy was kept, out of the moment written down. `14:32` rather than
## `2026-05-03 14:32:10`, because that is the part a person recognises as "a moment ago" - and the
## whole string back when it is not shaped like a moment, which is the honest answer for a file
## somebody edited by hand.
static func clock_of(when: String) -> String:
	if when.length() >= 16 and when[10] == " ":
		return when.substr(11, 5)
	return when


## What a copy holds, the way a person is told about it: what the drawing was called, how much is in
## it, and when the copy was kept.
static func describe(copy: Dictionary) -> String:
	var state: Variant = copy.get("state", {})
	var entities: Variant = (state as Dictionary).get("entities", {}) if state is Dictionary else {}
	var shapes: int = (entities as Dictionary).size() if entities is Dictionary else 0
	var where := String(copy.get("drawing_path", ""))
	var called := DrawingStore.display_name(where)
	if called.is_empty():
		called = UNTITLED
	var words := "%s, %d shape%s" % [called, shapes, "" if shapes == 1 else "s"]
	var when := clock_of(String(copy.get("when", "")))
	if not when.is_empty():
		words += ", kept %s" % when
	return words