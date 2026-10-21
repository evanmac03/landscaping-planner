extends Node
## The sun's study, joined to the Present menu and to the presentation.
##
## The report is tested in `test_sun_report.gd` and the page in `test_sun_window.gd`; this is the part
## that only exists when they are put together - that the Present menu offers the study and says how big
## the one in hand is, that the page is pointed at the site the *presentation* states rather than at a
## site of its own, that aiming from the page reaches the sun, and that a study renders one still per
## moment, each named for the moment it shows.
##
## The HUD and the page enter no tree, so no `_ready` runs and no window is ever shown: `popup_centered`
## needs a screen and a test does not have one, which is why filling the page is its own function.
##
## The *presentation* does enter the tree, and so does its light, for one reason: aiming a sun is
## `look_at`, and Godot refuses that on a node that is not in a tree. That is also why the still walk is
## deterministic here - a director with a light and no camera is a director whose `render_still` fails by
## name, so every step of the walk is countable without a renderer.

const HudScript := preload("res://scripts/hud.gd")
const DirectorScript := preload("res://scripts/vis/presentation_director.gd")
const SunReportScript := preload("res://scripts/vis/sun_report.gd")
const SunWindowScript := preload("res://scripts/sun_window.gd")
const SunStudyScript := preload("res://scripts/vis/sun_study.gd")

const NO_PRESENTATION := "there is no presentation to study the sun from"


# --- helpers --------------------------------------------------------------------------


## A presentation for a garden at Ottawa's latitude, with a light it can actually aim. The light is a
## child of the director so that freeing the director frees it.
func _presenting() -> PresentationDirector:
	var director := DirectorScript.new()
	director.latitude = 45.0
	director.longitude = -75.0
	director.utc_offset_hours = -5.0
	director.day_of_year = 172
	director.hour = 16.0
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	director.add_child(light)
	director.sun = light
	# Into the tree, because `look_at` - which is how a sun is aimed - refuses to work outside one.
	add_child(director)
	return director


func _hud_for(director: PresentationDirector) -> Node:
	var hud := HudScript.new()
	hud.presentation = director
	_wired(hud, director)
	return hud


## The four connections the presentation panel's own builder makes when the HUD is in a scene. A bare
## HUD has no panel and no `_ready`, so the test makes them itself - and they are not optional: a step of
## the study is finished by the *director's own report*, not by a loop that awaits, so a walk whose
## signals are not connected would wait at its first moment forever.
func _wired(hud: Node, director: PresentationDirector) -> void:
	director.presentation_changed.connect(hud._on_presentation_changed)
	director.note.connect(hud._on_presentation_note)
	director.still_beginning.connect(hud._on_still_beginning)
	director.still_written.connect(hud._on_still_written)
	director.still_failed.connect(hud._on_still_failed)


## A HUD with the page built, filled from the presentation, and the page handed back.
func _studying(director: PresentationDirector) -> Array:
	var hud: Node = _hud_for(director)
	hud._build_sun_window()
	hud._fill_sun_window()
	return [hud, hud._sun_window]


func _drop(director: PresentationDirector) -> void:
	if director != null and is_instance_valid(director):
		director.free()


# --- the menu -------------------------------------------------------------------------


func test_the_present_menu_offers_the_study_and_its_own_line() -> void:
	var entries: Array[Dictionary] = HudScript.present_items()
	var study: Dictionary = {}
	var line: Dictionary = {}
	for entry: Dictionary in entries:
		match String(entry.get("id", "")):
			"present.sun_study":
				study = entry
			"present.sun_info":
				line = entry
	assert(not study.is_empty(), "the Present menu offers the sun and shadow study")
	assert(StringName(study["kind"]) == &"command", "as a command")
	assert(String(study["label"]) == "Sun and shadow study...", String(study["label"]))
	assert(String(study["method"]) == "_menu_sun_window", String(study["method"]))
	# Shown rather than dropped in a scene with no presentation, but switched off: a command that
	# cannot run here is still a thing the program does.
	assert(StringName(study["needs"]) == HudScript.NEEDS_PRESENTATION, String(study["needs"]))
	assert(not line.is_empty(), "and it says how big the study in hand is")
	assert(StringName(line["kind"]) == &"info", "as a line rather than as a command")
	assert(String(line["label"]) == "the sun", String(line["label"]))
	var hud := HudScript.new()
	assert(hud.has_method("_menu_sun_window"), "and the method the command names is there")
	assert(hud.has_method("open_sun_window") and hud.has_method("is_sun_window_open"),
		"beside the pair that opens and reports on the page")
	assert(hud.has_method("apply_sun_moment") and hud.has_method("render_sun_study"),
		"and the two the page's own signals call")
	hud.free()


func test_a_scene_with_no_presentation_still_has_a_line_to_show() -> void:
	var hud := HudScript.new()
	assert(hud._sun_text() == NO_PRESENTATION, hud._sun_text())
	assert(hud._sun_site().is_empty(), "and no site to study")
	hud._build_sun_window()
	hud._fill_sun_window()
	assert(hud._sun_window != null, "the page is built")
	assert(not hud._sun_window.has_site(), "and told there is no site rather than a latitude of zero")
	assert(hud._sun_window.hint() == SunWindowScript.NO_SITE, hud._sun_window.hint())
	assert(hud._sun_text() == NO_PRESENTATION, "and the menu still says what is missing")
	var refused: Dictionary = hud.render_sun_study([SunStudyScript.moment(172, 12.0)])
	assert(not bool(refused["ok"]), "and there is nothing to render from")
	assert(String(refused["reason"]) == "there is no presentation to render from", String(refused["reason"]))
	assert(hud._sun_window.said() == "there is no presentation to render from",
		hud._sun_window.said())
	assert(not hud.apply_sun_moment(SunStudyScript.moment(172, 12.0)), "nor a sun to aim")
	assert(hud._sun_window.said() == "there is no presentation to aim", hud._sun_window.said())
	hud.free()


# --- the page, filled from the presentation -------------------------------------------


func test_the_page_is_built_and_filled_without_a_window_server() -> void:
	var director := _presenting()
	var built: Array = _studying(director)
	var hud: Node = built[0]
	var page: SunWindow = built[1]
	assert(hud._sun_window != null, "the page is built")
	assert(not hud.is_sun_window_open(), "and not shown: a form nobody opened is not over the drawing")
	# The site is the presentation's own. There is no second site form, because two places to state a
	# latitude is two answers to one question.
	assert(page.has_site(), "the page is pointed at a site")
	assert(is_equal_approx(float(page.site()["latitude"]), 45.0), str(page.site()))
	assert(is_equal_approx(float(page.site()["utc_offset_hours"]), -5.0), str(page.site()))
	assert(page.moment_count() == 6, "and it opens on a study rather than on nothing")
	assert(page.height_words() == "1.8 m", page.height_words())
	assert(
		hud._sun_text() == "45.0°N 75.0°W, UTC-5: 6 moments, 6 with the sun up",
		hud._sun_text()
	)
	page.free()
	hud.free()
	_drop(director)


func test_the_page_reopens_to_the_study_it_was_left_with() -> void:
	var director := _presenting()
	var built: Array = _studying(director)
	var hud: Node = built[0]
	var page: SunWindow = built[1]
	assert(
		SunReportScript.day_of(page.moments()[0]) == SunReportScript.JUNE_SOLSTICE,
		"the page opens on a June day"
	)
	assert(page.use_preset(&"december_day"), "a person asks for a December day instead")
	hud._fill_sun_window()
	assert(
		SunReportScript.day_of(page.moments()[0]) == SunReportScript.DECEMBER_SOLSTICE,
		"and opening the page again comes back to that study, not to a June day"
	)
	assert(page.moment_count() == 6, "with the study whole")
	page.free()
	hud.free()
	_drop(director)


func test_the_line_is_in_the_snapshot_every_menu_refresh_is_drawn_from() -> void:
	var director := _presenting()
	var built: Array = _studying(director)
	var hud: Node = built[0]
	var page: SunWindow = built[1]
	var world: Dictionary = hud.menu_world()
	assert(world.has("sun"), "the snapshot carries the study")
	assert(String(world["sun"]) == hud._sun_text(), "and it is the same line")
	page.clear_moments()
	assert(
		String(hud.menu_world()["sun"]) == "45.0°N 75.0°W, UTC-5: no moments chosen yet",
		String(hud.menu_world()["sun"])
	)
	assert(String(hud.menu_world()["sun"]) != String(world["sun"]),
		"so emptying the study on the page moves the menu")
	page.free()
	hud.free()
	_drop(director)


func test_a_page_left_open_keeps_up_with_the_site_moving_behind_it() -> void:
	var director := _presenting()
	var built: Array = _studying(director)
	var hud: Node = built[0]
	var page: SunWindow = built[1]
	page.use_preset(&"december_day")
	director.latitude = 60.0
	hud._tick_sun_window()
	assert(is_equal_approx(float(page.site()["latitude"]), 45.0),
		"a page that is not up is not read again: %s" % str(page.site()))
	page.visible = true
	hud._tick_sun_window()
	assert(is_equal_approx(float(page.site()["latitude"]), 60.0),
		"but one that is up catches up: %s" % str(page.site()))
	# The site is the page's to be told; the *study* is the page's own. Rebinding a site by itself
	# must not throw away a study somebody is in the middle of building.
	assert(
		SunReportScript.day_of(page.moments()[0]) == SunReportScript.DECEMBER_SOLSTICE,
		"and the study in hand is not thrown away"
	)
	assert(page.moment_count() == 6, "whole")
	page.visible = false
	page.free()
	hud.free()
	_drop(director)


# --- aiming the sun -------------------------------------------------------------------


func test_aiming_the_sun_from_the_page_reaches_the_presentation() -> void:
	var director := _presenting()
	var built: Array = _studying(director)
	var hud: Node = built[0]
	var page: SunWindow = built[1]
	# The middle of a June day, which is the third moment of the study the page opened on.
	var aimed: bool = hud.apply_sun_moment(page.moments()[2])
	assert(aimed, "the sun is aimed")
	assert(director.day_of_year == SunReportScript.JUNE_SOLSTICE, str(director.day_of_year))
	assert(is_equal_approx(director.hour, 12.0), str(director.hour))
	assert(director.sun.rotation_degrees != Vector3.ZERO, "and the light has actually moved")
	assert(page.said() == "the sun is at 21 June 12:00", page.said())
	page.free()
	hud.free()
	_drop(director)


func test_a_moment_the_sun_is_down_at_is_refused_by_the_presentation() -> void:
	var director := _presenting()
	var built: Array = _studying(director)
	var hud: Node = built[0]
	var page: SunWindow = built[1]
	# Six in the evening in December, which is after dark. The presentation refuses it rather than
	# clamping the light to something, and the page says what it last did.
	var dusk: Dictionary = SunStudyScript.moment(SunReportScript.DECEMBER_SOLSTICE, 18.0)
	assert(not hud.apply_sun_moment(dusk), "the sun is not moved")
	assert(page.said() == "the sun was not moved at 21 December 18:00", page.said())
	assert(
		page.hint().contains("18:00") or page.hint() == SunWindowScript.NO_CHOICE,
		"and the page's guidance is about the study in hand: %s" % page.hint()
	)
	page.free()
	hud.free()
	_drop(director)


# --- rendering the study -------------------------------------------------------------


func test_rendering_a_study_names_each_still_after_its_own_moment() -> void:
	var director := _presenting()
	var built: Array = _studying(director)
	var hud: Node = built[0]
	var page: SunWindow = built[1]
	var plan: Dictionary = hud.render_sun_study(page.renderable_moments())
	assert(bool(plan["ok"]), "the study is renderable")
	var names: Array = plan["names"]
	assert(names.size() == 6, "one still per moment: " + str(names.size()))
	assert(String(names[0]) == "sun-study-172-0800", String(names[0]))
	assert(String(names[5]) == "sun-study-172-1800", String(names[5]))
	# A study's still is named for its *moment*, not for the clock the render ran at, so a folder of
	# them sorts into the order the study was asked in.
	for name: String in names:
		assert(name.begins_with("sun-study-172-"), name)
	# This director has a light to aim and no camera to shoot with, so every step of the walk lands as a
	# named failure - which is exactly what makes the counting checkable without a renderer.
	assert(hud._sun_render_index == 6, str(hud._sun_render_index))
	assert(hud._sun_render_written == 0, str(hud._sun_render_written))
	assert(hud._sun_render_refused == 6, str(hud._sun_render_refused))
	assert(page.said() == "0 stills written, 6 moments could not be rendered", page.said())
	page.free()
	hud.free()
	_drop(director)


func test_a_study_with_nothing_to_render_is_refused_rather_than_started() -> void:
	var director := _presenting()
	var built: Array = _studying(director)
	var hud: Node = built[0]
	var page: SunWindow = built[1]
	# The page only ever hands over the moments with the sun up, so an empty list is what a study of
	# nothing but dark hours comes to - and a walk of nothing should not report a walk.
	var refused: Dictionary = hud.render_sun_study([])
	assert(not bool(refused["ok"]), "an empty study is refused")
	assert(
		String(refused["reason"]) == "no moment of this study has the sun up, so there is nothing to render",
		String(refused["reason"])
	)
	assert(page.said() == String(refused["reason"]), "and the page says why")
	assert(hud._sun_render_index == 0, "and no walk was started")
	page.free()
	hud.free()
	_drop(director)


func test_a_still_the_panel_asked_for_is_not_counted_as_one_of_the_study_s() -> void:
	var director := _presenting()
	var built: Array = _studying(director)
	var hud: Node = built[0]
	var page: SunWindow = built[1]
	hud.render_sun_study(page.renderable_moments())
	hud._sun_render_index = 0
	hud._sun_render_written = 0
	hud._sun_render_refused = 0
	hud._sun_render_waiting = false
	assert(
		not hud._sun_still_is_ours("user://proposals/sun-study-172-0800-1.png"),
		"a still nobody asked for is not a step of the study"
	)
	hud._sun_render_waiting = true
	assert(
		hud._sun_still_is_ours("user://proposals/sun-study-172-0800-1.png"),
		"the moment in hand is"
	)
	assert(
		not hud._sun_still_is_ours("user://proposals/presentation-1.png"),
		"and a still the panel's own button asked for is not, however long the study runs"
	)
	# One of the study's stills landing starts the next moment; the rest fail by name, and the walk's
	# closing sentence counts what it managed rather than claiming the whole study.
	hud._on_still_written("user://proposals/sun-study-172-0800-1.png")
	assert(hud._sun_render_written == 1, str(hud._sun_render_written))
	assert(hud._sun_render_refused == 5, str(hud._sun_render_refused))
	assert(hud._sun_render_index == 6, str(hud._sun_render_index))
	assert(page.said() == "1 still written, 5 moments could not be rendered", page.said())
	page.free()
	hud.free()
	_drop(director)