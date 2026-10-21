extends Node
## The copy kept in case the program stops without being asked.
##
## The module's own rules, tested with no controller and no scene: what it writes, what it refuses to
## write, what it reads back, and the one question that decides whether a copy is a rescue or somebody's
## own file handed back to them.
##
## Every test clears the recovery folder before it starts and again when it ends - a test that throws
## part-way through must not leave a copy of a test drawing waiting in the app the next time somebody
## opens it, and a copy left by one test must not be the reason the next one fails.

const AutosaveScript := preload("res://scripts/draft/autosave.gd")
const StoreScript := preload("res://scripts/draft/drawing_store.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")

## A drawing of its own, so that nothing here touches a drawing the project ships or a test another
## file owns.
const SCRATCH := "user://drawings/test-autosave.json"


## A drawing, as the controller would hold it.
func _document(count: int = 2) -> DraftDocument:
	var document := DocumentScript.new()
	for index in count:
		document.add(
			EntityScript.make_line(Vector2(0, index), Vector2(4, 2 + index)), LayerSetScript.NEW_HARDSCAPE
		)
	return document


## The same drawing, as the file format would hold it.
func _state(count: int = 2) -> Dictionary:
	return _document(count).to_dict()


func _write_text(to_path: String, text: String) -> void:
	AutosaveScript.ensure_dir()
	var file := FileAccess.open(to_path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


func _clean() -> void:
	AutosaveScript.clear_all()
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(SCRATCH)


func test_a_copy_is_a_file_that_comes_back_the_way_it_went_in() -> void:
	_clean()
	var kept: Dictionary = AutosaveScript.write(_state(3), "", "Backyard Design", 7)
	assert(bool(kept["ok"]), String(kept["reason"]))
	assert(String(kept["path"]) == "user://recovery/untitled.json", String(kept["path"]))
	var found: Dictionary = AutosaveScript.read(String(kept["path"]))
	assert(bool(found["ok"]), String(found["reason"]))
	assert(String(found["project_name"]) == "Backyard Design", String(found["project_name"]))
	assert(int(found["serial"]) == 7, str(found["serial"]))
	var state: Dictionary = found["state"]
	var entities: Dictionary = state["entities"]
	assert(entities.size() == 3, str(entities.size()))
	assert(not String(found["when"]).is_empty(), "and when it was kept is written down")
	_clean()


func test_a_copy_is_only_written_when_there_is_something_to_recover() -> void:
	# The refusal is the design: a copy of nothing, offered on the next launch, teaches a person to
	# click past the offer that matters.
	_clean()
	var empty: Dictionary = AutosaveScript.write({}, "", "", 0)
	assert(not bool(empty["ok"]), "an empty state is refused")
	assert(String(empty["reason"]) == "there is no drawing to keep a copy of", String(empty["reason"]))
	var nothing: Dictionary = AutosaveScript.write(_state(0), "", "", 0)
	assert(not bool(nothing["ok"]), "a drawing with nothing drawn on it is refused")
	assert(
		String(nothing["reason"]) == "this drawing is empty, so there is nothing worth keeping",
		String(nothing["reason"])
	)
	assert(AutosaveScript.list().is_empty(), "and refusing wrote nothing at all")
	assert(AutosaveScript.has_work(_state(1)), "whereas one shape is work")
	assert(not AutosaveScript.has_work(_state(0)), "and none is not")
	_clean()


func test_a_copy_of_a_drawing_that_is_already_on_disk_is_not_a_rescue() -> void:
	_clean()
	var written: Dictionary = StoreScript.write(_document(3), SCRATCH)
	assert(bool(written["ok"]), String(written["reason"]))
	# The same drawing as the file holds: a copy taken a moment before the save, which is the copy a
	# crash between the two writes would leave behind.
	AutosaveScript.write(_state(3), SCRATCH, "", 3)
	var found: Dictionary = AutosaveScript.read(AutosaveScript.path_for(SCRATCH))
	assert(bool(found["ok"]), String(found["reason"]))
	assert(not AutosaveScript.still_wanted(found), "the file already holds it, so it is not a rescue")
	assert(AutosaveScript.newest_wanted().is_empty(), "and so nothing is offered")
	# One shape more than the file holds: work that exists nowhere else.
	AutosaveScript.write(_state(4), SCRATCH, "", 4)
	var bigger: Dictionary = AutosaveScript.read(AutosaveScript.path_for(SCRATCH))
	assert(AutosaveScript.still_wanted(bigger), "a copy holding more than the file does is still wanted")
	assert(not AutosaveScript.newest_wanted().is_empty(), "and it is what gets offered")
	_clean()


func test_a_copy_whose_drawing_has_never_been_saved_is_always_a_rescue() -> void:
	# There is no file to compare against, so the copy is all there is. The same is true of a copy whose
	# file has since been deleted, which is the case that makes the comparison worth having at all.
	_clean()
	AutosaveScript.write(_state(2), "", "A", 1)
	var found: Dictionary = AutosaveScript.newest_wanted()
	assert(not found.is_empty(), "a drawing that has never been saved has a copy that is a rescue")
	assert(String(found["drawing_path"]) == "", "and it belongs to no file")
	assert(AutosaveScript.still_wanted(found), "with nothing to compare it against")
	_clean()


func test_one_identity_is_one_file_and_the_newer_copy_is_the_one_in_it() -> void:
	_clean()
	AutosaveScript.write(_state(2), "", "A", 1)
	AutosaveScript.write(_state(5), "", "B", 9)
	assert(AutosaveScript.list().size() == 1, "a nameless drawing has one slot, however often it is kept")
	var found: Dictionary = AutosaveScript.newest_wanted()
	assert(int(found["serial"]) == 9, "and what is in the slot is the newest copy, not the first")
	# A different drawing is a different identity, and so a second file rather than a replacement.
	AutosaveScript.write(_state(2), SCRATCH, "Backyard", 3)
	assert(AutosaveScript.list().size() == 2, "a named drawing is filed apart from a nameless one")
	assert(not AutosaveScript.newest_wanted().is_empty(), "and one of the two is still offered")
	_clean()


func test_a_file_that_is_not_a_copy_is_refused_rather_than_restored() -> void:
	# "It did not open" is not something a person can act on, so every refusal says which it is - and a
	# copy this build does not understand is refused rather than half-read into somebody's drawing.
	_clean()
	var missing: Dictionary = AutosaveScript.read(AutosaveScript.path_for(""))
	assert(not bool(missing["ok"]), "a copy that is not there is refused")
	assert(String(missing["reason"]) == "there is no copy called untitled.json", String(missing["reason"]))
	assert(not bool(AutosaveScript.read("")["ok"]), "and so is a read that named nothing")

	_write_text(AutosaveScript.path_for(""), "this is not a copy of anything")
	var broken: Dictionary = AutosaveScript.read(AutosaveScript.path_for(""))
	assert(not bool(broken["ok"]), "a file that will not parse is refused")
	assert(
		String(broken["reason"]).begins_with("untitled.json is not readable"),
		String(broken["reason"])
	)

	_write_text(AutosaveScript.path_for(""), JSON.stringify({"hello": "there"}))
	assert(
		String(AutosaveScript.read(AutosaveScript.path_for(""))["reason"])
			== "untitled.json is not a copy of a drawing",
		"JSON that is not a copy is refused"
	)

	_write_text(AutosaveScript.path_for(""), JSON.stringify([1, 2, 3]))
	assert(not bool(AutosaveScript.read(AutosaveScript.path_for(""))["ok"]), "a list is not a copy")

	_write_text(
		AutosaveScript.path_for(""),
		JSON.stringify({"version": 99, "state": {"entities": {"1": {}}}})
	)
	assert(
		not bool(AutosaveScript.read(AutosaveScript.path_for(""))["ok"]),
		"a copy written by a later build is refused rather than read for the parts this one knows"
	)

	_write_text(AutosaveScript.path_for(""), JSON.stringify({"version": 1, "state": 4}))
	assert(
		not bool(AutosaveScript.read(AutosaveScript.path_for(""))["ok"]),
		"and a copy with no drawing in it is not a copy of an empty drawing"
	)

	# None of those was offered, because none of them read.
	assert(AutosaveScript.newest_wanted().is_empty(), "a file that will not read is not a rescue")
	_clean()


func test_clearing_a_copy_that_is_not_there_is_not_a_failure() -> void:
	# It is the state the call exists to reach, so it cannot be an error: a save clears the copy of a
	# drawing that was never copied.
	_clean()
	assert(AutosaveScript.clear(""), "clearing a copy that is not there is the ordinary case")
	AutosaveScript.write(_state(2), "", "", 1)
	assert(AutosaveScript.list().size() == 1, "a copy is there")
	assert(AutosaveScript.clear(""), "and clearing it works")
	assert(AutosaveScript.list().is_empty(), "and it is gone")
	_clean()


func test_the_interval_is_what_stops_a_copy_every_frame() -> void:
	assert(not AutosaveScript.is_due(true, 0.0), "a copy is not kept on the frame it was asked for")
	assert(not AutosaveScript.is_due(true, AutosaveScript.INTERVAL - 0.1), "nor a moment before it is due")
	assert(AutosaveScript.is_due(true, AutosaveScript.INTERVAL), "it is due at the interval")
	assert(AutosaveScript.is_due(true, 900.0), "and later than that, if the frame was long")
	assert(not AutosaveScript.is_due(false, 900.0), "a drawing that has been saved is never due")
	assert(AutosaveScript.INTERVAL > 1.0, "and the interval is long enough to be worth having")


func test_a_copy_is_filed_under_the_drawing_and_a_nameless_one_under_untitled() -> void:
	assert(
		AutosaveScript.path_for("") == "user://recovery/untitled.json",
		AutosaveScript.path_for("")
	)
	assert(
		AutosaveScript.path_for("user://drawings/Backyard.json") == "user://recovery/Backyard.json",
		AutosaveScript.path_for("user://drawings/Backyard.json")
	)
	# The file name is made safe the same way a drawing's is, so a copy cannot be written somewhere the
	# rest of the program would not look for it.
	assert(
		AutosaveScript.path_for("user://drawings/front bed 2.json") == "user://recovery/front bed 2.json",
		AutosaveScript.path_for("user://drawings/front bed 2.json")
	)


func test_the_moment_reads_as_a_clock_and_a_string_that_is_not_a_moment_reads_as_itself() -> void:
	assert(AutosaveScript.clock_of("2026-05-03 14:32:10") == "14:32", AutosaveScript.clock_of("2026-05-03 14:32:10"))
	assert(AutosaveScript.clock_of("yesterday") == "yesterday", "a moment that is not one is read as itself")
	assert(AutosaveScript.clock_of("") == "", "and nothing reads as nothing")


func test_a_copy_describes_itself_the_way_a_person_is_told_about_it() -> void:
	var one: Dictionary = {
		"drawing_path": "user://drawings/Backyard.json",
		"when": "2026-05-03 14:32:10",
		"state": _state(1),
	}
	assert(
		AutosaveScript.describe(one) == "Backyard, 1 shape, kept 14:32",
		AutosaveScript.describe(one)
	)
	var many: Dictionary = {"drawing_path": "", "when": "2026-05-03 09:05:00", "state": _state(12)}
	assert(
		AutosaveScript.describe(many) == "untitled, 12 shapes, kept 09:05",
		AutosaveScript.describe(many)
	)
	# A copy read off disk rather than written here describes itself the same way, which is what makes
	# the sentence a person sees the sentence the file holds.
	_clean()
	var kept: Dictionary = AutosaveScript.write(_state(3), SCRATCH, "", 3)
	var found: Dictionary = AutosaveScript.read(String(kept["path"]))
	assert(
		String(AutosaveScript.describe(found)).begins_with("test-autosave, 3 shapes, kept "),
		AutosaveScript.describe(found)
	)
	# A damaged copy that somehow got this far says nothing rather than crashing: no shapes is the
	# honest count for a state with no drawing in it.
	assert(
		AutosaveScript.describe({"drawing_path": "", "when": "", "state": {}}) == "untitled, 0 shapes",
		AutosaveScript.describe({"drawing_path": "", "when": "", "state": {}})
	)
	_clean()