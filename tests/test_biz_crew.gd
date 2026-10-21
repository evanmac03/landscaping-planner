extends Node
## The crew member: effective-dated rates, tickets, and availability (spec §7.1).
##
## The property under test throughout is that a person's **cost is a question about a date** - so that
## a raise never reprices work already costed, and a person with no rate is refused rather than priced
## at nothing.

const CrewScript := preload("res://scripts/biz/crew.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")


func test_a_rate_answers_for_a_date_and_a_raise_does_not_go_backwards() -> void:
	var member: CrewScript = CrewScript.new(&"C1", "Dana")
	assert(member.add_rate("2026-01-01", MoneyScript.of(4500)))
	assert(member.add_rate("2026-07-01", MoneyScript.of(5000)))
	assert(member.rate_on("2026-03-15").format() == "45.00", "March is still the old rate")
	assert(member.rate_on("2026-09-01").format() == "50.00", "September is the new one")


func test_a_person_with_no_rate_is_unreadable_not_free() -> void:
	var member: CrewScript = CrewScript.new(&"C1", "Dana")
	assert(not member.rate_on("2026-03-15").is_valid(), "no rate is not a rate of nothing")
	var restored: CrewScript = CrewScript.from_dict(member.to_dict())
	assert(not restored.rate_on("2026-03-15").is_valid())


func test_a_rate_needs_a_date_a_readable_amount_and_is_one_per_date() -> void:
	var member: CrewScript = CrewScript.new(&"C1", "Dana")
	assert(not member.add_rate("", MoneyScript.of(4500)))
	assert(not member.add_rate("2026-01-01", MoneyScript.invalid()))
	assert(member.rate_rows().is_empty())
	assert(member.add_rate("2026-01-01", MoneyScript.of(4500)))
	assert(member.add_rate("2026-01-01", MoneyScript.of(4600)))
	assert(member.rate_rows().size() == 1, "the same date twice replaces rather than stacks")
	assert(member.rate_on("2026-01-01").format() == "46.00")


func test_roles_are_named_and_a_role_nobody_has_is_refused() -> void:
	assert(CrewScript.role_list().size() == 4)
	assert(CrewScript.role_name(&"FOREMAN") == "Foreman")
	assert(CrewScript.role_name(&"LEAD_HAND") == "Lead hand")
	assert(not CrewScript.is_role(&"WIZARD"))


func test_an_expired_ticket_is_not_a_ticket() -> void:
	var member: CrewScript = CrewScript.new(&"C1", "Dana")
	member.add_certification("First aid", "2026-06-30")
	assert(member.has_certification("First aid", "2026-05-01"))
	assert(not member.has_certification("First aid", "2026-07-15"), "it ran out in June")
	assert(not member.has_certification("Chainsaw", "2026-05-01"), "and she never had this one")


func test_availability_is_a_day_off_and_a_vacation() -> void:
	var member: CrewScript = CrewScript.new(&"C1", "Dana")
	member.add_availability({"kind": "DAY_OFF", "weekday": 0})
	assert(not member.available_on("2026-06-07"), "a Sunday")
	assert(member.available_on("2026-06-08"), "a Monday")
	member.add_availability({"kind": "VACATION", "from": "2026-06-15", "to": "2026-06-22"})
	assert(not member.available_on("2026-06-18"), "in the vacation")
	assert(member.available_on("2026-06-25"), "after it")
	assert(member.unavailability("2026-06-18").contains("vacation"))
	assert(member.unavailability("2026-07-01").is_empty(), "and nothing to report on a working day")


func test_the_weekday_of_a_date_is_the_one_the_calendar_says() -> void:
	assert(CrewScript._weekday_of("1970-01-01") == 4, "a Thursday")
	assert(CrewScript._weekday_of("2026-06-07") == 0, "a Sunday")
	assert(CrewScript._weekday_of("2026-06-08") == 1, "a Monday")


func test_a_crew_member_round_trips_through_the_file() -> void:
	var member: CrewScript = CrewScript.new(&"C1", "Dana")
	member.role = &"FOREMAN"
	member.home_base = Vector2(12.0, -3.5)
	member.add_rate("2026-01-01", MoneyScript.of(4500))
	member.add_certification("First aid", "2026-06-30")
	member.add_availability({"kind": "DAY_OFF", "weekday": 0})
	var restored: CrewScript = CrewScript.from_dict(member.to_dict())
	assert(String(restored.id) == "C1" and restored.name == "Dana")
	assert(restored.role == &"FOREMAN")
	assert(restored.home_base.is_equal_approx(Vector2(12.0, -3.5)))
	assert(restored.rate_on("2026-02-01").format() == "45.00")
	assert(restored.has_certification("First aid", "2026-05-01"))
	assert(not restored.available_on("2026-06-07"))


func test_a_record_with_no_id_is_dropped_and_a_bad_role_is_the_common_one() -> void:
	assert(CrewScript.from_dict({"name": "nobody"}) == null)
	var made: CrewScript = CrewScript.from_dict({"id": "C1", "role": "WIZARD"})
	assert(made.role == &"LABOURER", "a person has to be something, so the common case")