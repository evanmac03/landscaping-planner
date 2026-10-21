extends Node
## The estimate window: what the plan measures, what it prices at, and what goes out.
##
## Driven the way a click drives it - `build()`, then the same methods a control calls - because the
## window builds itself by hand and because a `Window` in a test is a window nobody has to look at.
##
## The rules under test are the ones that decide whether a proposal is honest:
##
## * a window with no drawing or no book **says which** rather than showing an empty table;
## * a line nothing can price is shown **where it would have been**, so a proposal that is missing a
##   patio does not look like a drawing that has no patio;
## * sending is the act that names the customer, freezes the prices, and closes the door on editing.

const WindowScript := preload("res://scripts/estimate_window.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const BookScript := preload("res://scripts/biz/cost_book.gd")

const PROPOSAL_PATH := "user://biz/proposals"


func _drawing() -> DraftDocument:
	var document: DraftDocument = Document.new()
	document.add(Entity.make_rectangle(Vector2(0, 0), Vector2(6, 4)), LayerSet.NEW_HARDSCAPE)
	document.add(Entity.make_circle(Vector2(20, 0), 1.5), LayerSet.NEW_PLANTING)
	return document


func _window(document: DraftDocument = null) -> EstimateWindow:
	var window: EstimateWindow = WindowScript.new()
	window.build()
	window.bind(document if document != null else _drawing())
	return window


func _clean_proposals() -> void:
	var dir: DirAccess = DirAccess.open(PROPOSAL_PATH)
	if dir == null:
		return
	for name: String in dir.get_files():
		dir.remove(name)


# --- what it shows -------------------------------------------------------------------------


func test_the_window_has_the_three_tables_a_proposal_is_made_of() -> void:
	var window: EstimateWindow = _window()
	assert(window.tab_titles() == ["Takeoff", "Proposal", "Cost book"], str(window.tab_titles()))
	assert(window.select_tab("Proposal"), "and each can be opened by name")
	assert(window.select_tab("Cost book"), "including the last one")
	assert(not window.select_tab("Nothing"), "and a tab that is not there is not opened")
	window.free()


func test_a_drawing_with_nothing_taken_off_it_says_so() -> void:
	var window: EstimateWindow = _window()
	assert(window.takeoff_texts().is_empty(), "nothing is measured yet")
	assert(window.line_texts() == ["Nothing is priced yet."], str(window.line_texts()))
	assert(window.totals_text() == "nothing is priced yet", window.totals_text())
	assert(window.plan_status_text().contains("nothing has been taken off"), window.plan_status_text())
	assert(window.send_button_disabled(), "and there is nothing to send")
	assert(window.revision_button_disabled(), "or to revise")
	window.free()


func test_a_window_with_no_drawing_says_that_rather_than_failing() -> void:
	var window: EstimateWindow = WindowScript.new()
	window.build()
	window.bind(null)
	assert(window.plan_status_text().contains("no drawing open"), window.plan_status_text())
	var result: Dictionary = window.take_off()
	assert(not bool(result["ok"]), "and taking off the plan is refused")
	assert(window.status_text().contains("drawing"), window.status_text())
	window.free()


func test_taking_off_the_plan_fills_all_three_tables() -> void:
	var window: EstimateWindow = _window()
	window.take_off()
	assert(window.takeoff_texts().size() == 2, str(window.takeoff_texts()))
	assert(window.line_texts().size() == 2, "and the proposal has the same two lines")
	assert(window.line_texts()[0].contains("Interlock"), window.line_texts()[0])
	# The panel prints the engine's own line, so the waste the paving orders is stated on it: a line
	# that did not multiply is a line a designer would telephone about.
	assert(window.line_texts()[0].contains("+5.0% waste"), window.line_texts()[0])
	assert(window.status_text().contains("2 lines measured and 2 priced"), window.status_text())
	assert(window.totals_text().contains("subtotal"), window.totals_text())
	assert(window.status_text().contains("$"), "and it says where the job stands: %s" % window.status_text())
	# The cost book tab shows the price list the lines were priced from, and reading it is all it
	# does: editing a price list is a dock, not a proposal.
	assert(window.book_texts().size() > 10, "the book is listed: %d" % window.book_texts().size())
	assert(window.book_texts()[0].contains("[HARDSCAPE]") or window.book_texts()[0].contains("["),
		"each item names the code it costs to: %s" % window.book_texts()[0])
	assert(window.note_texts()[1].contains("read from"), window.note_texts()[1])
	assert(not window.send_button_disabled(), "and now there is something to send")
	window.free()


func test_a_line_nothing_can_price_is_shown_where_it_would_have_been() -> void:
	var window: EstimateWindow = _window()
	window.desk.document.add(Entity.make_circle(Vector2(40, 0), 0.2), LayerSet.IRRIGATION)
	window.desk.book.erase_item(&"irr-head-spray")
	window.desk.book.erase_item(&"irr-zone-valve")
	window.take_off()
	var unpriceable: PackedStringArray = PackedStringArray()
	for text: String in window.line_texts():
		if text.begins_with("not priced:"):
			unpriceable.append(text)
	assert(unpriceable.size() == 1, "the refusal is shown in the proposal's own list: %s" % str(window.line_texts()))
	assert(String(unpriceable[0]).contains("IRRIGATION"), "naming the layer: %s" % String(unpriceable[0]))
	window.free()


# --- the tax, the totals, and sending -------------------------------------------------------


func test_the_tax_dropdown_charges_the_code_it_shows() -> void:
	var window: EstimateWindow = _window()
	window.take_off()
	assert(window.selected_tax() == "NONE", "an estimate starts with no tax charged")
	assert(window.tax_texts()[0].contains("No tax"), str(window.tax_texts()))
	assert(window.choose_tax(&"HST-ON"), "the dropdown offers the shipped codes")
	assert(window.selected_tax() == "HST-ON", window.selected_tax())
	assert(window.desk.estimate.tax(window.desk.book).cents > 0, "and the tax is charged")
	assert(window.status_text().contains("HST 13%"), window.status_text())
	assert(window.totals_text().contains("HST 13%"), window.totals_text())
	assert(not window.choose_tax(&"NOT-A-CODE"), "a code that is not a code is not choosable")
	window.free()


func test_sending_names_the_customer_and_freezes_what_went_out() -> void:
	var window: EstimateWindow = _window()
	window.take_off()
	window.send_it()
	assert(window.status_text().contains("needs somebody"), window.status_text())
	assert(not window.desk.estimate.is_frozen(), "nothing went out")
	window.set_recipient("Jane Doe")
	window.send_it()
	assert(window.desk.estimate.is_frozen(), "it went out: %s" % window.status_text())
	assert(window.desk.estimate.customer.get("name", "") == "Jane Doe", str(window.desk.estimate.customer))
	assert(window.status_text().contains("Jane Doe"), window.status_text())
	assert(window.send_button_disabled(), "and it cannot be sent twice")
	assert(window.send_hint().contains("already gone"), window.send_hint())
	assert(not window.revision_button_disabled(), "but it can be revised")
	window.new_revision()
	assert(window.desk.estimate.revision == 1, "revision 1: %s" % window.status_text())
	assert(not window.desk.estimate.is_frozen(), "and it is open again")
	assert(window.revision_button_disabled(), "with nothing to revise until it goes out again")
	window.free()


func test_writing_the_proposal_says_where_it_went() -> void:
	var window: EstimateWindow = _window()
	window.take_off()
	window.set_recipient("Jane Doe")
	window.send_it()
	window.write_proposal()
	assert(window.status_text().begins_with("written to "), window.status_text())
	var path: String = window.status_text().substr("written to ".length()).strip_edges()
	assert(FileAccess.file_exists(path), "there is a file at %s" % path)
	assert(FileAccess.open(path, FileAccess.READ).get_as_text().contains("Jane Doe"), "with the customer")
	_clean_proposals()
	window.free()


func test_checking_the_numbers_says_whether_they_foot() -> void:
	var window: EstimateWindow = _window()
	window.check_numbers()
	assert(window.status_text().contains("nothing is priced yet"), window.status_text())
	window.take_off()
	window.check_numbers()
	assert(window.status_text().contains("foot"), window.status_text())
	assert(window.status_text().contains("gross margin"), window.status_text())
	# A line the book cannot price is the one thing that makes the check unclean, and the window says
	# what it is rather than only that there is something.
	window.desk.document.add(Entity.make_circle(Vector2(40, 0), 0.2), LayerSet.IRRIGATION)
	window.desk.book.erase_item(&"irr-head-spray")
	window.desk.book.erase_item(&"irr-zone-valve")
	window.take_off()
	window.check_numbers()
	assert(window.status_text().contains("1 thing to fix"), window.status_text())
	assert(window.status_text().contains("no price"), window.status_text())
	window.free()


# --- starting a job from it ---------------------------------------------------------------------


## The estimate window keeps no jobs: a job is where crews, days and time live, and that is the job
## desk's. So this is a hand-off, and what is under test is that it happens once an estimate exists,
## that it says what it handed over, and that it is refused - in words - before one does.

var _handed: Estimate = null


func _note_job(estimate: Estimate) -> void:
	_handed = estimate


func test_the_job_button_is_dead_until_something_is_priced() -> void:
	var window: EstimateWindow = _window()
	assert(window.start_job_button_disabled(), "there is nothing to make a job of yet")
	assert(window.start_job_hint().contains("nothing is priced yet"), window.start_job_hint())
	assert(not bool(window.start_job()["ok"]))
	assert(String(window.start_job()["reason"]).contains("priced"))
	# The button's own path words the refusal on the status line.
	window._on_start_job()
	assert(window.status_text().contains("No job was started"), window.status_text())
	window.free()


func test_starting_a_job_hands_the_estimate_over_with_what_it_holds() -> void:
	var window: EstimateWindow = _window()
	window.take_off()
	assert(not window.start_job_button_disabled(), "there is a priced estimate now")
	assert(window.start_job_hint().is_empty())
	window.job_started.connect(_note_job)
	var started: Dictionary = window.start_job()
	assert(bool(started["ok"]), String(started["reason"]))
	assert(_handed == window.desk.estimate, "the estimate itself, not a copy of its numbers")
	assert(_handed.line_count() > 0)
	assert(window.status_text().contains("a job was started from this estimate"), window.status_text())
	assert(window.status_text().contains("revision 0"), window.status_text())
	window.free()