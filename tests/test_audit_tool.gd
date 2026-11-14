extends Node
## Tests for the audit tool.
##
## `tools/audit.gd` is a dev tool and not a test, so there is nothing here about what it prints. What
## there *is* here is the one thing the tool cannot check about itself: **that a check can fail.**
##
## A table that says PASS is theatre if every check is a printout wearing a verdict, and the only way to
## show that a verdict is derived rather than decorative is to hand a check a scene that is not the game
## and see it refuse. So each check is called with a bare node - which is exactly what a scene that is
## not `main.tscn` looks like - and its verdict is read.
##
## The two printed lines these tests make are the checks saying what they found. They are deliberate:
## a check that refused in silence would be the thing being tested against.

const LayoutCheck := preload("res://tools/hud_layout_check.gd")
const PlantCheck := preload("res://tools/plant_scene_check.gd")


## The audit's whole premise is that each check is a function it can call on a game it brought up
## itself. Both call it as `SomeCheck.run(...)`, so a check without one would not parse - but a check
## whose `run` is not *static* would, and would fail only when the audit was run.
func test_both_checks_offer_the_call_the_audit_makes() -> void:
	for path: String in ["res://tools/hud_layout_check.gd", "res://tools/plant_scene_check.gd"]:
		var source: String = FileAccess.get_file_as_string(path)
		assert(source.contains("static func run("), path + " has no run() the audit can call")


## A scene with no Hud in it is not the game, and the check says so rather than reading a null.
func test_the_plant_check_refuses_a_scene_that_is_not_the_game() -> void:
	var bare := Node.new()
	var verdict: Dictionary = PlantCheck.run(bare)
	bare.free()
	assert(not bool(verdict["ok"]), "a scene with nothing to plant is not a pass")
	assert(String(verdict["name"]) == "what the scene plants", String(verdict["name"]))
	assert(int(verdict["planted"]) == 0, "and nothing was planted in it")
	assert(String(verdict["summary"]).contains("no Hud"), String(verdict["summary"]))


## The same for the layout check. It refuses before it reaches any frame, which is why it can be
## called with no tree at all - and why the `await` below never actually waits for anything.
func test_the_layout_check_refuses_a_scene_that_is_not_the_game() -> void:
	var bare := Node.new()
	var verdict: Dictionary = await LayoutCheck.run(bare, null)
	bare.free()
	assert(not bool(verdict["ok"]), "a scene with no HUD has no layout to pass")
	assert(String(verdict["name"]) == "HUD layout", String(verdict["name"]))
	assert(int(verdict["clashes"]) == 0, "and no clash was counted in it")
	assert(String(verdict["summary"]).contains("no Hud/Root"), String(verdict["summary"]))


## Every verdict carries the three things the table prints, so a check that grew a different shape
## would be a fault rather than a row of the table with blanks in it.
func test_a_verdict_carries_what_the_table_prints() -> void:
	var bare := Node.new()
	var verdict: Dictionary = PlantCheck.run(bare)
	bare.free()
	for key: String in ["name", "ok", "summary"]:
		assert(verdict.has(key), "a verdict has no " + key)
	assert(verdict["name"] is String and verdict["summary"] is String, "a name and a summary are words")


func test_the_audit_scene_runs_the_audit_script() -> void:
	var packed := ResourceLoader.load("res://tools/audit.tscn", "PackedScene") as PackedScene
	assert(packed != null, "the audit scene loads")
	var root: Node = packed.instantiate()
	var script: Script = root.get_script()
	var path: String = script.resource_path if script != null else ""
	root.free()
	assert(path == "res://tools/audit.gd", path)


# --- the finger pass's own rule, and the room it has to put back -------------------------------
#
# The HUD layout check's verdict rests on two things no other test can reach: what it makes of the palette's
# place at a finger's type, and whether it leaves the room as it found it. Both are held here, on a room built
# by hand, because the suite runs headless and the pass itself needs the real game.
#
# **A room of the shape the question reads**, with `TopBar`, `Palette` and `Hints` named as `run` finds them.
func _room_with_the_bar_the_palette_and_the_foot(palette_top: float, palette_height: float, foot_top: float) -> Control:
	var room := Control.new()
	var bar := Control.new()
	bar.name = "TopBar"
	bar.size = Vector2(400.0, 100.0)
	room.add_child(bar)
	var palette := Control.new()
	palette.name = "Palette"
	palette.position = Vector2(0.0, palette_top)
	palette.size = Vector2(200.0, palette_height)
	room.add_child(palette)
	var foot := Control.new()
	foot.name = "Hints"
	foot.position = Vector2(0.0, foot_top)
	room.add_child(foot)
	return room


## The palette's place is decided by **two heights and no width at all** - which is the whole reason a desk-sized
## window can be asked a phone's question - so a room a test built answers it. This is the half a headless suite
## can hold, and the screen is stated because that is the rule's own shape; the refusal is the next test.
func test_the_palette_between_the_bar_and_the_foot_is_a_question_a_room_can_answer() -> void:
	var room: Control = _room_with_the_bar_the_palette_and_the_foot(110.0, 300.0, 500.0)
	var place: Dictionary = LayoutCheck.palette_between_the_bar_and_the_foot(room, true)
	assert(bool(place["asked"]), "the question was asked of a room with the screen stated")
	assert(bool(place["held"]), "110 is below the bar's own foot of 100, and 410 is above the foot line's 500")
	assert(float(place["bar_foot"]) == 100.0, "and the bar's foot is read, not restated: %.1f" % place["bar_foot"])
	(room.get_node(^"Palette") as Control).position = Vector2(0.0, 90.0)
	var over: Dictionary = LayoutCheck.palette_between_the_bar_and_the_foot(room, true)
	assert(not bool(over["held"]), "at 90 the palette is drawn over the bar's foot of 100, so it is not held")
	assert(float(over["palette_top"]) == 90.0, "and the offending height is reported: %.1f" % over["palette_top"])
	room.free()


## And where there is no screen the question is refused in words rather than answered with a nonsense number.
## A headless run's dummy display is 64 x 64, so a finger-typed foot line wraps to several screen-heights and
## its top has come back as `-69443` - measured, and it made the audit `FAIL HUD layout` on a fault nobody had.
## The rule is `HudProbe._a_real_screen`, the same one the probe's own `small` and `close` lines follow.
func test_the_palette_between_the_bar_and_the_foot_refuses_without_a_screen() -> void:
	var room: Control = _room_with_the_bar_the_palette_and_the_foot(110.0, 300.0, 500.0)
	var place: Dictionary = LayoutCheck.palette_between_the_bar_and_the_foot(room, false)
	room.free()
	assert(not bool(place["asked"]), "nothing is asked where there is no screen to have the answer on")
	assert(not bool(place["held"]), "and nothing is called held")
	assert(String(place["why"]).contains("no screen"), "and it says why: %s" % place["why"])
	assert(not place.has("bar_foot"), "with no numbers read at all, rather than numbers nobody could have")


## A finger's fitting is **forward-only** - `PhoneHud.size_for_a_finger` refuses an answer that is not a finger,
## so nothing in the program puts a desk back - and the pass writes the room back by hand. This is that half, and
## it is the one that matters to whatever runs behind the pass: without it the front door was left 527 px off the
## right edge of the room the checks after it measure.
func test_what_a_finger_changes_can_be_put_back_exactly() -> void:
	var hud := Control.new()
	var grown := Label.new()
	grown.name = "HintsLabel"
	grown.custom_minimum_size = Vector2(0.0, 31.0)
	hud.add_child(grown)
	var put_away := Label.new()
	put_away.name = "Kept"
	hud.add_child(put_away)
	var was: Dictionary = LayoutCheck._remember_what_a_finger_changes(hud)
	# What the fitting does: a taller least size, a caption's type stated, and a child put away.
	grown.custom_minimum_size = Vector2(0.0, 97.0)
	grown.add_theme_font_size_override(&"font_size", 25)
	put_away.visible = false
	LayoutCheck._put_back_what_a_finger_changed(hud, was)
	assert(grown.custom_minimum_size == Vector2(0.0, 31.0), "the least size came back: %s" % grown.custom_minimum_size)
	assert(
		not grown.has_theme_font_size_override(&"font_size"),
		"the type override the fitting added is gone again, because none was stated before it ran",
	)
	assert(put_away.visible, "and the child the fitting put away is shown again")
	hud.free()
