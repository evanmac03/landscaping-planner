extends Node
## The manual as the program reaches it: the Help menu's way in, the page the HUD builds and fills,
## and the one subject the manual does not carry as prose - the keys, which come from the tables that
## drive the program rather than from a fourth copy written out by hand.
##
## A page is never opened here with `popup_centered`, because that needs a window server and a test
## process has not got one. Being shown is what the page's own `visible` flag means, which is what
## these tests set - exactly as the other page tests do - and the filling is driven separately, which
## is why the HUD keeps the filling and the showing apart in the first place.

const HudScript := preload("res://scripts/hud.gd")
const HelpDocScript := preload("res://scripts/help_doc.gd")
const HelpWindowScript := preload("res://scripts/help_window.gd")


func _hud() -> HudScript:
	var hud: HudScript = HudScript.new()
	hud._build_help_window()
	return hud


func _entry(id: StringName) -> Dictionary:
	for entry: Dictionary in HudScript.menu_entries():
		if StringName(entry.get("id", &"")) == id:
			return entry
	assert(false, "no menu entry with id %s" % String(id))
	return {}


func test_the_help_menu_offers_the_palette_the_manual_then_the_keys() -> void:
	# The palette comes first because it is the shortest way to *any* command, including the ones
	# that are not in this menu - it is the commands themselves rather than prose about them. The
	# manual comes next, and the key reference last.
	var ids: Array[String] = []
	for entry: Dictionary in HudScript.items_for("Help"):
		ids.append(String(entry.get("id", "")))
	var expected: Array[String] = ["help.palette", "help.manual", "help.keys"]
	assert(ids == expected, "the palette, then the manual, then the keys")


func test_the_manual_reaches_nothing_in_the_scene_it_is_opened_from() -> void:
	var manual: Dictionary = _entry(&"help.manual")
	assert(StringName(manual.get("kind", &"")) == &"command", "it is a command rather than a toggle")
	assert(String(manual.get("method", "")) == "_menu_help", "and it runs the handler that opens it")
	assert(
		StringName(manual.get("needs", &"")) == HudScript.NEEDS_NOTHING,
		"a manual needs nothing of the scene it is opened in"
	)
	assert(
		String(manual.get("action", "")) == "",
		"it advertises no key: a manual is not something a hand reaches for mid-draw"
	)


func test_the_topics_the_hud_hands_over_are_the_manuals_and_then_the_keys() -> void:
	var hud: HudScript = _hud()
	var topics: Array[Dictionary] = hud.help_topics()
	assert(topics.size() == HelpDocScript.topic_count() + 1, "one more than the subjects the manual has")
	assert(
		String(topics[0]["title"]) == HelpDocScript.SUBJECTS[0],
		"the manual's own subjects come first, in the order the manual has them"
	)
	var last: Dictionary = topics[topics.size() - 1]
	assert(String(last["title"]) == HudScript.KEYS_TOPIC, "and the keys come last")
	assert(
		String(last["body"]) == hud.keys_text(),
		"the keys topic *is* the key reference, so the manual cannot name a key that does nothing"
	)
	hud.free()


func test_the_window_the_program_builds_is_pointed_at_the_topics_it_should_show() -> void:
	var hud: HudScript = _hud()
	hud._fill_help_window()
	var page: HelpWindowScript = hud._help_window
	assert(page.topic_count() == HelpDocScript.topic_count() + 1, "the page holds the keys as well")
	assert(page.list_texts().size() == page.topic_count(), "and lists every one of them")
	assert(
		String(page.list_texts()[page.topic_count() - 1]) == HudScript.KEYS_TOPIC,
		"with the keys at the foot of the contents"
	)
	assert(page.shown_topic_index() == 0, "and a subject on the page rather than a blank frame")
	hud.free()


func test_the_page_is_shown_when_it_is_made_visible_and_hidden_when_it_is_closed() -> void:
	var hud: HudScript = _hud()
	assert(not hud.is_help_window_open(), "a page the HUD has built is not on the screen")
	hud._help_window.visible = true
	assert(hud.is_help_window_open(), "a page on the screen is open")
	hud.close_help_window()
	assert(not hud.is_help_window_open(), "and closing it hides it")
	hud.free()


func test_a_hud_with_no_page_at_all_says_nothing_rather_than_failing() -> void:
	var hud: HudScript = HudScript.new()
	assert(not hud.is_help_window_open(), "there is no page, so nothing is open")
	hud.close_help_window()
	hud._fill_help_window()
	# Opening with no page must refuse before it reaches `popup_centered`, which is what makes this
	# safe to call with no window server behind it.
	hud.open_help_window()
	assert(not hud.is_help_window_open(), "and nothing was opened")
	assert(
		hud.help_topics().size() == HelpDocScript.topic_count() + 1,
		"the topics are the manual's own, which need no scene to be read"
	)
	hud.free()