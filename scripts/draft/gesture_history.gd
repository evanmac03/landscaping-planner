class_name DraftGestureHistory
extends RefCounted
## The gestures a drafting document has been through: what undo and redo walk, and what the drawing's
## history is counted in.
##
## ## Why snapshots
##
## Inverse commands are the textbook answer, but every tool then needs a correct inverse, and a subtly
## wrong one corrupts the drawing in a way the user cannot see or repair. A plan is small: a few thousand
## vertices is tens of kilobytes, so a snapshot per committed edit costs almost nothing and removes the
## whole class of failure (docs/drafting-subsystem-spec.md §5.5).
##
## ## Why a gesture has a name and a number
##
## A stack of anonymous snapshots can only answer "undo": a person looking at the button cannot tell
## whether it will put back the line they just trimmed or a survey they overlaid two hours ago. So every
## gesture carries the **label** of the act that made it - `DraftController` writes them - and the undo
## and redo buttons say what they would do.
##
## It also carries a **serial**: which gesture it was in this drawing's life, counted from the first. That
## number is what joins this history to `DraftRevisionLog`: a revision records the serial it was taken at,
## so the history can say how many gestures have happened since the drawing was sent to a client. Neither
## a stack nor a list of timestamps can answer that on its own - one forgets, the other never knew.
##
## **A serial is never reset by trimming.** The oldest gestures fall off the end of the stack; a count
## that went backwards would tell a revision that gestures had *un*happened since it was taken. Only a
## new document starts again at zero.
##
## This class holds no reference to the document, so the document may depend on it without a cycle. It
## deals only in opaque snapshots.

const DEFAULT_LIMIT := 200

## What an act nobody labelled is called. A tool that forgot to say what it was is still a gesture, and a
## blank button is worse than a vague one.
const UNNAMED := "an edit"

var limit: int = DEFAULT_LIMIT

## The gestures that can be undone, oldest first, and those that can be redone, newest first. An entry is
## `{serial, label, state}` - the state being the drawing *before* the gesture.
var _past: Array[Dictionary] = []
var _future: Array[Dictionary] = []
## How many gestures this history has seen, ever. Monotonic - see the header.
var _serial: int = 0


func can_undo() -> bool:
	return not _past.is_empty()


func can_redo() -> bool:
	return not _future.is_empty()


func depth() -> int:
	return _past.size()


func redo_depth() -> int:
	return _future.size()


## How many gestures this drawing has been through. A revision recorded now is taken at this number, so
## "how many gestures since" is this minus the number the revision kept.
func serial() -> int:
	return _serial


## Record the state as it was *before* a gesture, and what that gesture was. Call once per gesture, never
## per motion event, or the history fills with intermediate states.
##
## Returns the serial this gesture was given, so a caller that wants to remember where in the drawing's
## life something happened keeps the number rather than a count of its own.
func push(snapshot: Dictionary, label: String = "") -> int:
	_serial += 1
	_past.append(_gesture(_serial, snapshot, label))
	while _past.size() > limit:
		_past.pop_front()
	_future.clear()
	return _serial


## Returns the snapshot to restore, or an empty dictionary when there is nothing to undo. `current` is
## recorded so the operation can be redone - under the same label and serial, because redoing a gesture
## is that gesture happening again.
func undo(current: Dictionary) -> Dictionary:
	if _past.is_empty():
		return {}
	var entry: Dictionary = _past.pop_back()
	_future.append(_gesture(int(entry["serial"]), current, String(entry["label"])))
	return entry["state"]


## Returns the snapshot to restore, or an empty dictionary.
func redo(current: Dictionary) -> Dictionary:
	if _future.is_empty():
		return {}
	var entry: Dictionary = _future.pop_back()
	_past.append(_gesture(int(entry["serial"]), current, String(entry["label"])))
	return entry["state"]


## One gesture, in the one shape this class stores it. Everything that writes an entry comes through
## here, so a label can never be missing from one of them and present in another.
static func _gesture(number: int, snapshot: Dictionary, label: String) -> Dictionary:
	var words := label.strip_edges()
	return {
		"serial": number,
		"label": words if not words.is_empty() else UNNAMED,
		"state": snapshot,
	}


## What undo would put back, in words - "drawing a line" for a gesture that drew one. Empty when there is
## nothing to undo, which is what a button that cannot do anything should say.
func undo_label() -> String:
	if _past.is_empty():
		return ""
	return String((_past.back() as Dictionary)["label"])


func redo_label() -> String:
	if _future.is_empty():
		return ""
	return String((_future.back() as Dictionary)["label"])


## The gestures that can be undone, oldest first, by name.
func labels() -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in _past:
		out.append(String(entry["label"]))
	return out


## Forget every gesture. The *serial* is not reset: what happened to this drawing does not unhappen
## because it was forgotten, and a revision taken 40 gestures in stays 40 gestures in.
func clear() -> void:
	_past.clear()
	_future.clear()