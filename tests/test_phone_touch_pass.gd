extends Node
## `tools/phone_touch_pass.gd`'s own arithmetic, held down without a phone: it is the only instrument the touch
## GUI has on a real device, so everything in it that can be decided by reading is decided here rather than by
## spending a run.
##
## Nothing here touches adb. The script is instantiated but **never added to the tree**, so `_ready` - which
## installs, launches and taps - does not run, and each instance is freed by the test that made it. The
## device-side half is proved by running the tool itself.

const ToolScript := preload("res://tools/phone_touch_pass.gd")
const HudProbeScript := preload("res://scripts/hud_probe.gd")


## **A numbered `tap` line is still read exactly as it was.** The probe now ends each tap line with the control's
## number in the block, and this tool's own readers find a line's rectangle by the **last** `screen (` and its name
## by the words before that - so the number must change neither. Held here because these two readers are what mark
## the block's rectangles on the glass: a number that quietly moved a rectangle would paint every control in the
## wrong place, and the picture is the arbiter.
func test_a_numbered_tap_line_gives_the_rectangle_and_the_name_it_gave_before() -> void:
	const PLAIN := (
		"tap      the board                    \"Line / 1\""
		+ "                        screen (28, 115) .. (131, 169) 103x54 px  centre (80, 142)"
	)
	var before: Rect2i = ToolScript.rect_of(PLAIN)
	assert(before == Rect2i(28, 115, 103, 54), "the rectangle is the line's last `screen (`: %s" % str(before))
	assert(ToolScript.rect_of(PLAIN + "  #4") == before, "a numbered line gives the very rectangle it gave unnumbered")
	var named: Array[Dictionary] = ToolScript.named_boxes_of(PackedStringArray([PLAIN + "  #4"]), "tap")
	assert(named.size() == 1, "one line, one box")
	assert(
		not String(named[0]["name"]).contains("#"),
		"the number is after the rectangle, so it cannot reach the name: %s" % String(named[0]["name"]),
	)
	assert(int(named[0]["n"]) == 4, "and the box carries the block's own number for it: %s" % str(named[0]["n"]))


## **A number is read off the end of a `tap` line, and only from the end.** A caption is free to hold a `#` - and
## some do - so a reader that took the first one it found would number a control from the words of another. A line
## from a block written before the numbers existed answers 0, which is what tells a caller to leave the number off
## rather than draw one it made up.
func test_the_number_of_a_line_is_its_last_token_and_nothing_else() -> void:
	const A_LINE := (
		"tap      the board                    \"Line / 1\""
		+ "                        screen (28, 115) .. (131, 169) 103x54 px  centre (80, 142)"
	)
	assert(ToolScript.number_in(A_LINE + "  #4") == 4, "the number a numbered line ends with")
	assert(ToolScript.number_in(A_LINE + "  #12") == 12, "however many digits it has")
	assert(ToolScript.number_in(A_LINE) == 0, "a line from before the numbers existed has none")
	assert(
		ToolScript.number_in("tap   the board   \"Row #3\"   screen (1, 2) .. (3, 4) 2x2 px  centre (2, 3)") == 0,
		"and a caption holding a # is not the number",
	)
	assert(ToolScript.number_in("page   start_window  \"A page\"") == 0, "and a line of another kind has none either")


## **The two sentences a phone logged on every launch of a build that carried a library it did not contain.** Both
## were read off the SM-A166W on 2026-11-10, on a build that went on to draw a screen with nothing wrong on it -
## which is why the pass reported no trouble at all. The touch rules ask about rectangles and cannot see a library
## that never loaded; this rule is what says so, and `SCRIPT ERROR` is the same kind of line, printed by the engine
## with `ERROR:` in front of it.
func test_a_launch_fault_is_named_the_way_the_device_logs_it() -> void:
	var log := (
		"1763605000.123456  1234  1234 I godot   : Error loading extension\n"
		+ "1763605000.223456  1234  1234 E godot   : ERROR: Node CrabbyConsole of type CrabConsole"
		+ " cannot be created. A placeholder will be created instead.\n"
	)
	var found: PackedStringArray = ToolScript.launch_faults(log)
	assert(found.size() == 2, "both sentences are faults: %s" % str(found))
	assert(String(found[0]).contains("Error loading extension"), "the loader's own words: %s" % String(found[0]))
	assert(
		String(found[1]).contains("cannot be created"),
		"and the placeholder's, on the line that begins with ERROR:: %s" % String(found[1]),
	)
	assert(
		ToolScript.launch_faults("godot   : SCRIPT ERROR: Parse Error: Identifier \"x\" not found").size() == 1,
		"a script error is the same kind of line and is named too",
	)


## **A line that says how many errors there were is not one of them**, and neither is a block. This is the whole
## reason the rule names markers instead of searching for the word "error": a log is full of numbers a fault rule
## cannot tell from a reading, and naming a report's own summary as a fault is the defect a marker avoids.
func test_a_count_of_errors_and_a_block_are_not_faults() -> void:
	assert(
		ToolScript.launch_faults("godot   : 0 errors, 3 warnings, and the launch was clean").is_empty(),
		"a count of errors is not a fault",
	)
	assert(
		ToolScript.launch_faults("godot   : PROBE --- what is on the screen ---").is_empty(),
		"and neither is the program's own block",
	)
	assert(ToolScript.launch_faults("").is_empty(), "and an empty log has nothing to say")


## A fault that happens on every launch is **one** fault however often the log carries it: the report is read by a
## person, and the same sentence four times is one thing to go and fix.
func test_the_same_fault_logged_again_is_reported_once() -> void:
	const LINE := "1763605000.1  1234  1234 I godot   : Error loading extension"
	var found: PackedStringArray = ToolScript.launch_faults("%s\n%s\n%s\n" % [LINE, LINE, LINE])
	assert(found.size() == 1, "one fault, said once: %s" % str(found))
	assert(found[0] == LINE, "and the line is the device's own, unreworded: %s" % String(found[0]))


## **An age is a subtraction, and a line the device did not stamp has none.** logcat is read with `-v epoch` for
## exactly this reason: the stamp is an absolute second, so how old a fault is comes from here rather than from two
## clocks' opinions of what "14:44" means. A line that cannot be dated must answer nothing, never a guess - and
## the report says so in words instead of claiming the fault came up with the program.
func test_a_lines_age_comes_from_the_devices_own_stamp_or_from_nothing() -> void:
	var stamped: float = ToolScript.when_a_line_was_logged(
		"1795138280.048 14410 14514 E godot   : ERROR: Node CrabbyConsole cannot be created"
	)
	assert(stamped > 1795138279.0 and stamped < 1795138281.0, "the leading epoch is the stamp: %f" % stamped)
	assert(ToolScript.when_a_line_was_logged("godot   : ERROR: x") == 0.0, "a line with no stamp has no age")
	assert(ToolScript.when_a_line_was_logged("") == 0.0, "and neither has nothing at all")
	assert(ToolScript.when_a_line_was_logged("PROBE device   finger=true") == 0.0, "a block line is not stamped either")


## The A16W's own `dumpsys window displays`, cut to the fields a band comes from. **Every field here was read off the
## device**, not written from what the format was thought to be - which is why the rectangle is spelled with the dash
## the phone really uses, the one thing that would otherwise have been guessed wrong.
const A16W_SAID := (
	"    init=1080x2340 450dpi mMinSizeOfResizeableTaskDp=220"
	+ "\n    initCutout=DisplayCutout{insets=Rect(0, 100 - 0, 0)"
	+ " waterfall=Insets{left=0, top=0, right=0, bottom=0} sideOverrides={}}"
	+ "\n      ROTATION_0={nonDecorInsets=[0,0][0,0], overrideNonDecorInsets=[0,100][0,42],"
	+ " configInsets=[0,0][0,0], overrideConfigInsets=[0,100][0,42]}"
	+ "\n      ROTATION_90={nonDecorInsets=[0,0][0,0], overrideNonDecorInsets=[100,0][0,42],"
	+ " configInsets=[0,0][0,0], overrideConfigInsets=[100,84][0,42]}"
	+ "\n      ROTATION_180={nonDecorInsets=[0,0][0,0], overrideNonDecorInsets=[0,0][0,142],"
	+ " configInsets=[0,0][0,0], overrideConfigInsets=[0,100][0,142]}"
	+ "\n      ROTATION_270={nonDecorInsets=[0,0][0,0], overrideNonDecorInsets=[0,0][100,42],"
	+ " configInsets=[0,0][0,0], overrideConfigInsets=[0,84][100,42]}" + "\n      mDisplayCutoutTouchableRegionSize=34"
)


## The A16W's four frames, as the phone writes them: the area left when the bars and the cutout have had their ground.
## Upright and upside-down are taller than wide, lying and its other side are wider than tall - which is the only
## thing that tells the four apart from the outside.
const A16W_FRAMES := (
	"      ROTATION_0={overrideNonDecorInsets=[0,100][0,42], overrideNonDecorFrame=[0,100][1080,2298]}"
	+ "\n      ROTATION_90={overrideNonDecorInsets=[100,0][0,42], overrideNonDecorFrame=[100,0][2340,1038]}"
	+ "\n      ROTATION_180={overrideNonDecorInsets=[0,0][0,142], overrideNonDecorFrame=[0,0][1080,2198]}"
	+ "\n      ROTATION_270={overrideNonDecorInsets=[0,0][100,42], overrideNonDecorFrame=[0,0][2240,1038]}"
)


## A verb that answers before anything is made cannot be asked for beside a build: `--capture` and `--band` both
## return above the build path, so `--build --band` in one line would read the band, never make the build, and say
## nothing about the half it skipped. The verb that would have won is **named**, and the shape a build is actually
## for - a build with an install and a launch - is left alone.
func test_a_build_beside_a_verb_that_answers_early_is_refused_and_the_verb_named() -> void:
	var both: PackedStringArray = ToolScript.verbs_that_answer_before_a_build(PackedStringArray(["--build", "--band"]))
	assert(both.size() == 1, str(both))
	assert(both[0] == "--band", str(both))
	var capturing: PackedStringArray = ToolScript.verbs_that_answer_before_a_build(
		PackedStringArray(["--build", "--capture"])
	)
	assert(capturing.size() == 1 and capturing[0] == "--capture", str(capturing))
	var a_build_with_a_launch: PackedStringArray = ToolScript.verbs_that_answer_before_a_build(
		PackedStringArray(["--build", "--install", "--launch", "--wait", "25"])
	)
	assert(a_build_with_a_launch.is_empty(), "a build with an install and a launch is one run's work")
	var a_band_on_its_own: PackedStringArray = ToolScript.verbs_that_answer_before_a_build(
		PackedStringArray(["--band"])
	)
	assert(a_band_on_its_own.size() == 1, "a band on its own is unaffected: nothing there asks for a build")


func test_the_frame_is_chosen_by_its_shape_and_the_programs_own_reading_never_by_a_rotation() -> void:
	var standing := Vector2i(1185, 2567)
	var lying := Vector2i(1444, 666)

	# Standing: one frame is taller than it is wide, and it is the one, with no rotation named anywhere.
	assert(
		ToolScript.the_band_rect(A16W_FRAMES, standing, Vector4i(0, 100, 0, 0)) == Rect2i(0, 100, 1080, 2198),
		"standing, the frame with the camera along its top",
	)

	# Lying: two frames are wider than tall, and the program's own reading says which - a band on the left is the
	# camera on the left, and that is ROTATION_90's frame. This is the pair a rotation name would have had to guess.
	assert(
		ToolScript.the_band_rect(A16W_FRAMES, lying, Vector4i(100, 0, 0, 0)) == Rect2i(100, 0, 2240, 1038),
		"lying, with the camera on the left, the frame that gives ground there",
	)
	assert(
		ToolScript.the_band_rect(A16W_FRAMES, lying, Vector4i(0, 0, 100, 0)) == Rect2i(0, 0, 2240, 1038),
		"and the other side, the frame that gives it on the right - told apart by the reading, not by a rotation",
	)

	# And a report or a room that says nothing is no frame rather than a guess at one.
	assert(
		ToolScript.the_band_rect("nothing here at all", lying, Vector4i.ZERO) == Rect2i(),
		"a report naming no frame gives no frame",
	)
	assert(
		ToolScript.the_band_rect(A16W_FRAMES, Vector2i.ZERO, Vector4i.ZERO) == Rect2i(),
		"and neither does a room with no shape to match",
	)


## **The judgement, on a block and a band both written by hand**, so that what the sentence says can be held without a
## phone. The band is the A16W's lying frame - the camera on the left, so nothing may stand in the first 100 px - and
## the three controls are the three cases: one wholly inside, one whose **middle** the band covers, and one that only
## reaches in. The two questions are the block's own two words, and the middle one is the sharper.
func test_each_control_in_the_band_is_named_by_the_modules_own_sentence() -> void:
	var lines := PackedStringArray(
		[
			"tap      Fit         screen (700, 10) .. (760, 70) 60x60 px  centre (730, 40)",
			"tap      Line / 1    screen (10, 200) .. (100, 260) 90x60 px  centre (55, 230)",
			"tap      Polyline / 2 screen (80, 300) .. (140, 360) 60x60 px  centre (110, 330)",
		]
	)
	var band := Rect2i(100, 0, 2240, 1038)

	var middle: PackedStringArray = ToolScript.middle_in_the_band(lines, band)
	assert(middle.size() == 1, "one control takes a finger where the device keeps: %s" % str(middle))
	assert(middle[0].contains("Line / 1"), "named as the block named it: %s" % middle[0])
	assert(middle[0].contains("middle"), "and named by what it is - the middle, where a finger lands: %s" % middle[0])

	var reaching: PackedStringArray = ToolScript.reaching_into_the_band(lines, band)
	assert(reaching.size() == 2, "two reach in, which is a wider question than the one above: %s" % str(reaching))
	assert(not "\n".join(reaching).contains("Fit"), "and the control wholly inside is named by neither")

	assert(
		ToolScript.middle_in_the_band(lines, Rect2i()).is_empty(),
		"a device that keeps nothing judges nothing, rather than judging every control against a band that is not there",
	)


## **A picture has to be a picture of this program**, and the only instrument that can say so is the phone's own
## window list: a block is a memory of a screen, the photograph is the glass, and a run on 2026-11-17 marked the board's
## rectangles onto a photograph of the music player without a word. Both forms the phone writes are read.
func test_the_focused_window_is_read_as_a_package_and_a_screen_showing_nothing_names_none() -> void:
	assert(
		ToolScript.package_of_the_focused_window(
			"  mCurrentFocus=Window{9f4b2c1 u0 ca.storm.landscapingplanner/ca.storm.landscapingplanner.MainActivity}"
		)
		== "ca.storm.landscapingplanner",
		"the package, and not the window's id beside it nor the activity after it",
	)
	assert(
		ToolScript.package_of_the_focused_window(
			"  mCurrentFocus=Window{com.android.music/com.android.music.MusicBrowserActivity}"
		)
		== "com.android.music",
		"and another program is named as itself, which is the whole point of asking",
	)
	assert(
		ToolScript.package_of_the_focused_window("  mCurrentFocus=null") == "",
		"a phone showing nothing names nothing, so nothing can be claimed to be on the glass",
	)
	assert(
		ToolScript.package_of_the_focused_window("  mFocusedApp=ActivityRecord{1a2b com.android.music}") == "",
		"and a dump with no `mCurrentFocus` at all gives nothing rather than the first package it can find",
	)


func test_the_phones_own_band_is_read_out_of_the_phones_own_report() -> void:
	assert(
		ToolScript.cutout_insets_from(A16W_SAID) == Vector4i(0, 100, 0, 0),
		(
			"the camera cutout comes out of the rectangle the phone writes with a dash in it, which is the shape a"
			+ " comma-split would have read as three numbers: %s" % str(ToolScript.cutout_insets_from(A16W_SAID))
		),
	)

	var kept: Array[Vector4i] = ToolScript.kept_bands_from(A16W_SAID)
	assert(kept.size() == 8, "one band per kind per way up, and the size is the report's own: %d" % kept.size())
	assert(kept[0] == Vector4i(0, 100, 0, 42), "upright, the camera at the top: %s" % str(kept[0]))
	assert(
		ToolScript.BAND_ROWS[0].begins_with("ROTATION_0"),
		"and the name at that index is the one that band belongs to: %s" % ToolScript.BAND_ROWS[0],
	)
	assert(kept[3] == Vector4i(100, 84, 0, 42), "on its side, the camera is on the left and the top is kept too")
	assert(kept[5] == Vector4i(0, 100, 0, 142), "upside down, the bar along the foot is the biggest of them")
	assert(kept[6] == Vector4i(0, 0, 100, 42), "and the other side, the camera is on the right")


func test_a_report_this_reader_does_not_know_is_no_bands_rather_than_bands_of_nothing() -> void:
	# The distinction the caller prints: a phone keeping nothing and a report this cannot read are different answers,
	# and a pile of zeros claiming to be the second is how a wrong reading gets to look like a measurement.
	assert(
		ToolScript.kept_bands_from("init=1080x2340 450dpi").is_empty(),
		"a report with no insets block answers no bands at all",
	)
	assert(
		ToolScript.kept_bands_from(A16W_SAID.replace("ROTATION_270={", "gone={")).is_empty(),
		"and so does one that names only three of the four ways up, because a name read off one list by an index"
		+ " into another is how a band gets called by the wrong name",
	)
	assert(
		ToolScript.cutout_insets_from("init=1080x2340 450dpi") == Vector4i.ZERO,
		"a report with no cutout in it answers nothing rather than a guess",
	)


func test_the_band_the_tool_looks_for_is_the_one_the_probe_writes() -> void:
	# The tool's own check for a build that predates the band line is only true while it looks for the marker the
	# probe really writes. Two strings, one of them in `scripts/`, and this is what keeps them the same one.
	assert(
		HudProbeScript.BAND_MARK == "display l=",
		"the marker a block writes its band with: %s" % HudProbeScript.BAND_MARK,
	)


func test_the_verdict_names_which_of_the_two_readings_the_program_matched() -> void:
	var cutout := Vector4i(0, 100, 0, 0)
	var kept: Array[Vector4i] = [Vector4i(0, 100, 0, 42), Vector4i(100, 84, 0, 42)]
	assert(
		ToolScript.band_verdict(cutout, cutout, kept).contains("IS the phone's own camera cutout"),
		ToolScript.band_verdict(cutout, cutout, kept),
	)
	assert(
		ToolScript.band_verdict(kept[1], cutout, kept).contains("IS the band the phone keeps"),
		"a reading that is one of the phone's own bands is named as such: %s"
		% ToolScript.band_verdict(kept[1], cutout, kept),
	)
	assert(
		ToolScript.band_verdict(Vector4i(0, 200, 0, 0), cutout, kept).contains("matches none"),
		(
			"and a reading the phone never states says so, which is the whole answer worth having - it is what a"
			+ " disagreement between Godot's safe area and the phone looks like"
		),
	)
	assert(
		ToolScript.band_verdict(Vector4i.ZERO, cutout, kept).contains("no band at all"),
		"with a desk's own answer kept apart from a disagreement: %s"
		% ToolScript.band_verdict(Vector4i.ZERO, cutout, kept),
	)


## **A verdict that says "matches none" has to say what that means**, or the next reader investigates the whole
## question again. Measured on the A16W, 2026-11-17: the program could not *read* the phone's system bars at all,
## because Godot's safe area is the display cutout and `screen_get_usable_rect` answers the whole screen there - so
## the sentence is the finding, and it has to name the door the ground comes through.
##
## **And that door is no longer JNI**, which is what this test said until 2026-11-18. The foot band the phone keeps
## is now stated in `PhoneHud.KEPT_FEET` and given to the plates at the foot, so a verdict still promising that
## "giving it ground needs the phone's own insets over JNI" would be a sentence left standing from before the fix -
## the kind this project sends back. What it must say instead is where the number came from and where to read it:
## the `kept` line the block now publishes beside its `insets` line.
func test_a_reading_that_matches_nothing_says_the_program_cannot_read_the_band() -> void:
	var said: String = ToolScript.band_verdict(
		Vector4i(0, 200, 0, 0),
		Vector4i(0, 100, 0, 0),
		[Vector4i(100, 0, 0, 42)],
	)
	assert(said.contains("cannot read this"), "it names the gap rather than the disagreement: %s" % said)
	assert(said.contains("KEPT_FEET"), "and says where the ground comes from instead: %s" % said)
	assert(not said.contains("over JNI"), "and it no longer promises a fix that was made without JNI: %s" % said)
	assert(
		not said.contains("report disagree"),
		"and it does not invite a reader to argue with a reading that was never made",
	)


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


## **A build is made again for exactly three reasons, and every one of them reaches the phone.** A script or a
## scene written after it; the export preset written after it - a preset decides what a build *contains*, and
## Android's INTERNET permission took a fresh export before the phone had it (2026-11-10); and a tree nobody can
## walk at all, which is answered by making a build rather than by believing an age.
func test_a_build_is_made_again_only_when_something_that_reaches_the_phone_has_moved() -> void:
	var made: int = 1_700_000_000
	var nothing: Dictionary = { "count": 0, "newest": 0, "path": "", "paths": PackedStringArray(), "readable": true }
	assert(
		ToolScript.rebuild_reason(made, nothing, made - 100, made + 60).is_empty(),
		"a build with nothing newer than it, and a preset older still, is the work in hand",
	)
	var changed: Dictionary = {
		"count": 2,
		"newest": made + 30,
		"path": "res://scripts/hud.gd",
		"paths": PackedStringArray(["res://scripts/hud.gd", "res://scenes/main.tscn"]),
		"readable": true,
	}
	var scripted: String = ToolScript.rebuild_reason(made, changed, made - 100, made + 60)
	assert(scripted.contains("changed since"), "a script written after it makes it stale: %s" % scripted)
	assert(scripted.contains("hud.gd"), "and the file is named rather than counted: %s" % scripted)
	var preset: String = ToolScript.rebuild_reason(made, nothing, made + 10, made + 60)
	assert(preset.contains("export_presets.cfg"), "a preset written after it does too: %s" % preset)
	var unreadable: Dictionary = { "count": 0, "newest": 0, "path": "", "readable": false }
	assert(
		not ToolScript.rebuild_reason(made, unreadable, made - 100, made + 60).is_empty(),
		"and a tree nobody could walk is answered by making a build, not by trusting an age",
	)
	assert(
		not ToolScript.rebuild_reason(0, nothing, 0, made).is_empty(),
		"and a build that is not there at all is the plainest reason there is",
	)


## The three words `--turn` takes, and the fourth answer: **a typo is not a hold.** A word this does not know
## leaves the device alone rather than picking a rotation for somebody's phone.
func test_the_turn_reads_three_words_and_refuses_any_other() -> void:
	assert(ToolScript.turn_of(PackedStringArray(["--turn", "portrait"])) == "portrait", "upright, as asked")
	assert(ToolScript.turn_of(PackedStringArray(["--turn", "landscape"])) == "landscape", "on its side, as asked")
	assert(ToolScript.turn_of(PackedStringArray(["--turn", "auto"])) == "auto", "and the device's own answer")
	for refused: String in ["sideways", "1", "", "Portrait"]:
		assert(
			ToolScript.turn_of(PackedStringArray(["--turn", refused])).is_empty(),
			"`%s` is not a way up this will hold a phone in" % refused,
		)
	assert(ToolScript.turn_of(PackedStringArray([])).is_empty(), "and no flag at all is no turn")


## **What the device reports is the reading; what was written to it is an intention.** A `settings put` Android
## refused looks exactly like one it obeyed until something is read back, so the line carries both readings and
## refuses to call the device held when its own numbers disagree.
func test_a_turn_says_what_the_device_reports_rather_than_what_was_asked() -> void:
	var taken: String = ToolScript.turn_words("landscape", "1", "0")
	assert(taken.contains("lying"), "the device's own answer is a word, not a number: %s" % taken)
	assert(taken.contains("user_rotation=1"), "and the number it reported is in it: %s" % taken)
	var refused: String = ToolScript.turn_words("portrait", "1", "1")
	assert(refused.contains("NOT take the hold"), "a device that did not take it says so: %s" % refused)
	assert(refused.contains("user_rotation=1"), "naming what it reports instead: %s" % refused)
	assert(ToolScript.turn_words("portrait", "0", "0").contains("upright"), "while the upright hold reads as upright")
	assert(
		ToolScript.turn_words("auto", "0", "1").contains("its own answer again"),
		"and going back to the device's own answer is its own sentence",
	)
	assert(
		ToolScript.turn_words("auto", "0", "0").contains("would not go back"),
		"which is refused as plainly when the device keeps it",
	)
	assert(ToolScript.turn_words("", "0", "0").is_empty(), "and no turn asked for says nothing at all")


## The export is asked for with **both paths absolute** - the project with `--path`, the file to write in full - so
## a tool started from another directory builds this project rather than whatever sits beside the shell.
func test_the_export_names_the_project_and_the_file_in_full() -> void:
	var argv: Array[String] = ToolScript.export_argv()
	assert(argv.has("--export-debug"), "the export is the one Godot is asked for: %s" % str(argv))
	assert(argv.has("Android (phone)"), "on the preset this project builds for a phone with")
	var names_the_build: bool = false
	var names_the_project: bool = false
	for argument: String in argv:
		if argument.ends_with("phone-adapt.apk") and not argument.begins_with("res://"):
			names_the_build = true
		if argument == ProjectSettings.globalize_path("res://"):
			names_the_project = true
	assert(names_the_build, "the build's own file is named by its place on this computer: %s" % str(argv))
	assert(names_the_project, "and so is the project, so where a person stood cannot change it")


## **The phone's own numbers, out of the blocks the log holds** - every one of them for the scale, because a phone
## answers differently in each orientation and a rotation publishes a block. That is what lets a scale a file
## states be *judged* rather than shrugged at when the phone has been seen both ways up. A log with nothing in it is
## **no reading**, which is what lets the check say it has nothing to compare a file against instead of comparing
## every file with zero and calling them all wrong.
func test_the_phones_numbers_are_read_from_the_blocks_the_log_holds() -> void:
	# **Every line of a block carries the `PROBE ` prefix** - in `probe.log` as well as in logcat, which
	# `test_hud_probe` holds down - and `blocks_in` reads the blocks by it: a fixture written without the prefix is
	# read as *no block at all*, which is how this test first failed and is worth keeping in front of a reader.
	var lying: String = (
		"PROBE --- what is on the screen ---\n"
		+ "PROBE device   finger=true zooming=true touchscreen=true dpi=450.0 scale=1.62 shape=lying\n"
		+ "PROBE room     viewport=(1444, 666) native=(2340, 1080)"
	)
	var upright: String = (
		"PROBE --- what is on the screen ---\n"
		+ "PROBE device   finger=true zooming=true touchscreen=true dpi=450.0 scale=0.91 shape=standing\n"
		+ "PROBE room     viewport=(1185, 2567) native=(1080, 2340)"
	)
	var said: Dictionary = ToolScript.the_phones_numbers(lying + "\n" + upright)
	assert(is_equal_approx(float(said.get("dpi", 0.0)), 450.0), "the density, off the newest block: %s" % str(said))
	assert(is_equal_approx(float(said.get("scale", 0.0)), 0.91), "and its own scale, this way up: %s" % str(said))
	var scales: Array = said.get("scales", [])
	assert(scales.size() == 2, "**both** orientations' scales, since the log has seen both: %s" % str(said))
	assert(
		is_equal_approx(float(scales[0]), 0.91) and is_equal_approx(float(scales[1]), 1.62),
		"in order, and one of each: %s" % str(said),
	)
	assert(int(said.get("blocks", 0)) == 2, "and how many blocks were read: %s" % str(said))
	# A lone block is a reading still - and a text with no heading in it at all is read as one block rather than
	# refused, which is what the same block looks like with the prefix taken off.
	var lone: Dictionary = ToolScript.the_phones_numbers(lying)
	assert(is_equal_approx(float(lone.get("dpi", 0.0)), 450.0), "one block in the log is a reading: %s" % str(lone))
	assert(int(lone.get("blocks", 0)) == 1, "and it counts as the one block it is")
	var bare: Dictionary = ToolScript.the_phones_numbers(lying.replace("PROBE ", ""))
	assert(is_equal_approx(float(bare.get("dpi", 0.0)), 450.0), "and a bare block with no prefix: %s" % str(bare))
	assert(int(bare.get("blocks", 0)) == 1, "read as the one block it is")
	var absent: Dictionary = ToolScript.the_phones_numbers("")
	assert(float(absent.get("dpi", 0.0)) == 0.0, "no block, no density - and not a zero to compare against")
	assert(float(absent.get("scale", 0.0)) == 0.0, "and no scale either")


## **A stated density is a fault; a stated scale may be the other orientation's**, and one block cannot tell which.
## This is the check that would have caught three fixtures carrying `PHONE_DPI := 384.6` while the phone that is
## actually on the desk says 450.0 - a number a desk cannot disagree with, which is why it needs a device.
func test_a_files_number_is_compared_with_the_phones_own_and_a_stale_one_is_named() -> void:
	var said: Dictionary = { "dpi": 450.0, "scale": 1.62, "scales": [1.62] }
	var stale: Dictionary = ToolScript.stated_numbers_in("sample.gd", "const PHONE_DPI := 384.6", said)
	var stale_ones: Array = stale.get("disagrees", [])
	assert(stale_ones.size() == 1, "a density the phone disagrees with is named: %s" % str(stale))
	assert(String(stale_ones[0]).contains("384.6"), "with the number it states in it: %s" % str(stale_ones[0]))
	assert(String(stale_ones[0]).contains("sample.gd:1"), "and where it is: %s" % str(stale_ones[0]))
	assert(int(stale.get("agreed", 0)) == 0, "and it is not counted among the ones that agree")
	assert(
		int(ToolScript.stated_numbers_in("sample.gd", "const PHONE_DPI := 450.0", said).get("agreed", 0)) == 1,
		"while the phone's own density agrees, and is counted as read",
	)
	# The other name this project's tools use for a density, and a typed `const`: both are read, not left as
	# numbers nobody checks. `hud_layout_check.gd` spells it `PHONE_DENSITY`.
	var other_names: Dictionary = ToolScript.stated_numbers_in(
		"hud_layout_check.gd",
		"const PHONE_DENSITY := 450.0\nconst PHONE_DPI: float = 450.0",
		said,
	)
	assert(int(other_names.get("agreed", 0)) == 2, "both spellings of a density are read: %s" % str(other_names))
	# **The orientation trap.** 0.91 is this phone's portrait scale and 1.62 its landscape one, so a landscape
	# block cannot judge a fixture holding the upright figure: it is named as unjudged, never as a fault, because
	# calling it one would be the false positive this project's doctrine is written against.
	var upright: Dictionary = ToolScript.stated_numbers_in(
		"test_hud_question.gd",
		"const PHONE_SCALE_UPRIGHT := 0.91",
		said,
	)
	var no_faults: Array = upright.get("disagrees", [])
	assert(no_faults.is_empty(), "the other orientation's scale is not called a fault: %s" % str(upright))
	var unjudged: Array = upright.get("not_this_way_up", [])
	assert(unjudged.size() == 1, "it is named as one this block cannot judge: %s" % str(upright))
	assert(
		String(unjudged[0]).contains("cannot say"),
		"and that naming says why rather than guessing: %s" % str(unjudged[0]),
	)
	assert(
		String(unjudged[0]).contains("not this orientation's"),
		"while still saying which way up the block it is about was: %s" % str(unjudged[0]),
	)
	# **A log that has seen the phone both ways up judges both**, and then a scale matching neither is a *fault*
	# rather than a shrug - named with the scales the phone itself states. This is what the instrument is for.
	var both: Dictionary = { "dpi": 450.0, "scale": 1.62, "scales": [0.91, 1.62] }
	assert(
		int(ToolScript.stated_numbers_in("sample.gd", "const PHONE_SCALE_UPRIGHT := 0.91", both).get("agreed", 0)) == 1,
		"the upright scale agrees once the log knows it",
	)
	var nowhere: Dictionary = ToolScript.stated_numbers_in("sample.gd", "const PHONE_SCALE := 0.5", both)
	var faults: Array = nowhere.get("disagrees", [])
	assert(faults.size() == 1, "and a scale this phone has never stated is a fault: %s" % str(nowhere))
	assert(String(faults[0]).contains("0.91"), "naming the scales the phone does state: %s" % str(faults[0]))
	var no_shrug: Array = nowhere.get("not_this_way_up", [])
	assert(no_shrug.is_empty(), "with no shrug left over it: %s" % str(nowhere))
	assert(
		int(ToolScript.stated_numbers_in("sample.gd", "const PHONE_SCALE := 1.62", said).get("agreed", 0)) == 1,
		"while this way up's own scale does agree",
	)
	# **What the check cannot see, said rather than left to be discovered.** A number under another name, or inside
	# a Vector, or a quoted one, is not read at all - so the count of what was looked at is the honest measure of
	# the check, and a run that read nothing proves nothing.
	var nothing: Dictionary = ToolScript.stated_numbers_in(
		"sample.gd",
		(
			"const TABLE_DPI_LIMIT := 384.6\n"
			+ "const HELD_UPRIGHT := Vector2i(1080, 2340)\n" + "const PHONE_LABEL := \"450\""
		),
		said,
	)
	assert(int(nothing.get("agreed", 0)) == 0, "the name decides what is read: %s" % str(nothing))
	var none_found: Array = nothing.get("disagrees", [])
	assert(none_found.is_empty(), "and a number that is not a stated density is not read as one: %s" % str(nothing))
	# **Two constants the first live run called faults before the rule was narrowed, on 2026-11-17.** A density
	# floor is not a device's density and a tablet's is another device's entirely: both are `_DPI` constants this
	# phone disagrees with, and neither is a number *for this phone*. Calling them faults is the false positive the
	# project's doctrine is written against, so the name is the whole basis of the rule and this holds it there.
	var not_for_this_phone: Dictionary = ToolScript.stated_numbers_in(
		"sample.gd",
		"const HELD_DPI := 200.0\nconst TABLET_DPI := 300.0",
		said,
	)
	var no_such_faults: Array = not_for_this_phone.get("disagrees", [])
	assert(no_such_faults.is_empty(), "a floor and a tablet are not this phone's numbers: %s" % str(not_for_this_phone))
	assert(int(not_for_this_phone.get("agreed", 0)) == 0, "and they are not read as this phone's either")


## One line read as a stated number, and the two shapes a name may take - because a fixture may be typed, and a
## comment or a longer expression after the number is not part of it.
func test_a_stated_number_is_read_only_where_one_begins() -> void:
	var plain: Dictionary = ToolScript.a_stated_number("const PHONE_DPI := 384.6")
	assert(String(plain.get("name", "")) == "PHONE_DPI", "the name: %s" % str(plain))
	assert(is_equal_approx(float(plain.get("value", 0.0)), 384.6), "and the number: %s" % str(plain))
	var typed: Dictionary = ToolScript.a_stated_number("const PHONE_DPI: float = 450.0")
	assert(String(typed.get("name", "")) == "PHONE_DPI", "a typed const reads the same: %s" % str(typed))
	assert(is_equal_approx(float(typed.get("value", 0.0)), 450.0), "with its own number: %s" % str(typed))
	assert(
		is_equal_approx(
			float(ToolScript.a_stated_number("const PHONE_DPI := 450.0  # the A16W").get("value", 0.0)),
			450.0,
		),
		"and a comment after the number is not part of it",
	)
	assert(ToolScript.a_stated_number("var PHONE_DPI := 450.0").is_empty(), "a var is not a stated constant")
	assert(ToolScript.a_stated_number("const HELD := Vector2i(1080, 2340)").is_empty(), "a Vector is no number")
	assert(ToolScript.a_stated_number("const PHONE_NAME := \"450\"").is_empty(), "and a quoted one is not either")


## **A tap is a place on the glass, so it is measured against the screen - not against the room.** A block's `tap`
## lines are the screen's own pixels; the `room` line's `viewport=` figure is the logical room a page is laid out
## in, 1.62 times smaller on the A16W. Measuring one against the other called a press that had plainly landed a
## miss: measured 2026-11-17, `--press "Design the garden"` sent (1213, 753) into a 2340 x 1080 screen and the tool
## said it was "outside the room ... (1444, 666)". That is the fault this test holds down.
##
## The device turns under the program, and the question the check exists for is unchanged: a centre sent from a
## portrait block to a landscape screen reaches nothing at all - measured, a centre at y 1654 on a 1080-tall
## screen - and the only thing that said so was a person wondering at the run afterwards.
func test_a_tap_is_measured_against_the_screen_and_not_the_room() -> void:
	var screen := Vector2i(2340, 1080)
	var landed: String = ToolScript.tap_words(Vector2i(700, 300), screen)
	assert(landed.contains("inside"), "a tap on the screen is on it: %s" % landed)
	# The press that was wrongly called a miss: a real centre out of a real block, in the screen's own pixels.
	var pressed: String = ToolScript.tap_words(Vector2i(1213, 753), screen)
	assert(pressed.contains("inside"), "a centre the block published is on that screen: %s" % pressed)
	# And the tap this check is for: a centre from a block taken the other way up, past the far edge.
	var adrift: String = ToolScript.tap_words(Vector2i(540, 1654), screen)
	assert(adrift.contains("outside"), "a tap past the foot of the screen is outside it: %s" % adrift)
	assert(adrift.contains("(2340, 1080)"), "and the screen it was measured against is named: %s" % adrift)
	# No screen is no reading of the tap either, rather than a tap inside a screen of no size that would clear it.
	assert(
		ToolScript.tap_words(Vector2i(540, 552), Vector2i.ZERO).contains("names no screen"),
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
		"a hold that says landscape is not upright - which is the right ask for a device turned landscape, and the "
		+ "wrong one for a device turned portrait",
	)
	assert(
		ToolScript.hold_words("{orientation:portrait}").contains("not readable JSON"),
		"and the file the device was actually found holding is named as unreadable rather than read as portrait",
	)
	assert(
		ToolScript.hold_words("").contains("no orientation.json"),
		"an absent hold names the file that is missing rather than reading as a default",
	)


func test_the_board_s_hold_follows_the_turn_so_a_lying_device_gets_a_lying_board() -> void:
	assert(
		ToolScript.hold_for("portrait") == ToolScript.UPRIGHT_HOLD,
		"a device turned upright is given the upright hold",
	)
	assert(
		ToolScript.hold_for("landscape") == ToolScript.LYING_HOLD,
		"a device turned landscape is given the lying hold, or every page is laid out for the wrong shape",
	)
	assert(
		ToolScript.hold_for("") == ToolScript.UPRIGHT_HOLD,
		"and a run that asked for no turn keeps the upright default, so the every-day capture is unchanged",
	)
	assert(
		ToolScript.hold_for("auto") == ToolScript.UPRIGHT_HOLD,
		"a turn by the device's own accelerometer is not the landscape word, so it takes the upright hold",
	)


func test_whether_the_board_took_its_hold_is_asked_of_the_text_it_was_given() -> void:
	assert(
		ToolScript.hold_took(ToolScript.hold_words(ToolScript.LYING_HOLD), ToolScript.LYING_HOLD),
		"a board holding the lying hold has taken it",
	)
	assert(
		not ToolScript.hold_took(ToolScript.hold_words(ToolScript.UPRIGHT_HOLD), ToolScript.LYING_HOLD),
		"and a board still upright under a lying ask has not - the answer is always about the ask",
	)
	assert(
		not ToolScript.hold_took(ToolScript.hold_words("{orientation:portrait}"), ToolScript.UPRIGHT_HOLD),
		"an unreadable hold is never the text this tool wrote, however the file is worded",
	)
	assert(not ToolScript.hold_took(ToolScript.hold_words(""), ToolScript.UPRIGHT_HOLD), "and neither is an absent one")


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

	# **Every changed file is named, not only the newest one**, so that "3 files have changed" can be judged and
	# not only counted: the paths come back newest first, and there are as many of them as the count says.
	var named: PackedStringArray = all_time["paths"]
	assert(
		named.size() == int(all_time["count"]),
		"the paths and the count are the same walk: %d against %d" % [named.size(), int(all_time["count"])],
	)
	assert(
		named[0] == String(all_time["path"]),
		"and the first is the newest, the one the sentence used to name alone: %s" % named[0],
	)

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
	# **The singular is a reading a person can be shown**, because this words a block's age as well as a build's
	# and a block is published the moment a screen changes. Both of these were found by running the tool: the
	# build line said "1 hours old" on 2026-11-17, and a block a second old would have read "1 seconds ago".
	assert(ToolScript.age_words(1) == "1 second", "one second is not one seconds")
	assert(ToolScript.age_words(100) == "1 minute", "a minute and a bit reads as one minute")
	assert(ToolScript.age_words(5400) == "1 hour", "and an hour and a half reads as one hour, where it read 1 hours")


## **Every changed file is named, not only the newest**, because a count says a build may be stale and the names
## say whether it matters. Measured 2026-11-17: a build 66 minutes old had three changed files that were a comment
## correction and the moved demo scenes, so it *was* the work in hand in everything but its comments - a judgement
## the count alone could not support.
func test_a_stale_build_names_the_files_that_changed_and_counts_the_rest() -> void:
	var newest_first: PackedStringArray = PackedStringArray(
		["res://tools/e.gd", "res://tools/d.gd", "res://tools/c.gd", "res://tools/b.gd", "res://tools/a.gd"]
	)
	var several: String = ToolScript.build_words(
		1_000_000,
		{ "count": 5, "path": "res://tools/e.gd", "paths": newest_first, "readable": true },
		1_000_600,
	)
	assert(several.contains("5 script"), "the count is still the whole of it: %s" % several)
	assert(several.contains("res://tools/e.gd"), "and the newest is named: %s" % several)
	assert(several.contains("and 2 more"), "with the rest counted rather than listed: %s" % several)
	assert(not several.contains("res://tools/b.gd"), "so a file past the third is not listed: %s" % several)


## **A block cannot say how old it is**, and a reader who does not know the age cannot tell whether the geometry a
## block publishes is about the screen in front of them. The age comes from the device's own stamp, so no log and no
## stamp both answer *nothing* rather than "0 seconds" - which would read as the freshest possible reading.
func test_the_age_of_a_block_comes_from_the_device_and_is_nothing_when_it_cannot() -> void:
	var tool: Node = ToolScript.new()
	assert(tool._age_of_the_newest_block("") == "", "no log, no age")
	assert(
		tool._age_of_the_newest_block("PROBE --- what is on the screen ---\n") == "",
		"a block with no stamp on it has no age, rather than an age of nothing",
	)
	tool.free()


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


## **The screen a tap is measured against is the newest block's, not the log's first.** A log holds every block
## since it was cleared, and the block a launch publishes is not always about the screen in front of a person:
## measured on the A16W on 2026-11-17, a phone lying on the desk published an **upright** block first
## (`scale=0.91 shape=standing`, `native=(1080, 2340)`) and a lying one after it, because the program's window is
## portrait for its first moment and re-lays out. Measuring a lying block's centre - (1163, 299), inside the
## 2340 x 1080 screen that published it - against the log's own first screen called a press that had plainly
## landed a miss: `--press "2D plan"` moved the button's own label and the run still said "outside the screen".
## The reader is right; the block it is handed is the whole log rather than the newest block.
func test_a_tap_is_measured_against_the_newest_blocks_screen_not_the_logs_first() -> void:
	# A block begins at the probe's own heading, and the blank lines adb leaves between them are not the separator:
	# this is the shape `probe.log` really has, taken from the writer's own constant rather than retyped.
	var head: String = "PROBE %s\n" % ToolScript.BLOCK_HEAD
	var log := (
		head + "PROBE room     viewport=(1185, 2567) native=(1080, 2340)\n"
		+ head + "PROBE room     viewport=(1444, 666) native=(2340, 1080)"
	)
	var newest: String = "\n".join(ToolScript.newest_block(log))
	var screen: Vector2i = HudProbeScript.read_screen_line(newest)
	assert(screen == Vector2i(2340, 1080), "the newest block's own screen: %s" % str(screen))
	assert(
		ToolScript.tap_words(Vector2i(1163, 299), screen).begins_with("the tap at (1163, 299) is inside"),
		"so a centre that landed is read as one: %s" % ToolScript.tap_words(Vector2i(1163, 299), screen),
	)
	assert(
		ToolScript
		.tap_words(Vector2i(1163, 299), HudProbeScript.read_screen_line(log))
		.begins_with("the tap at (1163, 299) is outside"),
		"where the log's first block is the one that cries wolf - which is why the call site is handed the newest",
	)


## A `--keep` name is a person's own words, and the file it becomes is made of letters, digits and underscores, ends
## `.png`, and stays inside the capture directory whatever was typed - a name is a person's, and a path is not
## somewhere a name should be able to point a tool that writes files.
func test_a_kept_picture_name_is_a_name_and_never_a_path() -> void:
	assert(
		ToolScript.kept_picture_name("Widened Bar") == "widened_bar.png",
		ToolScript.kept_picture_name("Widened Bar"),
	)
	assert(
		ToolScript.kept_picture_name("  after-build  ") == "after_build.png",
		"spaces and dashes are the one separator a name is written with",
	)
	assert(
		ToolScript.kept_picture_name("../../etc/passwd") == "etcpasswd.png",
		"a path typed as a name stays a name: %s" % ToolScript.kept_picture_name("../../etc/passwd"),
	)
	assert(ToolScript.kept_picture_name("...") == "kept.png", "and a name with nothing in it becomes the plain one")


## A phone that leaves the link mid-run is named in terms of what the run had already done: after an export there is
## nothing to export again, and before one there is nothing to install - the same command is the answer.
func test_a_phone_that_left_the_link_is_told_what_to_do_next() -> void:
	var after: String = ToolScript.the_device_left_words(true)
	assert(after.contains("--install --launch"), "a build already made is not one to make again: %s" % after)
	assert(after.contains("nothing left to export"), "and that is the whole of it: %s" % after)
	var before: String = ToolScript.the_device_left_words(false)
	assert(not before.contains("--install"), "with no build made there is nothing to install: %s" % before)
	assert(before.contains("again"), "so the same command again is the answer: %s" % before)


## A capture's three pictures carry the same names every time, so a second capture wrote over the first one's
## evidence - a gap that was only documented until this ran. Given a `--keep` name they are prefixed by it, and
## with none they keep the names a person goes looking for.
func test_a_capture_picture_is_prefixed_by_a_kept_name_or_keeps_its_own() -> void:
	assert(
		ToolScript.capture_picture_name("", "board_upright.png") == "board_upright.png",
		"with no name asked for, the picture keeps its own",
	)
	assert(
		ToolScript.capture_picture_name("Widened Bar", "board_upright.png") == "widened_bar_board_upright.png",
		ToolScript.capture_picture_name("Widened Bar", "board_upright.png"),
	)
	assert(
		ToolScript.capture_picture_name("../../etc", "a_line_drawn.png") == "etc_a_line_drawn.png",
		"and a path typed as a name is still only a name",
	)
