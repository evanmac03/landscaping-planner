extends Node
## The way in to this project's debugging, for a person and for an agent: one run says what the machine
## is, what the autoloads really are, and every instrument this project already has with the question each
## one answers.
##
##     run_scene res://tools/debug_toolbox.tscn
##
## **It reads, it names, and it drives the two checks that can be run in this process; it decides
## nothing.** The checks this project owns are good and there are many of them, so the fault this file
## exists to cure is not a missing check - it is that the instruments in the table below have to
## be known before any one of them can be reached. `tests/test_debug_toolbox.gd` holds every line of that
## table to naming a file that is really there, because an index with a dead line in it sends a person
## somewhere that is not there and is worse than no index at all.
##
## **And the walk's scope is named here, because a verdict with an unstated scope is not a reading.** The
## audit's "every scene loads" check leaves the third-party trees alone - the editor's cache, and the packages
## installed here or vendored rather than written here - and the count it prints cannot be weighed without them.
## That list is the audit's own `SKIP_DIRS`, published by the walk below and summarized here; this file keeps no
## copy of it, so the two cannot disagree.
##
## **Every figure comes from the module that owns it** - `PhoneHud` states the row a finger needs, the
## engine states its own version and its own settings, and whether there is a screen to measure on at all
## is `HudProbe`'s question, asked of it here rather than asked again: `tests/test_screen_doctrine.gd`
## holds that exactly one file in these two trees asks it. Where a reading needs a screen this says so
## rather than printing a zero - a floor counted in pixels needs a screen to count it on, and the monitors
## a headless run reports are not this program's cost. `tools/mem_report.gd` is the instrument that
## measures that properly, with the real `main.tscn` up, and this file names it rather than repeating it.
##
## Not part of the game. The export excludes `tools/*`, so nothing here ships.

## Where Godot keeps an autoload's setting name: one setting per autoload, `autoload/<Name>`. There is no
## single `autoload` setting, which is the trap `autoload_names` below is written around.
const AUTOLOAD_PREFIX := "autoload/"

## The row a thumb needs, and whether a finger is what presses the controls, are `PhoneHud`'s to state: it
## owns the number this program itself draws at, and a second copy of it here could disagree with that one.
const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const AuditScript := preload("res://tools/audit.gd")
const TreeSitterAuditScript := preload("res://tools/tree_sitter_audit.gd")
const HudProbeScript := preload("res://scripts/hud_probe.gd")

## The instruments this project already has, in the order a person meets them: the name it is run by, the
## question it answers, and the scene that answers it. Held down by `tests/test_debug_toolbox.gd`.
const INSTRUMENTS: Array[Dictionary] = [
	{
		"name": "run_tests",
		"question": "does everything this project promises still hold",
		"scene": "res://tools/run_tests.tscn",
	},
	{
		"name": "audit",
		"question": "one pass: the plant check, the HUD layout, the page layout, every scene of this project's own loading",
		"scene": "res://tools/audit.tscn",
	},
	{
		"name": "tree_sitter_audit",
		"question": "is every declaration, return type and parameter typed",
		"scene": "res://tools/tree_sitter_audit.tscn",
	},
	{
		"name": "mem_report",
		"question": "what the program costs, stage by stage, with the real main.tscn up",
		"scene": "res://tools/mem_report.tscn",
	},
	{
		"name": "console",
		"question": "what the running program thinks: :where, :pages, :probe, :mode, :doc",
		"scene": "res://tools/console.tscn",
	},
	{
		"name": "vocabulary",
		"question": "what this program itself calls things: its pages, its menus, its tools, its keys and its layers",
		"scene": "res://tools/vocabulary.tscn",
	},
	{
		"name": "gui_sweep",
		"question": "every page holding prose or a list: its cut boxes and its wrong words",
		"scene": "res://tools/gui_sweep.tscn",
	},
	{
		"name": "hud_layout_check",
		"question": "the same two faults, for whatever is on the screen now",
		"scene": "res://tools/hud_layout_check.tscn",
	},
	{
		"name": "gui_captions",
		"question": "what moved on the screen around one action, and what held still",
		"scene": "res://tools/gui_captions.tscn",
	},
	{
		"name": "gui_stillness",
		"question": "the screen compared with itself over time",
		"scene": "res://tools/gui_stillness.tscn",
	},
	{
		"name": "gui_overlap_show",
		"question": "the picture that shows one surface drawn over another",
		"scene": "res://tools/gui_overlap_show.tscn",
	},
	{
		"name": "screen_shot",
		"question": "a picture of the screen as it is now, with the moment named - one region of any picture twice as big, or what moved between two pictures and when each was taken",
		"scene": "res://tools/screen_shot.tscn",
	},
	{
		"name": "page_chrome_probe",
		"question": "a page's own strip, and a colour walk down the screen",
		"scene": "res://tools/page_chrome_probe.tscn",
	},
	{
		"name": "phone_screen",
		"question": "the program laid out in the A16W's own room on this desk, with a picture of it and the device's own block",
		"scene": "res://tools/phone_screen.tscn",
	},
	{
		"name": "phone_touch_sweep",
		"question": "a finger's questions asked of every page, at the A16W's own numbers",
		"scene": "res://tools/phone_touch_sweep.tscn",
	},
	{
		"name": "phone_touch_pass",
		"question": "the newest probe block, pulled off the phone, in that order",
		"scene": "res://tools/phone_touch_pass.tscn",
	},
	{
		"name": "touch_hud_workspace",
		"question": "the phone's HUD standing still - the bar's four words, the dock's five tabs and the sheet - for looking at and pushing about in the editor rather than reading out of a block",
		"scene": "res://tools/touch_hud_workspace.tscn",
	},
	{
		"name": "plant_scene_check",
		"question": "one species of every category planted in the real main.tscn",
		"scene": "res://tools/plant_scene_check.tscn",
	},
	{
		"name": "help_shot",
		"question": "the picture one of the manual's subjects shows",
		"scene": "res://tools/help_shot.tscn",
	},
]


func _ready() -> void:
	print("################ DEBUG TOOLBOX ################")
	print("")
	_say_the_machine()
	_say_the_autoloads()
	await _run_the_checks()
	_say_the_instruments()
	print("")
	print("################ END DEBUG TOOLBOX ################")
	get_tree().quit()


## Engine, renderer, physics and the screen: the facts that decide most "it behaves differently on my
## machine" questions, and the ones a run with no screen genuinely cannot have.
func _say_the_machine() -> void:
	print("MACHINE")
	var version: Dictionary = Engine.get_version_info()
	print("  engine        ", version["string"])
	print("  project       ", ProjectSettings.get_setting("application/config/name", "(unnamed)"))
	print("  renderer      ", ProjectSettings.get_setting("rendering/renderer/rendering_method", "(unstated)"))
	print("  physics       ", ProjectSettings.get_setting("physics/2d/physics_engine", "(unstated)"))
	print("  system        ", OS.get_name())
	print("  editor build  ", OS.has_feature("editor"), "     debug build  ", OS.is_debug_build())
	# Whether there is a screen at all is **not this file's question**: `HudProbe` owns it, and
	# `tests/test_screen_doctrine.gd` holds that exactly one file in these two trees asks it.
	var real_screen: bool = HudProbeScript._a_real_screen()
	print("  a real screen ", real_screen)
	if not real_screen:
		print("  screen        not stated: a run with no screen has no size, no density, and no")
		print("                row a thumb needs. The instruments below want a window.")
		return
	var screen: Vector2i = DisplayServer.screen_get_size()
	print("  screen        ", screen.x, " x ", screen.y, "  at ", DisplayServer.screen_get_dpi(), " dpi")
	print("  answered by a thumb ", PhoneHudScript.on_a_finger_here())
	var scale: float = PhoneHudScript.canvas_scale(get_window())
	var density: float = PhoneHudScript.dpi()
	print(
		"  row a thumb needs %.1f px   (canvas scale %.2f, density %.0f)"
		% [PhoneHudScript.row_height(scale, density), scale, density]
	)


## The autoloads Godot really has, so that "why is there a second autoload" is a reading and not an
## argument. What this project's rule about them is belongs to AGENTS.md and is held down by a test.
func _say_the_autoloads() -> void:
	print("")
	print("AUTOLOADS")
	var names: Array[String] = autoload_names()
	print("  count         ", names.size())
	for autoload_name: String in names:
		var path := str(ProjectSettings.get_setting(AUTOLOAD_PREFIX + autoload_name, "")).trim_prefix("*")
		print("  ", autoload_name, "  ->  ", path, "   loads: ", ResourceLoader.exists(path))


## The checks that can be run in this process, run. Each prints its own detail in its own words and hands
## back its verdict, so this file owns the running order and nothing else.
##
## **The suite is deliberately not here, and not because it is hard.** It has to run in a process of its
## own twice over: its rule is a fresh instance per test with its own log capture, which is what makes it
## the arbiter, and it must carry `GODOT_MCP_RUNTIME=0` or it binds this project's runtime port and takes
## it from a live session - neither of which a child started from inside this one can be given. It is
## named in the table below, which is the honest place for it.
func _run_the_checks() -> void:
	print("")
	print("CHECKS, DRIVEN NOW")
	var typing: Node = TreeSitterAuditScript.new()
	var found: Dictionary = typing.scan()
	typing.free()
	var faults: int = TreeSitterAuditScript.faults(found)
	if faults == 0:
		print("  typing        nothing to answer: every file read in full, every declaration typed,")
		print("                the parameters within the allowance")
	else:
		print("  typing        %d fault(s), named in the table above" % faults)
	var rows: Array[Dictionary] = await AuditScript.run(self)
	var passed: int = 0
	for row: Dictionary in rows:
		if bool(row["ok"]):
			passed += 1
	print("  audit         %d of %d checks passed" % [passed, rows.size()])
	print(
		"  walk          the scene walk leaves %d tree(s) alone - the editor's cache and the packages"
		% AuditScript.SKIP_DIRS.size()
	)
	print("                installed here or vendored rather than written here, named by the audit above")
	print("  the suite     not in this process: res://tools/run_tests.tscn  (see the note on this function)")


## What this project already has to look at a fault with, one line each, and the command that runs it.
func _say_the_instruments() -> void:
	print("")
	print("INSTRUMENTS   (open the scene and press F6, or run the command under its name)")
	for row: Dictionary in INSTRUMENTS:
		print("  ", row["name"])
		print("      ", row["question"])
		print("      ", row["scene"])


## Every autoload this project really has, in alphabetical order, read where Godot keeps them.
##
## **This is the reading that a reader can get wrong and never be told.** Asking for a setting named
## `autoload` and iterating it as a dictionary finds an empty dictionary on every project there has ever
## been - Godot writes one setting per autoload instead - so a report built that way says "every autoload
## is registered" for a project with four broken ones, and says it silently. `tests/test_debug_toolbox.gd`
## asserts this reading against the settings themselves.
static func autoload_names() -> Array[String]:
	var names: Array[String] = []
	for property: Dictionary in ProjectSettings.get_property_list():
		var setting_name := String(property["name"])
		if setting_name.begins_with(AUTOLOAD_PREFIX):
			names.append(setting_name.substr(AUTOLOAD_PREFIX.length()))
	names.sort()
	return names
