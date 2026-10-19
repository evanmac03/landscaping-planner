class_name DraftUndoStack
extends RefCounted
## Undo and redo for a drafting document, by whole-document snapshot.
##
## Inverse commands are the textbook answer, but every tool then needs a correct
## inverse, and a subtly wrong one corrupts the drawing in a way the user cannot
## see or repair. A plan is small: a few thousand vertices is tens of kilobytes,
## so a snapshot per committed edit costs almost nothing and removes the whole
## class of failure (docs/drafting-subsystem-spec.md §5.5).
##
## This class holds no reference to the document, so the document may depend on
## it without a cycle. It deals only in opaque snapshots.

const DEFAULT_LIMIT := 200

var limit: int = DEFAULT_LIMIT

var _past: Array[Dictionary] = []
var _future: Array[Dictionary] = []


func can_undo() -> bool:
	return not _past.is_empty()


func can_redo() -> bool:
	return not _future.is_empty()


func depth() -> int:
	return _past.size()


func redo_depth() -> int:
	return _future.size()


## Record the state as it was *before* a gesture. Call once per gesture, never
## per motion event, or the stack fills with intermediate states.
func push(snapshot: Dictionary) -> void:
	_past.append(snapshot)
	while _past.size() > limit:
		_past.pop_front()
	_future.clear()


## Returns the snapshot to restore, or an empty dictionary when there is nothing
## to undo. `current` is recorded so the operation can be redone.
func undo(current: Dictionary) -> Dictionary:
	if _past.is_empty():
		return {}
	_future.append(current)
	return _past.pop_back()


## Returns the snapshot to restore, or an empty dictionary.
func redo(current: Dictionary) -> Dictionary:
	if _future.is_empty():
		return {}
	_past.append(current)
	return _future.pop_back()


func clear() -> void:
	_past.clear()
	_future.clear()