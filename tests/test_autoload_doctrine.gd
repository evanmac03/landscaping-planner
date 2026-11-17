extends Node
## The autoload doctrine, held down where it can be: **no autoload of this project's own.**
##
## AGENTS.md states that there is exactly one autoload, and that whatever a script needs is handed to it by
## the scene as an `@export var`, so a global is out of the question. Nothing pinned that until this file.
##
## **The count itself is not the rule, and cannot be**: the addons register their own, they are installed
## per machine rather than committed, and on the machine this was written the count was three. So what is
## asserted here is the half that travels - the project's own scripts are never autoloads, and an autoload
## of the project's own would have to put itself out outside an editor, as AGENTS.md requires of the one it
## does allow. A fixed number belongs to a machine, not to a test: `tools/debug_toolbox.gd` is where the
## count is read, and reading it is what that tool is for.

const Toolbox := preload("res://tools/debug_toolbox.gd")


## The project's own code is reached by the scene that needs it, never by a name that is always there.
func test_no_autoload_is_one_of_this_projects_own_scripts() -> void:
	var ours: Array[String] = []
	var autoloads: Dictionary = _autoloads()
	for autoload_name: String in autoloads:
		var path := String(autoloads[autoload_name])
		if _is_the_projects_own(path):
			ours.append("%s -> %s" % [autoload_name, path])
	assert(
		ours.is_empty(),
		"an autoload is this project's own code, where the scene hands things in: " + ", ".join(ours),
	)


## The other half: an autoload has to destroy itself outside an editor, so a shipped build neither listens
## nor logs. It is asserted of the project's own autoloads, of which there are none today - and this says
## so rather than passing quietly, because a rule with no case in front of it is worth naming as such. The
## addons that do register one are not this project's code to judge, and a fresh clone has none of them.
func test_an_autoload_of_the_projects_own_would_have_to_be_inert_outside_an_editor() -> void:
	var judged: Array[String] = []
	var autoloads: Dictionary = _autoloads()
	for autoload_name: String in autoloads:
		var path := String(autoloads[autoload_name])
		if not _is_the_projects_own(path):
			continue
		var source := FileAccess.get_file_as_string(path)
		var inert := (
			source.contains("Engine.is_editor_hint()") or source.contains("OS.has_feature(\"editor\")")
		)
		assert(
			inert,
			"%s is an autoload of this project's own and never puts itself out: %s" % [autoload_name, path],
		)
		judged.append(autoload_name)
	if judged.is_empty():
		print(
			"AUTOLOADS  none of this project's own, so nothing here to judge inert - "
			+ "the ones that exist come from addons"
		)


## Every autoload and the path it names, read where Godot keeps them (`autoload/<Name>`) through the one
## reader for that shape, so a mistake in that reading shows up here as well as in its own test.
func _autoloads() -> Dictionary:
	var autoloads: Dictionary = {}
	for autoload_name: String in Toolbox.autoload_names():
		var path := str(
			ProjectSettings.get_setting(Toolbox.AUTOLOAD_PREFIX + autoload_name, "")
		).trim_prefix("*")
		if path.begins_with("uid://"):
			path = ResourceUID.get_id_path(ResourceUID.text_to_id(path))
		autoloads[autoload_name] = path
	return autoloads


## Whether a path is this project's own code: `scripts/` is the program, and `scenes/` its scenes.
func _is_the_projects_own(path: String) -> bool:
	return path.begins_with("res://scripts/") or path.begins_with("res://scenes/")
