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


## **A block is a moment, and the log holds several of them.** The reading only has a newest block because the
## probe's own heading separates them, and the heading's line is `--- what is on the screen ---`, published like
## every other. Getting this wrong by one block is getting the whole reading wrong, silently: measured 2026-11-14,
## a diagnosis was built on a block published at launch while the screen it was about had long moved on.
##
## The text comes off `adb`, which puts a carriage return on every line, so that is in the log handed over here as
## well - a parse that broke on it would break on the device and nowhere else.
func test_a_logs_blocks_are_read_from_the_probes_own_heading_and_the_newest_is_last() -> void:
	var log: String = (
		"PROBE --- what is on the screen ---\r\n"
		+ "PROBE device   finger=true zooming=true\r\n"
		+ "PROBE room     viewport=(1185, 2567) native=(1080, 2340)\r\n"
		+ "PROBE --- what is on the screen ---\r\n"
		+ "PROBE device   finger=true zooming=true\r\n"
		+ "PROBE overlap  50 surface(s) drawn, and nothing meets anything it may not\r\n"
	)
	var blocks: Array[String] = ToolScript.blocks_in(log)
	assert(blocks.size() == 2, "the heading separates two blocks, not one: %d" % blocks.size())
	assert(blocks[1].contains("nothing meets anything it may not"), "and the newest is the last: %s" % blocks[1])
	assert(not blocks[0].contains("overlap"), "the older one does not carry the newer one's news: %s" % blocks[0])
	# Text that is not the probe's at all is not a block, so neither logcat nor a shell's own noise gets in.
	assert(ToolScript.blocks_in("some other program's line\n").is_empty(), "a log with no probe line holds no block")


## **A phone is easy to read a screen the program in hand has never been given.** The build on disk is compared with
## the tree it was made from, and by how long ago it was made rather than by a clock time: a unix time printed back
## is in UTC, and this desk is not, so "14:44" would be four or five hours from what a person sees in their file
## manager. An age cannot be wrong about that.
##
## Only what reaches the phone's program is counted. A test, a doc or a dev tool is nothing to export for, so a
## tree full of yesterday's tests is not a reason to install again.
func test_the_tree_is_asked_whether_a_script_has_changed_since_the_build_was_made() -> void:
	# Nothing built at all is named as such rather than read as a tree that has held still.
	assert(
		ToolScript.build_words(0, ToolScript.files_since([], [], 0), 1000).contains("no build"),
		"a build that is not there says so",
	)

	# Every script in this suite's own tree is newer than the epoch, which is the walk working at all.
	var all_time: Dictionary = ToolScript.files_since(["res://tests"], [".gd"], 0)
	assert(int(all_time["count"]) > 0, "the walk found this suite's own scripts: %s" % str(all_time))
	assert(String(all_time["path"]).begins_with("res://tests/"), "and names one of them: %s" % str(all_time["path"]))
	assert(bool(all_time["readable"]), "and says the tree could be walked")

	# The suffix is what decides, not the directory: nothing here is a `.txt`.
	assert(
		int(ToolScript.files_since(["res://tests"], [".txt"], 0)["count"]) == 0,
		"a suffix no file has finds nothing",
	)
	# And nothing is newer than a moment far in the future, which is the reading a fresh build gets.
	assert(
		int(ToolScript.files_since(["res://tests"], [".gd"], 4102444800)["count"]) == 0,
		"a build made in 2100 is behind nothing",
	)
	# **An exported program cannot list `res://` at all**, so a walk that found nothing says nothing about the
	# build rather than reading as a tree that has held still.
	assert(
		not bool(ToolScript.files_since(["res://no-such-folder"], [".gd"], 0)["readable"]),
		"a tree that cannot be walked is not a tree that has held still",
	)

	var written: String = ToolScript.build_words(
		1_000_000, {"count": 3, "path": "res://scripts/hud.gd", "readable": true}, 1_000_600
	)
	assert(
		written.contains("3 script") and written.contains("res://scripts/hud.gd"),
		"it names what changed: %s" % written,
	)
	assert(written.contains("10 minutes"), "and how old the build is, in words a person uses: %s" % written)
	assert(
		ToolScript.build_words(1_000_000, {"count": 0, "readable": true}, 1_000_600).contains("work"),
		"a build nothing has changed since is the work in hand",
	)
	assert(ToolScript.age_words(30) == "30 seconds", "under a minute and a half, seconds")
	assert(ToolScript.age_words(600) == "10 minutes", "up to an hour and a half, minutes")
	assert(ToolScript.age_words(7200) == "2 hours", "and hours after that")


## **The centres are the half of the tool a driver needs, and a driver usually wants one control.** `--taps` on its
## own prints every centre the newest block published, so it is worth being able to name the words wanted instead -
## and a flag typed after it is not a word to search for, which would find nothing and look like a clean answer.
func test_the_centres_can_be_narrowed_by_one_word_and_not_by_a_flag() -> void:
	assert(ToolScript.tap_filter(PackedStringArray(["--taps", "Cancel"])) == "Cancel", "the word as typed")
	assert(ToolScript.tap_filter(PackedStringArray(["--taps"])) == "", "a bare `--taps` narrows nothing")
	assert(
		ToolScript.tap_filter(PackedStringArray(["--taps", "--back"])) == "",
		"and the flag after it is not read as a word to look for",
	)
	assert(ToolScript.tap_filter(PackedStringArray(["--fresh"])) == "", "no `--taps` at all narrows nothing")


## **A block with no touch line in it is good news, not silence, and only the device line says which.** The first
## version could never reach its own sentence for this: it asked only when *nothing at all* had been printed, and
## the device line was one of the kinds it printed. Measured 2026-11-14.
func test_a_block_says_whether_a_finger_is_being_served() -> void:
	assert(
		ToolScript.says_a_finger(PackedStringArray(["device   finger=true zooming=true scale=0.91"])),
		"a block serving a finger says so",
	)
	assert(
		not ToolScript.says_a_finger(PackedStringArray(["device   finger=false zooming=false scale=1.0"])),
		"and a desk's block does not",
	)
	assert(
		not ToolScript.says_a_finger(PackedStringArray(["room     viewport=(1185, 2567)"])),
		"and a block with no device line answers neither way rather than guessing",
	)
