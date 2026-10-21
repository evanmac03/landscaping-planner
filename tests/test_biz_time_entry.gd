extends Node
## Time entries: exact minutes, a recorded rate, approval, and overlaps (spec §7.3).
##
## The two properties under test: the labour cost is the **recorded** rate for the **exact** minutes
## (so a raise or a payroll rounding never restates a costed job), and an entry that does not read is
## flagged rather than averaged away.

const EntryScript := preload("res://scripts/biz/time_entry.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")


func _entry(start: String, end: String, rate_cents: int = 4500) -> EntryScript:
	var entry: EntryScript = EntryScript.new("T1")
	entry.job = "J1"
	entry.cost_code = &"PLANTING"
	entry.crew_member = &"C1"
	entry.started_at = start
	entry.ended_at = end
	entry.loaded_rate = MoneyScript.of(rate_cents)
	return entry


func test_minutes_are_the_shift_less_the_break() -> void:
	var entry := _entry("2026-06-01T08:00:00Z", "2026-06-01T16:30:00Z")
	entry.break_minutes = 30
	assert(entry.minutes() == 480, str(entry.minutes()))
	assert(entry.is_valid())


func test_an_entry_that_ends_before_it_starts_is_a_problem_not_a_negative() -> void:
	var entry := _entry("2026-06-01T16:00:00Z", "2026-06-01T08:00:00Z")
	assert(not entry.is_valid())
	assert(entry.problem().contains("before it starts"), entry.problem())
	assert(entry.minutes() < 0, "the arithmetic is honest; the problem is what refuses it")


func test_an_unreadable_time_is_a_problem() -> void:
	var entry := _entry("tomorrow morning", "2026-06-01T08:00:00Z")
	assert(not entry.is_valid())
	assert(entry.problem().contains("not a time"))


func test_a_break_longer_than_the_shift_is_refused() -> void:
	var entry := _entry("2026-06-01T08:00:00Z", "2026-06-01T12:00:00Z")
	entry.break_minutes = 300
	assert(not entry.is_valid())
	assert(entry.problem().contains("longer than the shift"))


func test_a_shift_longer_than_a_day_is_a_mis_typed_date() -> void:
	var entry := _entry("2026-06-01T08:00:00Z", "2026-06-03T08:00:00Z")
	assert(not entry.is_valid())
	assert(entry.problem().contains("longer than a day"))


func test_labour_is_the_recorded_rate_for_the_exact_minutes_rounded_once() -> void:
	# 45.00 an hour for eight hours is 360.00.
	var entry := _entry("2026-06-01T08:00:00Z", "2026-06-01T16:00:00Z")
	assert(entry.labour().format() == "360.00", entry.labour().format())
	# And a half hour is exactly half: 22.50, not 22.49.
	entry.ended_at = "2026-06-01T08:30:00Z"
	assert(entry.labour().format() == "22.50")


func test_an_unreadable_rate_stays_unreadable_not_free_labour() -> void:
	var entry := _entry("2026-06-01T08:00:00Z", "2026-06-01T16:00:00Z")
	entry.loaded_rate = MoneyScript.invalid()
	assert(not entry.labour().is_valid())


func test_approval_needs_an_entry_that_reads_and_somebody_to_approve_it() -> void:
	var entry := _entry("2026-06-01T08:00:00Z", "2026-06-01T16:00:00Z")
	assert(not entry.is_approved(), "an entry is pending until it is approved")
	assert(not entry.approve(""), "somebody has to approve it")
	assert(entry.approve("evan"))
	assert(entry.is_approved())
	var broken := _entry("2026-06-01T16:00:00Z", "2026-06-01T08:00:00Z")
	assert(not broken.approve("evan"), "there is nothing to approve in an entry that does not read")


func test_two_entries_for_one_person_that_overlap_are_caught() -> void:
	var morning := _entry("2026-06-01T08:00:00Z", "2026-06-01T12:00:00Z")
	var late := _entry("2026-06-01T11:00:00Z", "2026-06-01T15:00:00Z")
	late.id = "T2"
	assert(morning.overlaps(late), "the same person cannot be in two places at once")
	late.started_at = "2026-06-01T12:30:00Z"
	late.ended_at = "2026-06-01T15:00:00Z"
	assert(not morning.overlaps(late), "an hour apart is not an overlap")


func test_a_different_person_never_overlaps() -> void:
	var one := _entry("2026-06-01T08:00:00Z", "2026-06-01T12:00:00Z")
	var two := _entry("2026-06-01T08:00:00Z", "2026-06-01T12:00:00Z")
	two.crew_member = &"C2"
	assert(not one.overlaps(two))


func test_source_names_read_the_way_a_person_says_them() -> void:
	assert(EntryScript.source_name(EntryScript.MANUAL) == "typed in")
	assert(EntryScript.source_name(EntryScript.CLOCK) == "clocked")
	assert(EntryScript.source_name(EntryScript.IMPORT) == "imported")


func test_an_entry_round_trips_through_the_file() -> void:
	var entry := _entry("2026-06-01T08:00:00Z", "2026-06-01T16:00:00Z", 5250)
	entry.break_minutes = 45
	entry.source = EntryScript.CLOCK
	entry.approve("evan")
	entry.note = "planted the west bed"
	var restored: EntryScript = EntryScript.from_dict(entry.to_dict())
	assert(restored.id == "T1" and restored.job == "J1" and restored.crew_member == &"C1")
	assert(restored.minutes() == 435)
	assert(restored.labour().format() == entry.labour().format())
	assert(restored.is_approved())
	assert(restored.source == EntryScript.CLOCK)
	assert(restored.note == "planted the west bed")


func test_a_record_with_no_id_is_dropped() -> void:
	assert(EntryScript.from_dict({"job": "J1"}) == null)