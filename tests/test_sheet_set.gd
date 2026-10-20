extends Node
## Tests for the sheet set: the sheets a drawing is plotted as.
##
## A bare `DraftSheetSet.new()` and nothing else - no drawing, no plotter, no screen - because the set
## is a pure model of *paper*: what a sheet is called, which sheet is current, and the options one sheet
## of it plots with. Everything about putting ink on a page is `test_sheet_export.gd`'s subject.
##
## Two rules are held down here, and both are about what a set may not become:
##
## * a set is never empty, because a drawing always plots as at least one sheet;
## * a sheet is paper and not geometry, so nothing here can hold an entity or a second copy of the plan.

const SheetSetScript := preload("res://scripts/draft/sheet_set.gd")
const PlotScale := preload("res://scripts/draft/plot_scale.gd")


## A set and nothing else.
##
## The trailing underscore is not decoration: a helper called `_set` **collides with the `_set` every
## `Object` in Godot already has**, which is the trap this test file fell into first - the analyser
## read every call as the two-argument property setter and reported "too few arguments" fifteen times.
## Nothing about the name says it; the signature rule does.
static func _set_() -> DraftSheetSet:
	return SheetSetScript.new()


# --- a new set ------------------------------------------------------------------------


func test_a_new_set_is_one_sheet_numbered_under_the_drawing_number() -> void:
	var set: DraftSheetSet = _set_()
	assert(set.count() == 1, "a drawing plots as at least one sheet")
	assert(set.current_index() == 0)
	assert(set.numbers() == [SheetSetScript.PREFIX + "1"], str(set.numbers()))
	assert(set.sheet(0)["sheet"] == SheetSetScript.DEFAULT_SHEET)
	assert(set.sheet(0)["scale"] == SheetSetScript.DEFAULT_SCALE)
	assert(bool(set.sheet(0)["legend"]), "the key is drawn until somebody says otherwise")
	assert(set.describe(0).contains("1:100"), set.describe(0))


func test_adding_a_sheet_gives_it_the_next_number_and_makes_it_current() -> void:
	var set: DraftSheetSet = _set_()
	var index: int = set.add("Planting plan")
	assert(index == 1)
	assert(set.count() == 2)
	assert(set.current_index() == 1, "the sheet just added is the one in hand")
	assert(set.numbers() == ["L1.1", "L1.2"], str(set.numbers()))
	assert(set.titles() == ["Landscaping Plan", "Planting plan"])


func test_a_number_already_in_use_is_not_handed_out_twice() -> void:
	var set: DraftSheetSet = _set_()
	set.add("Second")
	assert(set.remove(0), "the first sheet can go while a second one is there")
	assert(set.count() == 1)
	# The first sheet being gone, the next new sheet takes back its number rather than skipping to L1.3:
	# a set numbered 1, 3 is a set somebody wonders what happened to.
	assert(set.next_number() == "L1.1", set.next_number())
	assert(set.add("Third") == 1)
	assert(set.numbers() == ["L1.2", "L1.1"], str(set.numbers()))


func test_the_last_sheet_cannot_be_removed() -> void:
	var set: DraftSheetSet = _set_()
	assert(not set.remove(0), "a drawing always plots as at least one sheet")
	assert(set.count() == 1)
	assert(not set.remove(7), "and a sheet that is not there is not removed either")
	set.add("Second")
	assert(set.remove(1))
	assert(set.count() == 1)
	assert(set.current_index() == 0, "and the current sheet follows the set rather than the hole")


func test_a_set_is_capped_rather_than_growing_without_bound() -> void:
	var set: DraftSheetSet = _set_()
	for index in SheetSetScript.LIMIT * 2:
		set.add("Sheet %d" % index)
	assert(set.count() == SheetSetScript.LIMIT, str(set.count()))


# --- editing a set --------------------------------------------------------------------


func test_moving_a_sheet_changes_the_order_and_carries_the_selection() -> void:
	var set: DraftSheetSet = _set_()
	set.add("Second")
	set.add("Third")
	assert(set.move(2, -1) == 1, "the third sheet moves up one place")
	assert(set.titles() == ["Landscaping Plan", "Third", "Second"], str(set.titles()))
	# The row that was at 2 is now at 1, and the selection was on that row, so it went with it: a sheet
	# moving up must not leave the highlight on whatever slid into its place.
	assert(set.current_index() == 1, "the selected sheet follows the row it was moved to")
	assert(set.move(0, -1) == 0, "a sheet at the top stays where it is")
	assert(set.move(9, 1) == -1, "and a sheet that is not there cannot move at all")


func test_renumbering_numbers_a_set_from_its_places() -> void:
	var set: DraftSheetSet = _set_()
	set.add("Second")
	set.add("Third")
	assert(set.set_field(0, "number", "A-101"), "a hand-typed number is kept")
	assert(set.set_field(2, "number", "A-103"))
	set.renumber()
	assert(set.numbers() == ["L1.1", "L1.2", "L1.3"], str(set.numbers()))


func test_a_field_that_is_not_a_field_is_refused() -> void:
	var set: DraftSheetSet = _set_()
	assert(not set.set_field(0, "colour", "blue"), "there is no such thing on a sheet")
	assert(not set.set_field(4, "title", "x"), "and no such sheet")
	assert(not set.set_field(0, "scale", "big"), "a scale is a number")
	assert(not set.set_field(0, "legend", "yes"), "a flag is a flag")
	assert(set.set_field(0, "title", "Layout plan"))
	assert(set.sheet(0)["title"] == "Layout plan")
	assert(set.set_field(0, "scale", 200.0))
	assert(set.sheet(0)["scale"] == 200.0)


func test_a_portrait_sheet_says_so_in_its_own_line() -> void:
	var set: DraftSheetSet = _set_()
	assert(set.set_field(0, "portrait", true))
	assert(set.describe(0).contains("A3 portrait"), set.describe(0))
	assert(set.set_field(0, "revision", "B"))
	assert(set.describe(0).contains("rev B"), set.describe(0))


# --- what a sheet plots with ----------------------------------------------------------


func test_one_sheet_lays_its_own_paper_over_the_drawing() -> void:
	var set: DraftSheetSet = _set_()
	set.add("Planting plan")
	assert(set.set_field(1, "sheet", "A2"))
	assert(set.set_field(1, "scale", 200.0))
	assert(set.set_field(1, "legend", false))
	assert(set.set_field(1, "portrait", true))
	assert(set.set_field(1, "revision", "C"))
	var options: Dictionary = set.options_for(1, {"project": "Riverbend", "pen_table": null})
	assert(options["sheet"] == "A2", "the sheet's paper is what plots")
	assert(options["scale"] == 200.0)
	assert(options["legend"] == false)
	assert(options["portrait"] == true, "and a portrait sheet plots portrait")
	assert(options["drawing"] == "Planting plan", "the sheet titles the drawing")
	assert(options["revision"] == "C")
	assert(options["number"] == "L1.2")
	assert(options["project"] == "Riverbend", "what the drawing already said is left alone")
	assert(options.has("pen_table"))


func test_a_project_and_a_date_are_the_whole_set_s_and_are_stated_or_absent() -> void:
	var set: DraftSheetSet = _set_()
	var bare: Dictionary = set.options_for(0, {})
	# Nothing stated is not an instruction to draw nothing: the plotter's own defaults stand.
	assert(not bare.has("project"), "an unstated project is left out rather than blanked")
	assert(not bare.has("date"), "and so is an unstated date, which means today")
	set.project = "Riverbend"
	set.date = "2026-05-04"
	var stated: Dictionary = set.options_for(0, {})
	assert(stated["project"] == "Riverbend")
	assert(stated["date"] == "2026-05-04")
	set.add("Planting plan")
	var second: Dictionary = set.options_for(1, {})
	assert(second["project"] == "Riverbend", "every sheet of the set is the same job on one date")
	assert(second["date"] == "2026-05-04", "and the same date: a set is one transmittal")


func test_options_for_a_sheet_that_is_not_there_leaves_the_options_alone() -> void:
	var set: DraftSheetSet = _set_()
	var base := {"sheet": "A4", "scale": 50.0}
	var options: Dictionary = set.options_for(9, base)
	assert(options["sheet"] == "A4", "there is no such sheet, so nothing is laid over")
	assert(options["scale"] == 50.0)


# --- what a file keeps ----------------------------------------------------------------


func test_a_set_round_trips_through_the_drawing() -> void:
	var set: DraftSheetSet = _set_()
	set.add("Planting plan")
	set.set_field(1, "revision", "B")
	set.set_field(1, "portrait", true)
	set.set_field(0, "number", "A-101")
	set.project = "Riverbend"
	set.date = "2026-05-04"
	set.select(1)
	var back: DraftSheetSet = SheetSetScript.from_dict(JSON.parse_string(JSON.stringify(set.to_dict())))
	assert(back.count() == 2)
	assert(back.titles() == ["Landscaping Plan", "Planting plan"], str(back.titles()))
	assert(back.numbers() == ["A-101", "L1.2"], str(back.numbers()))
	assert(back.current_index() == 1, "which sheet is in hand is part of the set")
	assert(bool(back.sheet(1)["portrait"]), "and so is which way its paper is turned")
	assert(back.sheet(1)["revision"] == "B")
	assert(back.project == "Riverbend")
	assert(back.date == "2026-05-04")


func test_a_file_with_no_sheets_gets_one_rather_than_nothing() -> void:
	# A drawing from before sets existed, and a file that has been damaged: both are one sheet at A3
	# rather than a set of none, which is the drawing this app plotted before sets existed.
	for junk: Variant in [null, {}, "not a set", {"sheets": []}, {"sheets": "no"}]:
		var set: DraftSheetSet = SheetSetScript.from_dict(junk)
		assert(set.count() == 1, "one sheet: %s" % str(junk))
		assert(set.sheet(0)["sheet"] == "A3")


func test_a_sheet_record_that_is_not_a_sheet_is_dropped_rather_than_invented() -> void:
	var set: DraftSheetSet = SheetSetScript.from_dict({
		"current": 5,
		"sheets": [{"title": "Layout"}, "rubbish", {"title": "Planting", "scale": 200.0}],
	})
	# A record that is not an object cannot say what paper it is on, so it is dropped rather than turned
	# into a sheet nobody named.
	assert(set.count() == 2, "the rubbish record is not a sheet: %d" % set.count())
	assert(set.titles() == ["Layout", "Planting"], str(set.titles()))
	assert(set.current_index() == 1, "a current sheet past the end lands on the last one")
	assert(set.sheet(1)["scale"] == 200.0, "a scale that arrived from JSON as a number is still a number")
	assert(set.sheet(0)["sheet"] == "A3", "and a record with no paper is on the default sheet")


# --- paper ----------------------------------------------------------------------------


func test_a_portrait_sheet_is_the_same_sheet_turned() -> void:
	var landscape: Vector2 = PlotScale.sheet_size_mm("A3")
	var portrait: Vector2 = PlotScale.sheet_size_mm("A3", true)
	assert(landscape == Vector2(420.0, 297.0), str(landscape))
	assert(portrait == Vector2(297.0, 420.0), str(portrait))
	assert(is_equal_approx(portrait.x * portrait.y, landscape.x * landscape.y), "the same area of paper")
	var box: Vector2 = PlotScale.sheet_size_points("A3", true)
	assert(is_equal_approx(box.x, PlotScale.points_from_mm(297.0)), str(box))
	assert(is_equal_approx(box.y, PlotScale.points_from_mm(420.0)))
	assert(PlotScale.printable_size_mm("A3", 15.0, true).x < PlotScale.printable_size_mm("A3").x,
		"a turned sheet has its margin on the other edge")