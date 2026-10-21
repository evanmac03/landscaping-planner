extends Node
## Tests for the presentation diagnostics (specification 11.3).
##
## The report is what a person reads to find out why a picture came out wrong, so what matters is that
## it says the *right* things: that a layer deliberately not washed is silent rather than noisy, that a
## layer the tables have never heard of is named along with the file to change, that a layer nobody has
## drawn on is not reported at all, and that the same drawing gives the same report twice.

const Doc := preload("res://scripts/draft/draft_document.gd")
const Ent := preload("res://scripts/draft/draft_entity.gd")
const Layer := preload("res://scripts/draft/draft_layer.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const Diag := preload("res://scripts/vis/vis_diagnostics.gd")

## A layer the two tables have never heard of. This is the real gap the report exists to find: not a
## layer that will not wash, but a layer nobody has decided about.
const POND := &"450-NEW-POND"


## A drawing with something on the hardscape, the bed and the callout layers.
func _drawing() -> DraftDocument:
	var doc := Doc.new()
	doc.add(Ent.make_line(Vector2(0, 0), Vector2(6, 0)), LayerSet.NEW_HARDSCAPE)
	doc.add(Ent.make_polyline(PackedVector2Array([
		Vector2(0, 2), Vector2(6, 2), Vector2(6, 5), Vector2(0, 5),
	]), true), LayerSet.NEW_BED)
	doc.add(Ent.make_text(Vector2(1, 1), "valley gutter"), LayerSet.CALLOUT)
	return doc


## Put a layer on the drawing that the tables do not know, with geometry on it.
func _with_a_pond(doc: DraftDocument) -> DraftDocument:
	var extra := Layer._new()
	extra.name = POND
	extra.purpose = "A pond"
	doc.layers.add(extra)
	doc.add(Ent.make_polyline(PackedVector2Array([
		Vector2(0, 6), Vector2(3, 6), Vector2(3, 8), Vector2(0, 8),
	]), true), POND)
	return doc


func _severities(findings: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for finding: Dictionary in findings:
		out.append(String(finding["severity"]))
	return out


# --- what a healthy drawing reports -----------------------------------------------------------


func test_a_healthy_drawing_has_nothing_to_fix() -> void:
	var doc := _drawing()
	var findings: Array[Dictionary] = Diag.report(doc, doc.layers)
	assert(Diag.problems(findings).is_empty(), "nothing to fix: %s" % Diag.report_text(findings))
	assert(Diag.count_of(findings, Diag.ERROR) == 0)
	assert(Diag.count_of(findings, Diag.WARNING) == 0)


func test_a_layer_that_is_deliberately_flat_is_a_note_and_not_a_problem() -> void:
	# The callout layer carries geometry, plots, and is in neither table's WASHES nor SOLIDS - the
	# tables record why it is flat, which is a decision and not a gap.
	var doc := _drawing()
	var findings: Array[Dictionary] = Diag.report(doc, doc.layers)
	var about: Array[Dictionary] = Diag.mentions(findings, LayerSet.CALLOUT)
	assert(about.size() == 1, "the callout layer is mentioned once, got %d" % about.size())
	assert(String(about[0]["severity"]) == Diag.NOTE, "and as a note: %s" % about[0]["severity"])
	assert(String(about[0]["what"]).contains("builds no solid"), "naming what it is flat about: %s" % about[0]["what"])
	# Its reason is the table's own sentence, not one this module made up.
	assert(String(about[0]["what"]).contains("An annotation"), "quoted from the table: %s" % about[0]["what"])


# --- the gap the report exists to find --------------------------------------------------------


func test_a_layer_the_tables_have_never_heard_of_is_a_warning_naming_the_file() -> void:
	var doc := _with_a_pond(_drawing())
	var findings: Array[Dictionary] = Diag.report(doc, doc.layers)
	var about: Array[Dictionary] = Diag.mentions(findings, String(POND))
	assert(about.size() == 2, "a pond layer has two things wrong with it, got %d" % about.size())
	assert(Diag.count_of(findings, Diag.WARNING) == 2, "both are warnings")
	for finding: Dictionary in about:
		assert(String(finding["severity"]) == Diag.WARNING, "warnings, not notes: %s" % finding["severity"])
		assert(String(finding["what"]).contains(String(POND)), "named: %s" % finding["what"])
	# One names the wash table and one the solid table, so a person knows which script to open.
	var wheres: Array[String] = []
	for finding: Dictionary in about:
		wheres.append(String(finding["where"]))
	assert(wheres.has("scripts/vis/wash_table.gd"), "the wash table is named: %s" % str(wheres))
	assert(wheres.has("scripts/vis/solid_table.gd"), "and the solid table: %s" % str(wheres))


func test_a_gap_says_what_to_do_about_it_rather_than_just_that_it_is_one() -> void:
	var doc := _with_a_pond(_drawing())
	var findings: Array[Dictionary] = Diag.report(doc, doc.layers)
	var about: Array[Dictionary] = Diag.mentions(findings, String(POND))
	for finding: Dictionary in about:
		var what := String(finding["what"])
		assert(what.contains("add it to"), "it says what to add it to: %s" % what)
		assert(what.contains("or record why"), "or that a reason would do instead: %s" % what)


func test_a_layer_nobody_has_drawn_on_is_not_reported_at_all() -> void:
	# A layer with no geometry cannot be missing anything, and reporting every unused layer would
	# bury the one that matters.
	var doc := Doc.new()
	var extra := Layer._new()
	extra.name = POND
	doc.layers.add(extra)
	var findings: Array[Dictionary] = Diag.report(doc, doc.layers)
	assert(Diag.mentions(findings, String(POND)).is_empty(), "the empty pond layer is silent")
	assert(findings.is_empty(), "and so is a drawing with nothing on it at all: %s" % Diag.report_text(findings))


func test_a_layer_that_does_not_plot_is_not_a_picture() -> void:
	# Specification 4.2: construction and tracing layers are not drawn on.
	var doc := Doc.new()
	doc.add(Ent.make_line(Vector2(0, 0), Vector2(3, 0)), LayerSet.GUIDES)
	var findings: Array[Dictionary] = Diag.report(doc, doc.layers)
	assert(Diag.mentions(findings, LayerSet.GUIDES).is_empty(), "a tracing layer is skipped")


# --- the order a person reads them in ---------------------------------------------------------


func test_the_report_is_most_serious_first() -> void:
	var doc := _with_a_pond(_drawing())
	var findings: Array[Dictionary] = Diag.report(doc, doc.layers)
	var ranks: Array[int] = []
	for finding: Dictionary in findings:
		ranks.append(Diag.severity_rank(String(finding["severity"])))
	for index in ranks.size() - 1:
		assert(ranks[index] <= ranks[index + 1], "severities run downhill: %s" % str(ranks))


func test_an_unknown_severity_sorts_last_rather_than_first() -> void:
	assert(Diag.severity_rank(Diag.ERROR) == 0)
	assert(Diag.severity_rank(Diag.WARNING) == 1)
	assert(Diag.severity_rank(Diag.NOTE) == 2)
	assert(Diag.severity_rank("catastrophe") == Diag.SEVERITY_ORDER.size(), "a typo cannot outrank an error")


func test_the_same_drawing_gives_the_same_report_twice() -> void:
	var doc := _with_a_pond(_drawing())
	var once: Array[Dictionary] = Diag.report(doc, doc.layers)
	var twice: Array[Dictionary] = Diag.report(doc, doc.layers)
	assert(once.size() == twice.size())
	for index in once.size():
		assert(String(once[index]["what"]) == String(twice[index]["what"]), "row %d is the same" % index)
	assert(Diag.report_text(once) == Diag.report_text(twice), "and the whole page reads the same")


# --- the texture maps -------------------------------------------------------------------------


func test_the_texture_findings_are_exactly_the_maps_that_are_not_on_disk() -> void:
	var doc := _drawing()
	var findings: Array[Dictionary] = Diag.report(doc, doc.layers)
	var about_textures: Array[Dictionary] = []
	for finding: Dictionary in findings:
		if String(finding["where"]).begins_with("res://resources/textures/hardscape/"):
			about_textures.append(finding)
	var missing: Array[String] = Diag.HardscapeScript.missing_paths()
	assert(about_textures.size() == missing.size(), "one finding per missing map, got %d for %d" % [
		about_textures.size(), missing.size(),
	])
	for finding: Dictionary in about_textures:
		# A missing texture is the one thing that stops a render being right, so it is an error.
		assert(String(finding["severity"]) == Diag.ERROR, "an error: %s" % finding["severity"])
		assert(missing.has(String(finding["where"])), "and it names a path the table says is missing: %s" % finding["where"])


func test_a_solid_asking_for_a_set_nobody_has_is_an_error() -> void:
	# Every solid's material set exists in this project, so the healthy answer is that nothing is
	# said - and the check is asked of the two tables rather than of a list written out here.
	var doc := _drawing()
	var findings: Array[Dictionary] = Diag.report(doc, doc.layers)
	for set_name: String in Diag.SolidTableScript.material_sets():
		assert(Diag.HardscapeScript.has_set(set_name), "%s is a set the texture table has" % set_name)
	for finding: Dictionary in findings:
		assert(not String(finding["what"]).contains("texture set"), "nothing said: %s" % finding["what"])


# --- the shape of the report ------------------------------------------------------------------


func test_a_report_reads_as_one_line_that_counts_what_is_there() -> void:
	assert(Diag.summarise([]).begins_with("nothing to report"), "an empty report says so")
	assert(Diag.summarise([]).contains("everything it asks for"))
	var doc := _with_a_pond(_drawing())
	var findings: Array[Dictionary] = Diag.report(doc, doc.layers)
	var line := Diag.summarise(findings)
	assert(line.contains("2 warnings"), "the count is named: %s" % line)
	assert(line.contains("1 note"), "and so is the note: %s" % line)
	assert(not line.contains("error"), "and nothing is said about errors there are none of: %s" % line)


func test_a_report_text_is_the_summary_and_then_one_line_per_finding() -> void:
	var doc := _with_a_pond(_drawing())
	var findings: Array[Dictionary] = Diag.report(doc, doc.layers)
	var lines: PackedStringArray = Diag.report_text(findings).split("\n")
	assert(lines.size() == findings.size() + 1, "a heading and a line each, got %d" % lines.size())
	assert(String(lines[0]) == Diag.summarise(findings), "the first line is the summary")


func test_rows_carry_the_words_a_table_shows() -> void:
	var doc := _with_a_pond(_drawing())
	var findings: Array[Dictionary] = Diag.report(doc, doc.layers)
	var rows: Array[Dictionary] = Diag.rows(findings)
	assert(rows.size() == findings.size())
	var first: Dictionary = rows[0]
	assert(String(first["severity"]) == String(findings[0]["severity"]))
	assert(String(first["where"]) == String(findings[0]["where"]))
	assert(String(first["what"]) == String(findings[0]["what"]))
	assert(String(first["text"]).contains(String(first["what"])), "the row is a sentence: %s" % first["text"])
	assert(String(first["text"]).contains(String(first["where"])), "and names where to fix it: %s" % first["text"])
	assert(String(first["text"]).begins_with(String(first["severity"]).to_upper()), "and leads with the severity")


func test_counting_a_severity_nobody_has_is_nought() -> void:
	var findings: Array[Dictionary] = Diag.report(_drawing(), _drawing().layers)
	assert(Diag.count_of(findings, Diag.WARNING) == 0)
	assert(Diag.count_of(findings, "catastrophe") == 0)
	assert(Diag.count_of([], Diag.ERROR) == 0)


func test_problems_are_the_errors_and_warnings_and_not_the_notes() -> void:
	var doc := _with_a_pond(_drawing())
	var findings: Array[Dictionary] = Diag.report(doc, doc.layers)
	var problems: Array[Dictionary] = Diag.problems(findings)
	assert(problems.size() == 2, "only the two warnings: %s" % Diag.report_text(problems))
	for problem: Dictionary in problems:
		assert(String(problem["severity"]) != Diag.NOTE, "no notes among the problems")


func test_a_report_with_nothing_handed_over_still_answers() -> void:
	# A layer set with no drawing is the whole-project answer: every plotting layer counts as used.
	var findings: Array[Dictionary] = Diag.report(null, LayerSet.default_set())
	assert(not findings.is_empty(), "the layer set alone has something to say")
	assert(Diag.count_of(findings, Diag.WARNING) == 0, "and nothing is a gap in the shipped set")
	var doc := Doc.new()
	assert(Diag.report(doc, null).is_empty(), "a drawing with no layer set has nothing to say")


func test_the_describe_line_names_the_three_tables() -> void:
	var text := Diag.describe()
	assert(text.contains("washes"), text)
	assert(text.contains("solids"), text)
	assert(text.contains("texture"), text)