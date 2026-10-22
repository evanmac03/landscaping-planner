extends Node
## A warranty: what a job's work is guaranteed for, and every claim made against it (phase 12).
##
## Three properties are under test. The **calendar** - the term ends on its anniversary, and a month
## with no such day clamps - because a warranty that expired a day early would refuse a claim it
## should have paid. The **states of a claim**, worked out from its records, because "answered, not
## covered" and "answered, to be done" are different sentences to the person holding the phone. And
## the **refusals**: a term nobody can read, or an answer with no reason on it, is not stored.

const WarrantyScript := preload("res://scripts/biz/warranty.gd")
const ClaimScript := preload("res://scripts/biz/warranty_claim.gd")

const STARTED := "2026-06-30"


func _warranty(covered: Array = ["plant material", "workmanship"], months: int = 12) -> Warranty:
	return WarrantyScript.make("J1", covered, months, STARTED)


func test_the_calendar_lives_in_one_place_and_the_day_clamps() -> void:
	assert(WarrantyScript.months_after("2026-06-30", 12) == "2027-06-30", "the anniversary")
	assert(WarrantyScript.months_after("2026-06-30", 1) == "2026-07-30")
	assert(WarrantyScript.months_after("2026-01-31", 1) == "2026-02-28", "February has no 31st")
	assert(WarrantyScript.months_after("2026-08-31", 6) == "2027-02-28", "nor does it in a later year")
	assert(WarrantyScript.months_after("2024-02-29", 12) == "2025-02-28", "and a leap day clamps")
	assert(WarrantyScript.months_after("2024-02-29", 48) == "2028-02-29", "unless the year has one")
	assert(WarrantyScript.months_after("July", 12) == "", "not a date")
	assert(WarrantyScript.months_after("2026-06-30", 0) == "", "not a term")


func test_the_term_runs_to_its_anniversary_and_the_last_day_is_covered() -> void:
	var record := _warranty()
	assert(record.ends_on() == "2027-06-30")
	assert(record.covers_on(STARTED), "the day it starts is covered")
	assert(record.covers_on("2027-06-30"), "and the day it runs out is the last claim it takes")
	assert(not record.covers_on("2027-07-01"), "the next day is not")
	assert(not record.covers_on("2026-06-29"), "nor is the day before it started")
	assert(not record.covers_on("next June"), "and a date that is not a date is not a yes")


func test_a_term_has_to_be_readable() -> void:
	assert(WarrantyScript.make("J1", [], 12, STARTED) == null, "a warranty covering nothing")
	assert(WarrantyScript.make("J1", ["plant material", "the weather"], 12, STARTED) == null, "not a part")
	assert(WarrantyScript.make("J1", ["plant material"], 0, STARTED) == null, "no term")
	assert(
		WarrantyScript.make("J1", ["plant material"], WarrantyScript.MAX_MONTHS + 1, STARTED) == null,
		"a term longer than anything a plant warranty is"
	)
	assert(WarrantyScript.make("J1", ["plant material"], 12, "June") == null, "no start")
	assert(WarrantyScript.make("J1", ["plant material"], WarrantyScript.MAX_MONTHS, STARTED) != null)


func test_the_parts_are_read_in_the_tables_order_however_they_are_stated() -> void:
	var record := _warranty(["workmanship", "plant material"])
	assert(record.parts == ["plant material", "workmanship"], str(record.parts))
	assert(WarrantyScript.is_part(" Plant Material "), "case and spacing do not matter")
	assert(not WarrantyScript.is_part("irrigation heads"))
	assert(_warranty(["lighting"]).covers("lighting"))
	assert(not _warranty(["lighting"]).covers("workmanship"))


func test_the_terms_line_is_the_sentence_a_contract_writes() -> void:
	var record := _warranty()
	assert(
		record.terms_text() == "plant material and workmanship for 12 months from 2026-06-30, so until 2027-06-30",
		record.terms_text()
	)
	assert(_warranty(["plant material"], 1).terms_text().contains("1 month from"), "one month reads as one")
	var bare := WarrantyScript.new("J1")
	assert(bare.terms_text() == WarrantyScript.NOTHING_STATED)
	assert(bare.excludes_text() == WarrantyScript.NOTHING_STATED, "and no exclusions state nothing")


func test_joining_a_list_reads_the_way_a_person_says_it() -> void:
	assert(WarrantyScript.and_join([]) == "")
	assert(WarrantyScript.and_join(["soil"]) == "soil")
	assert(WarrantyScript.and_join(["plant material", "workmanship"]) == "plant material and workmanship")
	assert(WarrantyScript.and_join(["a", "b", "c"]) == "a, b and c")
	assert(WarrantyScript.and_join(["a", " ", "b"]) == "a and b", "a blank sentence is not a sentence")


func test_the_claims_are_numbered_past_the_highest_ever_handed_out() -> void:
	var record := _warranty()
	assert(record.next_claim_id() == "WC-1")
	var first: WarrantyClaim = record.file_claim("2026-08-01", "the maple died", "the client")
	assert(first != null and first.id == "WC-1")
	record.file_claim("2026-08-02", "the gate sags", "the client")
	assert(record.next_claim_id() == "WC-3")
	record.claims.remove_at(0)
	assert(record.next_claim_id() == "WC-3", "a claim dropped by hand does not hand its number out again")


func test_a_claim_that_cannot_be_read_is_refused_rather_than_filed() -> void:
	var record := _warranty()
	assert(record.file_claim("August", "the maple died", "the client") == null, "not a date")
	assert(record.file_claim("2026-08-01", "", "the client") == null, "nothing said to have failed")
	assert(record.file_claim("2026-08-01", "the maple died", "") == null, "nobody made the claim")
	assert(record.claims.is_empty(), "and nothing was filed")
	var unsound := WarrantyScript.new("J1")
	assert(unsound.file_claim("2026-08-01", "the maple died", "the client") == null, "no term to claim against")


func test_an_answer_is_recorded_once_with_its_reason() -> void:
	var record := _warranty()
	record.file_claim("2026-08-01", "the maple died", "the client")
	assert(not record.answer_claim("WC-1", "", "2026-08-04", true, "the nursery replaces it"), "nobody")
	assert(not record.answer_claim("WC-1", "Marc", "2026-08-04", true, ""), "no reason")
	assert(not record.answer_claim("WC-1", "Marc", "the 4th", true, "because"), "not a date")
	assert(record.answer_claim("WC-1", "Marc", "2026-08-04", true, "the nursery replaces it"))
	var claim: WarrantyClaim = record.claim("WC-1")
	assert(claim.covered)
	assert(claim.answer_why == "the nursery replaces it")
	assert(not record.answer_claim("WC-1", "Marc", "2026-08-05", false, "actually not"), "answered once")


func test_a_claim_is_done_when_there_is_nothing_left_to_do() -> void:
	var record := _warranty()
	record.file_claim("2026-08-01", "the maple died", "the client")
	record.file_claim("2026-08-02", "the gate sags", "the client")
	record.answer_claim("WC-1", "Marc", "2026-08-04", true, "the nursery replaces it")
	record.answer_claim("WC-2", "Marc", "2026-08-04", false, "the client's own gate, not ours")
	var refused: WarrantyClaim = record.claim("WC-2")
	assert(refused.is_done(), "a claim that is not covered is finished by answering it")
	assert(refused.state_name() == "done")
	assert(not record.claim("WC-1").is_done(), "a covered claim is not done until the work is")
	assert(record.claim("WC-1").state_name() == "answered")
	assert(not record.finish_claim("WC-2", "2026-08-06"), "nothing is owed on an uncovered claim")
	assert(record.finish_claim("WC-1", "2026-08-06", "replaced with a two-year-old maple"))
	assert(record.claim("WC-1").is_done())
	assert(not record.finish_claim("WC-1", "2026-08-07"), "and it is not put right twice")


func test_what_wants_attention_is_both_kinds_of_unfinished_claim() -> void:
	var record := _warranty()
	record.file_claim("2026-08-01", "the maple died", "the client")
	record.file_claim("2026-08-02", "the gate sags", "the client")
	assert(record.claims_needing_attention().size() == 2, "neither has been answered")
	record.answer_claim("WC-1", "Marc", "2026-08-04", false, "not ours")
	assert(record.claims_needing_attention().size() == 1, "the unanswered one still wants somebody")
	record.answer_claim("WC-2", "Marc", "2026-08-04", true, "ours")
	assert(record.claims_needing_attention().size() == 1, "and now the covered one does")
	assert(record.claims_needing_attention()[0].id == "WC-2")


func test_the_line_counts_the_claims_and_says_what_the_term_covers() -> void:
	var record := _warranty()
	assert(record.describe().contains("no claims against it"), record.describe())
	record.file_claim("2026-08-01", "the maple died", "the client")
	assert(record.describe().contains("1 of 1 claim still wanting somebody"), record.describe())
	record.answer_claim("WC-1", "Marc", "2026-08-04", false, "not ours")
	assert(record.describe().contains("1 claim settled"), record.describe())
	record.excludes = ["damage by others"]
	assert(record.describe().contains("not covering damage by others"), record.describe())


func test_a_warranty_that_cannot_read_says_which_way_it_is_wrong() -> void:
	var bare := WarrantyScript.new("J1")
	assert(bare.problem().contains("covers nothing"), bare.problem())
	assert(bare.describe() == bare.problem(), "and the line is the problem")
	var unowned := WarrantyScript.new("")
	unowned.parts = ["workmanship"]
	unowned.months = 12
	unowned.starts_on = STARTED
	assert(unowned.problem().contains("belongs to no job"), unowned.problem())
	var wrong_part := _warranty()
	wrong_part.parts = ["the weather"]
	assert(wrong_part.problem().contains("which is not a thing it can cover"), wrong_part.problem())
	var long_term := _warranty()
	long_term.months = WarrantyScript.MAX_MONTHS + 1
	assert(long_term.problem().contains("runs for"), long_term.problem())
	var late_start := _warranty()
	late_start.starts_on = "June"
	assert(late_start.problem().contains("not a date"), late_start.problem())
	var bad_claim := _warranty()
	bad_claim.claims.append(ClaimScript.new(""))
	assert(bad_claim.problem().contains("claim with no id"), bad_claim.problem())


func test_a_warranty_survives_the_file_with_its_claims() -> void:
	var record := _warranty(["workmanship", "plant material"], 18)
	record.excludes = ["damage by others", " "]
	record.file_claim("2026-08-01", "the maple died", "the client")
	record.answer_claim("WC-1", "Marc", "2026-08-04", true, "the nursery replaces it")
	var back: Warranty = WarrantyScript.from_dict(record.to_dict())
	assert(back.job_id == "J1")
	assert(back.parts == ["plant material", "workmanship"])
	assert(int(back.months) == 18, "a whole number arrives from a file as a float: %s" % str(back.months))
	assert(back.starts_on == STARTED)
	assert(back.ends_on() == record.ends_on())
	assert(back.excludes.size() == 2, "the blank one is not dropped by the reader: %s" % str(back.excludes))
	assert(back.excludes_text() == "damage by others", "and it is not shown on the line either")
	assert(back.claims.size() == 1)
	assert(back.claim("WC-1").covered)
	assert(back.describe() == record.describe(), "the line reads the same after a round trip")
	assert(back.is_sound())


func test_a_copy_is_independent() -> void:
	var record := _warranty()
	record.file_claim("2026-08-01", "the maple died", "the client")
	var other: Warranty = record.copy()
	other.answer_claim("WC-1", "Marc", "2026-08-04", false, "not ours")
	assert(not record.claim("WC-1").is_answered(), "the original is untouched")
	assert(other.claim("WC-1").is_answered())
	other.parts.append("lighting")
	assert(not record.covers("lighting"))
	other.excludes.append("damage by others")
	assert(record.excludes.is_empty())