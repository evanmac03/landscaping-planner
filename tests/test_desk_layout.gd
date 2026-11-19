extends Node
## The desk's layout, written down, so that a change meant for a phone cannot move the desktop in silence.
##
## **Why it is worth a guard.** The suite holds the desk's *rules*: a page too tall keeps the size it declared,
## the front door is the 520 by 540 it states, a desk is not judged for legibility. Rules catch a leak that
## changes *behaviour*, and they are what caught the leaks this project has already had. They do not catch one
## that changes *geometry* - and the phone's answers are derived from the same declarations the desk uses, so an
## edit to a shared number (a page's padding, a row's height, a constant the desk passes through on its way to a
## thumb's floor) can move Windows by one pixel and turn nothing red. That is the difference between "should not
## affect the desktop" and "cannot", and this is the instrument for the second word.
##
## **What is recorded.** Four facts per page, and every one of them is a fact about the page rather than about the
## machine that measured it: **`declared`**, the size the page states for itself, which is the floor it opens at;
## **`wanted_width`**, the widest thing its contents need, which is what a padding, a button's words or a row's
## makeup moves; **`children`**, how many controls the page's content root holds and shows, which is what a control
## added or taken away moves; and **`scrolls`**, whether the page's column can carry its own length into view.
##
## Every page is built, shown at the size it declares, and read through `PageLayout` - the one measurement of a
## page this project has - so this check reads the desk the same way the page layout check does, rather than
## inventing a second reading of it.
##
## **The type is the desk's.** This program carries no theme: its words are set in Godot's default theme and in
## the overrides each page and each control states for itself, so a page in a bare tree is set in the same type it
## is set in on the board. `project.godot` names no theme, and the only theme overrides under `res://scenes` are
## `hud.tscn`'s own panels.
##
## **What is *not* recorded, and the finding that decided it: the height a page's contents want.** It is not a
## fact about the page. A height is the sum of the heights its children take *at the width they are given*, so a
## page whose words wrap wants more height in a narrow room and less in a wide one - and the room belongs to
## whoever is running the tests, not to the page. **Measured, and it cost this check its first version:**
## `analytics_window`, one page at one declared size, wants **834 px** of height under the recording tool and
## **570 px** under the project's own test runner. Both are real readings of a real page; neither is the desk's,
## and comparing them would redden the suite for whichever runner a person happened to use. The cause was not
## found - the obvious candidate, a page's own `content_scale_factor` inherited from the tree, was stated and
## **changed nothing** - so the height is left out of the record rather than guessed at. A page's height belongs
## to `tools/page_layout_check.gd` and to `tools/audit.gd`, on a real screen, as a verdict rather than a number.
##
## A minimum **width**, by contrast, is a fact the page states: the widest label's longest word, a button's
## caption, a stated minimum. That is why `wanted_width` is in the record and the height is not - the two runners
## agree on the width to the tenth of a pixel while disagreeing about the height by 264.
##
## **What is deliberately not recorded.** The board's chrome - the top bar, the palette, the strip below the bar -
## and any on-screen rectangle whatever. Those are readings of a *screen*, and a headless runner has a 64 x 64
## dummy display with the canvas drawn at 0.04, so a record of them would be a record of the runner's own
## artefact: at a finger's type the foot line wraps to several screen-heights and its top comes back as a number
## like -69443, which is a fault nobody has. That half of the question is `tools/hud_layout_check.gd`'s, which
## measures the real panels on a real desk inside `tools/audit.gd`. The split is not a preference: one of the two
## can run in CI and the other cannot.
##
## **Why a page with no record, and a record with no page, are both faults.** The pages are found by walking
## `res://scripts` and asking each script what it inherits - `PageIndex`, the one walk of that folder - so a page
## added tomorrow is measured tomorrow and a page deleted today leaves a line behind. The first is a page nobody
## looked at, and the second is a line that has stopped describing anything; both are named.
##
## **Re-recording is a deliberate act**, and `tools/record_desk_layout.gd` is how it is done. It is meant to be
## one: a desk layout that changed on purpose is a change to be looked at, and the record is written one page per
## block, in the page's own name, sorted - so a diff names the page and the number that moved rather than showing
## a wall of digits. Nothing in this file writes it, because a test that records its own answer is a test that
## cannot fail.

const PageIndexScript := preload("res://scripts/page_index.gd")
const PageLayoutScript := preload("res://scripts/page_layout.gd")

## Where the record lives: beside this check, under the tree every export preset excludes.
const GOLDEN := "res://tests/fixtures/desk_layout.json"

## What the recorder - the tool, this time - is called, for the reader who opens the file itself. The record is
## read by a machine and by a person, and a person opening a wall of JSON deserves one line saying where it came
## from and how to make it again.
const NOTE := (
	"The desk's layout, measured by tests/test_desk_layout.gd."
	+ " Re-record it with tools/record_desk_layout.gd, and read the diff that leaves."
)

## The screen each page is measured against, the same laptop the page layout check holds pages to. It decides
## nothing that is recorded - every page is measured at the size it declares for itself - and is stated because
## `measure` asks for it.
const A_LAPTOP := Vector2i(1366, 768)

## The four facts an entry holds, in the order a diff line reads them.
const FACTS: Array[String] = ["declared", "wanted_width", "children", "scrolls"]

## How near two measurements must be to be the same layout. A tenth of a pixel is where a size lands differently
## between two runs of the same code; a whole pixel is a layout that moved, which is what this exists to catch.
const SAME_LAYOUT := 0.1

# --- the record ------------------------------------------------------------------------------------------------


## The record as it is on disk, or an empty dictionary for a file that is not there or does not hold a record.
##
## The caller says which it was - a missing record and a record of nothing are the same empty dictionary here,
## and the check refuses on it rather than reporting every page as newly added.
##
## `JSON.parse_string` on purpose: what it gives back is left untyped, because every number in a JSON file comes
## back as a float and nothing comes back typed. Both sides of the comparison are therefore put through the same
## reading before they meet - see `_of` - rather than compared as dictionaries, which cannot be compared at all.
static func read_record(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return { }
	var held: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (held is Dictionary):
		return { }
	var pages: Variant = (held as Dictionary).get("pages", { })
	return pages if pages is Dictionary else { }


## Every page's own measurements, measured as a desk:
## `{name: {read, declared, wanted_width, children, scrolls}}`.
##
## One page at a time, each freed before the next is built, so that no page is left standing when the measurement
## is done - a leaked page fails the whole run. A page that could not be read is recorded as `read: false` rather
## than left out: a page that has *become* unreadable is a change like any other, and a record that dropped it
## would report that change as nothing.
static func recorded(tree: SceneTree) -> Dictionary:
	var pages: Dictionary = { }
	for path: String in PageIndexScript.scripts():
		pages[path.get_file().get_basename()] = await _measure_one(path, tree)
	return pages


## Write the record, in the one shape both sides read: one page per block, sorted, so that a change is a line a
## person can see in a diff.
##
## Through a temporary file and a rename, like every other save in this project, so that a write that fails never
## leaves a shorter record where the real one was.
static func write_record(path: String, pages: Dictionary) -> bool:
	var names := PackedStringArray()
	for page_name: String in pages.keys():
		names.append(page_name)
	names.sort()
	var sorted: Dictionary = { }
	for page_name: String in names:
		sorted[page_name] = pages[page_name]
	var document: Dictionary = { "note": NOTE, "pages": sorted }
	var folder: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var temp: String = path + ".writing"
	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(document, "\t") + "\n")
	file.close()
	return (DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path)) == OK)


## Build one page, measure it as a desk, and take it down again, answering with the page's entry.
##
## Freed here rather than left to the tree, because a page still standing when the run ends is a leaked resource
## and the runner fails the whole run for one. An entry is answered even for a page that could not be built, so
## that every page this project has leaves exactly one line in the record.
static func _measure_one(path: String, tree: SceneTree) -> Dictionary:
	var nothing: Dictionary = {
		"read": false,
		"declared": [0.0, 0.0],
		"wanted_width": 0.0,
		"children": 0,
		"scrolls": false,
	}
	var script: Script = load(path) as Script
	if script == null or not script.can_instantiate():
		return nothing
	var page: Window = script.new() as Window
	if page == null:
		return nothing

	# In the tree before it is built, because `_ready` is where several pages build themselves and a page must
	# not be built twice. `build` is idempotent for exactly this.
	tree.root.add_child(page)
	if page.has_method("build"):
		page.build()
	var row: Dictionary = await PageLayoutScript.measure(page, tree, A_LAPTOP)
	# Read off the page while it is still standing: `measure` has shown it, set it to the size it declares and
	# given the containers their settling frames, which is what makes the contents it read the contents a person
	# would meet.
	var declared: Vector2i = row["declared"]
	var wanted: Vector2 = row["wanted"]
	var entry: Dictionary = {
		"read": bool(row["read"]),
		"declared": [float(declared.x), float(declared.y)],
		"wanted_width": wanted.x,
		"children": _children_of(page),
		"scrolls": bool(row["scrolls"]),
	}
	tree.root.remove_child(page)
	page.free()
	return entry


## How many controls the page's content root holds and shows - the same nodes, and the same rule about showing,
## that `PageLayout.wanted_contents` adds up, so that the count and the width are two readings of one thing.
static func _children_of(page: Window) -> int:
	var root: Control = PageLayoutScript.content_root(page)
	if root == null:
		return 0
	var shown: int = 0
	for child: Node in root.get_children():
		var control: Control = child as Control
		if control != null and control.visible:
			shown += 1
	return shown

# --- the rule --------------------------------------------------------------------------------------------------


## What the record and the measurement disagree about, in the words a person reads: empty when the desk is
## exactly where it was recorded.
##
## Each line names the page and what moved on it, with both numbers, because which of the two readings is right
## is not something this can know - the record is the desk as it was and the measurement is the desk as it is,
## and the person who changed one of them is the one who knows which way it should be settled.
static func differences(measured: Dictionary, record: Dictionary) -> Array[String]:
	var said: Array[String] = []
	var names := PackedStringArray()
	for page_name: String in measured.keys():
		names.append(page_name)
	for page_name: String in record.keys():
		if not names.has(page_name):
			names.append(page_name)
	names.sort()
	for page_name: String in names:
		if not record.has(page_name):
			said.append("%s is a page this project has and the record does not: measure it and record it" % page_name)
			continue
		if not measured.has(page_name):
			said.append("%s is in the record and is no longer a page here: take its line out" % page_name)
			continue
		var was: Dictionary = _of(record[page_name])
		var now: Dictionary = _of(measured[page_name])
		if bool(was["read"]) != bool(now["read"]):
			said.append(
				"%s: %s -> %s"
				% [
					page_name,
					"a page that was read" if was["read"] else "a page that could not be read",
					("a page that was read" if now["read"] else "a page that could not be read"),
				]
			)
		for fact: String in FACTS:
			if _same(was[fact], now[fact]):
				continue
			said.append("%s: %s %s -> %s" % [page_name, fact, _said(was[fact]), _said(now[fact])])
	return said


## One page's entry, from either side, as the same facts in the same types. A record read back from JSON and a
## measurement just taken must be read the same way or there is no comparing them: the file hands back `[1180,
## 850]` as two floats and `children` as `12.0`, where the measurement holds a pair and a whole number.
static func _of(entry: Dictionary) -> Dictionary:
	return {
		"read": bool(entry.get("read", false)),
		"declared": _a_pair(entry.get("declared", [])),
		"wanted_width": float(entry.get("wanted_width", 0.0)),
		"children": int(entry.get("children", 0)),
		"scrolls": bool(entry.get("scrolls", false)),
	}


## Two numbers, from the `Array` a JSON file gave back or from a pair this project holds. Anything else is zero,
## which no page in this project declares or wants - so a broken entry reads as a page that changed rather than
## as one that matches.
static func _a_pair(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Vector2i:
		return Vector2(value as Vector2i)
	if value is Array:
		var pair: Array = value
		if pair.size() >= 2:
			return Vector2(float(pair[0]), float(pair[1]))
	return Vector2.ZERO


## Whether two of these facts are the same fact. A length is the same when it is within `SAME_LAYOUT`, and the
## other two are whole things - a count and a yes or no - and are compared as they are.
static func _same(one: Variant, other: Variant) -> bool:
	if one is Vector2 and other is Vector2:
		var mine: Vector2 = one
		var theirs: Vector2 = other
		return absf(mine.x - theirs.x) <= SAME_LAYOUT and absf(mine.y - theirs.y) <= SAME_LAYOUT
	if one is float and other is float:
		return absf(one - other) <= SAME_LAYOUT
	return one == other


## One of the facts as a diff line says it.
static func _said(value: Variant) -> String:
	if value is Vector2:
		var pair: Vector2 = value
		return "%.1f x %.1f" % [pair.x, pair.y]
	if value is float:
		return "%.1f" % value
	return str(value)

# --- the guard -------------------------------------------------------------------------------------------------


## The desk is where it was recorded, page for page.
func test_the_desks_layout_is_what_was_recorded_for_it() -> void:
	var record: Dictionary = read_record(GOLDEN)
	assert(not record.is_empty(), "%s holds a record: %d page(s)" % [GOLDEN, record.size()])
	var measured: Dictionary = await recorded(get_tree())
	assert(
		measured.size() == PageIndexScript.scripts().size(),
		"every page this project has was measured: %d of %d" % [measured.size(), PageIndexScript.scripts().size()],
	)
	var said: Array[String] = differences(measured, record)
	assert(said.is_empty(), "and it is where it was recorded:\n  " + "\n  ".join(said))


## The record is written to be read by a person in a diff, so its pages are in their own names and in order. A
## file that was reordered by hand would turn every later change into a wall of moved lines.
func test_the_record_is_in_the_pages_own_names_and_in_order() -> void:
	var record: Dictionary = read_record(GOLDEN)
	assert(not record.is_empty(), "there is a record to read")
	var as_written := PackedStringArray()
	for page_name: String in record.keys():
		as_written.append(page_name)
	var in_order := as_written.duplicate()
	in_order.sort()
	assert(as_written == in_order, "the record's pages are sorted: %s" % ", ".join(as_written))
	for page_name: String in as_written:
		assert(not page_name.contains("."), "%s is a page's own name, with no file extension" % page_name)
		var entry: Dictionary = record[page_name]
		for fact: String in FACTS:
			assert(entry.has(fact), "%s states %s" % [page_name, fact])


## A guard that cannot fail is not a guard, so the comparison is run against differences written here by hand -
## the one a phone edit really makes, a page that moved by a single pixel.
func test_the_guard_names_a_page_that_moved_by_a_pixel() -> void:
	var record: Dictionary = { "a_page": _an_entry([1180, 850], 1100.0, 12, false) }
	var moved: Dictionary = { "a_page": _an_entry([1180, 850], 1101.0, 12, false) }
	var said: Array[String] = differences(moved, record)
	assert(said.size() == 1, "one page that moved by a pixel is one line: %s" % str(said))
	assert(
		said[0].contains("a_page") and said[0].contains("wanted_width"),
		"naming the page and what moved on it: %s" % said[0],
	)
	assert(said[0].contains("1100") and said[0].contains("1101"), "and both numbers: %s" % said[0])


## A control added to a page and a control taken away: the same page, the same size, one row different - which is
## what a phone-only row left inside the desk's page would look like.
func test_the_guard_names_a_page_that_gained_a_control() -> void:
	var record: Dictionary = { "a_page": _an_entry([1180, 850], 1100.0, 12, false) }
	var gained: Dictionary = { "a_page": _an_entry([1180, 850], 1100.0, 13, false) }
	var said: Array[String] = differences(gained, record)
	assert(said.size() == 1, "one control is one line: %s" % str(said))
	assert(
		said[0].contains("children") and said[0].contains("12") and said[0].contains("13"),
		"naming the count that moved: %s" % said[0],
	)


## A page nobody recorded, and a record whose page has gone. Both are faults, and they are not the same fault:
## the first is a page nobody looked at, the second a line that has stopped describing anything.
func test_a_page_with_no_record_and_a_record_with_no_page_are_both_named() -> void:
	var measured: Dictionary = { "a_new_page": _an_entry([400, 300], 10.0, 2, false) }
	var record: Dictionary = { "a_page_that_went": _an_entry([400, 300], 10.0, 2, false) }
	var said: Array[String] = differences(measured, record)
	assert(said.size() == 2, "one for each side: %s" % str(said))
	assert(said[0].contains("a_new_page"), "the page with no record is named: %s" % said[0])
	assert(said[1].contains("a_page_that_went"), "and the record with no page: %s" % said[1])


## A tenth of a pixel is not a layout change. A size that lands a hair differently between two runs of the same
## code must not turn this red, or it would be noise and would be read as noise.
func test_a_size_that_lands_a_hair_differently_is_not_a_change() -> void:
	var record: Dictionary = { "a_page": _an_entry([1180, 850], 1100.0, 12, false) }
	var nearly: Dictionary = { "a_page": _an_entry([1180, 850], 1100.04, 12, false) }
	assert(differences(nearly, record).is_empty(), "a hair is not a change")
	var scrolled: Dictionary = { "a_page": _an_entry([1180, 850], 1100.0, 12, true) }
	assert(differences(scrolled, record).size() == 1, "while a page that has begun to scroll is")


## The record is written by one place and held by another, and the two must read the desk the same way. The tool
## does not measure anything of its own: it calls the two functions this check does, which is what stops a
## recorded desk and a checked desk from becoming two readings of one program.
func test_the_recorder_writes_through_the_same_reading_the_check_takes() -> void:
	var source: String = FileAccess.get_file_as_string("res://tools/record_desk_layout.gd")
	assert(source.contains("DeskLayout.recorded("), "the recorder measures through the check's own reading")
	assert(source.contains("DeskLayout.write_record("), "and writes through its own writer")
	assert(
		not source.contains("PageLayout.measure("),
		"taking no measurement of its own, which is how two readings of one desk would start",
	)


## A page's entry as the record holds it, written by hand so that the controls above do not depend on the file.
func _an_entry(declared: Array, wanted_width: float, children: int, scrolls: bool) -> Dictionary:
	return {
		"read": true,
		"declared": declared,
		"wanted_width": wanted_width,
		"children": children,
		"scrolls": scrolls,
	}
