extends Node
## Tests for the render batch: the ledger of what to render and what came back.
##
## The behaviour worth pinning is that it is a *ledger* rather than a loop - it hands out
## one job at a time and files the outcome - and that one view which will not render does
## not cost the others. A batch that stopped at the first failure would turn a missing sun
## study into a proposal with no plan in it.

const Batch := preload("res://scripts/vis/render_batch.gd")


func _fake_batch() -> Batch:
	var batch := Batch.new()
	batch.add("Painted plan", &"a3_300", "Painted plan")
	batch.add("3D presentation", &"hd", "3D presentation")
	return batch


func test_a_new_batch_holds_nothing() -> void:
	var batch := Batch.new()
	assert(batch.is_empty())
	assert(batch.count() == 0)
	assert(batch.names().is_empty())
	assert(batch.refusal() != "", "an empty batch says why it cannot run")


func test_a_job_carries_its_name_its_size_and_its_view() -> void:
	var batch := Batch.new()
	assert(batch.add("Painted plan", &"a3_300", "Painted plan", true, "the wash"), "the job was taken")
	var job: Dictionary = batch.jobs()[0]
	assert(String(job["name"]) == "Painted plan")
	assert(StringName(job["preset"]) == &"a3_300")
	assert(String(job["view"]) == "Painted plan")
	assert(bool(job["flatten"]))
	assert(String(job["note"]) == "the wash")


func test_one_name_is_one_job() -> void:
	var batch := Batch.new()
	assert(batch.add("Painted plan", &"hd"))
	assert(not batch.add("Painted plan", &"a3_300"), "a second job with the first's name is refused")
	assert(batch.count() == 1, "the duplicate did not become a job")
	# A name of nothing is not a name.
	assert(not batch.add("   ", &"hd"), "a blank name is refused")


func test_a_batch_is_capped_and_a_full_one_refuses() -> void:
	var batch := Batch.new()
	for index in Batch.MAX_JOBS:
		assert(batch.add("view %d" % index, &"hd"), "job %d should fit" % index)
	assert(batch.count() == Batch.MAX_JOBS)
	assert(not batch.add("one too many", &"hd"), "a full batch refuses")


func test_every_view_adds_the_standard_four_once() -> void:
	var batch := Batch.new()
	var added: int = batch.add_every_view(&"hd")
	assert(added == Batch.DEFAULT_VIEWS.size(), "the four views were added")
	assert(batch.count() == Batch.DEFAULT_VIEWS.size())
	# Running it again adds nothing, because every view is already a job.
	assert(batch.add_every_view(&"hd") == 0, "the views are already in the batch")


func test_next_job_hands_out_the_unattempted_ones_in_order() -> void:
	var batch := _fake_batch()
	assert(String(batch.next_job()["name"]) == "Painted plan")
	batch.record("Painted plan", "/p/a.png")
	assert(String(batch.next_job()["name"]) == "3D presentation", "the next one is the second")
	batch.record("3D presentation", "/p/b.png")
	assert(batch.next_job().is_empty(), "there is nothing left")
	assert(batch.is_done())


func test_an_outcome_is_recorded_once_per_job() -> void:
	var batch := _fake_batch()
	assert(batch.record("Painted plan", "/p/a.png"))
	assert(not batch.record("Painted plan", "/p/again.png"), "a job's outcome is filed once")
	# An outcome for a job the batch does not have is refused rather than invented.
	assert(not batch.record("Sun study", "/p/s.png"))
	assert(batch.attempted() == 1)


func test_a_failure_is_counted_and_the_batch_carries_on() -> void:
	var batch := _fake_batch()
	batch.record("Painted plan", "")
	batch.record("3D presentation", "/p/b.png")
	assert(batch.succeeded() == 1)
	assert(batch.failed() == 1)
	assert(batch.is_done(), "one failure does not stop the batch finishing")
	assert(batch.summary().contains("1 could not be"), "the summary counts the failure: %s" % batch.summary())
	assert(batch.report_text().contains("could not be rendered"), "the report names it")


func test_the_summary_says_what_state_the_batch_is_in() -> void:
	var batch := Batch.new()
	assert(batch.summary() == "nothing to render")
	batch.add("Painted plan", &"hd")
	batch.add("Sun study", &"hd")
	assert(batch.summary().contains("waiting"), "before anything runs it is waiting: %s" % batch.summary())
	batch.record("Painted plan", "/p/a.png")
	assert(batch.summary().contains("1 of 2"), "half-way reads as a count: %s" % batch.summary())
	batch.record("Sun study", "/p/s.png")
	assert(batch.summary() == "2 of 2 stills rendered", "got %s" % batch.summary())


func test_a_finished_batch_refuses_to_run_again() -> void:
	var batch := Batch.new()
	batch.add("Painted plan", &"hd")
	batch.record("Painted plan", "/p/a.png")
	assert(batch.refusal() != "", "a finished batch says so")


func test_the_batch_can_be_driven_by_a_synchronous_executor() -> void:
	var batch := _fake_batch()
	var outcome: Dictionary = batch.run(func(job: Dictionary) -> String:
		return "/p/%s.png" % String(job["name"]).to_lower().replace(" ", "-"))
	assert(bool(outcome["ok"]))
	assert(int(outcome["succeeded"]) == 2)
	assert(int(outcome["waiting"]) == 0)
	assert(batch.is_done())


func test_the_executor_may_refuse_one_and_the_rest_still_run() -> void:
	var batch := _fake_batch()
	var outcome: Dictionary = batch.run(func(job: Dictionary) -> String:
		return "" if String(job["name"]) == "3D presentation" else "/p/a.png")
	assert(int(outcome["failed"]) == 1, "the refusal was counted")
	assert(int(outcome["succeeded"]) == 1, "the other still was rendered")
	assert(batch.is_done())


func test_a_batch_is_a_thing_a_person_makes_once() -> void:
	var batch := _fake_batch()
	batch.record("Painted plan", "/p/a.png")
	batch.clear()
	assert(batch.is_empty())
	assert(batch.results().is_empty())
	assert(batch.summary() == "nothing to render")


func test_the_report_reads_one_line_per_job_in_order() -> void:
	var batch := _fake_batch()
	batch.record("Painted plan", "/p/a.png")
	var lines: PackedStringArray = batch.report_text().split("\n")
	assert(lines.size() == 2, "one line a job")
	assert(lines[0].contains("Painted plan") and lines[0].contains("/p/a.png"), "the first line names the file")
	assert(lines[1].contains("waiting"), "the untouched job reads as waiting: %s" % lines[1])


func test_a_refused_name_is_refused_in_words() -> void:
	# The batch says *why* a still will not be taken, so a panel driving it has a sentence to show
	# rather than a bare false to invent a reason for.
	var batch := _fake_batch()
	assert(batch.reason_against("Working plan") == "", "a name nobody has is free")
	assert(batch.add("A new one", "hd", "Painted plan"))
	assert(batch.reason_against("Working plan") == "", "and the old name is still free")
	assert(batch.reason_against("A new one").contains("already"), "a taken name says so: %s" % batch.reason_against("A new one"))
	assert(batch.reason_against("A new one").contains("A new one"), "and names it")
	assert(batch.reason_against("   ").contains("name"), "a blank one asks for a name: %s" % batch.reason_against("   "))
	# A full batch refuses the next one, and says how many it holds.
	var small := Batch.new()
	for index in small.MAX_JOBS:
		assert(small.add("still %d" % index, "hd", "Painted plan"), "still %d fits" % index)
	assert(small.reason_against("one too many").contains(str(small.MAX_JOBS)), "a full batch counts itself: %s" % small.reason_against("one too many"))
	assert(not small.add("one too many", "hd", "Painted plan"))