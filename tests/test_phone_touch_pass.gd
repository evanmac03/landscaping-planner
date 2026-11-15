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
		"PROBE --- what is on the screen ---\r\n" + "PROBE device   finger=true zooming=true\r\n"
		+ "PROBE room     viewport=(1185, 2567) native=(1080, 2340)\r\n"
		+ "PROBE --- what is on the screen ---\r\n" + "PROBE device   finger=true zooming=true\r\n"
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
		1_000_000,
		{ "count": 3, "path": "res://scripts/hud.gd", "readable": true },
		1_000_600,
	)
	assert(
		written.contains("3 script") and written.contains("res://scripts/hud.gd"),
		"it names what changed: %s" % written,
	)
	assert(written.contains("10 minutes"), "and how old the build is, in words a person uses: %s" % written)
	assert(
		ToolScript.build_words(1_000_000, { "count": 0, "readable": true }, 1_000_600).contains("work"),
		"a build nothing has changed since is the work in hand",
	)
	# **The line a person is handed has to be the line they can paste**, and the path this tool keeps for the file is
	# not the one either its own header or the manual writes: printing the constant straight out said
	# `res://build/phone-adapt.apk`, which is the wrong shape for the engine's own `--export-debug`.
	assert(
		ToolScript.export_words().contains("build/phone-adapt.apk"),
		"the line to make a build names the file the way it is typed: %s" % ToolScript.export_words(),
	)
	assert(not ToolScript.export_words().contains("res://"), "and not the project path the constant wears")
	assert(ToolScript.age_words(30) == "30 seconds", "under a minute and a half, seconds")
	assert(ToolScript.age_words(600) == "10 minutes", "up to an hour and a half, minutes")
	assert(ToolScript.age_words(7200) == "2 hours", "and hours after that")


## **A key name is a device keycode, and two of them are refused for reasons that were measured.** The refusals are
## the point of the verb: a tool exists so that a session is not repeated, and what a session learned about Escape
## cost a whole pass - the phone's own USB settings panel was on the screen while the tool went on driving into it.
func test_the_keys_a_phone_answers_are_named_and_the_ones_it_does_not_are_refused() -> void:
	assert(ToolScript.the_key_number("back") == 4, "BACK is the device's own 4")
	assert(ToolScript.the_key_number("TAB") == 61, "and a name is read in any case")
	assert(ToolScript.the_key_number("enter") == 66, "ENTER is what drives a dialog's own buttons")
	assert(ToolScript.the_key_number("nonsense") == -1, "a name nobody has is answered with -1, not with a key")
	assert(ToolScript.the_key_number("escape") == -1, "and Escape is one this tool will not send")
	assert(
		ToolScript.key_words("escape").contains("never reached this program"),
		"the refusal for Escape says what was measured: %s" % ToolScript.key_words("escape"),
	)
	assert(
		ToolScript.key_words("8").contains("keyevent 8"),
		"a single character's refusal names the measurement behind it: %s" % ToolScript.key_words("8"),
	)
	assert(
		ToolScript.key_words("w").contains("--taps"),
		"and hands over the thing that does work instead: %s" % ToolScript.key_words("w"),
	)
	assert(ToolScript.key_words("nonsense").contains("back"), "an unknown name is told what there is")


## **The age of a block is the one thing its own text cannot say, and the whole question a stale reading turns on.**
## A block with no readable stamp is not a block that is no seconds old: it is one whose moment is unknown, and that
## is a different answer which must not be read as a fresh one.
func test_the_blocks_in_a_log_are_listed_by_age_and_by_what_each_named() -> void:
	var logcat := (
		"1000.500  17160  17269 I godot   : PROBE --- what is on the screen ---\n"
		+ "1000.500  17160  17269 I godot   : PROBE device   finger=true\n"
		+ "1000.600  17160  17269 I godot   : PROBE page     start_window  \"Landscaping Planner\"  at (0, 481)\n"
		+ "1012.000  17160  17269 I godot   : PROBE --- what is on the screen ---\n"
		+ "1012.000  17160  17269 I godot   : PROBE device   finger=true\n"
	)
	var blocks: Array[Dictionary] = ToolScript.block_headings(logcat, 1020.0)
	assert(blocks.size() == 2, "two headings make two blocks: %s" % str(blocks))
	assert(is_equal_approx(float(blocks[0]["age"]), 19.5), "the first block is 19.5 s old")
	assert((blocks[0]["names"] as PackedStringArray)[0] == "start_window", "and it named the page that was up")
	assert(is_equal_approx(float(blocks[1]["age"]), 8.0), "the newest is 8 s old, counted from its own heading")
	assert((blocks[1]["names"] as PackedStringArray).is_empty(), "and named no page: the board was what was up")
	var unstamped: Array[Dictionary] = ToolScript.block_headings("PROBE --- what is on the screen ---\n", 1020.0)
	assert(float(unstamped[0]["age"]) < 0.0, "a block with no clock on it is not a block that is no seconds old")


## **A rectangle on a line is where a finger would land, and it is read in the probe's own words.** A tap line
## carries the control's screen rectangle and the centre published for it; a line with no rectangle is not a place on
## any picture, and must not be mistaken for one.
func test_a_line_publishes_the_rectangle_its_centre_was_measured_in() -> void:
	var line := (
		"tap      board                        \"Line / 1\"                         screen (150, 380) .. (210, 440)"
		+ " 60x60 px  centre (180, 410)"
	)
	var rect: Rect2i = ToolScript.rect_of(line)
	assert(rect == Rect2i(150, 380, 60, 60), "two corners become a place and a size: %s" % str(rect))
	assert(ToolScript.centre_of(line) == Vector2i(180, 410), "and the centre is inside it")
	assert(ToolScript.rect_of("tap      board   \"Fit\"   centre (10, 10)") == Rect2i(), "no rectangle is not one")
	assert(
		ToolScript.rect_of(
			"page     start_window  \"x\"  at (0, 481)  ->  screen (70, 1069) .. (1021, 1459) 951x390 px"
		)
		== Rect2i(70, 1069, 951, 390),
		"a page's own line gives its rectangle in the same words",
	)


## Only the lines that published a rectangle of the kind asked for are boxes, and a page's rectangle is a box of its
## own: the two are different questions, which is why `--overlay` draws them in two colours.
func test_the_boxes_are_only_the_lines_that_published_a_rectangle_of_that_kind() -> void:
	var block := PackedStringArray(
		[
			"device   finger=true",
			"page     start_window  \"Landscaping Planner\"  ->  screen (70, 1069) .. (1021, 1459) 951x390 px",
			"tap      startwindow                  \"Design the garden\"                screen (100, 1200) .. (980, 1500) 880x300 px  centre (540, 1350)",
			"tap      startwindow                  \"Learn more\"                       screen (100, 1500) .. (980, 1600) 880x100 px  centre (540, 1550)",
			"foot     \"Left-drag: move\"",
		]
	)
	var taps: Array[Rect2i] = ToolScript.boxes_of(block, "tap")
	assert(taps.size() == 2, "two controls were published: %s" % str(taps))
	assert(taps[0] == Rect2i(100, 1200, 880, 300), "each with its own rectangle")
	assert(ToolScript.boxes_of(block, "page").size() == 1, "and the page is a box on its own")
	assert(ToolScript.boxes_of(block, "foot").is_empty(), "a line that published no rectangle is not a box")


## The pages one block named, in the words a driver reads - including the board's own case, which is not a fault but
## simply nothing being in front.
func test_the_page_a_block_named_is_read_off_its_own_line() -> void:
	var board := PackedStringArray(["device   finger=true", "foot     \"Left-drag: move\""])
	var one := PackedStringArray(["page     start_window  \"Landscaping Planner\"  at (0, 481)"])
	var two := PackedStringArray(
		["page     start_window  \"Landscaping Planner\"", "page     start_drawing_window  \"Begin a drawing\""]
	)
	assert(ToolScript.page_names_in(board) == "no page", "the board is a board, not a page")
	assert(ToolScript.page_names_in(one) == "1 page(s): start_window", "one page is named")
	assert(ToolScript.page_names_in(two).contains("start_drawing_window"), "and two are both named")


## **What the phone is running is a fact rather than an inference from a timestamp.** The path comes from the
## phone's own `pm path` and the hash from its own `md5sum`, and either can answer with *nothing* - a phone that
## will not name its copy, or will not read it - which is a different answer from a hash that does not match.
func test_what_the_phone_is_running_is_read_from_its_own_path_and_hash() -> void:
	var named := "package:/data/app/~~abc==/ca.storm.landscapingplanner-xyz==/base.apk"
	assert(
		ToolScript.apk_path_from(named) == "/data/app/~~abc==/ca.storm.landscapingplanner-xyz==/base.apk",
		"the path is read past the word `package:` it is carried behind",
	)
	assert(ToolScript.apk_path_from("") == "", "a phone that named nothing is answered with nothing")
	assert(ToolScript.apk_path_from("Error: package not found") == "", "and so is one that refused")
	assert(
		ToolScript.apk_path_from(named + "\npackage:/data/app/~~abc==/split_config.en.apk")
		== "/data/app/~~abc==/ca.storm.landscapingplanner-xyz==/base.apk",
		"an app installed as split APKs names its base one first, which is what an install replaces",
	)
	var line := "d41d8cd98f00b204e9800998ecf8427e  /data/app/x/base.apk"
	assert(ToolScript.hash_of(line) == "d41d8cd98f00b204e9800998ecf8427e", "a hash is the first word of its line")
	assert(ToolScript.hash_of("/data/app/x/base.apk: No such file") == "", "a line holding no hash is not a hash")
	assert(ToolScript.hash_of("") == "", "and neither is nothing")


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


## **A centre is read off the line the program itself printed, and a line without one says so.** `--press` aims at
## one of these, so a misread here presses something else - which is the whole reason the verb exists instead of a
## person copying a pair of numbers out of a block and typing them again.
func test_a_centre_is_read_off_the_line_the_probe_printed() -> void:
	var printed: String = (
		"tap      the board                    \"Cancel\"                           "
		+ "screen (260, 510) .. (380, 541) 120x31 px  centre (320, 526)"
	)
	assert(ToolScript.centre_of(printed) == Vector2i(320, 526), "the centre is the line's own last words")
	# A line of another kind names no centre, and a line whose numbers are not numbers is not a place either.
	var overlap_line: String = "overlap  Drawing (0) (words) and start_window (bar) share 464 x 12 px at (25, 325)"
	assert(ToolScript.centre_of(overlap_line) == Vector2i(-1, -1), "a line that names no centre is no centre")
	assert(
		ToolScript.centre_of("tap      the board  \"Cancel\"  centre (32x, 5)") == Vector2i(-1, -1),
		"and neither is one whose numbers are not numbers",
	)
	assert(
		ToolScript.centre_of("tap      the board  \"Cancel\"  centre (320)") == Vector2i(-1, -1),
		"nor is half a pair a place to aim at",
	)


## **Only a `tap` line is a control a finger can press, and the block's other lines are full of the words wanted.**
## The phone's own foot line says `Esc: cancel`, so a search that did not ask for the kind first would find a
## sentence and report a place no finger can reach. Measured on the A16W, 2026-11-14.
##
## And a control the block does not name is refused in words that say how it is reached instead: the palette's own
## `Cancel` sits below its column's fold when the board is held upright, so `--swipe` is the answer rather than a
## guessed centre.
func test_pressing_a_control_uses_the_blocks_own_centre_and_refuses_by_name() -> void:
	var block: PackedStringArray = PackedStringArray(
		[
			"device   finger=true zooming=true",
			"foot     \"Esc: cancel     Left-drag: move a plant\"",
			"tap      the board  \"Cancel\"   screen (260, 510) .. (380, 541) 120x31 px  centre (320, 526)",
		]
	)
	var found: Dictionary = ToolScript.press_words(block, "cancel")
	assert(bool(found["found"]), "the words are found whatever their case: %s" % str(found))
	assert(found["at"] == Vector2i(320, 526), "and the centre is the one the line published: %s" % str(found["at"]))
	assert(String(found["line"]).begins_with("tap "), "the line found is the tap line and not the foot line")

	var missing: Dictionary = ToolScript.press_words(block, "Undo")
	assert(not bool(missing["found"]), "a control the block does not name cannot be pressed")
	var said: String = String(missing["said"])
	assert(said.contains("Undo"), "the refusal names what was looked for: %s" % said)
	assert(said.contains("--swipe"), "and names the way to bring it into view: %s" % said)


## **A drag is four numbers, and a duration it may not have.** A drag missing its end is not a drag - reading one as
## a press would be a guess - and the duration is bounded at both ends, so a mistyped one is a slow drag rather than
## something that never finishes.
func test_a_drag_is_read_from_four_numbers_and_a_duration_it_may_not_have() -> void:
	var drag: Array[Vector2i] = ToolScript.the_swipe(PackedStringArray(["--swipe", "540", "1800", "540", "1200"]))
	assert(drag.size() == 2, "a start and an end: %d" % drag.size())
	assert(drag[0] == Vector2i(540, 1800) and drag[1] == Vector2i(540, 1200), "the numbers as typed: %s" % str(drag))
	assert(
		ToolScript.the_swipe(PackedStringArray(["--swipe", "540", "1800", "540"])).is_empty(),
		"half a drag is no drag, which is not the same thing as a press",
	)
	assert(ToolScript.the_swipe(PackedStringArray(["--swipe", "540", "1800", "540", "down"])).is_empty(), "and neither is one whose numbers are not numbers")
	assert(ToolScript.the_drag_ms(PackedStringArray(["--swipe", "1", "2", "3", "4"])) == 300, "the drag has a default")
	assert(ToolScript.the_drag_ms(PackedStringArray(["--swipe", "1", "2", "3", "4", "900"])) == 900, "and takes one")
	assert(
		ToolScript.the_drag_ms(PackedStringArray(["--swipe", "1", "2", "3", "4", "1"])) == 50,
		"kept above an eyeblink",
	)
	assert(
		ToolScript.the_drag_ms(PackedStringArray(["--swipe", "1", "2", "3", "4", "99999"])) == 5000,
		"and below a wait nobody would sit through",
	)


## **A crop nobody asked for is a file that lies about what it is**, so a region with missing numbers, or with words
## where numbers belong, is nothing at all rather than the whole screen as a consolation.
func test_a_crop_region_is_four_numbers_and_nothing_otherwise() -> void:
	assert(
		ToolScript.the_region(PackedStringArray(["--crop", "0", "1700", "1080", "500"])) == Rect2i(0, 1700, 1080, 500),
		"the region as typed",
	)
	assert(
		ToolScript.the_region(PackedStringArray(["--crop", "0", "1700", "1080"])) == Rect2i(),
		"three numbers is no region",
	)
	assert(ToolScript.the_region(PackedStringArray(["--fresh"])) == Rect2i(), "no `--crop` at all is no region")
	assert(
		ToolScript.the_region(PackedStringArray(["--crop", "0", "1700", "wide", "500"])) == Rect2i(),
		"and a word where a number belongs is no region",
	)


## **A block names the page it is for, or names none when there is nothing in front of the board.** That is all this
## rule answers, and nothing more: whether a block *arrives* when a page leaves is the program's business, and on
## 2026-11-14 it did not. Measured on the A16W, a BACK that the picture proved had landed left the newest block
## still naming the page it had put away, because only the pages built at start-up had been watched - and the cure
## the same day was for `Hud` to ask the *screen* instead. A driver still reads this as the block's answer and not
## the screen's, which is why every run takes a picture.
func test_a_block_is_asked_whether_it_names_a_page() -> void:
	assert(
		ToolScript.a_block_names_a_page(PackedStringArray(["device   finger=true", "page     start_window  \"x\""])),
		"a block taken with a page up names it",
	)
	assert(
		not ToolScript.a_block_names_a_page(PackedStringArray(["device   finger=true", "overlap  24 surface(s) drawn"])),
		"and a block taken with the board in front names no page",
	)
	assert(not ToolScript.a_block_names_a_page(PackedStringArray()), "and neither does a block holding nothing")


## **The word after a flag is one rule**, read by `--taps` and by `--press` alike, so that the two cannot come to
## disagree about whether a following flag is a word to look for.
func test_the_word_after_a_flag_is_the_first_thing_that_is_not_a_flag() -> void:
	assert(
		ToolScript.the_word_after(PackedStringArray(["--press", "Begin"]), "--press") == "Begin",
		"the word as typed",
	)
	assert(
		ToolScript.the_word_after(PackedStringArray(["--press", "--back"]), "--press") == "",
		"a flag after it is not a word to look for",
	)
	assert(
		ToolScript.the_word_after(PackedStringArray(["--fresh"]), "--press") == "",
		"and no flag at all names nothing",
	)
	assert(
		ToolScript.tap_filter(PackedStringArray(["--taps", "Cancel"]))
		== ToolScript.the_word_after(PackedStringArray(["--taps", "Cancel"]), "--taps"),
		"`--taps` reads its word by the same rule, because it is the same rule",
	)
