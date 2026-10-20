class_name DrawingStore
extends RefCounted
## Where a drawing lives on disk, and how it is written and read back.
##
## A drawing is a JSON file in `user://drawings`, written from `DraftDocument.to_dict()` - a
## format the document could already produce and consume, and which its own tests round-trip.
## What this adds is the part a *file* needs that an object does not:
##
## * a folder that exists,
## * a name that is safe on every platform this runs on,
## * a write that cannot leave half a file behind,
## * a read that refuses what it cannot understand rather than opening a half-understood
##   drawing over the one somebody has open,
## * and the list of what was opened recently, which is the whole of a file manager that a
##   File menu actually needs.


## Where drawings live. `user://` because a drawing belongs to the person who made it, not to
## the installation - the same reason a proposal still goes there.
const DIR := "user://drawings"
const EXTENSION := ".json"
## The recent list, deliberately NOT in `DIR`. The file dialogs open on `DIR`, so anything kept
## there is a file somebody can browse to and save over - and the recent list is the one file in
## this app that nothing but this app may write. It also keeps the folder showing drawings only.
const RECENT_FILE := "user://recent-drawings.json"
## The named revisions of a drawing, one file per drawing, and **also deliberately not in `DIR`**: the
## same reason as the recent list. A file dialogs opens on the drawing folder, so a histories folder
## inside it would put one file per drawing in the list of drawings a person is offered.
##
## Keyed by the drawing's *name* rather than by its path, which means Save As starts a fresh history.
## That is the right reading of what a history is: the revisions belong to the design that was sent,
## and the copy somebody keeps working on is a new document.
const REVISIONS_DIR := "user://revisions"
## What the recent list was called while it lived in `DIR`. A build from before the move left its
## list behind in the drawings folder, and a Save dialog opens on that folder.
const LEGACY_RECENT_NAME := "recent.json"
## How many drawings the menu remembers. Eight is a menu that still opens in one column.
const RECENT_MAX := 8
## The name a write goes through on its way to the real one.
const TEMP_SUFFIX := ".writing"
## Long enough for a descriptive name, short enough for every filesystem this runs on.
const MAX_NAME := 64
const DEFAULT_NAME := "drawing"
## What a name may keep, and what everything else becomes.
const ALLOWED := " _-"


## Make sure the folder is there. Every write, read and listing needs it, and a menu that lists
## drawings needs it to exist in order to have nothing to list.
static func ensure_dir() -> bool:
	if DirAccess.open(DIR) == null and DirAccess.make_dir_recursive_absolute(DIR) != OK:
		return false
	_migrate_the_recent_list()
	return true


## Carry the recent list out of the drawings folder, once, if a build left it there.
##
## The folder is where a Save dialog opens, and the recent list is the one file here that only this
## app may write: browsing to it and saving over it would lose the list. What decides whether the
## file is the list is its *contents* - the list is a JSON array of paths and a drawing is a JSON
## object - because a person may legitimately name a drawing "recent".
static func _migrate_the_recent_list() -> void:
	var legacy := DIR.path_join(LEGACY_RECENT_NAME)
	var file := FileAccess.open(legacy, FileAccess.READ)
	if file == null:
		return
	# Read it without going through `write_recent`, which would call back into here.
	var reader := JSON.new()
	var readable: bool = reader.parse(file.get_as_text()) == OK
	file.close()
	if not readable or not (reader.data is Array):
		return
	var paths: Array[String] = read_recent(legacy)
	if not paths.is_empty() and not FileAccess.file_exists(RECENT_FILE):
		var out := FileAccess.open(RECENT_FILE, FileAccess.WRITE)
		if out != null:
			out.store_string(JSON.stringify(paths, "  "))
			out.close()
	DirAccess.remove_absolute(legacy)


## A file name for a drawing title: its letters, digits, spaces, dashes and underscores, with
## anything else turned into a dash.
##
## Legal on every platform this runs on, and still recognisable, which a hash or a UUID would
## not be. An accented letter becomes a dash: this is a file name, and pretending to know how
## some other filesystem will store "café" is how a drawing ends up unfindable.
static func sanitise(title: String) -> String:
	var out := ""
	for index in title.length():
		var character := title[index]
		if _is_allowed(character):
			out += character
		else:
			out += "-"
	out = out.strip_edges()
	if out.is_empty():
		out = DEFAULT_NAME
	return out.substr(0, MAX_NAME)


static func _is_allowed(character: String) -> bool:
	if ALLOWED.contains(character):
		return true
	return (character >= "a" and character <= "z") \
		or (character >= "A" and character <= "Z") \
		or (character >= "0" and character <= "9")


## The path a drawing with this title gets, inside the drawings folder.
static func path_for(title: String) -> String:
	return DIR.path_join(sanitise(title) + EXTENSION)


## What to call a file when it is offered in a menu: the name without the folder or the
## extension, which is all a person needs to recognise their own drawing.
static func display_name(path: String) -> String:
	if path.is_empty():
		return ""
	return path.get_file().get_basename()


# --- writing and reading --------------------------------------------------------------


## Write a drawing to a path.
##
## Through a temporary file and a rename, because the alternative is a save that fails halfway
## and leaves the file shorter than the drawing it was supposed to hold - which is the one
## failure a file menu must not have. Returns `{"ok", "reason", "path"}`.
static func write(document: DraftDocument, path: String) -> Dictionary:
	if document == null:
		return _refused("there is no drawing to save")
	if path.is_empty():
		return _refused("this drawing has no file name yet")
	if not ensure_dir():
		return _refused("cannot open the drawings folder")
	var temp := path + TEMP_SUFFIX
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return _refused("cannot write %s" % temp.get_file())
	file.store_string(JSON.stringify(document.to_dict(), "  "))
	file.close()
	var error := DirAccess.rename_absolute(temp, path)
	if error != OK:
		DirAccess.remove_absolute(temp)
		return _refused("cannot put %s in place: %s" % [path.get_file(), error_string(error)])
	return {"ok": true, "reason": "", "path": path}


## Read a drawing.
##
## Refuses a missing file, a file that is not JSON, JSON that is not an object, and an object
## with no version - each with a sentence saying which, because "it did not open" is not
## something a person can act on. A file written by a *newer* version is read for the parts
## this one understands, which is what the document's own `restore()` is written to do.
static func read(path: String) -> Dictionary:
	if path.is_empty():
		return _refused("no drawing was named")
	if not FileAccess.file_exists(path):
		return _refused("there is no drawing called %s" % display_name(path))
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _refused("cannot read %s" % display_name(path))
	var text := file.get_as_text()
	file.close()
	# Parsed with a reader rather than with `JSON.parse_string`, which logs an engine error to the
	# console when it fails: the person is already being told in a sentence what is wrong, and an
	# error line nobody can act on is noise in a console that should carry only real faults. The
	# reader also says which line it gave up on, which is worth putting in the sentence.
	var reader := JSON.new()
	if reader.parse(text) != OK:
		return _refused("%s is not readable as a drawing: %s (line %d)" % [
			display_name(path), reader.get_error_message(), reader.get_error_line()
		])
	if not (reader.data is Dictionary):
		return _refused("%s is not a drawing" % display_name(path))
	var data: Dictionary = reader.data
	if not data.has("version"):
		return _refused("%s is not a drawing" % display_name(path))
	return {"ok": true, "reason": "", "data": data}


static func _refused(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "path": "", "data": {}}


## Every drawing in the folder. What an Open dialog is pointed at, and what a "show me what I
## have" command would list.
static func list_drawings() -> Array[String]:
	var out: Array[String] = []
	# Which also takes a recent list left in here by an older build out of the folder, so that it
	# is not offered as a drawing and cannot be saved over.
	if not ensure_dir():
		return out
	var directory := DirAccess.open(DIR)
	if directory == null:
		return out
	for name in directory.get_files():
		# A temp file cannot be mistaken for a drawing: `<name>.json.writing` does not end in the
		# extension.
		if name.ends_with(EXTENSION):
			out.append(DIR.path_join(name))
	return out


# --- the named revisions of a drawing -------------------------------------------------


## Where a drawing's history is kept, or "" when the drawing has no file name yet - a drawing that has
## never been saved has no identity for a history to belong to.
static func revisions_path(drawing_path: String) -> String:
	if drawing_path.is_empty():
		return ""
	return REVISIONS_DIR.path_join(sanitise(display_name(drawing_path)) + EXTENSION)


## Write a drawing's history, through a temporary file and a rename like the drawing itself: a history
## that fails halfway would lose the revisions it was supposed to keep, which is the one thing it must
## not do.
##
## The parameter is not called `log`: that is a built-in function, and one of the names this project
## treats as taken.
static func write_revisions(history: DraftRevisionLog, drawing_path: String) -> Dictionary:
	var path: String = revisions_path(drawing_path)
	if path.is_empty():
		return _refused("this drawing has no file name yet, so it has no history to keep")
	if history == null:
		return _refused("there are no revisions to write")
	if DirAccess.open(REVISIONS_DIR) == null and DirAccess.make_dir_recursive_absolute(REVISIONS_DIR) != OK:
		return _refused("cannot open the revisions folder")
	var temp := path + TEMP_SUFFIX
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return _refused("cannot write %s" % temp.get_file())
	file.store_string(JSON.stringify(history.to_dict(), "  "))
	file.close()
	var error := DirAccess.rename_absolute(temp, path)
	if error != OK:
		DirAccess.remove_absolute(temp)
		return _refused("cannot put %s in place: %s" % [path.get_file(), error_string(error)])
	return {"ok": true, "reason": "", "path": path}


## Read a drawing's history. No file is not a failure: it is a drawing nothing has been recorded
## against yet, which is what every drawing is to begin with.
static func read_revisions(drawing_path: String) -> DraftRevisionLog:
	var path: String = revisions_path(drawing_path)
	if path.is_empty() or not FileAccess.file_exists(path):
		return DraftRevisionLog.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return DraftRevisionLog.new()
	var text := file.get_as_text()
	file.close()
	var reader := JSON.new()
	if reader.parse(text) != OK:
		return DraftRevisionLog.new()
	return DraftRevisionLog.from_dict(reader.data)


# --- what was opened recently ---------------------------------------------------------


## The drawings that were opened last time, newest first.
##
## A remembered drawing that is no longer on disk is dropped rather than offered: a menu entry
## for a file that is not there is a command that cannot work, and the person would rather not
## see it than be told about it when they choose it.
static func read_recent(from_path: String = RECENT_FILE) -> Array[String]:
	var out: Array[String] = []
	var file := FileAccess.open(from_path, FileAccess.READ)
	if file == null:
		return out
	# A reader rather than `JSON.parse_string`, so that a half-written list is a shorter list
	# rather than an engine error in the console.
	var reader := JSON.new()
	if reader.parse(file.get_as_text()) != OK:
		file.close()
		return out
	file.close()
	if not (reader.data is Array):
		return out
	for value in reader.data:
		# `str()`, not `String()`: on a value that came out of a file, `String(value)` fails at
		# run time with "Invalid call 'String' constructor" and takes the whole function with it -
		# which showed up as a recent list that was always empty, however many drawings were in
		# it. `str()` is the conversion that accepts anything, and the only thing that matters
		# here is that a string stays a string.
		var path := str(value)
		if not path.is_empty() and FileAccess.file_exists(path) and not out.has(path):
			out.append(path)
	return out


static func write_recent(paths: Array[String], to_path: String = RECENT_FILE) -> bool:
	if not ensure_dir():
		return false
	var file := FileAccess.open(to_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(paths, "  "))
	file.close()
	return true


## Put a drawing at the head of the list, once. Write the drawing first: this list only keeps
## files that are there.
static func remember(path: String, in_file: String = RECENT_FILE) -> Array[String]:
	var paths := read_recent(in_file)
	paths.erase(path)
	paths.push_front(path)
	while paths.size() > RECENT_MAX:
		paths.pop_back()
	write_recent(paths, in_file)
	return paths


static func forget(path: String, in_file: String = RECENT_FILE) -> Array[String]:
	var paths := read_recent(in_file)
	paths.erase(path)
	write_recent(paths, in_file)
	return paths