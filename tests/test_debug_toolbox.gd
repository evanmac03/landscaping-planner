extends Node
## The debug toolbox's two rules, held down.
##
## The toolbox is a dev tool, so there is little here about what it prints. What is held down is the two
## things that would let it lie: the autoloads must be read where Godot keeps them - asking for a setting
## that does not exist reported every project as perfect, and said nothing while doing it - and every
## instrument it names must be a file that is really there, because an index with a dead line in it sends
## a person somewhere that is not there.

const Toolbox := preload("res://tools/debug_toolbox.gd")


## Godot writes one setting per autoload, named `autoload/<Name>`. There is no single `autoload` setting,
## so a reader that asks for one iterates an empty dictionary and reports a project with no autoloads, a
## project with four broken ones and a project with none at all in exactly the same words. This asserts
## the reading against the settings themselves, which is what that reader could never do.
func test_the_autoloads_are_read_where_godot_keeps_them() -> void:
	assert(
		not ProjectSettings.has_setting("autoload"),
		"there is no single `autoload` setting to read, which is the whole trap",
	)
	var toolbox_names: Array[String] = Toolbox.autoload_names()
	var setting_names: Array[String] = _autoloads_in_the_settings()
	assert(
		toolbox_names == setting_names,
		(
			"the toolbox reports every autoload Godot has and no other: %s against %s"
			% [toolbox_names, setting_names]
		),
	)
	for autoload_name: String in toolbox_names:
		assert(
			ProjectSettings.has_setting(Toolbox.AUTOLOAD_PREFIX + autoload_name),
			autoload_name + " is reported by the toolbox and is not a setting Godot has",
		)


## An index with a dead line in it is worse than no index. Every instrument named is a file that is really
## there, is a dev tool rather than something shipped, and comes with the question it answers.
func test_every_instrument_it_names_is_really_there() -> void:
	assert(not Toolbox.INSTRUMENTS.is_empty(), "the toolbox names the instruments this project has")
	var seen: Array[String] = []
	for row: Dictionary in Toolbox.INSTRUMENTS:
		var scene := String(row["scene"])
		assert(ResourceLoader.exists(scene), scene + " is named by the toolbox and is not there")
		assert(scene.begins_with("res://tools/"), scene + " is not a dev tool under res://tools/")
		assert(not String(row["question"]).is_empty(), scene + " is named with no question")
		assert(not seen.has(scene), scene + " is named twice")
		seen.append(scene)


## Every autoload, read from the settings by hand, for the reading above to be compared against.
func _autoloads_in_the_settings() -> Array[String]:
	var names: Array[String] = []
	for property: Dictionary in ProjectSettings.get_property_list():
		var setting_name := String(property["name"])
		if setting_name.begins_with("autoload/"):
			names.append(setting_name.substr("autoload/".length()))
	names.sort()
	return names
