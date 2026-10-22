extends Node
## The closeout desk and the report it hands out: the punch list, the hand-over date and the warranty
## (phase 12).
##
## Four properties are under test. A punch item belongs to **a job the desk actually has**, so a list
## against a job nobody can look up is refused rather than kept. A hand-over date is **stated again
## rather than edited**, so a wrong date is correctable and moving it is on the record. Stating the
## warranty again **keeps its claims**, so correcting a term is not a new warranty. And the report
## answers what is **outstanding** separately from what is merely **worth naming** - an open item
## stands between the job and being finished, an unanswered claim does not.

const DeskScript := preload("res://scripts/biz/closeout_desk.gd")
const JobDeskScript := preload("res://scripts/biz/job_desk.gd")
const JobScript := preload("res://scripts/biz/job.gd")
const ItemScript := preload("res://scripts/biz/punch_item.gd")
const WarrantyScript := preload("res://scripts/biz/warranty.gd")

const RAISED := "2026-07-06"
const FIXED_ON := "2026-07-14"
const HANDED_OVER := "2026-07-20"


func make_desk() -> CloseoutDesk:
	var jobs := JobDeskScript.new()
	var contracted: Job = JobScript.new("J1")
	contracted.name = "Riverside back garden"
	jobs.add_job(contracted)
	var desk := DeskScript.new()
	desk.bind(jobs)
	return desk


func _with_item() -> CloseoutDesk:
	var desk := make_desk()
	desk.raise_item("J1", "back patio, north edge", "paver out of level", "Dana", RAISED)
	return desk


# --- the punch list, through the desk ---------------------------------------------------------


func test_a_desk_with_no_jobs_cannot_take_a_punch_item() -> void:
	var loose := DeskScript.new()
	var refused: Dictionary = loose.raise_item("J1", "here", "something", "Dana", RAISED)
	assert(not bool(refused["ok"]))
	assert(String(refused["reason"]) == "there is no desk of jobs to put that against", String(refused["reason"]))
	assert(loose.items.is_empty(), "and nothing was stored")


func test_an_item_against_a_job_the_desk_does_not_have_is_refused_by_name() -> void:
	var refused: Dictionary = make_desk().raise_item("J9", "here", "something", "Dana", RAISED)
	assert(not bool(refused["ok"]))
	assert(String(refused["reason"]) == "there is no job J9", String(refused["reason"]))
	var nothing: Dictionary = make_desk().raise_item("", "here", "something", "Dana", RAISED)
	assert(not bool(nothing["ok"]))
	assert(String(nothing["reason"]).contains("needs a job"), String(nothing["reason"]))


func test_an_item_that_cannot_be_read_says_which_field_is_missing() -> void:
	var desk := make_desk()
	assert(
		String(desk.raise_item("J1", "", "something", "Dana", RAISED)["reason"]).contains("has to say where it is"),
		"a place is required"
	)
	assert(
		String(desk.raise_item("J1", "here", "", "Dana", RAISED)["reason"]).contains("has to say what is wrong"),
		"a description is required"
	)
	assert(
		String(desk.raise_item("J1", "here", "something", "", RAISED)["reason"]).contains("who raised it"),
		"a name is required"
	)
	assert(
		String(desk.raise_item("J1", "here", "something", "Dana", "July")["reason"]).contains("not a date"),
		"a date is required"
	)
	assert(desk.items.is_empty(), "and nothing was stored")


func test_the_list_is_worked_through_with_numbers_that_are_never_reused() -> void:
	var desk := _with_item()
	assert(desk.items.size() == 1)
	assert(desk.items[0].id == "PL-1")
	var second: Dictionary = desk.raise_item("J1", "front walk", "edging missing", "Dana", RAISED)
	assert(String(second["id"]) == "PL-2")
	assert(desk.next_item_id() == "PL-3")
	assert(desk.fix_item("PL-1", FIXED_ON, "lifted and re-laid")["ok"])
	assert(desk.item("PL-1").is_fixed())
	assert(desk.accept_item("PL-1", "Marc", "2026-07-16")["ok"])
	assert(desk.item("PL-1").is_closed())
	assert(desk.item("PL-1").accepted_by == "Marc")
	assert(desk.outstanding_count() == 1, "PL-2 is still open")


func test_the_acts_refuse_what_the_record_refuses_and_say_why() -> void:
	var desk := _with_item()
	assert(String(desk.fix_item("PL-9", FIXED_ON)["reason"]) == "there is no item PL-9", "no such item")
	assert(String(desk.accept_item("PL-1", "Marc", "2026-07-16")["reason"]).contains("nothing to check"))
	assert(String(desk.fix_item("PL-1", "July")["reason"]).contains("not a date"))
	assert(desk.fix_item("PL-1", FIXED_ON)["ok"])
	assert(String(desk.fix_item("PL-1", FIXED_ON)["reason"]).contains("cannot be fixed"), "already fixed")
	assert(
		String(desk.reject_item("PL-1", "Marc", "2026-07-16", "")["reason"]).contains("takes a reason"),
		"a rejection with no reason on it"
	)
	assert(
		String(desk.reject_item("PL-1", "", "2026-07-16", "still proud")["reason"]).contains("somebody's name"),
		"and one with nobody to ask"
	)
	assert(String(desk.reject_item("PL-1", "Marc", "2026-07-16", "still proud")["reason"]).is_empty())
	assert(desk.item("PL-1").state() == ItemScript.OPEN, "and the rejection put it back on the list")


func test_taking_an_item_off_through_the_desk_keeps_it_on_the_record() -> void:
	var desk := _with_item()
	assert(desk.withdraw_item("PL-1", "Dana", "2026-07-08", "the client wants it left")["ok"])
	assert(desk.items.size() == 1, "it is off the list and still on the record")
	assert(desk.item("PL-1").is_withdrawn())
	assert(not desk.withdraw_item("PL-1", "Dana", "2026-07-09", "again")["ok"], "and not twice")
	assert(desk.outstanding_count() == 0)


# --- the hand-over date ------------------------------------------------------------------------


func test_the_hand_over_date_is_stated_by_somebody_on_a_date() -> void:
	var desk := make_desk()
	assert(
		String(desk.state_completion("J1", HANDED_OVER, "")["reason"]).contains("somebody to state it"),
		"a date nobody stated"
	)
	assert(String(desk.state_completion("J1", "the 20th", "Dana")["reason"]).contains("not a date"))
	assert(String(desk.state_completion("J9", HANDED_OVER, "Dana")["reason"]).contains("no job J9"))
	assert(bool(desk.state_completion("J1", HANDED_OVER, "Dana")["ok"]))
	assert(desk.completed_on("J1") == HANDED_OVER)
	assert(desk.completed_by("J1") == "Dana")


func test_moving_the_date_needs_a_reason_and_both_dates_are_kept() -> void:
	var desk := make_desk()
	desk.state_completion("J1", HANDED_OVER, "Dana")
	assert(
		String(desk.state_completion("J1", "2026-07-24", "Dana")["reason"]).contains("needs a reason"),
		"a correction with no reason"
	)
	assert(bool(desk.state_completion("J1", "2026-07-24", "Dana", "the walk was put off a week")["ok"]))
	assert(desk.completed_on("J1") == "2026-07-24", "the new date is in force")
	var history: Array[Dictionary] = desk.completion_history("J1")
	assert(history.size() == 2, "%d statements" % history.size())
	assert(String(history[0]["at"]) == HANDED_OVER, "and the date it replaced is on the record")
	assert(String(history[0]["why"]).is_empty(), "the first statement needs nothing explained")
	assert(String(history[1]["why"]) == "the walk was put off a week")


# --- the warranty ------------------------------------------------------------------------------


func test_a_warranty_starts_at_the_hand_over_and_not_before_it() -> void:
	var desk := make_desk()
	var early: Dictionary = desk.state_warranty("J1", ["plant material"], 12, HANDED_OVER)
	assert(not bool(early["ok"]))
	assert(String(early["reason"]).contains("has not been handed over yet"), String(early["reason"]))
	assert(not desk.has_warranty("J1"))
	desk.state_completion("J1", HANDED_OVER, "Dana")
	assert(bool(desk.state_warranty("J1", ["plant material", "workmanship"], 12, HANDED_OVER)["ok"]))
	var record: Warranty = desk.warranty_for("J1")
	assert(record.ends_on() == "2027-07-20")
	assert(record.covers("plant material"))


func test_a_term_that_cannot_be_read_is_refused_with_the_parts_it_could_cover() -> void:
	var desk := make_desk()
	desk.state_completion("J1", HANDED_OVER, "Dana")
	assert(String(desk.state_warranty("J1", [], 12, HANDED_OVER)["reason"]).contains("cover something"))
	var wrong: String = String(desk.state_warranty("J1", ["the weather"], 12, HANDED_OVER)["reason"])
	assert(wrong.contains("plant material"), "the refusal names what it can cover: %s" % wrong)
	assert(
		String(desk.state_warranty("J1", ["workmanship"], 400, HANDED_OVER)["reason"]).contains("between 1 and 120"),
		"a term nobody meant"
	)
	assert(not desk.has_warranty("J1"), "and nothing was stated")


func test_stating_the_warranty_again_corrects_the_term_and_keeps_its_claims() -> void:
	var desk := make_desk()
	desk.state_completion("J1", HANDED_OVER, "Dana")
	desk.state_warranty("J1", ["plant material"], 12, HANDED_OVER)
	desk.file_claim("J1", "2026-08-01", "the maple died", "the client")
	assert(bool(desk.state_warranty("J1", ["plant material", "workmanship"], 24, HANDED_OVER)["ok"]))
	var record: Warranty = desk.warranty_for("J1")
	assert(record.parts.size() == 2, "the corrected term")
	assert(record.ends_on() == "2028-07-20")
	assert(record.claims.size() == 1, "and the claim it had already taken is still there")
	assert(desk.has_warranty("J1"))


func test_a_claim_needs_a_warranty_a_report_and_a_person() -> void:
	var desk := make_desk()
	desk.state_completion("J1", HANDED_OVER, "Dana")
	var none: Dictionary = desk.file_claim("J1", "2026-08-01", "the maple died", "the client")
	assert(not bool(none["ok"]))
	assert(String(none["reason"]).contains("has no warranty yet"), String(none["reason"]))
	desk.state_warranty("J1", ["plant material"], 12, HANDED_OVER)
	assert(String(desk.file_claim("J1", "August", "the maple died", "the client")["reason"]).contains("date"))
	assert(String(desk.file_claim("J1", "2026-08-01", "", "the client")["reason"]).contains("what failed"))
	assert(String(desk.file_claim("J1", "2026-08-01", "the maple died", "")["reason"]).contains("who reported"))
	assert(bool(desk.file_claim("J1", "2026-08-01", "the maple died", "the client")["ok"]))
	assert(desk.claim_rows("J1").size() == 1)


func test_a_claim_is_answered_and_then_put_right_through_the_desk() -> void:
	var desk := make_desk()
	desk.state_completion("J1", HANDED_OVER, "Dana")
	desk.state_warranty("J1", ["plant material"], 12, HANDED_OVER)
	desk.file_claim("J1", "2026-08-01", "the maple died", "the client")
	assert(String(desk.answer_claim("J1", "WC-9", "Marc", "2026-08-04", true, "ours")["reason"]).contains("no claim"))
	assert(String(desk.answer_claim("J1", "WC-1", "", "2026-08-04", true, "ours")["reason"]).contains("name"))
	assert(String(desk.answer_claim("J1", "WC-1", "Marc", "2026-08-04", true, "")["reason"]).contains("reason"))
	assert(bool(desk.answer_claim("J1", "WC-1", "Marc", "2026-08-04", true, "the nursery replaces it")["ok"]))
	assert(String(desk.answer_claim("J1", "WC-1", "Marc", "2026-08-05", false, "no")["reason"]).contains("already"))
	assert(String(desk.finish_claim("J1", "WC-1", "2026-08-06", "replaced")["reason"]).is_empty(), "and it is done")
	assert(desk.claims_needing_attention() == 0)
	var uncovered := make_desk()
	uncovered.state_completion("J1", HANDED_OVER, "Dana")
	uncovered.state_warranty("J1", ["workmanship"], 12, HANDED_OVER)
	uncovered.file_claim("J1", "2026-08-01", "the gate sags", "the client")
	uncovered.answer_claim("J1", "WC-1", "Marc", "2026-08-04", false, "the client's own gate")
	assert(String(uncovered.finish_claim("J1", "WC-1", "2026-08-06")["reason"]).contains("nothing to do"))
	assert(uncovered.claims_needing_attention() == 0, "an uncovered claim is finished by answering it")


# --- the report a page asks for -----------------------------------------------------------------


func test_the_report_needs_a_job_the_desk_has() -> void:
	assert(make_desk().report("J9") == null, "a job nobody has")


func test_the_punch_list_is_counted_by_what_each_item_is_waiting_for() -> void:
	var desk := make_desk()
	desk.raise_item("J1", "patio", "paver out of level", "Dana", RAISED)
	desk.raise_item("J1", "walk", "edging missing", "Dana", RAISED)
	desk.raise_item("J1", "gate", "does not latch", "Dana", RAISED)
	desk.fix_item("PL-1", FIXED_ON)
	desk.accept_item("PL-1", "Marc", "2026-07-16")
	desk.fix_item("PL-2", FIXED_ON)
	var report: Closeout = desk.report("J1", "2026-07-18")
	assert(report != null)
	assert(report.count() == 3)
	var held: Dictionary = report.counts()
	assert(int(held["closed"]) == 1)
	assert(int(held["fixed"]) == 1)
	assert(int(held["open"]) == 1)
	assert(int(held["withdrawn"]) == 0)
	assert(report.outstanding_count() == 2, "the fixed one still counts: nobody has checked it")
	assert(not report.is_finished(), "and the job is not finished")


func test_a_finished_job_needs_a_date_and_nothing_outstanding() -> void:
	var desk := _with_item()
	var walked: Closeout = desk.report("J1")
	assert(walked.outstanding_count() == 1)
	assert(not walked.is_finished())
	desk.fix_item("PL-1", FIXED_ON)
	assert(not desk.report("J1").is_finished(), "a fix nobody has checked is not a finished job")
	desk.accept_item("PL-1", "Marc", "2026-07-16")
	assert(not desk.report("J1").is_finished(), "nor is a job nobody has handed over")
	desk.state_completion("J1", HANDED_OVER, "Dana")
	assert(desk.report("J1").is_finished())


func test_the_lines_say_where_the_job_has_got_to() -> void:
	var desk := _with_item()
	var report: Closeout = desk.report("J1")
	assert(report.punch_text() == "the punch list: 0 of 1 item closed, 1 still to be put right", report.punch_text())
	assert(report.completion_text().contains("has not been stated"), report.completion_text())
	assert(report.warranty_text() == "no warranty has been stated for this job", report.warranty_text())
	desk.fix_item("PL-1", FIXED_ON)
	assert(desk.report("J1").punch_text().contains("1 fixed and waiting to be checked"))
	desk.accept_item("PL-1", "Marc", "2026-07-16")
	desk.state_completion("J1", HANDED_OVER, "Dana")
	var done: Closeout = desk.report("J1")
	assert(done.punch_text() == "the punch list is done: 1 item closed", done.punch_text())
	assert(done.completion_text().contains("handed over on 2026-07-20"), done.completion_text())
	assert(done.describe().contains("the punch list is done"), done.describe())


func test_the_warranty_line_answers_whether_it_is_still_running() -> void:
	var desk := _with_item()
	desk.state_completion("J1", HANDED_OVER, "Dana")
	desk.state_warranty("J1", ["plant material"], 12, HANDED_OVER)
	var early: Closeout = desk.report("J1", "2026-08-01")
	assert(early.is_warranty_running())
	assert(early.warranty_text().contains("running on 2026-08-01"), early.warranty_text())
	var late: Closeout = desk.report("J1", "2027-08-01")
	assert(not late.is_warranty_running())
	assert(late.warranty_text().contains("had run out by 2027-08-01"), late.warranty_text())
	var undated: Closeout = desk.report("J1")
	assert(undated.as_of.is_empty(), "a report asked for no moment says nothing about today")
	assert(not undated.is_warranty_running())
	assert(not undated.warranty_text().contains("running"), undated.warranty_text())


func test_a_claim_outside_the_term_is_named() -> void:
	var desk := _with_item()
	desk.state_completion("J1", HANDED_OVER, "Dana")
	desk.state_warranty("J1", ["plant material"], 12, HANDED_OVER)
	desk.file_claim("J1", "2027-07-20", "the maple died again", "the client")
	assert(desk.report("J1").claims_out_of_term().is_empty(), "the last day of the term is inside it")
	desk.file_claim("J1", "2027-09-01", "and the birch", "the client")
	var late: Array = desk.report("J1").claims_out_of_term()
	assert(late.size() == 1, "%d out of term" % late.size())
	assert(late[0].id == "WC-2")
	var named := false
	for line: String in desk.report("J1").problems():
		if line.contains("reported outside the term, which ended on 2027-07-20"):
			named = true
	assert(named, "the claim out of term is named: %s" % str(desk.report("J1").problems()))


func test_what_wants_looking_at_is_counted_and_named() -> void:
	var desk := make_desk()
	var bare: Array[String] = desk.report("J1").problems()
	assert(bare.size() == 2, "%d problems on a job with nothing: %s" % [bare.size(), str(bare)])
	assert(bare[0].contains("substantial completion has not been stated"), bare[0])
	assert(bare[1].contains("no warranty has been stated"), bare[1])
	desk.raise_item("J1", "patio", "paver out of level", "Dana", RAISED)
	desk.raise_item("J1", "walk", "edging missing", "Dana", RAISED)
	desk.fix_item("PL-2", FIXED_ON)
	var mixed: Array[String] = desk.report("J1").problems()
	assert(mixed[1] == "1 item still to be put right", mixed[1])
	assert(mixed[2] == "1 item fixed and waiting to be checked", mixed[2])
	desk.state_completion("J1", HANDED_OVER, "Dana")
	desk.state_warranty("J1", ["plant material"], 12, HANDED_OVER)
	desk.file_claim("J1", "2026-09-01", "the maple died", "the client")
	var claimed: Array[String] = desk.report("J1").problems()
	assert(not claimed[0].contains("substantial completion"), "the date is stated now")
	assert(claimed[claimed.size() - 1] == "claim WC-1: open, not yet answered", claimed[claimed.size() - 1])


func test_the_lines_a_page_draws_come_in_the_order_the_work_is_done() -> void:
	var desk := _with_item()
	desk.state_completion("J1", HANDED_OVER, "Dana")
	var lines: Array[String] = desk.report("J1").text_lines()
	assert(lines[0].contains("handed over on 2026-07-20"), lines[0])
	assert(lines[1].contains("the punch list:"), lines[1])
	assert(lines[2].contains("back patio, north edge"), lines[2])
	assert(lines[3] == "no warranty has been stated for this job", lines[3])


# --- the desk as a whole ------------------------------------------------------------------------


func test_the_menu_line_says_how_much_is_outstanding() -> void:
	var empty := make_desk()
	assert(empty.describe() == "nothing is being closed out", empty.describe())
	var desk := _with_item()
	assert(desk.describe() == "1 job in closeout, 1 item, 1 outstanding", desk.describe())
	desk.fix_item("PL-1", FIXED_ON)
	desk.accept_item("PL-1", "Marc", "2026-07-16")
	assert(desk.describe() == "1 job in closeout, 1 item", desk.describe())
	desk.state_completion("J1", HANDED_OVER, "Dana")
	desk.state_warranty("J1", ["plant material"], 12, HANDED_OVER)
	desk.file_claim("J1", "2026-08-01", "the maple died", "the client")
	assert(desk.describe().contains("1 claim wanting somebody"), desk.describe())


func test_the_jobs_in_closeout_are_the_ones_with_something_to_say() -> void:
	var desk := make_desk()
	assert(desk.jobs_in_closeout().is_empty(), "a job with nothing said about it is not in closeout")
	desk.raise_item("J1", "patio", "paver out of level", "Dana", RAISED)
	assert(desk.jobs_in_closeout() == ["J1"])
	desk.state_completion("J1", HANDED_OVER, "Dana")
	desk.state_warranty("J1", ["plant material"], 12, HANDED_OVER)
	assert(desk.jobs_in_closeout() == ["J1"], "and saying three things about one job is one job")


func test_a_record_that_cannot_read_is_named_by_the_desk() -> void:
	var desk := _with_item()
	assert(desk.problems().is_empty(), "a sound desk has nothing wrong with it")
	desk.item("PL-1").where = ""
	assert(desk.problems()[0].contains("does not say where it is"), desk.problems()[0])
	var moved := _with_item()
	moved.item("PL-1").job_id = "J9"
	var named: Array[String] = moved.problems()
	assert(named[0].contains("belongs to a job this desk does not have"), named[0])


func test_a_desk_survives_the_file_with_its_lists_and_its_terms() -> void:
	var desk := _with_item()
	desk.fix_item("PL-1", FIXED_ON)
	desk.state_completion("J1", HANDED_OVER, "Dana")
	desk.state_warranty("J1", ["plant material"], 12, HANDED_OVER)
	desk.file_claim("J1", "2026-08-01", "the maple died", "the client")
	var back: CloseoutDesk = DeskScript.from_dict(desk.to_dict())
	back.bind(desk.job_desk)
	assert(back.items.size() == 1)
	assert(back.item("PL-1").is_fixed(), "the state came back")
	assert(int(back.warranty_for("J1").months) == 12, "a whole number arrives from a file as a float")
	assert(back.completed_on("J1") == HANDED_OVER)
	assert(back.claim_rows("J1").size() == 1)
	assert(back.report("J1").punch_text() == desk.report("J1").punch_text(), "and the report reads the same")