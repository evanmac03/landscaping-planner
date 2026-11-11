extends RefCounted
## The suite's named signal assertion: it watches the signals on an object for one test and says what
## it heard.
##
## A test that wants to know whether a page announced something writes the same four moves out every
## time - make an array, connect a lambda that appends to it, poke the page, compare the array's size.
## It is easy to get the lambda's parameters wrong, and when they are wrong Godot refuses to call it at
## all rather than saying so. This is that shape, written once.
##
## Godot will not call a handler whose parameters do not match a signal's arguments, so a single
## handler cannot watch signals of different length: each watched signal gets its own closure. The
## closure holds only that signal's own list of firings and nothing else, so this object can be freed
## while the source lives on and no connection reaches back to it. A signal carrying more than eight
## arguments is not something this project has.

var _source: Object
var _heard: Dictionary = {}   # StringName -> the array of argument lists heard, one per firing
var _handlers: Array = []     # [StringName, Callable] pairs, so that `stop` can let go


## Begin watching `source`. `signals` names the ones to listen for; a name the object does not carry is
## refused rather than watched, because a watch that can never fire is a test that cannot fail.
func _init(source: Object, signals: Array = []) -> void:
	_source = source
	for name: String in signals:
		_listen(StringName(name))


## How many times `name` has been heard.
func count(name: StringName) -> int:
	if not _heard.has(name):
		return 0
	return (_heard[name] as Array).size()


## Whether `name` has been heard at all.
func heard(name: StringName) -> bool:
	return count(name) > 0


## The arguments carried by the most recent firing of `name`, with the unused tail trimmed off - so a
## signal that carried nothing gives an empty list, and one that carried a word gives just the word.
func arguments_of(name: StringName) -> Array:
	if not _heard.has(name):
		return []
	var firings: Array = _heard[name]
	if firings.is_empty():
		return []
	var last: Array = (firings[firings.size() - 1] as Array).duplicate()
	while not last.is_empty() and last[last.size() - 1] == null:
		last.remove_at(last.size() - 1)
	return last


## Hold the test to `name` having been heard exactly once.
func expect_once(name: StringName, what: String = "") -> void:
	# The words are built only when there is something to say, for the reason `CloseEnough.almost`
	# states: an `assert` message is worked out whether or not it holds.
	if count(name) != 1:
		assert(false, _missed_times(name, count(name), "exactly once", what))


## Hold the test to `name` never having been heard.
func expect_never(name: StringName, what: String = "") -> void:
	if count(name) != 0:
		assert(false, _never(name, count(name), what))


## Hold the test to `name` having been heard `times` times.
func expect_count(name: StringName, times: int, what: String = "") -> void:
	if count(name) != times:
		assert(false, _missed_times(name, count(name), "exactly %d time(s)" % times, what))


## Let go of the source, so a watch kept past the test it was made for leaves no connection behind.
func stop() -> void:
	for pair: Array in _handlers:
		var name: StringName = pair[0]
		var handler: Callable = pair[1]
		if _source != null and _source.has_signal(name) and _source.is_connected(name, handler):
			_source.disconnect(name, handler)
	_handlers.clear()


func _listen(name: StringName) -> void:
	if _source == null or not _source.has_signal(name):
		var owner_name := "nothing" if _source == null else _source.get_class()
		assert(false, "%s carries no signal '%s' to watch" % [owner_name, name])
		return
	var firings: Array = []
	_heard[name] = firings
	# One closure per signal, holding its own list and nothing else, so it neither keeps this object
	# alive nor reaches back into it.
	var handler := func(a = null, b = null, c = null, d = null, e = null, f = null, g = null, h = null) -> void:
		firings.append([a, b, c, d, e, f, g, h])
	_source.connect(name, handler)
	_handlers.append([name, handler])


func _missed_times(name: StringName, heard: int, should: String, what: String) -> String:
	var sentence := "'%s' was heard %d time(s); it should have been heard %s" % [name, heard, should]
	if what.is_empty():
		return sentence
	return "%s: %s" % [what, sentence]


func _never(name: StringName, heard: int, what: String) -> String:
	var sentence := "'%s' was heard %d time(s) when it should not have been heard at all" % [name, heard]
	if what.is_empty():
		return sentence
	return "%s: %s" % [what, sentence]