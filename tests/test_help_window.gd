extends Node
## The page that shows the manual: its contents, the subject it is showing, and the search.
##
## Built off-tree and never popped up: `popup_centered` needs a window server and a test process has
## not got one, so the rows and the search box are driven the way a click and a keystroke drive them -
## which is what the list's `item_selected` and the box's `text_changed` end up calling.
##
## What is under test is that the page shows the manual's own words rather than a copy of them, that a
## search narrows the contents without losing the manual behind it, and that nothing in here but the
## search box can take the keyboard.

const HelpWindowScript := preload("res://scripts/help_window.gd")
const HelpDocScript := preload("res://scripts/help_doc.gd")


## A page with the manual on it, as the HUD leaves it before showing it.
func _page() -> HelpWindowScript:
	var page: HelpWindowScript = HelpWindowScript.new()
	page.build()
	page.set_topics(HelpDocScript.topics())
	return page


func test_the_contents_lists_every_subject_the_manual_has() -> void:
	var page: HelpWindowScript = _page()
	assert(page.topic_count() == HelpDocScript.topic_count(), "every subject is on the page")
	assert(page.list_texts() == HelpDocScript.titles(), "and the contents is the manual's own list")
	assert(page.shown_count() == page.topic_count(), "with nothing filtered out")
	page.free()


func test_choosing_a_subject_shows_that_subject() -> void:
	var page: HelpWindowScript = _page()
	assert(page.shown_topic_index() == 0, "a page opens on its first subject")
	assert(page.shown_title() == HelpDocScript.title_at(0), "and names it")
	assert(page.shown_body() == HelpDocScript.body_for(HelpDocScript.title_at(0)), "and shows its body")
	assert(page.select(3), "a row of the contents can be chosen")
	assert(page.shown_topic_index() == 3, "which is the subject that row stands for")
	assert(page.shown_title() == HelpDocScript.title_at(3))
	assert(page.shown_body() == HelpDocScript.body_for(HelpDocScript.title_at(3)))
	assert(page.shown_body().length() > 100, "and something is actually written there")
	assert(not page.select(9999), "there is no row past the end of the contents")
	assert(not page.select(-1), "and none before the beginning")
	assert(page.shown_topic_index() == 3, "so the page is left where it was")
	page.free()


func test_a_subject_can_be_chosen_by_its_name() -> void:
	var page: HelpWindowScript = _page()
	assert(page.select_topic("Plants"), "a subject is found by the name in the contents")
	assert(page.shown_title() == "Plants")
	assert(page.shown_body() == HelpDocScript.body_for("Plants"))
	assert(not page.select_topic("How to fly a kite"), "and a subject nobody has is not found")
	assert(page.shown_title() == "Plants", "which leaves the page where it was")
	page.free()


func test_the_search_narrows_the_contents_and_clearing_it_brings_them_back() -> void:
	var page: HelpWindowScript = _page()
	page.type_search("transformer")
	assert(page.shown_count() >= 1, "a search finds the subjects that mention the word")
	assert(page.shown_count() < page.topic_count(), "and leaves the rest out")
	assert(page.list_texts().size() == page.shown_count(), "the contents is exactly what was found")
	assert(page.shown_body().to_lower().contains("transformer"), "the page shows one of them")
	assert(
		page.topic_count() == HelpDocScript.topic_count(),
		"narrowing the contents does not throw the manual away"
	)
	page.type_search("")
	assert(page.shown_count() == HelpDocScript.topic_count(), "emptying the box is the way back")
	assert(page.shown_topic_index() == 0, "and the page goes back to the beginning")
	page.free()


func test_a_search_that_finds_nothing_says_so_rather_than_showing_a_near_miss() -> void:
	var page: HelpWindowScript = _page()
	page.type_search("zzzznotaword")
	assert(page.shown_count() == 0, "nothing is found")
	assert(page.list_texts().is_empty(), "so the contents is empty")
	assert(page.shown_topic_index() == -1, "and nothing is on the page")
	assert(page.shown_title() == "Nothing found", "the page says so rather than showing the last one")
	assert(page.shown_body().contains("zzzznotaword"), "and names what was asked for")
	assert(page.said().contains("zzzznotaword"), "the status line says it too")
	page.type_search("")
	assert(page.shown_topic_index() == 0, "and clearing the box puts a subject back on the page")
	page.free()


func test_a_search_says_how_much_of_the_manual_it_found() -> void:
	var page: HelpWindowScript = _page()
	assert(page.said().contains(str(HelpDocScript.topic_count())), "the status line counts the manual")
	page.type_search("valve")
	assert(page.said().contains(str(page.shown_count())), "and says how many the search found")
	assert(page.said().contains("valve"), "and names the word it looked for")
	page.free()


func test_a_page_with_no_manual_at_all_says_exactly_that() -> void:
	var page: HelpWindowScript = HelpWindowScript.new()
	page.build()
	assert(page.topic_count() == 0, "there are no subjects")
	assert(page.shown_count() == 0)
	assert(page.shown_topic_index() == -1)
	assert(page.shown_title() == "The manual is empty", "the page does not blame the search box for it")
	assert(page.said() != "", "and says something about it")
	page.free()


func test_the_page_does_not_take_the_keyboard_except_in_the_search_box() -> void:
	var page: HelpWindowScript = _page()
	assert(
		page.topics_list().focus_mode == Control.FOCUS_NONE,
		"a list is picked from rather than typed into"
	)
	assert(
		page.body_view().focus_mode == Control.FOCUS_NONE,
		"and prose is read rather than typed into, even when a sentence is selected"
	)
	assert(page.search_field() != null, "the search box is the one control that may hold the keyboard")
	assert(
		page.search_field().focus_mode != Control.FOCUS_NONE,
		"which it does, because a manual this long is looked things up in"
	)
	page.free()


func test_closing_the_page_takes_it_off_the_screen_and_announces_itself() -> void:
	# A `Window` is visible the moment it is made, which is the trap the site-map window fell into -
	# so being open is a property of being *shown*, and the HUD is what hides a page it has built.
	# What is under test here is that closing says so, takes the page off the screen, and leaves what
	# it was showing where it was.
	var page: HelpWindowScript = _page()
	var told := {"closed": false}
	page.closed.connect(func() -> void: told["closed"] = true)
	page.visible = true
	page.close_requested.emit()
	assert(told["closed"], "the page says so when it is closed")
	assert(not page.visible, "and takes itself off the screen")
	assert(page.shown_topic_index() == 0, "keeping what it was showing for next time")
	page.free()