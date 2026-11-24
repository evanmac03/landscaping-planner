extends Node

## A scene a person runs to look at one thing is a development tool, and development tools live in
## `res://tools/` and nowhere else.
##
## Why it matters here more than it would elsewhere: the export presets exclude `tools/*` and `tests/*` from
## every build, and they do **not** exclude `scenes/*`. So a demonstration scene left in `scenes/` is not a
## tidiness problem - it is a scene written to be run once by the person who made it, shipped inside the APK on
## the user's phone. Forty-four of them were, until this test had something to say about it.
##
## The rule is one sentence: a file named `<something>_demo.tscn` belongs under `res://tools/`. `addons/` is
## left alone because it is third-party and none of it is this project's to arrange.

## The one tree the walk does not enter. Third-party addons are not ours to file.
const THIRD_PARTY_ROOT := "res://addons"

## Where a development scene belongs.
const TOOLS_ROOT := "res://tools"


## Every development scene in the project, wherever it lives, so a failure can name the ones that are wrong.
func _development_scenes() -> Array[String]:
	var found: Array[String] = []
	_walk("res://", found)
	found.sort()
	return found


## Collects `<...>_demo.tscn` under `folder` and everything below it. Directories whose name starts with a dot
## are skipped, because `.godot` is the editor's own cache and not part of the program.
func _walk(folder: String, found: Array[String]) -> void:
	var here: DirAccess = DirAccess.open(folder)
	if here == null:
		return
	for file_name in here.get_files():
		if file_name.ends_with("_demo.tscn"):
			found.append(folder.path_join(file_name))
	for directory in here.get_directories():
		if directory.begins_with("."):
			continue
		var path: String = folder.path_join(directory)
		if path == THIRD_PARTY_ROOT:
			continue
		_walk(path, found)


## The walk must be able to see the scenes at all. Without this, a walker that looked in the wrong place, or
## stopped descending, would pass the rule below by finding nothing - and a rule that cannot fail is not a rule.
func test_the_walk_finds_the_development_scenes_where_they_are() -> void:
	var found: Array[String] = _development_scenes()
	assert(
		found.size() >= 40,
		"the walk found %d development scene(s), which is too few - it is not looking where they are" % found.size(),
	)
	for scene in found:
		assert(
			scene.begins_with(TOOLS_ROOT + "/"),
			"the walk found %s outside %s, so it is not gathering what the rule is about" % [scene, TOOLS_ROOT],
		)


## The rule. A development scene anywhere but `res://tools/` is one that ships.
func test_no_development_scene_lives_outside_the_tools_folder() -> void:
	var stray: Array[String] = []
	for scene in _development_scenes():
		if not scene.begins_with(TOOLS_ROOT + "/"):
			stray.append(scene)
	assert(
		stray.is_empty(),
		(
			"these development scenes ship in the APK because the export excludes tools/* and not where they are: %s"
			% ", ".join(stray)
		),
	)
