class_name StatusHistory
extends RefCounted
## What the drawing has said, in the order it said it.
##
## The status line tells you what just happened and then it is gone: do three things and the third
## answer is the only one still readable. This is the same answers, kept, so "what did it say when I did
## that" is a question with an answer.
##
## ## It is told, not polled
##
## The drawing hands each message over as it says it, so there is nothing to compare and nothing to
## miss: erasing a shape twice says the same sentence twice, and both are kept. An empty message is not
## an answer at all - the line is cleared when a tool is put away, and keeping that would fill the
## history with lines saying nothing.
##
## Nothing here reads a clock, a document or a scene: it is a list of sentences with a cap on it, which
## is why it can be tested on its own.

## How many answers are kept. Long enough to cover a while at the drawing, short enough that the page
## listing them is a page rather than a file.
const CAP := 60

## Newest first, because a history is read from the top.
var _lines: Array[String] = []


## Keep a message the drawing has just said. Returns whether it was kept.
func note(words: String) -> bool:
	if words.strip_edges() == "":
		return false
	_lines.push_front(words)
	if _lines.size() > CAP:
		_lines.resize(CAP)
	return true


## Forget everything: what a drawing that has been replaced, or written over, has said is not this
## drawing's.
func clear() -> void:
	_lines.clear()


func count() -> int:
	return _lines.size()


func is_empty() -> bool:
	return _lines.is_empty()


## The last thing said, or nothing when nothing has been said.
func latest() -> String:
	return _lines[0] if not _lines.is_empty() else ""


## The oldest thing still kept.
func oldest() -> String:
	return _lines[_lines.size() - 1] if not _lines.is_empty() else ""


## Every answer, newest first. A copy: the history is the only thing that decides what is in it.
func lines() -> Array[String]:
	var out: Array[String] = []
	out.assign(_lines)
	return out