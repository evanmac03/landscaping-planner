extends Node
## A punch item: one thing on the list a job is finished by (phase 12).
##
## Two properties are under test. The first is that the **state is worked out from the records** -
## withdrawn, accepted, fixed, open - so a list and a page cannot disagree about where an item has got
## to, and so the step an office forgets (an item that has been put right and never looked at) has a
## name of its own. The second is that a **rejection puts the item back** and keeps the fix it was
## rejecting, so a list that has been round twice says so rather than looking like a list that has been
## round once.

const ItemScript := preload("res://scripts/biz/punch_item.gd")

const RAISED := "2026-07-06"
const FIXED_ON := "2026-07-14"
const CHECKED_ON := "2026-07-16"


func _item() -> PunchItem:
	return ItemScript.make("PL-1", "J1", RAISED, "back patio, north edge", "paver out of level", "Dana")


## An item that has been put right and is waiting to be checked.
func _fixed() -> PunchItem:
	var item := _item()
	item.mark_fixed(FIXED_ON, "lifted and re-laid")
	return item


func test_a_new_item_is_open_and_waiting_to_be_put_right() -> void:
	var item := _item()
	assert(item.state() == ItemScript.OPEN)
	assert(item.state_name() == "open")
	assert(item.waiting_name() == "waiting to be put right")
	assert(item.is_open())
	assert(item.is_outstanding())
	assert(item.rejection_count() == 0)


func test_an_item_that_has_been_put_right_is_waiting_to_be_checked_not_closed() -> void:
	var item := _fixed()
	assert(item.state() == ItemScript.FIXED, "a fix is not an acceptance")
	assert(item.state_name() == "fixed, waiting to be checked")
	assert(item.waiting_name() == "waiting to be checked")
	assert(item.is_outstanding(), "and it still counts against the job")
	assert(not item.is_closed())


func test_the_check_passes_and_the_item_closes() -> void:
	var item := _fixed()
	assert(item.mark_accepted("Marc", CHECKED_ON))
	assert(item.state() == ItemScript.CLOSED)
	assert(item.waiting_name() == "", "a closed item waits for nothing")
	assert(not item.is_outstanding())
	assert(item.accepted_by == "Marc")
	assert(item.accepted_at == CHECKED_ON)


func test_a_rejection_puts_the_item_back_and_keeps_the_fix_it_rejected() -> void:
	var item := _fixed()
	assert(item.mark_rejected("Marc", CHECKED_ON, "the same corner is still proud"))
	assert(item.state() == ItemScript.OPEN, "a rejected fix is not a fix")
	assert(item.is_outstanding())
	assert(item.rejection_count() == 1)
	var held: Dictionary = item.rejections[0]
	assert(String(held["at"]) == CHECKED_ON)
	assert(String(held["by"]) == "Marc")
	assert(String(held["why"]) == "the same corner is still proud")
	assert(
		String(held["was_fixed_at"]) == FIXED_ON,
		"and the fix it was rejecting is on the record: %s" % String(held["was_fixed_at"])
	)
	assert(item.fixed_at.is_empty(), "the fix is cleared, so the state is derivable")


func test_a_list_that_has_been_round_twice_says_so() -> void:
	var item := _fixed()
	item.mark_rejected("Marc", CHECKED_ON, "still proud")
	item.mark_fixed("2026-07-20", "ground the corner down")
	item.mark_rejected("Marc", "2026-07-22", "now it is stained")
	assert(item.rejection_count() == 2)
	assert(item.state() == ItemScript.OPEN)
	assert(item.describe().contains("rejected 2 times"), item.describe())


func test_an_item_can_be_taken_off_the_list_and_stops_counting() -> void:
	var item := _item()
	assert(item.mark_withdrawn("Dana", "2026-07-08", "the client asked for it to stay as it is"))
	assert(item.state() == ItemScript.WITHDRAWN)
	assert(item.is_withdrawn())
	assert(not item.is_outstanding(), "a withdrawn item is not outstanding")
	assert(item.withdrawn_why == "the client asked for it to stay as it is")


func test_withdrawing_outranks_a_check_however_far_round_it_had_got() -> void:
	var item := _fixed()
	item.mark_accepted("Marc", CHECKED_ON)
	assert(not item.mark_withdrawn("Dana", "2026-07-18", "raised by mistake"), "a closed item stays closed")
	assert(item.state() == ItemScript.CLOSED)


func test_an_item_that_cannot_be_read_is_refused_rather_than_made() -> void:
	assert(ItemScript.make("", "J1", RAISED, "here", "something", "Dana") == null, "no id")
	assert(ItemScript.make("PL-1", "", RAISED, "here", "something", "Dana") == null, "no job")
	assert(ItemScript.make("PL-1", "J1", RAISED, "", "something", "Dana") == null, "no place")
	assert(ItemScript.make("PL-1", "J1", RAISED, "here", "  ", "Dana") == null, "no description")
	assert(ItemScript.make("PL-1", "J1", RAISED, "here", "something", "") == null, "nobody to ask")
	assert(ItemScript.make("PL-1", "J1", "July", "here", "something", "Dana") == null, "not a date")
	var made: PunchItem = ItemScript.make("PL-1", "J1", RAISED, "  here  ", "something", " Dana ")
	assert(made != null, "and one that reads is made")
	assert(made.where == "here", "with the space trimmed: '%s'" % made.where)
	assert(made.raised_by == "Dana")


func test_an_acceptance_takes_a_person_and_a_check_takes_something_to_check() -> void:
	assert(not _item().mark_accepted("Marc", CHECKED_ON), "nothing has been fixed yet")
	assert(not _fixed().mark_accepted("", CHECKED_ON), "an acceptance nobody signed")
	assert(not _fixed().mark_accepted("Marc", "the 16th"), "a check on a day that is not a date")
	assert(_fixed().mark_accepted("Marc", CHECKED_ON))


func test_a_rejection_takes_a_reason() -> void:
	assert(not _fixed().mark_rejected("Marc", CHECKED_ON, ""), "a rejection nobody explained")
	assert(not _fixed().mark_rejected("", CHECKED_ON, "still proud"), "nobody to ask")
	assert(not _fixed().mark_rejected("Marc", "", "still proud"), "no moment")
	assert(not _item().mark_rejected("Marc", CHECKED_ON, "still proud"), "nothing had been fixed")


func test_taking_an_item_off_takes_a_reason_and_cannot_be_done_twice() -> void:
	assert(not _item().mark_withdrawn("Dana", "2026-07-08", ""), "no reason")
	assert(not _item().mark_withdrawn("", "2026-07-08", "raised by mistake"), "nobody to ask")
	var once := _item()
	assert(once.mark_withdrawn("Dana", "2026-07-08", "raised by mistake"))
	assert(not once.mark_withdrawn("Dana", "2026-07-09", "and again"), "it is off the list")


func test_a_fix_takes_a_moment_and_only_a_fix_that_is_still_open() -> void:
	assert(not _item().mark_fixed("the 14th"), "not a date")
	var twice := _fixed()
	assert(not twice.mark_fixed("2026-07-15"), "it has been fixed already")
	var closed := _fixed()
	closed.mark_accepted("Marc", CHECKED_ON)
	assert(not closed.mark_fixed("2026-07-17"), "and a closed item is not fixed again")


func test_the_row_a_list_draws_is_the_records_own_words() -> void:
	var item := _fixed()
	var row: Dictionary = item.row()
	assert(String(row["id"]) == "PL-1")
	assert(String(row["where"]) == "back patio, north edge")
	assert(String(row["state"]) == "FIXED")
	assert(String(row["state_name"]) == "fixed, waiting to be checked")
	assert(String(row["text"]) == item.describe(), "the row's text is the record's own line")
	assert(int(row["rejections"]) == 0)


func test_the_line_reads_as_a_person_reads_a_punch_list() -> void:
	var item := _fixed()
	var line: String = item.describe()
	assert(line.begins_with("back patio, north edge: paver out of level"), line)
	assert(line.contains("raised 2026-07-06 by Dana"), line)
	assert(line.contains("waiting to be checked"), line)
	assert(line.contains("done: lifted and re-laid"), "what was done is on the line: %s" % line)
	var closed := _fixed()
	closed.mark_accepted("Marc", CHECKED_ON)
	assert(closed.describe().contains("checked by Marc on 2026-07-16"), closed.describe())
	var withdrawn := _item()
	withdrawn.mark_withdrawn("Dana", "2026-07-08", "raised by mistake")
	assert(withdrawn.describe().contains("raised by mistake"), withdrawn.describe())


## A record that cannot be read is named by `describe`, and `problem` says which way it is wrong.
## This is the half of the record that matters when a file has been edited by hand: the file is not
## the editor, and an item that stops being readable has to say so rather than print a blank line.
func test_a_record_that_cannot_read_says_which_way_it_is_wrong() -> void:
	assert(_item().problem() == "", "a sound item has nothing wrong with it")
	assert(_item().is_sound())

	var blanked := _item()
	blanked.where = ""
	assert(blanked.problem().contains("does not say where it is"), blanked.problem())
	assert(blanked.describe() == blanked.problem(), "and the line is the problem, not a blank row")

	var nothing := _item()
	nothing.what = "  "
	assert(nothing.problem().contains("does not say what is wrong"), nothing.problem())

	var dateless := _item()
	dateless.raised_at = "July"
	assert(dateless.problem().contains("not a date"), dateless.problem())

	var unowned := _item()
	unowned.raised_by = ""
	assert(unowned.problem().contains("does not say who raised it"), unowned.problem())

	var unnumbered := _item()
	unnumbered.id = ""
	assert(unnumbered.problem().contains("no id"), unnumbered.problem())

	var orphan := _item()
	orphan.job_id = ""
	assert(orphan.problem().contains("belongs to no job"), orphan.problem())

	var unnamed_check := _item()
	unnamed_check.fixed_at = FIXED_ON
	unnamed_check.accepted_at = CHECKED_ON
	assert(unnamed_check.problem().contains("does not say by whom"), unnamed_check.problem())

	var checked_with_nothing_fixed := _item()
	checked_with_nothing_fixed.accepted_by = "Marc"
	checked_with_nothing_fixed.accepted_at = CHECKED_ON
	assert(
		checked_with_nothing_fixed.problem().contains("accepted with nothing recorded as fixed"),
		checked_with_nothing_fixed.problem()
	)

	var sourceless := _item()
	sourceless.rejections.append({"at": CHECKED_ON, "by": "Marc", "why": ""})
	assert(sourceless.problem().contains("rejection nobody explained"), sourceless.problem())


func test_an_item_survives_the_file_with_where_it_has_got_to() -> void:
	var item := _fixed()
	item.mark_rejected("Marc", CHECKED_ON, "still proud")
	item.mark_fixed("2026-07-20", "ground it down")
	var back: PunchItem = ItemScript.from_dict(item.to_dict())
	assert(back.id == item.id)
	assert(back.where == item.where)
	assert(back.what == item.what)
	assert(back.is_fixed(), "the state came back: %s" % back.state_name())
	assert(back.rejection_count() == 1)
	assert(
		String((back.rejections[0] as Dictionary)["was_fixed_at"]) == FIXED_ON,
		"and the rejection kept the fix it rejected"
	)
	assert(back.describe() == item.describe(), "the line reads the same after a round trip")
	assert(back.is_sound())


func test_a_copy_is_independent() -> void:
	var item := _fixed()
	var other: PunchItem = item.copy()
	other.mark_accepted("Marc", CHECKED_ON)
	assert(item.is_fixed(), "the original is untouched")
	assert(other.is_closed())
	other.mark_rejected("Marc", "2026-07-18", "no, actually")
	assert(item.rejection_count() == 0, "and a rejection on the copy is not on the original")