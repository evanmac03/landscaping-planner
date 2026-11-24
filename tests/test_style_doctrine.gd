extends Node
## The workspace's own style, held to the one rule a machine can check: every GDScript file ends with a newline.
##
## It is a rule at all because the formatter makes it one - the project was run through it at
## `--max-line-length 120` on 2026-11-12 and kept - and because **the tools that write files here do not add the
## byte**: `create_file` and `edit_file` both leave a file ending on a real character, measured twice. That is
## how 18 of the most recent files came to be the only ones a formatter run would touch, and why this rule is
## worth holding rather than remembering.
##
## It walks where the code lives and nowhere else: `addons/` is third-party, and a vendored addon's whitespace
## is not this project's business. Nothing here needs a display, a scene or a device - it is a walk and a byte,
## which is the shape `test_screen_doctrine.gd` already keeps for the other rule no reading may spell for itself.

const WALKED := ["res://scripts", "res://tests", "res://tools"]

## A walk that finds nothing is a walk that has stopped working, and a rule held by a broken walk is worse than
## no rule at all - so the walk has to say how much it saw before its answer is believed.
const PLENTY := 400

## Where the failing half of this writes, and removes again: the project keeps no scratch files.
const SCRATCH := "user://test_style_doctrine.txt"
const NEWLINE := 10


func test_every_gdscript_file_in_the_workspace_ends_with_a_newline() -> void:
	var walked: PackedStringArray = _all_the_scripts()
	assert(walked.size() >= PLENTY, "the walk found only %d file(s), so it is not a walk" % walked.size())
	var without := PackedStringArray()
	for path: String in walked:
		if not _ends_with_a_newline(path):
			without.append(path)
	assert(
		without.is_empty(),
		(
			"these %d file(s) end on a real character, which no formatter run would leave: %s"
			% [without.size(), ", ".join(without)]
		),
	)


## The byte test can tell both ways, on a file written for the purpose: a rule that only ever answers "fine" is
## a rule nobody has seen work, and the 18 files this was written for were the ones nobody had looked at.
func test_the_byte_test_can_say_no() -> void:
	_write(SCRATCH, "extends Node")
	assert(not _ends_with_a_newline(SCRATCH), "a file written without the byte is seen to be without it")
	_write(SCRATCH, "extends Node\n")
	assert(_ends_with_a_newline(SCRATCH), "and one written with it is seen to have it")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


## Every `.gd` under the three folders, at any depth.
func _all_the_scripts() -> PackedStringArray:
	var found := PackedStringArray()
	for folder: String in WALKED:
		_gather(folder, found)
	return found


func _gather(folder: String, into: PackedStringArray) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if dir.current_is_dir():
			if not name.begins_with("."):
				_gather("%s/%s" % [folder, name], into)
		elif name.ends_with(".gd"):
			into.append("%s/%s" % [folder, name])
		name = dir.get_next()
	dir.list_dir_end()


## Whether a file's last byte is a newline. The byte is read rather than the text, so that nothing about how a
## file is decoded can change the answer.
func _ends_with_a_newline(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var long_enough: bool = file.get_length() > 0
	if long_enough:
		file.seek_end()
		file.seek(file.get_position() - 1)
		long_enough = file.get_8() == NEWLINE
	file.close()
	return long_enough


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
