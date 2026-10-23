extends Node
## The closeout page: the punch list, the hand-over date and the warranty (phase 12).
##
## The page is built **off-tree**, which is how every page in this project is tested: no window is
## shown and no `_ready` runs, so what is under test is what the page hands the desk and what it reads
## back. Three things are checked beyond the acts themselves. The buttons beside an item are **live
## only for the acts its state is ready for**, so the check an office forgets cannot be skipped
## silently. A refusal is **said on the page** rather than thrown. And the page holds no arithmetic of
## its own: every line is a line the report or the record wrote.

const PageScript := preload("res://scripts/closeout_window.gd")
const DeskScript := preload("res://scripts/biz/closeout_desk.gd")
const JobDeskScript := preload("res://scripts/biz/job_desk.gd")
const JobScript := preload("res://scripts/biz/job.gd")
const ItemScript := preload("res://scripts/biz/punch_item.gd")

const HANDED_OVER := "2026-07-20"


## A desk with one job, and the page pointed at it. Nothing is added to the tree.
func _set_up() -> Array:
	var jobs := JobDeskScript.new()
	var contracted: Job = JobScript.new("J1")
	contracted.name = "Riverside back garden"
	jobs.add_job(contracted)
	var desk := DeskScript.new()
	desk.bind(jobs)
	var page := PageScript.new()
	page.build()
	page.bind(desk)
	return [page, desk]


## Each test frees the window it built, which is what the other page tests do: a `Window` is a tree
## with a viewport, and letting one live to engine exit is a leaked resource.
func _free(page: CloseoutWindow) -> void:
	page.free()


# --- what the page is ---------------------------------------------------------------------------


func test_the_page_has_the_controls_a_page_about_finishing_a_job_has() -> void:
	var pair: Array = _set_up()
	var page: CloseoutWindow = pair[0]
	assert(page.title == "Finishing the job: the punch list and the warranty")
	assert(page.min_size == PageScript.SIZE)
	assert(page.row_count() == 0, "no items on a job nothing has been said about")
	assert(page.claim_row_count() == 0)
	assert(page.buttons_are_focus_free(), "no button takes the keyboard from the drawing")
	_free(page)


func test_the_page_opens_saying_what_to_do_with_it() -> void:
	var pair: Array = _set_up()
	var page: CloseoutWindow = pair[0]
	assert(page.selected_job() == "J1", "the only job is the one in hand")
	assert(page.status_text().contains("Walk the job"), page.status_text())
	assert(page.hint_text().contains("substantial completion has not been stated"), page.hint_text())
	assert(page.summary_text().contains("nothing on the punch list"), page.summary_text())
	assert(page.warranty_text() == "no warranty has been stated for this job", page.warranty_text())
	_free(page)


func test_building_the_page_twice_builds_it_once() -> void:
	var pair: Array = _set_up()
	var page: CloseoutWindow = pair[0]
	page.build()
	assert(page.get_child_count() == 1, "one column, built once: %d" % page.get_child_count())
	_free(page)


func test_a_page_with_no_desk_at_all_is_still_a_page() -> void:
	var page := PageScript.new()
	page.build()
	assert(page.selected_job() == "", "no job to pick")
	assert(page.summary_text() == "No job is picked.")
	assert(page.hint_text().contains("Pick a job"), page.hint_text())
	assert(page.status_text().contains("No job has been started yet"), page.status_text())
	_free(page)


# --- the punch list -----------------------------------------------------------------------------


func test_an_item_raised_on_the_page_is_on_the_list_it_draws() -> void:
	var pair: Array = _set_up()
	var page: CloseoutWindow = pair[0]
	var desk: CloseoutDesk = pair[1]
	page.set_item_fields("back patio, north edge", "paver out of level", "the paving crew", "Dana")
	page._on_raise()
	assert(desk.items.size() == 1)
	assert(desk.item("PL-1").who == "the paving crew", "the trade it was handed to")
	assert(page.row_count() == 1)
	assert(page.item_texts()[0].contains("back patio, north edge: paver out of level"), page.item_texts()[0])
	assert(page.status_text() == "PL-1 is on the list.", page.status_text())
	assert(page.summary_text().contains("1 job in closeout"), page.summary_text())
	_free(page)


func test_an_item_the_desk_refuses_says_why_on_the_page_and_is_not_on_the_list() -> void:
	var pair: Array = _set_up()
	var page: CloseoutWindow = pair[0]
	page.set_item_fields("", "paver out of level", "", "Dana")
	page._on_raise()
	assert(page.row_count() == 0, "nothing reached the list")
	assert(page.status_text().contains("has to say where it is"), page.status_text())
	_free(page)


func test_the_buttons_beside_an_item_are_live_only_for_the_next_step() -> void:
	var pair: Array = _set_up()
	var page: CloseoutWindow = pair[0]
	var desk: CloseoutDesk = pair[1]
	desk.raise_item("J1", "back patio", "paver out of level", "Dana", "2026-07-06")
	page.refresh()
	var row: Node = page.row_for("PL-1")
	assert(row != null, "the item has a row of its own")
	assert(not page.button_in(row, "Fix").disabled, "an open item can be fixed")
	assert(page.button_in(row, "Accept").disabled, "and nothing has been fixed to check")
	assert(page.button_in(row, "Reject").disabled)
	assert(not page.button_in(row, "Take off").disabled, "but it can be taken off the list")
	desk.fix_item("PL-1", "2026-07-14")
	page.refresh()
	assert(page.button_in(page.row_for("PL-1"), "Fix").disabled, "it has been fixed")
	assert(not page.button_in(page.row_for("PL-1"), "Accept").disabled, "and now it wants checking")
	assert(not page.button_in(page.row_for("PL-1"), "Reject").disabled)
	desk.accept_item("PL-1", "Marc", "2026-07-16")
	page.refresh()
	assert(page.button_in(page.row_for("PL-1"), "Accept").disabled, "and a closed item wants nothing")
	assert(page.button_in(page.row_for("PL-1"), "Take off").disabled)
	_free(page)


func test_the_three_steps_are_reached_through_the_page() -> void:
	var pair: Array = _set_up()
	var page: CloseoutWindow = pair[0]
	var desk: CloseoutDesk = pair[1]
	desk.raise_item("J1", "back patio", "paver out of level", "Dana", "2026-07-06")
	page.refresh()
	page._on_fix("PL-1")
	assert(desk.item("PL-1").is_fixed())
	assert(page.status_text() == "PL-1 is fixed and waiting to be checked.", page.status_text())
	assert(page.hint_text().contains("1 item fixed and waiting to be checked"), page.hint_text())
	page.set_check_by("Marc")
	page._on_accept("PL-1")
	assert(desk.item("PL-1").is_closed())
	assert(desk.item("PL-1").accepted_by == "Marc", "the check carries the name typed on the page")
	assert(page.status_text() == "PL-1 is closed: the check passed.", page.status_text())
	_free(page)


func test_a_rejection_needs_the_reason_field_the_page_offers() -> void:
	var pair: Array = _set_up()
	var page: CloseoutWindow = pair[0]
	var desk: CloseoutDesk = pair[1]
	desk.raise_item("J1", "back patio", "paver out of level", "Dana", "2026-07-06")
	desk.fix_item("PL-1", "2026-07-14")
	page.refresh()
	page.set_check_by("Marc")
	page._on_reject("PL-1")
	assert(desk.item("PL-1").is_fixed(), "nothing happened without a reason")
	assert(page.status_text() == "rejecting takes a reason", page.status_text())
	page.set_why("the same corner is still proud")
	page._on_reject("PL-1")
	assert(desk.item("PL-1").is_open(), "and with one, the item is back on the list")
	assert(page.status_text() == "PL-1 is back on the list.", page.status_text())
	assert(page.item_texts()[0].contains("rejected 1 time"), page.item_texts()[0])
	_free(page)


func test_taking_an_item_off_the_list_through_the_page() -> void:
	var pair: Array = _set_up()
	var page: CloseoutWindow = pair[0]
	var desk: CloseoutDesk = pair[1]
	desk.raise_item("J1", "back patio", "paver out of level", "Dana", "2026-07-06")
	page.refresh()
	page.set_check_by("Dana")
	page.set_why("the client asked for it to be left as it is")
	page._on_withdraw("PL-1")
	assert(desk.item("PL-1").is_withdrawn())
	assert(page.status_text().contains("off the list"), page.status_text())
	assert(
		page.summary_text().contains("the punch list is done: 1 item closed (1 withdrawn)"),
		"and it stops counting: %s" % page.summary_text()
	)
	_free(page)


# --- the hand-over date and the warranty --------------------------------------------------------


func test_the_date_is_stated_through_the_page_and_the_warranty_follows_it() -> void:
	var pair: Array = _set_up()
	var page: CloseoutWindow = pair[0]
	var desk: CloseoutDesk = pair[1]
	page.set_terms_fields(["plant material"], "12", HANDED_OVER, "")
	page._on_state_warranty()
	assert(page.status_text().contains("has not been handed over yet"), page.status_text())
	page.set_completion_fields(HANDED_OVER, "Dana")
	page._on_state_completion()
	assert(desk.completed_on("J1") == HANDED_OVER)
	assert(page.status_text() == "The garden was handed over on 2026-07-20.", page.status_text())
	page._on_state_warranty()
	assert(desk.has_warranty("J1"), "and now the warranty can start")
	assert(page.status_text().contains("12 months from 2026-07-20"), page.status_text())
	assert(page.warranty_text().contains("so until 2027-07-20"), page.warranty_text())
	_free(page)


func test_the_coverage_boxes_show_the_term_and_state_a_new_one() -> void:
	var pair: Array = _set_up()
	var page: CloseoutWindow = pair[0]
	var desk: CloseoutDesk = pair[1]
	desk.state_completion("J1", HANDED_OVER, "Dana")
	desk.state_warranty("J1", ["plant material"], 12, HANDED_OVER)
	page.refresh()
	assert(page.covered_parts() == ["plant material"], str(page.covered_parts()))
	page.set_terms_fields(["plant material", "workmanship"], "24", HANDED_OVER, "damage by others; ")
	assert(page.excluded_lines() == ["damage by others"], "the blank sentence is dropped")
	page._on_state_warranty()
	assert(desk.warranty_for("J1").parts.size() == 2)
	assert(int(desk.warranty_for("J1").months) == 24)
	assert(desk.warranty_for("J1").excludes == ["damage by others"])
	assert(page.warranty_text().contains("not covering damage by others"), page.warranty_text())
	_free(page)


func test_a_term_nobody_meant_is_refused_with_the_parts_it_could_cover() -> void:
	var pair: Array = _set_up()
	var page: CloseoutWindow = pair[0]
	var desk: CloseoutDesk = pair[1]
	desk.state_completion("J1", HANDED_OVER, "Dana")
	page.refresh()
	page.set_terms_fields([], "12", HANDED_OVER, "")
	page._on_state_warranty()
	assert(page.status_text() == "a warranty has to cover something", page.status_text())
	page.set_terms_fields(["plant material"], "600", HANDED_OVER, "")
	page._on_state_warranty()
	assert(page.status_text().contains("between 1 and 120"), page.status_text())
	assert(not desk.has_warranty("J1"), "and nothing was stated")
	_free(page)


# --- the claims ---------------------------------------------------------------------------------


func test_a_claim_is_filed_and_answered_through_the_page() -> void:
	var pair: Array = _set_up()
	var page: CloseoutWindow = pair[0]
	var desk: CloseoutDesk = pair[1]
	desk.state_completion("J1", HANDED_OVER, "Dana")
	desk.state_warranty("J1", ["plant material"], 12, HANDED_OVER)
	page.refresh()
	page.set_claim_fields("the maple died", "the client")
	page._on_file_claim()
	assert(desk.claim_rows("J1").size() == 1)
	assert(page.claim_row_count() == 1)
	assert(page.status_text() == "WC-1 is filed against the warranty.", page.status_text())
	assert(page.claim_texts()[0].contains("the maple died"), page.claim_texts()[0])
	assert(page.summary_text().contains("1 claim wanting somebody"), page.summary_text())
	_free(page)


func test_filing_a_claim_with_no_warranty_says_which() -> void:
	var pair: Array = _set_up()
	var page: CloseoutWindow = pair[0]
	page.set_claim_fields("the maple died", "the client")
	page._on_file_claim()
	assert(page.claim_row_count() == 0)
	assert(page.status_text().contains("has no warranty yet"), page.status_text())
	_free(page)


func test_the_answer_buttons_are_live_only_before_the_claim_is_answered() -> void:
	var pair: Array = _set_up()
	var page: CloseoutWindow = pair[0]
	var desk: CloseoutDesk = pair[1]
	desk.state_completion("J1", HANDED_OVER, "Dana")
	desk.state_warranty("J1", ["plant material"], 12, HANDED_OVER)
	desk.file_claim("J1", "2026-08-01", "the maple died", "the client")
	page.refresh()
	var row: Node = page.claim_row_for("WC-1")
	assert(row != null, "the claim has a row of its own")
	assert(not page.button_in(row, "Covered").disabled, "an unanswered claim wants an answer")
	assert(page.button_in(row, "Done").disabled, "and cannot be done before it is covered")
	desk.answer_claim("J1", "WC-1", "Marc", "2026-08-04", true, "the nursery replaces it")
	page.refresh()
	assert(page.button_in(page.claim_row_for("WC-1"), "Covered").disabled, "it has been answered")
	assert(not page.button_in(page.claim_row_for("WC-1"), "Done").disabled, "and now the work is owed")
	desk.finish_claim("J1", "WC-1", "2026-08-06", "replaced")
	page.refresh()
	assert(page.button_in(page.claim_row_for("WC-1"), "Done").disabled, "and then it is finished")
	_free(page)


func test_a_claim_is_answered_with_its_reason_and_put_right_through_the_page() -> void:
	var pair: Array = _set_up()
	var page: CloseoutWindow = pair[0]
	var desk: CloseoutDesk = pair[1]
	desk.state_completion("J1", HANDED_OVER, "Dana")
	desk.state_warranty("J1", ["plant material"], 12, HANDED_OVER)
	desk.file_claim("J1", "2026-08-01", "the maple died", "the client")
	page.refresh()
	page.set_check_by("Marc")
	page._on_cover("WC-1")
	assert(page.status_text() == "answering takes a reason", "an answer with no reason is refused")
	page.set_why("the nursery replaces plant material in the first season")
	page._on_cover("WC-1")
	var claim: WarrantyClaim = desk.warranty_for("J1").claim("WC-1")
	assert(claim.is_answered() and claim.covered)
	assert(claim.answer_why == "the nursery replaces plant material in the first season")
	assert(claim.answered_by == "Marc")
	assert(page.status_text() == "claim WC-1 is covered.", page.status_text())
	page._on_done("WC-1")
	assert(claim.is_done(), "and the page can say the work is done")
	assert(desk.claims_needing_attention() == 0)
	_free(page)


func test_a_claim_refused_on_the_page_is_finished_by_that_answer() -> void:
	var pair: Array = _set_up()
	var page: CloseoutWindow = pair[0]
	var desk: CloseoutDesk = pair[1]
	desk.state_completion("J1", HANDED_OVER, "Dana")
	desk.state_warranty("J1", ["workmanship"], 12, HANDED_OVER)
	desk.file_claim("J1", "2026-08-01", "the gate sags", "the client")
	page.refresh()
	page.set_check_by("Marc")
	page.set_why("the client's own gate, not ours")
	page._on_refuse("WC-1")
	assert(page.status_text() == "claim WC-1 is not covered.", page.status_text())
	assert(desk.claims_needing_attention() == 0, "nothing is owed on it")
	assert(page.claim_texts()[0].contains("not covered"), page.claim_texts()[0])
	_free(page)


# --- the page as a whole ------------------------------------------------------------------------


func test_choosing_another_desk_starts_the_page_line_again() -> void:
	var pair: Array = _set_up()
	var page: CloseoutWindow = pair[0]
	page._on_raise()
	assert(not page.status_text().is_empty(), "something was said")
	page.bind(DeskScript.new())
	assert(page.status_text().contains("No job has been started yet"), page.status_text())
	assert(page.selected_job() == "", "and the desk it is now pointed at has no jobs")
	_free(page)


func test_closing_the_page_says_so_once() -> void:
	var pair: Array = _set_up()
	var page: CloseoutWindow = pair[0]
	var said: Array[int] = [0]
	page.closed.connect(func() -> void: said[0] += 1)
	page._on_close_requested()
	assert(said[0] == 1, "the window was closed")
	assert(not page.visible)
	page._on_close_requested()
	assert(said[0] == 2, "and closing it again is another close, not a silence")
	_free(page)


func test_every_act_announces_itself_so_the_menu_line_is_not_stale() -> void:
	var pair: Array = _set_up()
	var page: CloseoutWindow = pair[0]
	var seen: Array[int] = [0]
	page.closeout_changed.connect(func() -> void: seen[0] += 1)
	page.set_item_fields("back patio", "paver out of level", "", "Dana")
	page._on_raise()
	assert(seen[0] == 1, "raising an item")
	page._on_fix("PL-1")
	assert(seen[0] == 2, "fixing it")
	page.set_check_by("Marc")
	page._on_accept("PL-1")
	assert(seen[0] == 3, "checking it")
	page.set_item_fields("", "nothing", "", "Dana")
	page._on_raise()
	assert(seen[0] == 3, "and a refusal announces nothing, because nothing changed")
	_free(page)