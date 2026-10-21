extends Node
## The HUD's side of the pipeline: the Pipeline menu's way in, and what the board's own words make
## the menu say.
##
## The board is built by hand here and never shown: what is under test is the wiring, and the board is
## never popped up, because a `Window` popped up with no tree to hang it on hangs the process.

const HudScript := preload("res://scripts/hud.gd")


## Free the Hud and the board it built. A Node is not reference counted, and a leaked one is reported
## as a resource still in use at exit - which the runner counts as a failing test.
func _done(hud) -> void:
	hud.free()


func _entry(id: StringName) -> Dictionary:
	for entry: Dictionary in HudScript.menu_entries():
		if StringName(entry.get("id", &"")) == id:
			return entry
	assert(false, "no menu entry with id %s" % String(id))
	return {}


# --- the way in -----------------------------------------------------------------------


func test_the_pipeline_menu_offers_the_board() -> void:
	var entry: Dictionary = _entry(&"pipeline.board")
	assert(String(entry["label"]) == "Open the pipeline board...", String(entry["label"]))
	assert(StringName(entry["method"]) == &"_menu_pipeline_board", String(entry["method"]))
	# A lead is business data, not drawing data, so the entry needs nothing open to be available.
	assert(entry["needs"] == HudScript.NEEDS_NOTHING, "the board needs no drawing")
	var ids: Array[String] = []
	for listed: Dictionary in HudScript.items_for("Pipeline"):
		ids.append(String(listed.get("id", "")))
	assert(ids.has("pipeline.info"), "the menu reports the open pipeline")
	assert(ids.has("pipeline.board"), "and offers the board")
	var hud := HudScript.new()
	assert(hud.has_method(String(entry["method"])), "the method the entry names exists")
	_done(hud)


func test_a_hud_with_no_board_reports_no_leads() -> void:
	var hud := HudScript.new()
	assert(hud._pipeline_text() == "no open leads")
	assert(not hud.is_pipeline_board_open(), "and nothing is open")
	_done(hud)


# --- what the board's words make the menu say -----------------------------------------


func test_building_the_board_gives_the_menu_a_line_to_read() -> void:
	var hud := HudScript.new()
	hud._build_pipeline_board()
	assert(hud._pipeline_board != null, "the board was built")
	assert(hud._pipeline_board.get_parent() == hud, "and it is the HUD's own child")
	# An empty board has no open leads yet, in the board's own words.
	assert(hud._pipeline_text() == "no open leads")
	_done(hud)


func test_a_lead_on_the_board_is_what_the_menu_line_says() -> void:
	var hud := HudScript.new()
	hud._build_pipeline_board()
	var id: String = hud._pipeline_board.add_lead("Smith, patio", 500000)["id"]
	assert(hud._pipeline_text() == "open: 1 leads worth 5,000.00, weighted 500.00",
		hud._pipeline_text())
	# Moving it up the funnel changes the weighted figure the menu advertises.
	hud._pipeline_board.move_lead(id, 4)  # PROPOSED, weighed at 80%
	assert(hud._pipeline_text() == "open: 1 leads worth 5,000.00, weighted 4,000.00",
		hud._pipeline_text())
	_done(hud)


func test_closing_a_lead_as_lost_leaves_it_out_of_the_open_line() -> void:
	var hud := HudScript.new()
	hud._build_pipeline_board()
	var id: String = hud._pipeline_board.add_lead("Smith", 500000)["id"]
	hud._pipeline_board.move_lead(id, 6)  # LOST, held for a reason
	hud._pipeline_board.confirm_move("price")
	assert(hud._pipeline_text() == "no open leads", "a lost lead is not open")
	_done(hud)


func test_a_board_built_but_not_shown_is_not_open() -> void:
	var hud := HudScript.new()
	hud._build_pipeline_board()
	assert(not hud.is_pipeline_board_open(), "built is not shown")
	_done(hud)