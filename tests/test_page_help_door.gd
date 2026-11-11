extends Node
## The manual's door, from the page a person is looking at.
##
## The door is F1 and a Help-menu entry, and both come down to one question: *which subject answers what
## the page in front of me is asking*. So the question is what is tested here, on a bare HUD with the
## page variables set by hand - no scene, no drawing and no popping a window, because a bare `Hud` never
## runs `_ready` and `popup_centered` is not something a test should be doing.
##
## The refusals are as much of the feature as the answers: a page the manual has not reached has to say
## what that page is about, or the person holding the gap cannot pick it up.

const Hud := preload("res://scripts/hud.gd")
const SnapWindowScript := preload("res://scripts/snap_window.gd")
const HelpWindowScript := preload("res://scripts/help_window.gd")
const JobCostWindowScript := preload("res://scripts/job_cost_window.gd")
const PageHelpScript := preload("res://scripts/page_help.gd")

var _hud: Hud = null
var _pages: Array[Window] = []


func _free_all() -> void:
	for page: Window in _pages:
		page.free()
	_pages.clear()
	if _hud != null:
		_hud.free()
		_hud = null


## A HUD built by hand and never put in a tree, which is how the suite drives this HUD's decisions.
func _bare_hud() -> Hud:
	_hud = Hud.new()
	return _hud


func _page(script: Script) -> Window:
	var page: Window = script.new()
	page.build()
	_pages.append(page)
	return page


func test_with_no_page_open_there_is_no_subject_and_the_refusal_says_so() -> void:
	var hud: Hud = _bare_hud()
	assert(hud.page_in_front() == null, "a HUD with nothing open has no page in front")
	assert(hud.page_help_subject() == "", "so there is no subject to show")
	assert(hud.page_help_refusal().contains("no page is open"),
		"and the refusal says that, rather than being empty: %s" % hud.page_help_refusal())
	assert(not hud.open_page_help(), "and the door does not open")
	_free_all()


func test_the_subject_is_the_one_the_page_in_front_points_at() -> void:
	var hud: Hud = _bare_hud()
	var snap: Window = _page(SnapWindowScript)
	hud._snap_window = snap as SnapWindow
	snap.visible = true
	assert(hud.page_in_front() == snap, "the one page that is up is the page in front")
	assert(hud.page_help_subject() == "Snapping and precision",
		"and the manual's subject for it is the one the table maps: %s" % hud.page_help_subject())
	assert(hud.page_help_refusal() == "", "there is nothing to refuse")
	_free_all()


func test_the_page_in_front_is_the_last_one_the_hud_has_up() -> void:
	var hud: Hud = _bare_hud()
	var snap: Window = _page(SnapWindowScript)
	var cost: Window = _page(JobCostWindowScript)
	hud._snap_window = snap as SnapWindow
	hud._cost_window = cost as JobCostWindow
	snap.visible = true
	cost.visible = true
	# Which of the two is "in front" is decided by the order the HUD's own page list holds them, so the
	# rule is stated the same way the door reads it: the last one up wins, whichever that is.
	var pages: Array[Window] = hud.pages_in_windows()
	var later: Window = null
	for page: Window in pages:
		if page == snap or page == cost:
			later = page
	assert(hud.page_in_front() == later,
		"the last of the two in the HUD's own list is the page in front")
	_free_all()


func test_a_page_the_manual_has_not_reached_refuses_and_says_what_the_page_is_about() -> void:
	var hud: Hud = _bare_hud()
	var cost: Window = _page(JobCostWindowScript)
	hud._cost_window = cost as JobCostWindow
	cost.visible = true
	assert(hud.page_help_subject() == "", "there is no subject to open")
	var refusal: String = hud.page_help_refusal()
	assert(refusal.contains("job_cost_window"), "the refusal names the page: %s" % refusal)
	assert(refusal.contains(String(PageHelpScript.NOT_YET_WRITTEN["job_cost_window"])),
		"and quotes what the table says the page is about, so the gap can be picked up: %s" % refusal)
	assert(not hud.open_page_help(), "and the door does not open")
	_free_all()


func test_a_page_that_needs_no_subject_says_why_rather_than_nothing() -> void:
	var hud: Hud = _bare_hud()
	var manual: Window = _page(HelpWindowScript)
	hud._help_window = manual as HelpWindow
	manual.visible = true
	assert(hud.page_help_subject() == "", "the manual has no subject of its own to open")
	assert(hud.page_help_refusal() == String(PageHelpScript.WITHOUT_NEED["help_window"]),
		"and says the reason the table gives, rather than saying nothing: %s" % hud.page_help_refusal())
	_free_all()


func test_the_door_is_reachable_from_the_menu_as_well_as_the_key() -> void:
	# The key is only discoverable if the menu says so, and a menu entry that runs something the key
	# cannot is two answers to one question.
	var hud: Hud = _bare_hud()
	var found: Dictionary = {}
	for group: Dictionary in hud.menu_plan():
		for entry: Dictionary in Array(group.get("items", [])):
			if String(entry.get("id", "")) == "help.this_page":
				found = entry
	assert(not found.is_empty(), "the Help menu offers what the page in front of you is about")
	assert(String(found.get("method", "")).contains("page_help"),
		"and it runs the same door the key does: %s" % str(found))
	_free_all()