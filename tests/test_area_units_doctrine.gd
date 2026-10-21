extends Node
## A guard on the one-writer rule for areas.
##
## `docs/drafting-module.md`: **an area is turned into words in exactly one place, `DraftUnits.format_area`.**
## This test reads every script in `res://scripts` and asserts that the only file which puts a number and
## an area unit into the same string is the writer itself. Nothing here checks what the words say - that
## is `test_draft_core.gd`'s job, and `test_irrigation.gd`'s and `test_lighting.gd`'s and
## `test_survey_units.gd`'s. This checks only that there is one of them.
##
## **What it looks for, and why it is that narrow.** A hand-written area takes one of two shapes: an
## append (`String.num(area_m2, 1) + " m2"`) and a format string (`"%s m2" % [area_m2]`). Both put a
## space and a unit inside a string literal, and so does prose that names one (`"the bed is 18 m2"`), so
## the rule is simply **a literal that names an area unit after a space**. The unit has to *end* there:
## `" has no area"` begins with the letters of `ha` and is not a hectare, and `"the can"` is not two
## acres. Two other places `m2` appears are *not* areas turned into words and must not be flagged: a
## parsing table's key (`"m2": 1.0`) and a record's machine field (`"unit": "m2"`). Those are the same
## token used as a name, and a name is not a sentence - neither has the space in front of it. A comment
## is not a writer either.
##
## Tests are out of scope on purpose - quoting the words is how a test checks the writer, so `tests/`
## is not walked, and the same literal inside a test is not an offence.
##
## **Why it does not simply have a bigger allowlist.** The doctrine names `ZoneMap` as the owner of the
## row contract, and `Irrigation` and `Lighting` take its optional `units` parameter, so it would be
## easy to list all three as exempt and move on. `test_the_modules_that_hand_an_area_on_do_not_word_one`
## asserts they are clean instead, and the allowlist is one file long. An exemption nobody checks is
## how the second writer comes back.

## The shapes a string has to have to count as an area word.
const AREA_UNITS: Array[String] = [
	"m2", "m²", "sqm", "sq m", "sqft", "sq ft", "ft2", "ha", "hectare", "hectares", "acre", "acres",
	"ac",
]

## The one file allowed to word an area. A change that adds a second one has to be a decision.
const WRITERS: Array[String] = ["res://scripts/draft/units.gd"]

## A unit has to end at a boundary, or `has` is a hectare and `can` is two acres. The same letters
## followed by one of these is a longer word and not a unit.
const LETTERS := "abcdefghijklmnopqrstuvwxyz0123456789"


# --- the guard -------------------------------------------------------------------------------


func test_the_one_writer_is_the_only_file_in_scripts_that_words_an_area() -> void:
	var caught := PackedStringArray()
	for path: String in _scripts():
		if not offences_in(_read(path), path).is_empty():
			caught.append(path)
	assert(caught == PackedStringArray(WRITERS),
		"exactly one file words an area; these do: " + ", ".join(caught))


## An exemption is a promise that the exempt file earns. These are the files the doctrine leans on, and
## a private copy of the rule reappearing in any of them is what this catches.
func test_the_modules_that_hand_an_area_on_do_not_word_one() -> void:
	for path: String in [
		"res://scripts/zone_map.gd",
		"res://scripts/draft/irrigation.gd",
		"res://scripts/draft/lighting.gd",
		"res://scripts/draft/survey.gd",
		"res://scripts/draft/survey_file.gd",
		"res://scripts/plant_spacing.gd",
	]:
		var found := offences_in(_read(path), path)
		assert(found.is_empty(),
			path + " words an area by hand: " + ", ".join(PackedStringArray(found)))


## A guard that reads nothing passes everything. This is the assertion that the walk is a walk.
func test_the_guard_reads_the_whole_scripts_tree() -> void:
	var paths := _scripts()
	assert(paths.size() > 30, "the walk found the scripts: %d" % paths.size())
	assert(paths.has("res://scripts/draft/units.gd"), "including the writer")
	assert(paths.has("res://scripts/plant_spacing.gd"), "and a file that delegates across two modules")
	assert(not paths.has("res://tests/test_draft_core.gd"), "and nothing outside res://scripts")
	for path: String in paths:
		assert(not _read(path).is_empty(), path + " could be read")


## A guard that cannot fail is not a guard. The matcher is run against the shapes it exists to catch,
## written out by hand here rather than found in the tree, so it is still a guard on the day the tree
## is clean.
func test_the_guard_catches_the_shapes_a_hand_written_area_takes() -> void:
	assert(offences_in("var words := String.num(area_m2, 1) + \" m2\"", "sample.gd").size() == 1,
		"an append is caught")
	assert(offences_in("return \"%s m2\" % [area_m2]", "sample.gd").size() == 1,
		"a format string is caught")
	assert(offences_in("return \"over %.1f ft2 here\" % [area]", "sample.gd").size() == 1,
		"and an imperial one, and one with the unit mid-sentence")
	assert(offences_in("return \"%.1f ha\" % [area_m2]", "sample.gd").size() == 1,
		"and a hectare")
	assert(offences_in("return \"the bed is 18 m2\"", "sample.gd").size() == 1,
		"and prose that names one, which is what a hand-written sentence usually looks like")


## The other half of a guard being a guard: it must leave alone the things that look like an area word
## and are not. Every one of these appears somewhere in the real tree today, and the last two are the
## bug this rule was written twice to stop having.
func test_the_guard_leaves_a_key_and_a_machine_field_alone() -> void:
	assert(offences_in("\"m2\": 1.0, \"sqm\": 1.0, \"sq m\": 1.0", "sample.gd").is_empty(),
		"a parsing table is a name, not a sentence")
	assert(offences_in("return {\"unit\": \"m2\", \"area_text\": words.format_area(area)}", "sample.gd").is_empty(),
		"and a record's unit field is a machine fact")
	assert(offences_in("## One bed as a list reads it: \"bed 4, 6.2 m2\".", "sample.gd").is_empty(),
		"and a comment is not a writer")
	assert(offences_in("return \"%s has no area, so nothing can ever be inside it\"", "sample.gd").is_empty(),
		"a word that merely begins with the letters of a unit is not a unit")
	assert(offences_in("var words := \"the can has a placard\"", "sample.gd").is_empty(),
		"and two of them in one sentence are still a sentence")


# --- the matcher -----------------------------------------------------------------------------


## Every area word on one script, as `path:line: "the literal"`. Public so that a reader of this file
## can see the whole rule in one place.
static func offences_in(text: String, path: String) -> Array[String]:
	var out: Array[String] = []
	var lines := text.split("\n")
	for i in lines.size():
		for literal: Dictionary in _literals(String(lines[i])):
			var words := String(literal["text"])
			if _unit_in(words).is_empty():
				continue
			out.append("%s:%d: \"%s\"" % [path, i + 1, words])
	return out


## The one rule, in one place: a literal words an area when it names an area unit after a space and the
## unit ends there. `" m2"` and `"%s m2"` and `"the bed is 18 m2"` are all the same finding, because all
## three are a person reading an area the program wrote for itself.
static func _unit_in(words: String) -> String:
	for unit: String in AREA_UNITS:
		var at := words.find(" " + unit)
		if at < 0:
			continue
		var after := at + 1 + unit.length()
		if after < words.length() and LETTERS.contains(words[after]):
			continue
		return unit
	return ""


## The string literals on a line, so a finding can be pointed at rather than described. Stops at a `#`
## that is not inside a literal, because a comment is not a writer.
static func _literals(line: String) -> Array:
	var out: Array = []
	var at := 0
	while at < line.length():
		var letter := line[at]
		if letter == "#":
			break
		if letter != "\"":
			at += 1
			continue
		at += 1
		var words := ""
		while at < line.length() and line[at] != "\"":
			if line[at] == "\\" and at + 1 < line.length():
				at += 1
			words += line[at]
			at += 1
		at += 1
		out.append({"text": words})
	return out


static func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


## Every `.gd` under `res://scripts`, sorted, so a failure names the same files in the same order every
## time. A recursive walk rather than a list, because a list is a thing to forget to add to.
static func _scripts() -> Array[String]:
	var out: Array[String] = []
	_collect("res://scripts", out)
	out.sort()
	return out


static func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name: String in dir.get_files():
		if name.ends_with(".gd"):
			out.append(dir_path.path_join(name))
	for name: String in dir.get_directories():
		_collect(dir_path.path_join(name), out)