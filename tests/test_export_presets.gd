extends Node
## The presets this program is built from state the same filters, and this holds them to it.
##
## **Why it is worth a guard.** `export_presets.cfg` states what each build contains separately: the include
## filter and the exclude filter are written out once per preset, in a file no script reads, so one decision is
## written three times with nothing comparing the copies. That is this project's own definition of a defect - a
## second answer that can disagree - and it has already cost once: an exclusion the program's own preset carries
## was missing from the preset being built, and the dev scenes went out inside a build. The three presets are
## three platforms of one program, and what a person gets on Windows, on Linux and on a phone is the same
## drawing tool, so a filter that differs between them is a difference nobody chose.
##
## **What is compared, and how.** The two filters as *sets* rather than as written lines: the order a path is
## written in changes nothing about what is shipped, and the three do not agree on order today - the Linux
## preset writes `addons/godot_ai/*` before `project_godot_edit.godot` and the other two write it after - so a
## test comparing the lines would have failed on the day it was written, over nothing.
##
## **Why the phone's tool is named here too.** `phone_touch_pass --build` exports through a preset *by name*,
## and the name it uses is read from that tool rather than written here a second time. A preset renamed in the
## editor would otherwise leave `--build` exporting nothing, and saying so at the wrong moment: on a phone pass,
## three minutes in, instead of here.

const ToolScript := preload("res://tools/phone_touch_pass.gd")

## The file the editor writes and every build is made from.
const PRESETS := "res://export_presets.cfg"

## The two keys that decide what a build contains, and so the two that must agree.
const FILTERS: Array[String] = ["include_filter", "exclude_filter"]

## How each filter reads in a sentence a person can act on: the form the preset takes, and the bare one a
## "does not" needs - `the Linux preset keeps out` against `the Windows preset does not keep out`. "Ships" and
## "keeps out" are not the same verb, and one form used for both would be a half-truth of the kind this project
## refuses.
const FILTER_VERBS: Dictionary = { "include_filter": ["ships", "ship"], "exclude_filter": ["keeps out", "keep out"] }

# --- the rule --------------------------------------------------------------------------------------------------


## Every preset in the file, as `{section, name, filters}`: where it lives, the words a person gave it, and each
## filter as the *set* of paths written in it.
##
## Read with Godot's own `ConfigFile`, which is the reader of the format the editor writes - a hand-rolled
## parser for it would be a second reader of one file, which is the very thing this test is about. What `load`
## returns is deliberately not trusted: a section that is absent and one that is present but empty answer the
## same way there, and what is wanted here is what the file holds, which is read key by key.
static func presets_in(path: String) -> Array[Dictionary]:
	var config := ConfigFile.new()
	config.load(path)
	var found: Array[Dictionary] = []
	for section: String in config.get_sections():
		if not section.begins_with("preset."):
			continue
		# `[preset.2.options]` is the same preset's own settings and not a build: only the section whose number
		# is the whole of what follows the dot names one.
		if not section.trim_prefix("preset.").is_valid_int():
			continue
		var held: Dictionary = { }
		for key: String in FILTERS:
			held[key] = _paths_in(String(config.get_value(section, key, "")))
		found.append(
			{ "section": section, "name": String(config.get_value(section, "name", section)), "filters": held }
		)
	return found


## The paths written in one filter, as a set - a `Dictionary` used for its keys, so that a path written twice
## counts once and the order it was written in is not part of the answer.
static func _paths_in(filter: String) -> Dictionary:
	var paths: Dictionary = { }
	for one: String in filter.split(",", false):
		var trimmed: String = one.strip_edges()
		if not trimmed.is_empty():
			paths[trimmed] = true
	return paths


## One filter's paths in a stated order, which is what two of them are compared by. Sorted rather than compared
## as dictionaries, because a comparison that depends on how a value happens to be stored is not a comparison of
## what it says.
static func _listed(paths: Dictionary) -> PackedStringArray:
	var names := PackedStringArray()
	for path: String in paths.keys():
		names.append(path)
	names.sort()
	return names


## What the presets disagree about, in the words a person reads: empty when they all state the same filters.
##
## Each answer names the preset that differs, the filter it is about and the paths only it has - and **which of
## the two sides is the mistaken one is not something this can know.** The rule is that three builds of one
## program agree; the person who wrote the difference is the one who knows which way it should be settled, so
## the message hands them both sides and no verdict.
static func disagreements(presets: Array[Dictionary]) -> Array[String]:
	var said: Array[String] = []
	if presets.is_empty():
		return said
	var first: Dictionary = presets[0]
	var first_name: String = String(first.get("name", "the first preset"))
	for key: String in FILTERS:
		var words: Array = FILTER_VERBS.get(key, ["states", "state"])
		var verb: String = String(words[0])
		var bare: String = String(words[1])
		var wanted: PackedStringArray = _listed((first.get("filters", { }) as Dictionary).get(key, { }))
		for preset: Dictionary in presets:
			var mine: PackedStringArray = _listed((preset.get("filters", { }) as Dictionary).get(key, { }))
			if mine == wanted:
				continue
			var extra := PackedStringArray()
			for one: String in mine:
				if not wanted.has(one):
					extra.append(one)
			var missing := PackedStringArray()
			for one: String in wanted:
				if not mine.has(one):
					missing.append(one)
			var name: String = String(preset.get("name", "a preset"))
			if not extra.is_empty():
				said.append(
					"%s: the %s preset %s %s, and the %s preset does not"
					% [key, name, verb, " and ".join(extra), first_name]
				)
			if not missing.is_empty():
				said.append(
					"%s: the %s preset does not %s %s, and the %s preset does"
					% [key, name, bare, " and ".join(missing), first_name]
				)
	return said

# --- the guard -------------------------------------------------------------------------------------------------


## The builds this program is made from state the same filters, and there are at least the three there are.
##
## The count is asserted as well as the agreement, because a walk that found one preset would agree with itself
## and pass: a guard that reads nothing passes everything.
func test_the_presets_that_build_this_program_state_the_same_filters() -> void:
	var presets: Array[Dictionary] = presets_in(PRESETS)
	assert(presets.size() >= 3, "the three builds are in the file: %d preset(s) found" % presets.size())
	var said: Array[String] = disagreements(presets)
	assert(said.is_empty(), "and they state the same filters, path for path:\n  " + "\n  ".join(said))


## The preset `phone_touch_pass --build` exports through is the name that tool states. Read from the tool rather
## than written here a second time, so the two cannot drift apart: a preset renamed in the editor would leave
## `--build` exporting nothing, and saying so on a phone pass rather than here.
func test_the_preset_the_phone_tool_exports_through_is_one_of_them() -> void:
	var named: String = String(ToolScript.PRESET_NAME)
	var names := PackedStringArray()
	for preset: Dictionary in presets_in(PRESETS):
		names.append(String(preset.get("name", "")))
	assert(names.has(named), "`%s` is one of the presets in %s: %s" % [named, PRESETS, " and ".join(names)])


## A guard that cannot fail is not a guard, so the rule is run against differences written here by hand - the
## two directions a filter can differ in, and the one difference that is not one.
func test_the_guard_names_the_preset_that_states_something_different() -> void:
	var fewer := _a_preset("preset.2", "Linux", { "tests/*": true, "tools/*": true })
	var more := _a_preset("preset.0", "Windows Desktop", { "tests/*": true, "tools/*": true, "scenes/*": true })
	var both: Array[Dictionary] = [more, fewer]
	var said: Array[String] = disagreements(both)
	assert(said.size() == 1, "one preset stating less is one disagreement: %s" % str(said))
	assert(
		said[0].contains("Linux") and said[0].contains("scenes/*"),
		"naming the preset that differs and the path only it has: %s" % said[0],
	)
	assert(said[0].contains("exclude_filter"), "and the filter it is about: %s" % said[0])
	assert(not said[0].contains("include_filter"), "while the filter they agree on is not named: %s" % said[0])


## The other direction, and the word a person acts on: a preset *missing* something says so with a "does not",
## rather than by the same sentence as one that has it.
func test_a_preset_that_is_missing_a_path_says_so_the_other_way_round() -> void:
	var fewer := _a_preset("preset.2", "Linux", { "tests/*": true })
	var more := _a_preset("preset.0", "Windows Desktop", { "tests/*": true, "tools/*": true })
	var both: Array[Dictionary] = [more, fewer]
	var said: Array[String] = disagreements(both)
	assert(said.size() == 1, "one disagreement either way: %s" % str(said))
	assert(
		said[0].contains("does not keep out") and said[0].contains("tools/*"),
		"and it reads as the preset not keeping the path out: %s" % said[0],
	)


## The order is not the answer. The three presets do not agree on it today, so a guard comparing written lines
## would have failed on the day it was written - over nothing.
func test_a_difference_of_order_alone_is_not_a_disagreement() -> void:
	var one := _a_preset("preset.0", "Windows Desktop", { "tests/*": true, "tools/*": true })
	var other := _a_preset("preset.2", "Linux", { "tools/*": true, "tests/*": true })
	var both: Array[Dictionary] = [one, other]
	assert(disagreements(both).is_empty(), "the same paths in another order are the same paths")


# --- the scratch the tools write -------------------------------------------------------------------------------

## The tools' own scratch is kept out of every build, and this is where that is held to.
##
## `build/` is inside `res://` and on no build's allow-list: it holds what the dev tools photograph and export, and
## whatever the formatter was given to write. The file that keeps it out is `export_presets.cfg`, one line per
## preset, and nothing else reads it - so a preset that forgot the line would put every screenshot the desk has
## taken, and a debug package, inside what a person installs. A script left there is worse than a stray picture: it
## registers the same `class_name` as the original, and the registry the exporter bakes into a build then names
## that class twice, which is how the phone build went out with a `PROBE` block that never appeared.
const SCRATCH := "build/*"


## The presets that would ship the scratch directory, in the words a person gave them: empty when every one of
## them keeps it out.
static func scratch_kept_out(presets: Array[Dictionary]) -> Array[String]:
	var slipped: Array[String] = []
	for preset: Dictionary in presets:
		var kept: Dictionary = (preset.get("filters", { }) as Dictionary).get("exclude_filter", { })
		if not kept.has(SCRATCH):
			slipped.append(String(preset.get("name", "a preset")))
	return slipped


## Every preset this program is built from keeps the tools' scratch out.
func test_every_preset_keeps_the_tools_own_scratch_out_of_the_build() -> void:
	var slipped: Array[String] = scratch_kept_out(presets_in(PRESETS))
	assert(slipped.is_empty(), "%s is kept out of every build; these do not: %s" % [SCRATCH, " and ".join(slipped)])


## And the guard can fail: a preset written here by hand without the line is named, and one with it is not - so
## the check above is a check of the file and not of itself.
func test_the_scratch_guard_names_a_preset_that_would_ship_it() -> void:
	var forgot := _a_preset("preset.2", "Linux", { "tests/*": true })
	var kept := _a_preset("preset.0", "Windows Desktop", { SCRATCH: true })
	var slipped: Array[String] = scratch_kept_out([kept, forgot])
	assert(slipped.size() == 1 and slipped[0] == "Linux", "the one that would ship it is named: %s" % str(slipped))
	assert(scratch_kept_out([kept]).is_empty(), "and the one that keeps it out is not named")


## A preset as the reader hands one over, written by hand so that the controls above do not depend on the file
## being right: both filters present, and one of them stated.
func _a_preset(section: String, name: String, excluded: Dictionary) -> Dictionary:
	return {
		"section": section,
		"name": name,
		"filters": { "include_filter": { "data/*": true }, "exclude_filter": excluded },
	}
