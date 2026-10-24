extends Node
## The page that shows the manual: its contents, the subject it is showing, and the search.
##
## Built off-tree and never popped up: `popup_centered` needs a window server and a test process has
## not got one, so the rows and the search box are driven the way a click and a keystroke drive them -
## which is what the list's `item_selected` and the box's `text_changed` end up calling.
##
## What is under test is that the page shows the manual's own words rather than a copy of them, that a
## search narrows the contents without losing the manual behind it, that the contents is grouped under
## headings that are furniture rather than subjects, that the arrow keys walk from subject to subject
## while the search box holds the keyboard, that a subject can be left along the ones it points at, that
## what has been read can be walked back and forward, and that nothing in here but the search box can
## take the keyboard.

const HelpWindowScript := preload("res://scripts/help_window.gd")
const HelpDocScript := preload("res://scripts/help_doc.gd")


## A page with the manual on it, as the HUD leaves it before showing it.
func _page() -> HelpWindowScript:
	var page: HelpWindowScript = HelpWindowScript.new()
	page.build()
	page.set_topics(HelpDocScript.topics())
	return page


## A picture is read from its *bytes* rather than by path, because a picture that ships inside the
## program lives inside its pack file and only `FileAccess` can see into one - reading it by path would
## work in the editor and quietly stop working in a built copy. So the reader is pinned here against a
## real file of each kind the manual could carry, and against bytes that are not a picture at all.
func test_a_picture_is_decoded_from_its_bytes_by_its_own_kind() -> void:
	var webp := "res://assets/help/snapping.webp"
	assert(FileAccess.file_exists(webp), "the manual's own pictures are there to be read")
	var image: Image = HelpWindowScript.decode(webp, FileAccess.get_file_as_bytes(webp))
	assert(image != null, "a webp reads")
	assert(image.get_width() > 100 and image.get_height() > 100, "at the size it was taken at: %s" % image.get_size())
	var png := "res://resources/textures/hardscape/mulch_bark_albedo.png"
	assert(HelpWindowScript.decode(png, FileAccess.get_file_as_bytes(png)) != null, "and so does a png")
	assert(
		HelpWindowScript.decode("res://nothing_at_all.webp", "not a picture".to_utf8_buffer()) == null,
		"and bytes that are not a picture answer nothing rather than failing"
	)


## A subject shows the pictures it was handed, and one handed none shows no strip at all.
##
## Driven with synthetic topics pointing at a texture that is already in the project: what is under test
## is the page rather than the manual's own table, which `test_help_doc.gd` holds. The pictures arrive on
## the topic for the same reason the section does - a page that knew where the manual keeps its pictures
## would be a page that knows the manual's business.
func test_a_subject_shows_the_pictures_it_is_handed_and_none_without_them() -> void:
	var shown := "res://resources/textures/hardscape/mulch_bark_albedo.png"
	var topics: Array[Dictionary] = [
		{"title": "Illustrated", "body": "a subject with a picture", "pictures": [shown]},
		{"title": "Plain", "body": "a subject with none", "pictures": []},
		{
			"title": "Missing",
			"body": "a subject whose picture is not there",
			"pictures": ["res://resources/textures/hardscape/no_such_picture_at_all.png"],
		},
	]
	var page: HelpWindowScript = HelpWindowScript.new()
	page.build()
	page.set_topics(topics)
	var on_the_page := page.shown_pictures()
	assert(on_the_page.size() == 1 and on_the_page[0] == shown, "%s" % [on_the_page])
	assert(page.picture_view().visible, "the picture is on the page")
	assert(page.picture_view().get_child_count() == 1, "one picture, one view")
	# And the row can really be given a height. Asserted because it cannot be seen: a picture row with no
	# minimum height is laid out as nothing and the picture is on the page without ever being visible -
	# which is what happened when the height was left to follow from the picture's own shape.
	assert(
		page.picture_view().get_combined_minimum_size().y > 0.0,
		"the row has a height to be laid out in"
	)
	# A picture is for looking at, so it is not a thing the mouse or the keyboard can take the page with.
	var view := page.picture_view().get_child(0) as TextureRect
	assert(view != null, "it is a picture rather than something else")
	assert(view.mouse_filter == Control.MOUSE_FILTER_IGNORE, "a picture does not take a click")
	assert(view.focus_mode == Control.FOCUS_NONE, "nor the keyboard")
	# A subject with none leaves no strip standing over its prose.
	assert(page.select_topic("Plain"), "the next subject can be chosen")
	assert(page.shown_pictures().is_empty(), "%s" % [page.shown_pictures()])
	assert(not page.picture_view().visible, "and the row is not left empty")
	# And a picture that cannot be read is a page with no picture rather than a page that failed.
	assert(page.select_topic("Missing"))
	assert(page.shown_pictures().is_empty(), "%s" % [page.shown_pictures()])
	assert(not page.picture_view().visible)
	assert(page.picture_view().get_child_count() == 0, "nothing is left standing in its place")
	page.free()


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
	assert(page.select(page.row_of(HelpDocScript.title_at(3))), "a row of the contents can be chosen")
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
	assert(page.shown_count() >= 1, "a search finds the subjects that match the word")
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


func test_the_contents_is_grouped_under_headings_nobody_can_choose() -> void:
	var page: HelpWindowScript = _page()
	var headings: Array[String] = HelpDocScript.section_titles()
	var rows: Array[String] = page.list_rows()
	assert(headings.size() > 1, "the manual is filed under more than one heading")
	assert(
		rows.size() == page.topic_count() + headings.size(),
		"the list is every subject plus one heading per section"
	)
	for heading: String in headings:
		assert(rows.has(heading), "the contents is grouped under \"%s\"" % heading)
	assert(
		page.list_texts() == HelpDocScript.titles(),
		"and what it offers to read is still the manual's own list, headings left out of it"
	)
	# A heading is furniture: it is drawn in the list and it is not a subject, so choosing it is refused
	# rather than silently opening whatever happens to be filed under it.
	assert(rows[0] == headings[0], "the first row is the heading of the first section")
	assert(not page.select(0), "which cannot be chosen")
	assert(page.shown_topic_index() == 0, "so the page is left where it was")
	page.free()


func test_a_subject_can_point_at_another_and_pressing_that_goes_there() -> void:
	var page: HelpWindowScript = _page()
	assert(page.select_topic("Plants"), "a subject that points at others")
	assert(
		page.see_links() == HelpDocScript.see_for("Plants"),
		"the page offers exactly the subjects the manual points at"
	)
	var wanted: String = page.see_links()[0]
	assert(page.follow(wanted), "one of which can be pressed")
	assert(page.shown_title() == wanted, "and goes to the subject it names")
	assert(page.shown_body() == HelpDocScript.body_for(wanted), "showing that subject's own words")
	assert(not page.follow("How to fly a kite"), "a subject nobody has is not gone to")
	assert(page.said().contains("How to fly a kite"), "and the status line says so")
	assert(page.shown_title() == wanted, "leaving the page where it was")
	page.free()


func test_a_subject_that_points_at_nothing_offers_nothing_to_read_next() -> void:
	var page: HelpWindowScript = _page()
	assert(HelpDocScript.see_for("What this program is").is_empty(), "the manual says it points at nothing")
	assert(page.select_topic("What this program is"))
	assert(page.see_links().is_empty(), "so no buttons are drawn")
	assert(
		not page.see_view().visible,
		"and the row is hidden rather than left as an empty strip under the prose"
	)
	assert(page.select_topic("Plants"), "while a subject that does point at others")
	assert(page.see_view().visible, "brings the row back")
	page.free()


func test_a_cross_reference_works_while_the_search_is_hiding_what_it_names() -> void:
	var page: HelpWindowScript = _page()
	page.type_search("crop")
	assert(page.shown_count() < page.topic_count(), "the search is not the whole manual")
	assert(page.select_topic("Food: what will crop here"), "it did find the cropping subject")
	var links: Array[String] = page.see_links()
	assert(links == HelpDocScript.see_for("Food: what will crop here"), "which points at others")
	var hidden := ""
	for link: String in links:
		if page.row_of(link) < 0:
			hidden = link
	assert(hidden != "", "at least one of them is a *different* subject, and so not what the search found")
	assert(page.follow(hidden), "pressing it goes there all the same")
	assert(page.shown_title() == hidden, "to the subject it names")
	assert(page.search_text() == "", "the box is cleared, because a link names a subject and not a row")
	assert(page.row_of(hidden) >= 0, "which brings it back into the contents")
	page.free()


func test_the_page_can_be_walked_back_and_forward_along_what_has_been_read() -> void:
	var page: HelpWindowScript = _page()
	assert(not page.can_go_back(), "a page that has only just opened has nowhere to go back to")
	assert(not page.can_go_forward())
	assert(page.select_topic("Plants"), "turn to another subject")
	assert(page.can_go_back(), "and back is now somewhere to go")
	assert(page.back(), "so back goes there")
	assert(page.shown_topic_index() == 0, "to the subject the page opened on")
	assert(page.can_go_forward(), "and forward is somewhere to go too")
	assert(page.forward(), "so forward goes")
	assert(page.shown_title() == "Plants", "back to where the page was")
	assert(not page.can_go_forward(), "and no further, because that is the end of the walk")
	assert(page.back(), "walking back again")
	assert(page.select_topic("Light: garden lighting"), "and then somewhere new")
	assert(
		not page.can_go_forward(),
		"turning to a subject that was not read before drops the way forward"
	)
	page.free()


func test_a_search_starts_a_fresh_walk() -> void:
	var page: HelpWindowScript = _page()
	assert(page.select_topic("Plants"), "a subject read")
	assert(page.can_go_back(), "with somewhere to go back to")
	page.type_search("valve")
	assert(
		not page.can_go_back(),
		"a search clears the walk: the subjects back would go to are not the ones on the contents any more"
	)
	assert(not page.can_go_forward())
	page.free()


func test_the_subjects_read_next_cannot_take_the_keyboard() -> void:
	var page: HelpWindowScript = _page()
	assert(page.select_topic("Plants"), "a subject that points at others")
	assert(not page.see_links().is_empty(), "so there are buttons to press")
	for child: Node in page.see_view().get_children():
		if child is Button:
			assert(
				(child as Button).focus_mode == Control.FOCUS_NONE,
				"a cross-reference is pressed with the mouse, like the rest of the page"
			)
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


func test_the_floor_comes_down_to_fit_a_smaller_screen_and_never_to_nothing() -> void:
	# A screen with room to spare leaves the floor at the page's own size.
	assert(HelpWindowScript.clamped_minimum(Vector2i(2000, 1200)) == HelpWindowScript.SIZE)
	# A screen with less room brings it down to that screen, one side at a time.
	assert(HelpWindowScript.clamped_minimum(Vector2i(800, 1200)) == Vector2i(800, 720))
	assert(HelpWindowScript.clamped_minimum(Vector2i(2000, 600)) == Vector2i(960, 600))
	assert(HelpWindowScript.clamped_minimum(Vector2i(640, 480)) == Vector2i(640, 480))
	# A screen that says nothing about itself leaves the floor alone, rather than at nothing: the page
	# is made smaller for want of room, never for want of knowing.
	assert(HelpWindowScript.clamped_minimum(Vector2i.ZERO) == HelpWindowScript.SIZE)
	assert(HelpWindowScript.clamped_minimum(Vector2i(-1, -1)) == HelpWindowScript.SIZE)


func test_the_window_fits_its_floor_to_the_screen_without_ever_going_over_the_page() -> void:
	var page: HelpWindowScript = _page()
	var floor_size: Vector2i = page.clamp_to_screen()
	assert(floor_size.x > 0 and floor_size.y > 0, "the floor is a size, never nothing")
	assert(
		floor_size.x <= HelpWindowScript.SIZE.x and floor_size.y <= HelpWindowScript.SIZE.y,
		"and never larger than the page asks for"
	)
	assert(page.min_size == floor_size, "which is the floor the window opens at")
	page.free()


func test_the_arrow_keys_walk_the_contents_end_to_end_without_landing_on_a_heading() -> void:
	# The real manual, whose contents carries a heading row for each of its sections. Walking it from
	# end to end must visit every subject exactly once and never land on a heading - a heading is
	# furniture, and a page that opened or stopped on one would be showing nothing.
	var page: HelpWindowScript = _page()
	assert(page.shown_topic_index() == 0, "the page opens on the first subject")
	var forward := 0
	while page.move_selection(1):
		forward += 1
		assert(page.shown_topic_index() >= 0, "each step lands on a subject, never on a heading")
	assert(forward == page.topic_count() - 1, "walking on visits exactly the other subjects")
	assert(page.shown_topic_index() == page.topic_count() - 1, "and stops on the last one")
	assert(not page.move_selection(1), "the foot of the contents is the end of it")
	var backward := 0
	while page.move_selection(-1):
		backward += 1
	assert(backward == forward, "and back walks the same subjects the same way")
	assert(page.shown_topic_index() == 0, "stopping at the first")
	assert(not page.move_selection(-1), "with nowhere further back to go")
	assert(not page.move_selection(0), "and a step of nothing moves nothing")
	page.free()


func test_the_search_box_turns_the_arrow_keys_into_walking_the_contents() -> void:
	# `gui_input` is the signal the box emits for every key it is given, which is where the page hangs
	# this - so emitting it here drives exactly what a real arrow key drives while the box has focus.
	var page: HelpWindowScript = _page()
	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.physical_keycode = KEY_DOWN
	down.pressed = true
	var up := InputEventKey.new()
	up.keycode = KEY_UP
	up.physical_keycode = KEY_UP
	up.pressed = true
	assert(page.shown_topic_index() == 0, "the page opens on the first subject")
	page.search_field().gui_input.emit(down)
	assert(page.shown_topic_index() == 1, "down steps on a subject")
	page.search_field().gui_input.emit(down)
	assert(page.shown_topic_index() == 2, "and again")
	page.search_field().gui_input.emit(up)
	assert(page.shown_topic_index() == 1, "and up steps back")
	# A key the box does care about is left to it: typing still searches rather than walking.
	page.type_search("valve")
	assert(page.shown_count() < page.topic_count(), "a word typed into the box still narrows the contents")
	page.free()