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


## **A capture is only worth taking the way up it was asked for, and the hold is what decides that.** The board
## obeys `OrientationChoice`'s own hold in `files/orientation.json`, and an unreadable one is refused *by design*,
## so the hold silently falls back to the wide default and the board answers `shape=lying`. The file the A16W was
## found holding read `{orientation:portrait}` with its key unquoted - which is not JSON - and that is why portrait
## looked impossible to force for a whole session. `--capture` says which way up the board is held **before** it
## launches anything, rather than leaving it to be noticed in a screenshot afterwards.
func test_the_hold_is_read_and_an_unreadable_one_is_named_rather_than_believed() -> void:
	assert(
		ToolScript.hold_words("{\"orientation\": \"portrait\"}").begins_with("the board is held upright"),
		"the one hold the capture can use says so in words",
	)
	assert(
		ToolScript.hold_words("{\"orientation\": \"landscape\"}").contains("not held upright"),
		"a hold that says landscape is not the one the two gaps ask for",
	)
	assert(
		ToolScript.hold_words("{orientation:portrait}").contains("not readable JSON"),
		"and the file the device was actually found holding is named as unreadable rather than read as portrait",
	)
	assert(
		ToolScript.hold_words("").contains("no orientation.json"),
		"an absent hold names the file that is missing rather than reading as a default",
	)


## **An instrument that has nothing to say is not the same as one that cannot ask.** Measured 2026-11-14 with the
## A16W's wireless debugging off: `adb devices -l` came back with an empty table and the tool went on to say "the
## log holds no block - has the program run since it was installed?", pointing a person at the program when the
## fault was that no phone was in reach. The word `device` on its own would have proved nothing - it is inside the
## header's `devices`, which every run carries - so what is read is the **state column**.
func test_a_phone_is_here_only_when_adb_names_the_state_column_a_device() -> void:
	assert(
		not ToolScript.a_device_is_here("List of devices attached\n\n"),
		"an empty table is no phone, and that is the reading that used to be mistaken for silence",
	)
	assert(
		not ToolScript.a_device_is_here("List of devices attached\n"),
		"and neither is the header the table always prints",
	)
	assert(
		ToolScript.a_device_is_here(
			("List of devices attached\nR5CYA269Q8P\tdevice product:a16 model:SM_A166W device:a16 transport_id:3\n")
		),
		"a device in the state column is one",
	)
	assert(
		not ToolScript.a_device_is_here("List of devices attached\nR5CYA269Q8P\tunauthorized\n"),
		"and one still waiting to be authorised is not yet a phone this can ask anything of",
	)
	# **A table with Windows line endings is the same table.** `adb` under Git Bash prints `device\r`, so a
	# readiness check that compared a whole line against `device` never matched and refused a phone that was
	# plugged in - measured: a whole capture cycle reported `NO DEVICE` while `adb devices -l` plainly listed it.
	assert(
		ToolScript.a_device_is_here("List of devices attached\r\nR5CYA269Q8P\tdevice product:a16\r\n"),
		"and the carriage return adb puts on every line is not read as part of the state column",
	)
