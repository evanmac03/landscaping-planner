extends Node
## A dev tool: build every page in the project, one at a time, and report the ones that ask for less
## room than their own contents want.
##
##     res://tools/page_layout_check.tscn
##
## The HUD's own panels are measured by `hud_layout_check`, which lets the engine lay the real game out
## and reads the rectangles back. These are the pages - the thirty `Window`s a menu opens - and they
## cannot be measured that way, because they are not on screen until a person opens one. So each page is
## built, put in the tree, shown at the size it declares for itself, and its contents are added up. What
## comes out is whether that declared floor has room for what the page puts in it.
##
## The pages are found by walking `res://scripts` and asking each script what it inherits, rather than by
## being listed here. A page added tomorrow is measured tomorrow; the alternative is a list that is right
## until someone forgets it, which is the defect this project spends the most effort avoiding.
##
## ## What is counted as a fault, and what is only named
##
## A page whose contents do not fit the size it declares for itself is a fault: it clips its own bottom,
## and the row it clips is nearly always the buttons. A page that could not be read at all is a fault
## too - the measurement says UNKNOWN rather than passing it, and this counts that as the failure it is.
##
## A page *taller than the screen it lands on* is named here and **not** counted as a fault, because the
## fix for it is not the page's own size: the shared show clamps a page to the room it lands in
## (`PageChrome.show_centred`), so such a page opens inside the screen rather than off it. What the clamp
## cannot do by itself is make the rest of the page *reachable* - that is the page's own business, and a
## page asks for it with `PageChrome.scrolling_column`. So each of those pages is reported with what it
## actually does: one whose column scrolls reaches the rest of itself, and one whose column does not would
## have its own bottom cut. Naming them without counting them keeps this check honest about what it proves
## - that no page clips itself at the size it declares - while showing which pages are ready for a screen
## smaller than the one this project is written for.
##
## `run()` and not the scene, so `tools/audit.gd` calls it on the same pass as the other checks; the
## scene is that call with nothing else. Returns `{name, ok, clipped, unread, needs_clamp, summary}`.

const PageLayoutScript := preload("res://scripts/page_layout.gd")

## Which scripts are pages comes from `PageIndex`, which is the one place that walks that folder. Two
## walks that could disagree about what a page is would be exactly the defect this project spends the
## most effort avoiding.
const PageIndexScript := preload("res://scripts/page_index.gd")

## The screen the check holds pages to: a 1366 x 768 laptop, which is the size that catches a page
## written for this project's 1600 x 900. Pages are measured at the size they declare, so this only
## decides whether their declared size would fit a smaller screen.
const SMALL_SCREEN := Vector2i(1366, 768)


func _ready() -> void:
	await run(get_tree())


## The check itself. Returns `{name, ok, clipped, unread, needs_clamp, summary}`.
static func run(tree: SceneTree) -> Dictionary:
	# A frame first, and not for tidiness: this is called from `_ready`, and a node cannot be added to
	# the root while the root is still setting up its own children. One frame and the root is ready.
	await tree.process_frame
	var paths: Array[String] = PageIndexScript.scripts()
	print("=== PAGE LAYOUT (%d page(s), held to a %d x %d screen) ===" % [
		paths.size(), SMALL_SCREEN.x, SMALL_SCREEN.y,
	])

	var clipped: Array[String] = []
	var unread: Array[String] = []
	var needs_clamp: Array[String] = []
	var would_cut: Array[String] = []
	for path: String in paths:
		var row: Dictionary = await _measure_page(path, tree)
		if not bool(row["read"]):
			unread.append(String(row["words"]))
			print("  %s" % String(row["words"]))
			continue
		var note: String = ""
		if not bool(row["fits_viewport"]):
			note = "   (declares more than a %d x %d screen holds: clamped when it lands%s)" % [
				SMALL_SCREEN.x, SMALL_SCREEN.y,
				" and scrolls the rest of itself into view" if bool(row["scrolls"])
					else ", which would cut its own bottom",
			]
		print("  %s%s" % [String(row["words"]), note])
		if not bool(row["fits_declared"]):
			clipped.append(String(row["name"]))
		elif not bool(row["fits_viewport"]):
			needs_clamp.append(String(row["name"]))
			if not bool(row["scrolls"]):
				would_cut.append(String(row["name"]))

	print("--- what the check found ---")
	if clipped.is_empty():
		print("  no page wants more room than it declares for itself")
	else:
		print("  %d page(s) clip their own contents: %s" % [clipped.size(), ", ".join(clipped)])
	if unread.is_empty():
		print("  every page could be read")
	else:
		print("  %d page(s) could not be read: %s" % [unread.size(), ", ".join(unread)])
	if needs_clamp.is_empty():
		print("  every page fits a %d x %d screen at the size it declares" % [
			SMALL_SCREEN.x, SMALL_SCREEN.y,
		])
	else:
		print("  %d page(s) declare more than a %d x %d screen holds (named, not counted as faults): %s"
			% [needs_clamp.size(), SMALL_SCREEN.x, SMALL_SCREEN.y, ", ".join(needs_clamp)])
		if would_cut.is_empty():
			print("    each lands clamped to the screen, and scrolls the rest of itself into view")
		else:
			print("    %d scroll the rest of themselves into view; %d have no scrolling column and would"
				% [needs_clamp.size() - would_cut.size(), would_cut.size()])
			print("    have their own bottom cut on a smaller screen: %s" % ", ".join(would_cut))

	var ok: bool = clipped.is_empty() and unread.is_empty()
	var summary: String
	if ok:
		summary = "%d page(s) fit the size they declare, and all of them were read" % paths.size()
	else:
		summary = "%d page(s) clip their own contents, %d could not be read" % [
			clipped.size(), unread.size(),
		]
	print("=== END PAGE LAYOUT ===")
	return {
		"name": "page layout", "ok": ok, "clipped": clipped.size(), "unread": unread.size(),
		"needs_clamp": needs_clamp, "summary": summary,
	}


## Build one page, measure it, and take it down again. Every page is freed here rather than left for the
## tree to clean up: a page that is still standing when the run ends is a leaked resource, and the test
## runner counts those as a failure of the run.
static func _measure_page(path: String, tree: SceneTree) -> Dictionary:
	var script: Script = load(path) as Script
	if script == null or not script.can_instantiate():
		return {"name": path.get_file(), "read": false, "fits_declared": false, "fits_viewport": true,
			"words": "%s: %s cannot be built" % [PageLayoutScript.UNKNOWN, path.get_file()]}
	var page: Window = script.new() as Window
	if page == null:
		return {"name": path.get_file(), "read": false, "fits_declared": false, "fits_viewport": true,
			"words": "%s: %s is not a window" % [PageLayoutScript.UNKNOWN, path.get_file()]}

	# The page is given a tree to live in before it is built, because `_ready` is where several pages
	# build themselves and a page must not be built twice. `build` is idempotent for exactly this.
	tree.root.add_child(page)
	if page.has_method("build"):
		page.build()
	var row: Dictionary = await PageLayoutScript.measure(page, tree, SMALL_SCREEN)
	tree.root.remove_child(page)
	page.free()
	return row