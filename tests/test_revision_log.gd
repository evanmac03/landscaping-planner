extends Node
## Tests for the revision log: what a revision is, what is kept when the log is full, and what the
## difference between two of them says.
##
## A bare `DraftRevisionLog.new()` and hand-written drawing *states*, because the log is a pure model of
## a history: it knows nothing about documents, canvases or files, and can therefore be held down
## without any of them.

const LogScript := preload("res://scripts/draft/revision_log.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")


## A drawing with one line and one rectangle in it, as `to_dict()` would hand it over.
func _state(extra: bool = false) -> Dictionary:
	var document: DraftDocument = Document.new()
	document.add(Entity.make_line(Vector2(0.0, 0.0), Vector2(4.0, 0.0)), LayerSet.NEW_HARDSCAPE)
	document.add(
		Entity.make_rectangle(Vector2(0.0, 2.0), Vector2(3.0, 3.0)), LayerSet.NEW_BED
	)
	if extra:
		document.add(Entity.make_line(Vector2(0.0, 6.0), Vector2(4.0, 6.0)), LayerSet.NEW_TURF)
	return document.to_dict()


# --- keeping a revision -----------------------------------------------------------------


func test_a_revision_keeps_the_drawing_the_message_who_and_when() -> void:
	var log: DraftRevisionLog = LogScript.make()
	var record: Dictionary = log.capture(_state(), "  sent to the client  ", "evan")
	assert(log.count() == 1)
	assert(String(record["message"]) == "sent to the client", "the message is trimmed: %s" % record["message"])
	assert(String(record["author"]) == "evan")
	assert(int(record["shapes"]) == 2, "and how big the drawing was")
	assert(not String(record["when"]).is_empty(), "a revision is dated")
	assert(log.describe(0).begins_with("rev 1  sent to the client"), log.describe(0))
	assert(log.describe(0).contains("2 shapes"), log.describe(0))


func test_a_revision_nobody_explained_is_still_a_revision() -> void:
	var log: DraftRevisionLog = LogScript.make()
	log.capture(_state(), "   ", "")
	assert(log.messages() == ["no message"], str(log.messages()))
	assert(log.describe(0).contains("no message"))
	# A log with nothing in it answers every question with nothing rather than failing.
	var empty: DraftRevisionLog = LogScript.make()
	assert(empty.count() == 0)
	assert(empty.snapshot(0).is_empty())
	assert(empty.describe(3) == "")
	assert(empty.messages().is_empty())


func test_the_snapshot_handed_out_is_a_copy() -> void:
	var log: DraftRevisionLog = LogScript.make()
	log.capture(_state(), "first")
	var state: Dictionary = log.snapshot(0)
	state["entities"] = {}
	assert(log.record_at(0)["shapes"] == 2, "changing what was handed out cannot change the revision")


func test_the_oldest_revisions_fall_off_and_are_counted() -> void:
	var log: DraftRevisionLog = LogScript.make()
	for index in LogScript.LIMIT + 5:
		log.capture(_state(), "rev %d" % index)
	assert(log.count() == LogScript.LIMIT, "the log is capped")
	assert(log.dropped == 5, "and says how many it let go: %d" % log.dropped)
	assert(log.messages()[0] == "rev 5", "the oldest kept is the sixth recorded")


func test_a_log_survives_the_file_format() -> void:
	var log: DraftRevisionLog = LogScript.make()
	log.capture(_state(), "sent to the client", "evan")
	log.capture(_state(true), "client asked for more lawn")
	log.dropped = 2
	var back: DraftRevisionLog = LogScript.from_dict(
		JSON.parse_string(JSON.stringify(log.to_dict()))
	)
	assert(back.count() == 2)
	assert(back.messages() == ["sent to the client", "client asked for more lawn"],
		str(back.messages()))
	assert(back.dropped == 2)
	assert(back.record_at(0)["author"] == "evan", "who made it survives")
	assert(back.record_at(1)["shapes"] == 3, "and so does the drawing itself")
	# The drawing that comes back out is the drawing that went in, which is the whole promise of a
	# history: a revision that restores something slightly different is worse than no history.
	assert(back.snapshot(1) == log.snapshot(1), "the snapshot round trips")


func test_a_damaged_history_keeps_the_revisions_it_can_read() -> void:
	for junk: Variant in [null, {}, "not a log", {"records": "no"}, {"records": []}]:
		var log: DraftRevisionLog = LogScript.from_dict(junk)
		assert(log.count() == 0, "nothing to read is an empty history: %s" % str(junk))
	var partly: DraftRevisionLog = LogScript.from_dict({
		"records": [
			{"message": "kept", "snapshot": {"entities": {"1": {"kind": "line"}}}},
			"rubbish",
			{"message": "no snapshot at all"},
		],
	})
	assert(partly.count() == 1, "a record with no drawing in it is dropped: %d" % partly.count())
	assert(partly.messages() == ["kept"])


# --- the difference between two of them -------------------------------------------------


func test_the_difference_is_by_id_which_is_what_makes_it_possible() -> void:
	var before := {
		"entities": {
			"1": {"kind": "line", "points": [[0.0, 0.0], [4.0, 0.0]]},
			"2": {"kind": "rectangle", "points": [[0.0, 2.0], [3.0, 3.0]]},
		},
	}
	var after := {
		"entities": {
			# The same shape, widened: same id, different geometry.
			"2": {"kind": "rectangle", "points": [[0.0, 2.0], [5.0, 3.0]]},
			"3": {"kind": "circle", "centre": [1.0, 1.0], "radius": 2.0},
		},
	}
	var changes: Dictionary = LogScript.compare(before, after)
	assert(bool(changes["ok"]))
	assert(changes["added"] == [3], str(changes["added"]))
	assert(changes["changed"] == [2], "a widened bed is the same bed: %s" % str(changes["changed"]))
	assert(changes["removed"] == [1], str(changes["removed"]))
	assert(not bool(changes["same"]))
	assert(LogScript.describe_diff(changes).begins_with("1 added, 1 changed, 1 removed"),
		LogScript.describe_diff(changes))
	assert(LogScript.describe_diff(changes).contains("#2"), "and the shapes are named")


func test_two_identical_revisions_say_they_are_identical() -> void:
	var log: DraftRevisionLog = LogScript.make()
	log.capture(_state(), "first")
	log.capture(_state(), "second")
	var changes: Dictionary = log.diff(0, 1)
	assert(bool(changes["same"]), LogScript.describe_diff(changes))
	assert(LogScript.describe_diff(changes) == "the drawing is the same in both revisions",
		LogScript.describe_diff(changes))


## A revision kept in memory has integer keys and integer lengths; the same revision read back from a
## file has strings and floats. Compared without a round trip of both sides, a revision would differ
## from itself - which is the trap this test exists for.
func test_a_revision_is_not_different_from_itself_after_a_file() -> void:
	var log: DraftRevisionLog = LogScript.make()
	log.capture(_state(), "sent")
	var back: DraftRevisionLog = LogScript.from_dict(
		JSON.parse_string(JSON.stringify(log.to_dict()))
	)
	assert(bool(back.diff(0, 0)["same"]), "a revision is never a change from itself")
	var recorded: DraftRevisionLog = LogScript.make()
	recorded.capture(_state(), "a copy of the same drawing")
	assert(bool(back.diff(0, 0)["same"]))
	# And a snapshot taken in memory compares equal to the same snapshot read back.
	assert(bool(LogScript.compare(recorded.snapshot(0), back.snapshot(0))["same"]),
		"a drawing from memory and the same drawing from a file are the same drawing")


func test_two_revisions_of_a_real_drawing_report_what_changed() -> void:
	var log: DraftRevisionLog = LogScript.make()
	log.capture(_state(), "first")
	log.capture(_state(true), "a line of turf added")
	var changes: Dictionary = log.diff(0, 1)
	assert(changes["added"].size() == 1, "one shape was added")
	assert(changes["changed"].is_empty(), "and nothing else moved")
	assert(changes["removed"].is_empty())
	assert(LogScript.describe_diff(changes).begins_with("1 added"), LogScript.describe_diff(changes))


func test_a_difference_that_cannot_be_asked_for_says_so() -> void:
	var log: DraftRevisionLog = LogScript.make()
	log.capture(_state(), "only one")
	var changes: Dictionary = log.diff(0, 4)
	assert(not bool(changes["ok"]))
	assert(LogScript.describe_diff(changes) == "there is no such revision", LogScript.describe_diff(changes))
	assert(LogScript.describe_diff({}) == "the two revisions cannot be compared")