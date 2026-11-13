extends Node
## `tools/phone_touch_pass.gd`'s own arithmetic, held down without a phone: it is the only instrument the touch
## GUI has on a real device, so everything in it that can be decided by reading is decided here rather than by
## spending a run.
##
## Nothing here touches adb. The script is instantiated but **never added to the tree**, so `_ready` - which
## installs, launches and taps - does not run, and each instance is freed by the test that made it. The
## device-side half is proved by running the tool itself.

const ToolScript := preload("res://tools/phone_touch_pass.gd")


func test_a_tap_is_read_from_the_two_numbers_a_person_types() -> void:
	var tool: Node = ToolScript.new()
	assert(tool._the_tap(PackedStringArray(["--tap", "540", "552"])) == Vector2i(540, 552), "the centre as typed")
	# An incomplete pair is not a tap at the origin, which is a real place on a screen: it is no tap at all.
	assert(tool._the_tap(PackedStringArray(["--tap", "540"])) == Vector2i.ZERO, "half a pair is read as no tap")
	assert(tool._the_tap(PackedStringArray([])) == Vector2i.ZERO, "and so is no flag at all")
	tool.free()


func test_the_wait_defaults_and_will_not_be_asked_for_less_than_two_seconds() -> void:
	var tool: Node = ToolScript.new()
	assert(tool._wait_seconds(PackedStringArray([])) == 14, "a phone with nothing asked for gets the default wait")
	assert(tool._wait_seconds(PackedStringArray(["--wait", "30"])) == 30, "and as long as it was asked for")
	assert(
		tool._wait_seconds(PackedStringArray(["--wait", "0"])) == 2,
		"a wait that is no wait at all is raised to the floor",
	)
	tool.free()


## **A centre is only where a finger should land in the room it was measured in.** The device turns under the
## program, and a tap sent from a portrait block to a landscape screen reaches nothing at all - measured on the
## A16W, a centre at y 1654 on a 1080-tall screen - and the only thing that said so was a person wondering at the
## run afterwards. The tool says it instead, with both numbers.
func test_a_tap_outside_the_room_the_block_was_taken_in_is_named_as_such() -> void:
	var room := Vector2i(1444, 666)
	var landed: String = ToolScript.tap_words(Vector2i(700, 300), room)
	assert(landed.contains("inside"), "a tap in the room is in it: %s" % landed)
	var adrift: String = ToolScript.tap_words(Vector2i(540, 1654), room)
	assert(adrift.contains("outside"), "a tap past the foot of the room is outside it: %s" % adrift)
	assert(adrift.contains("(1444, 666)"), "and the room it was measured against is named: %s" % adrift)
	# No room is no reading of the tap either, rather than a tap inside a room of no size that would clear it.
	assert(
		ToolScript.tap_words(Vector2i(540, 552), Vector2i.ZERO).contains("names no room"),
		"no block, no reading of where the tap landed",
	)
