extends Node
## The phone's design rules against the platform's own, and against the modules that own them.
##
## Most of this project's numbers are not its own invention - the touch floor and the two contrast ratios come from
## Android and Material - and the risk of a rule written down is that the document and the module drift apart. So
## each number the authority quotes is read back out of the module that owns it, and the section itself is read out
## of the file rather than trusted: a floor moved in `PhoneHud` without moving the paragraph fails here.
##
## No node and no scene: this is a question about two files and two constants.

const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const ContrastScript := preload("res://scripts/contrast.gd")

## The design authority for the phone: the one place the rules, and the one rule that is not met, are written down.
const SPEC := "res://docs/phone-target.md"

## The heading the authority opens with. It is a reading order rather than a numbered section, because it is what a
## person who has not designed for a phone before needs first, and the numbered sections behind it are in the order
## they are read rather than the order they were written.
const RECOMMENDED_HEADING := "## Where to start"


## The authority's own words, or nothing when it cannot be read - which fails every assertion below with the
## message that says what is wrong, rather than inside a helper.
func _the_spec() -> String:
	var reading: FileAccess = FileAccess.open(SPEC, FileAccess.READ)
	if reading == null:
		return ""
	var text: String = reading.get_as_text()
	reading.close()
	return text


## **The floor is this project's own, and the authority says whose number it is measured against.** Android asks for
## 48 by 48 dp; this program states 5.5 mm, because 48 dp is a 135 px row in a 349-pixel palette. Both halves are
## held here so neither can move alone: a floor raised to the platform's would have to change the paragraph saying
## why it is not.
func test_the_touch_floor_is_stated_and_the_platforms_number_is_beside_it() -> void:
	assert(
		PhoneHudScript.TOUCH_MM == 5.5,
		"the thumb floor this program chose: %s" % str(PhoneHudScript.TOUCH_MM),
	)
	var spec: String = _the_spec()
	assert(spec.contains("`TOUCH_MM` **5.5**"), "and the authority states it as the module does")
	assert(spec.contains("48 by 48 dp"), "beside the platform's own rule")
	assert(spec.contains("7.6 mm, or 135 px"), "worked into this phone's own pixels")


## The two ratios are the platform's own numbers, carried as the module's constants rather than as a sentence - so a
## page is judged by the rule itself and not by a restatement of it.
func test_the_contrast_ratios_are_the_platforms_own_two_numbers() -> void:
	assert(ContrastScript.LEAST == 4.5, "body text against its background: %s" % str(ContrastScript.LEAST))
	assert(ContrastScript.LEAST_LARGE == 3.0, "and larger text: %s" % str(ContrastScript.LEAST_LARGE))
	var spec: String = _the_spec()
	assert(
		spec.contains("`LEAST` and `LEAST_LARGE`"),
		"and the authority names the constants rather than restating the numbers",
	)


## **The one rule that is broken is written down.** Android 15 enforces edge-to-edge for an app targeting API 35 or
## higher, and the navigation bar's ground cannot be had through Godot at all - so that gap is a sentence in the
## authority rather than a silence, and this is what stops it being forgotten.
func test_the_navigation_bar_gap_is_written_down_rather_than_forgotten() -> void:
	var spec: String = _the_spec()
	assert(spec.contains("Android 15 enforces edge-to-edge"), "the platform rule the program breaks is named")
	assert(spec.contains("`targetSdk=36`"), "with the target this build really reports")
	assert(
		spec.contains("compliance gap and not a nicety"),
		"and what it is - a gap that cannot be seen, rather than a preference",
	)
	assert(
		spec.contains("screen_get_usable_rect"),
		"as is the second door measured and found wanting, so nobody tries it a third time",
	)


## A rule that is only remembered is what this section exists to stop, so the sources are cited where a reader can
## go and check them rather than take anybody's word - including this project's.
func test_the_authority_is_cited_so_it_need_not_be_remembered() -> void:
	var spec: String = _the_spec()
	assert(
		spec.contains("developer.android.com/guide/topics/ui/accessibility/apps"),
		"the touch target and the contrast ratios come from there",
	)
	assert(
		spec.contains("developer.android.com/about/versions/15/behavior-changes-15"),
		"and the behaviour change that makes the gap a compliance one, from there",
	)


## The reading order the authority opens with names files, and a map that points at a file which has moved is worse
## than no map at all: it sends the next reader somewhere that is not there. It also promises, in its own words, that
## **no row of it states a number** - each number belongs to the module the row names - and a promise written in
## prose is the kind this project keeps with a test that reads it.
##
## **What is held is the paths, and deliberately not the class names.** A `class_name` is a name the engine resolves
## wherever its file sits, so `WindowClass` stays true even if its file is renamed; a path does not, and a path is
## what a reader follows. Holding what can go stale and leaving what cannot is the same line
## `test_device_doctrine.gd` draws between a call and a comment about it.
func test_the_reading_orders_map_names_files_that_are_there_and_states_no_number() -> void:
	var map: String = _the_reading_order(_the_spec())
	assert(not map.is_empty(), "the authority opens with a reading order")
	var named: PackedStringArray = _the_paths_the_map_names(map)
	assert(named.size() >= 6, "and it names the modules that own the rules: %d" % named.size())
	for path: String in named:
		assert(FileAccess.file_exists(path), "the map names %s, which is a file" % path)
	var rows: PackedStringArray = _the_maps_rows(map)
	assert(rows.size() >= 6, "and its map carries a row per rule: %d" % rows.size())
	for row: String in rows:
		assert(
			not _holds_a_digit(row),
			(
				"a row of the map states no number, because the number belongs to the file it names: " + row
			),
		)


## The reading order itself: from its heading down to the first numbered section, which is where the document proper
## begins. An empty string when either end is missing, so a reader gets the assertion's own words rather than a
## failure inside a helper.
func _the_reading_order(spec: String) -> String:
	var from: int = spec.find(RECOMMENDED_HEADING)
	if from == -1:
		return ""
	var to: int = spec.find("## 1. The build", from)
	return "" if to == -1 else spec.substr(from, to - from)


## Every `scripts/...gd` the map names, as a project path - and the prose around the table is read too, which is
## intended: naming a module in a sentence is the same claim about where a rule lives as naming it in a row.
func _the_paths_the_map_names(map: String) -> PackedStringArray:
	var found := PackedStringArray()
	var at: int = map.find("`scripts/")
	while at != -1:
		var start: int = at + 1
		var stop: int = map.find("`", start)
		if stop == -1:
			break
		var path: String = "res://" + map.substr(start, stop - start)
		if path.ends_with(".gd") and not found.has(path):
			found.append(path)
		at = map.find("`scripts/", stop)
	return found


## The map's own rows, read the way markdown reads a table: everything below the line of dashes that separates a
## table's headings from its body. Read rather than counted, so a row added to the map is a row this checks.
func _the_maps_rows(map: String) -> PackedStringArray:
	var rows := PackedStringArray()
	var body: bool = false
	for line: String in map.split("\n"):
		var row: String = line.strip_edges()
		if not row.begins_with("|"):
			body = false
			continue
		if not body:
			body = row.replace("|", "").replace("-", "").strip_edges().is_empty()
			continue
		rows.append(row)
	return rows


## Whether a row states a number, which every row of the map promises not to.
func _holds_a_digit(text: String) -> bool:
	for i: int in text.length():
		if text[i] >= "0" and text[i] <= "9":
			return true
	return false


## A guard that cannot fail is not a guard. The three readings above are run against a map written here by hand -
## one row stating a number and one not, a path named in a sentence rather than in a row, and a document with no
## reading order in it at all - so they are still guards on the day the authority is clean, which is every day.
func test_the_reading_orders_guard_can_fail() -> void:
	var hand_written: String = (
		"## Where to start\n\n"
		+ "Read `scripts/spacing.gd` first.\n\n"
		+ "| the rule | the file that owns it |\n"
		+ "| --- | --- |\n"
		+ "| how close two targets may stand | `scripts/spacing.gd` |\n"
		+ "| how near the word 5.5 mm is | `scripts/legibility.gd` |\n"
		+ "\n"
		+ "## 1. The build\n"
	)
	var rows: PackedStringArray = _the_maps_rows(_the_reading_order(hand_written))
	assert(rows.size() == 2, "the table's body is read and its two heading lines are not rows: %d" % rows.size())
	assert(not _holds_a_digit(rows[0]), "a row stating no number passes")
	assert(_holds_a_digit(rows[1]), "and a row stating one is caught")
	assert(
		_the_paths_the_map_names(hand_written).has("res://scripts/spacing.gd"),
		"and a path is read out of a sentence as readily as out of a row",
	)
	assert(
		_the_reading_order("A document with no reading order in it.") == "",
		"while a document with no reading order reads as nothing rather than as everything",
	)
