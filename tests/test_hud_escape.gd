extends Node
## Escape: one key that means "out of this" on every surface this HUD draws itself.
##
## The pages are installed by hand rather than opened, because a bare HUD has no scene nodes for them
## to be built from and `open_*_panel` refuses without a drawing - what is tested here is the ladder's
## own decision, which is the half that can be wrong. The predicates are asserted on, not the members,
## so the door and the answer to "is it up?" cannot drift apart.
##
## The pages that live in a `Window` are deliberately not in the ladder and are not tested here: a
## focused window takes the keyboard into its own viewport, so this node never sees an Escape meant
## for one. Those pages answer for themselves - except for the phone's Back gesture, which arrives as a
## notification rather than as a key and so does reach this node. That one path is tested at the foot of
## this file, because it is the only way a page in a window is answered for from out here.
##
## The doorway's pages are the exception this file once relied on and no longer may: they are pages in a
## `Window` too, and they were left off both lists - the Escape pass and the page a Back gesture puts away.
## The section at the foot of this file is what holds them on both.

const HudScript := preload("res://scripts/hud.gd")

## Every page this HUD draws itself: the member the page lives in, and the predicate that says whether
## it is up. The order is the ladder's own, newest first.
const PAGES: Array = [
	["_site_report_panel", "is_site_report_open"],
	["_survey_panel", "is_survey_panel_open"],
	["_dxf_panel", "is_dxf_panel_open"],
	["_landxml_panel", "is_landxml_panel_open"],
	["_hatch_page", "is_hatch_panel_open"],
	["_water_page", "is_water_panel_open"],
	["_light_page", "is_light_panel_open"],
]


func test_nothing_up_leaves_the_key_to_the_drawing() -> void:
	# The half that matters as much as the rest: a key that answered when nothing was up would swallow
	# the drawing's own cancel, and the shape in hand could never be dropped.
	var hud := HudScript.new()
	assert(not hud.escape_puts_away(), "there is nothing here for the key to put away")
	hud.free()


func test_escape_puts_away_every_page_this_hud_draws() -> void:
	for pair: Array in PAGES:
		var hud := HudScript.new()
		var page := Control.new()
		hud.set(String(pair[0]), page)
		page.visible = true
		assert(bool(hud.call(String(pair[1]))), "%s is up before the key" % pair[0])
		assert(hud.escape_puts_away(), "%s is answered for" % pair[0])
		assert(not bool(hud.call(String(pair[1]))), "and %s is away" % pair[0])
		assert(not page.visible, "the page itself is hidden rather than merely reported away")
		page.free()
		hud.free()


func test_escape_puts_the_key_reference_away() -> void:
	# This one worked before the ladder existed; it is here so that moving it into the ladder cannot be
	# the change that quietly stops it working.
	var hud := HudScript.new()
	var keys := Control.new()
	hud._keys_panel = keys
	keys.visible = true
	assert(hud.escape_puts_away(), "the reference is answered for")
	assert(not hud.is_keys_open(), "and it is away")
	keys.free()
	hud.free()


func test_escape_puts_the_painted_sheet_away() -> void:
	var hud := HudScript.new()
	var sheet := Control.new()
	hud.painted_sheet = sheet
	sheet.visible = true
	assert(hud.escape_puts_away(), "the sheet is answered for")
	assert(not sheet.visible, "and it is away")
	sheet.free()
	hud.free()


func test_the_sheet_is_taken_off_before_a_page_behind_it() -> void:
	# The order is the whole point of a ladder: the sheet is what the person is looking at.
	var hud := HudScript.new()
	var sheet := Control.new()
	hud.painted_sheet = sheet
	sheet.visible = true
	var panel := Control.new()
	hud._water_page = panel
	panel.visible = true
	assert(hud.escape_puts_away(), "the first Escape is answered for")
	assert(not sheet.visible, "the sheet is what it took off")
	assert(panel.visible, "and the page behind it is still up")
	assert(hud.escape_puts_away(), "the second Escape is answered for too")
	assert(not panel.visible, "and now the page")
	sheet.free()
	panel.free()
	hud.free()


func test_one_key_takes_off_one_page() -> void:
	# Two pages up is a state the menu bar will not build, but the ladder must not answer for both:
	# one press of the key is one page, or a person cannot tell what they just did.
	var hud := HudScript.new()
	var front := Control.new()
	hud._site_report_panel = front
	front.visible = true
	var behind := Control.new()
	hud._water_page = behind
	behind.visible = true
	assert(hud.escape_puts_away(), "an Escape is answered for")
	assert(not front.visible, "the page it takes first went")
	assert(behind.visible, "the page behind it did not")
	front.free()
	behind.free()
	hud.free()


func test_a_page_that_is_already_away_is_not_a_page() -> void:
	# A hidden page in the ladder must not swallow the key: the drawing still needs its cancel.
	var hud := HudScript.new()
	var page := Control.new()
	hud._hatch_page = page
	page.visible = false
	assert(not hud.escape_puts_away(), "a page that is not up is not answered for")
	page.free()
	hud.free()

# --- the phone's Back gesture -----------------------------------------------------------


## Back means what Escape means, so a phone with no keyboard can still get out of a page. A page in a
## `Window` is closed by emitting `close_requested`, which is the door its own frame and its own Close
## button already use - which is why Back and the cross cannot come to answer differently.
func test_the_phone_back_gesture_closes_the_page_in_front() -> void:
	var hud := HudScript.new()
	var page := Window.new()
	var closed: Array[int] = [0]
	page.close_requested.connect(
		func() -> void:
			closed[0] += 1,
	)
	hud._plant_window = page
	page.visible = true
	assert(hud.page_in_front() == page, "the page is the one in front")
	hud.back_puts_away()
	assert(closed[0] == 1, "the page was asked to close, once: %d" % closed[0])
	page.free()
	hud.free()


## With no page in a window, Back is Escape's own ladder: a page this HUD draws itself is put away, and
## nothing is asked of the program.
func test_the_phone_back_gesture_falls_through_to_the_escape_ladder() -> void:
	var hud := HudScript.new()
	var keys := Control.new()
	hud._keys_panel = keys
	keys.visible = true
	hud.back_puts_away()
	assert(not hud.is_keys_open(), "the reference is away")
	keys.free()
	hud.free()


## And it is not the operating system that decides to leave the program, because that is a quit nobody is
## asked about: the drawing lives in memory until it is written, and a thumb brushes Back by accident.
func test_the_program_does_not_quit_behind_the_back_gestures_back() -> void:
	assert(
		ProjectSettings.get_setting("application/config/quit_on_go_back") == false,
		"Back is answered by the HUD, so unsaved work is asked about before the program goes",
	)

# --- the doorway's pages ----------------------------------------------------------------


## A door is a page in a `Window` like any other, and it was on neither of the two lists this file is about -
## the Escape pass and the page a Back gesture puts away. The claim the omission was made on was that a door
## answers its own Escape; measured, it does not. A real Escape on a launch with the front door up left it
## standing, and Back went on past it and left the program.
##
## **All three of them**, because all three are built when they are first opened rather than at launch: each
## `_build_*` door has to run the pass again once its page exists. Miss one and a page a person can open cannot
## be put away with the key.
func test_every_doorway_page_takes_a_closer_when_it_is_built() -> void:
	var hud := HudScript.new()
	hud._build_start_window()
	hud._build_start_drawing_window()
	hud._build_camera_window()
	var looked_at := 0
	for door: Window in hud._pages_that_can_be_up():
		if door == null:
			continue
		looked_at += 1
		assert(
			door.get_node_or_null(^"PageEscape") != null,
			"%s took no closer of its own, so Escape cannot put it away" % door.name,
		)
	assert(looked_at == 3, "all three doorway pages were built and looked at, not %d" % looked_at)
	hud.free()


## The commonest state this program is ever in is a launch with the front door up, so this is the Back most
## often pressed: it must put the door away, not the program. The door's own `closed` signal is watched rather
## than `close_requested`, so the whole chain is held - Back asks the door to close, the door hides itself and
## says so - which is exactly what the Close button does.
func test_the_phone_back_gesture_puts_the_front_door_away_rather_than_leaving() -> void:
	var hud := HudScript.new()
	hud._build_start_window()
	var door: Window = hud._start_window
	var closed: Array[int] = [0]
	door.closed.connect(
		func() -> void:
			closed[0] += 1,
	)
	door.visible = true
	assert(hud.page_in_front() == door, "the front door is the page in front of everything")
	hud.back_puts_away()
	assert(closed[0] == 1, "the door was put away, once: %d" % closed[0])
	assert(not door.visible, "and it is hidden rather than merely reported away")
	hud.free()


## And the camera is a doorway page standing over the door, so with both up it is the one Back takes first.
func test_the_camera_standing_over_the_door_is_the_one_back_takes_first() -> void:
	var hud := HudScript.new()
	hud._build_start_window()
	hud._start_window.visible = true
	hud._build_camera_window()
	hud._camera_window.visible = true
	assert(
		hud.page_in_front() == hud._camera_window,
		"the camera stands over the door, so it is the page in front and the one Back puts away first",
	)
	hud._camera_window.visible = false
	assert(hud.page_in_front() == hud._start_window, "and with it away the door is in front again")
	hud.free()

# --- one press is one act ---------------------------------------------------------------


## Godot 4.7.2 at `targetSdk 36` reports a single Back press twice - measured on the SM-A166W, two notifications
## 354 ms apart (`godotengine/godot#123454`, which reports one to fifteen milliseconds on other hardware). The
## gap is stated, so the rule can be held without a phone: the engine's repeat is inside it, and a press made
## after the window is not.
func test_the_engines_repeat_of_one_back_press_is_the_same_press() -> void:
	var hud := HudScript.new()
	assert(hud.is_a_repeat_of_the_last_back(1000, 1000), "the engine's own repeat is one press, not two")
	assert(
		hud.is_a_repeat_of_the_last_back(1354, 1000),
		"and still one press at the 354 ms the SM-A166W measured between the two notifications it sends",
	)
	assert(
		not hud.is_a_repeat_of_the_last_back(1000 + hud.BACK_REPEAT_GAP_MS, 1000),
		"a press made after the window is its own act",
	)
	assert(not hud.is_a_repeat_of_the_last_back(1000, 0), "and the first press is never a repeat of nothing")
	hud.free()


## The fault, held whole: with the door up, one press must put the door away, and the engine's own repeat of
## that press must not then find nothing in front and leave the program. If the repeat were answered the ladder
## would reach `quit_requested`, and a HUD with no tree cannot survive that - it is a script error in this run
## rather than a failed assert, which is why the door's own disappearance is asserted too.
func test_a_repeated_back_puts_the_door_away_once_and_leaves_the_program_standing() -> void:
	var hud := HudScript.new()
	hud._build_start_window()
	hud._start_window.visible = true
	hud.back_puts_away()
	hud.back_puts_away()
	assert(not hud._start_window.visible, "the press put the door away")
	assert(hud.page_in_front() == null, "and the repeat was not answered a second time")
	hud.free()
