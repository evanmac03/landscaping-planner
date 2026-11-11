extends Node
## A development session with the console in it: this program, with CrabbyConsole over the top of it.
##
## A development tool rather than part of the program, and deliberately **not** an autoload. CrabbyConsole's
## installer ticks its editor plugin, and that plugin adds an autoload of its own - and this project has none:
## whatever a script needs is handed to it by the scene, and a thing that installs itself into every launch is
## the opposite of that. It costs more than a principle here, too: the console is a GDExtension whose `bin/`
## carries a library for a desk and **none for Android**, so as an autoload it logged, on every launch on the
## phone, "Error loading extension" and "Node CrabbyConsole of type CrabConsole cannot be created. A
## placeholder will be created instead." Measured on the SM-A166W, 2026-11-10 - the app still ran, and the
## errors were still there.
##
## Run this scene instead. The console is then present exactly when a person asks for it, the shipped APK
## carries none of it, and `tools/` never reaches an export in the first place.
##
##     run `res://tools/console.tscn` - the console opens over the program by itself
##     `:help` lists the commands; anything not starting with `:` is run as GDScript
##     `~` toggles it; to open it with another key, add a project input action `crabbyconsole_toggle`
##
## Nothing here reaches inside the addon, which is the rule for `addons/`: it is loaded as a scene by path and
## its own classes are never named. What it needs from the program is nothing at all, which is why this can
## be a scene rather than a change to the program.
##
## ## Asking the program where things are
##
##     :where <path>    the on-screen rectangle of a control, in the screen pixels a person or `input tap` wants
##     :where <page>    a page answers for itself: the probe's own report for it, its controls and their centres
##     :pages           every page the project has; the ones that are up, where they stand, and whether they fit
##     :probe           say what is on the screen, in the very words a phone's PROBE block prints
##     :mode            the view, the tool in hand, the layer, and the status line
##     :doc             the drawing: how many entities, which layers, the file, and whether it is unsaved
##
## Paths are read from the **game's own root** (`App`), which is the way this project already writes them
## (`Hud/Root/TopBar/...`); an absolute path (`/root/App/Hud`) works too. Every figure comes from
## a module that already answers that question for the program itself - `scripts/hud_probe.gd` for what is
## on the screen, `scripts/page_index.gd` for which scripts are pages, `scripts/page_layout.gd` for how a
## page's contents stand against the room they have, and the drawing's own controller for its own state. This tool words
## nothing and works nothing out a second time. It is the desk-side companion to the `PROBE` block the same
## module prints on a phone, and it answers in one line the question that otherwise costs a screenshot and a
## scan: where is that control, and what is that page's real rectangle?

## Where the program lives, and where the console lives. Both by path, both loaded here and nowhere else.
const APP := "res://scenes/main.tscn"
const CONSOLE := "res://addons/crabbyconsole/scenes/autoload/console.tscn"

## The program already reports what is on its own screen; the console is only a place to ask it to.
const HudProbeScript := preload("res://scripts/hud_probe.gd")

## Which scripts are pages, and how a page's contents stand against the room they are given. Both are the
## project's own single sources for those two questions, and neither answer is worked out a second time here.
const PageIndexScript := preload("res://scripts/page_index.gd")
const PageLayoutScript := preload("res://scripts/page_layout.gd")

## The commands this tool teaches the console.
##
## One table rather than five separate calls, so that a command is registered, described and reported in one
## place: a sixth verb is a sixth entry here and nothing else. The name and the method are `StringName`s
## because that is how the console takes them, and each method is reached by name rather than by anything
## the addon owns.
const COMMANDS: Array[Dictionary] = [
	{"name": &"where", "method": &"_where",
		"help": "where <path> - the on-screen rectangle of a control, or a page's whole report"},
	{"name": &"pages", "method": &"_pages",
		"help": "pages - every page the project has; the ones that are up, where they stand, and whether they fit"},
	{"name": &"probe", "method": &"_probe",
		"help": "probe - say what is on the screen, in the very words a phone's PROBE block prints"},
	{"name": &"mode", "method": &"_mode",
		"help": "mode - the view, the tool in hand, the layer, and the status line"},
	{"name": &"doc", "method": &"_doc",
		"help": "doc - the drawing: how many entities, which layers, the file, and whether it is unsaved"},
]

## The game's root, once `_ready` has put it up. `where` reads its paths from here.
var _app: Node = null


func _ready() -> void:
	# The program first, so the console's layers land over a board that is already up. The console draws at
	# CanvasLayer 1023 and its node picker at 4095, above everything the program itself puts on the screen.
	var app: Node = load(APP).instantiate()
	app.name = "App"
	add_child(app)
	var crabby: Node = load(CONSOLE).instantiate()
	crabby.name = "CrabbyConsole"
	add_child(crabby)
	_app = app
	# The console refuses a command until its machinery has settled, and that is LATER than its own `_ready`.
	# Measured 2026-11-11: `add_custom_command` answered "cannot be used before CrabbyConsole._ready() -
	# please wait one frame and try again" even though `is_node_ready()` was already true. The reason is this
	# tool's own shape: it adds the console during its own `_ready`, so by the time anything can check, the
	# console has entered the tree and reports itself ready - and still refuses.
	#
	# So the frames come first and unconditionally, and the readiness wait only guards the rest. Bounded,
	# because a wait with no end in it is a hang, and the count is generous because being late costs a frame
	# where being early costs a refused registration and an error line in the log.
	await get_tree().process_frame
	await get_tree().process_frame
	var waited: int = 0
	while not crabby.is_node_ready() and waited < 60:
		waited += 1
		await get_tree().process_frame
	_take_the_commands(crabby)
	# Open the console here rather than leave it to the `~` key. That toggle lives inside the extension's
	# own library and watches a PHYSICAL key, which a keyboard without a backtick - or anything driving the
	# game that is not a person's hands - may never produce; and this tool is what put the console there, so
	# it may as well ask for it. Measured 2026-11-11: the console's layer is down before this and up after.
	await get_tree().process_frame
	if crabby.has_signal(&"console_toggle_requested"):
		crabby.emit_signal(&"console_toggle_requested")
		print("CONSOLE: the program is up, with the console open over it - `~` toggles it")
	else:
		print("CONSOLE: the program is up, but this console has no toggle signal to open it with")


## Ask the console to take this tool's commands, and say when it will not.
##
## Reached with `call()` rather than by naming the addon's class: this file may not reach inside `addons/`, and
## a call by name is the whole of what it needs from the console. A console with no such method answers
## `null`, which is not an error code and must never be read as one - so it is asked about separately.
func _take_the_commands(the_console: Node) -> void:
	for command: Dictionary in COMMANDS:
		# Named `verb`, not `name`: this script extends Node, and a local called `name` shadows the
		# property every Node already has, which the engine reports as an error on every run.
		var verb: StringName = command["name"]
		var answer: Variant = the_console.call(
			&"add_custom_command",
			verb,
			Callable(self, StringName(command["method"])),
			String(command["help"]),
		)
		if answer == null:
			print("CONSOLE: this console took no :%s command - is add_custom_command not its door?" % verb)
			continue
		print("CONSOLE: :%s registered (%s)" % [
			verb, "OK" if int(answer) == OK else "error %d" % int(answer)])


## `:where <path>` - where a control is on the screen, in the pixels a person or `input tap` wants.
##
## The figure is the probe's and never worked out here: `HudProbe` owns this arithmetic and composes it
## through `Viewport.get_screen_transform()`. This method decides only which of the probe's readers answers -
## a page answers for itself with its whole report, a control with its rectangle - and says what it was told.
##
## The three parameters are joined because how the console hands a command's arguments over is written down
## nowhere in what it ships: one string, the whole line, and one parameter per word all arrive as something
## this can read, and a node path has no spaces to lose between them.
func _where(first: String = "", second: String = "", third: String = "") -> String:
	var wanted: String = ("%s %s %s" % [first, second, third]).strip_edges()
	if wanted.is_empty():
		return "which control? for example: where Hud/Root/TopBar/Row/GroundButton"
	var node: Node = null
	if _app != null:
		node = _app.get_node_or_null(NodePath(wanted))
	if node == null:
		node = get_node_or_null(NodePath(wanted))
	if node == null:
		return "nothing at '%s' - a path is read from the game's own root, the way this project writes them (Hud/Root/...), or given absolutely (/root/...)" % wanted
	var said: String = ""
	if node is Window:
		# A page knows best: the probe's report for it carries its rectangle, its controls, their centres.
		said = HudProbeScript.line_for_printing(
			HudProbeScript.LINE_BREAK.join(HudProbeScript.page_lines(node as Window))
		)
	elif node is Control:
		var rect: Rect2 = HudProbeScript.screen_rect(node as Control)
		said = "%s  screen (%.0f, %.0f) .. (%.0f, %.0f)  %.0f x %.0f px" % [
			wanted, rect.position.x, rect.position.y, rect.end.x, rect.end.y, rect.size.x, rect.size.y,
		]
	else:
		return "'%s' is a %s, which has no rectangle on the screen" % [wanted, node.get_class()]
	print(said)
	return said


## A node of the running program, found by name under its own root: the console is looking at the program,
## and this is the one way it gets there.
func _somewhere(node_name: String) -> Node:
	if _app == null or not is_instance_valid(_app):
		return null
	return _app.find_child(node_name, true, false)


## `:pages` - every page the project has, and for each one that is up, where it stands and whether what is
## inside it fits the room it was given.
##
## Which scripts are pages is `PageIndex`'s answer, read rather than written down, so a page added tomorrow
## is here tomorrow. Which of them are **up** is the running tree's answer, and it is filtered through that
## list rather than being every `Window` in the program: a `PopupMenu` is a `Window` too, and a menu is not a
## page. The rectangle on each line is the probe's own line for the page - the same text a phone prints - and
## whether the contents fit is `PageLayout`'s figures and `PageLayout`'s own verdict words.
##
## This answers for the pages that are **on the screen now**, which is the question a console can settle in
## the frame it is typed in. Measuring a page that is not up needs the page built, shown and given two frames
## to settle, which is `tools/page_layout_check.gd`'s job and not a command's: that tool reports the whole
## thirty-page table on the desk, and this reports the handful a person is actually looking at.
func _pages(_first: String = "", _second: String = "", _third: String = "") -> String:
	if _app == null or not is_instance_valid(_app):
		return "there is no program to look at - run this scene, which puts it up"
	var known: Array[String] = PageIndexScript.scripts()
	var up := PackedStringArray()
	var pages_up: int = 0
	for node: Node in _app.find_children("*", "Window", true, false):
		var page: Window = node as Window
		if page == null or not page.visible:
			continue
		var script: Script = page.get_script() as Script
		if script == null or not known.has(script.resource_path):
			continue
		pages_up += 1
		var probe: PackedStringArray = HudProbeScript.page_lines(page)
		if probe.size() > 0:
			up.append(probe[0])
		up.append("         %s" % _how_the_contents_stand(page))
	if up.is_empty():
		return "no page is up right now; the project has %d page(s)" % known.size()
	var lines := PackedStringArray([
		"%d of the project's %d page(s) are up:" % [pages_up, known.size()]])
	lines.append_array(up)
	return "\n".join(lines)


## Whether a page's contents fit the room it is showing in, in `PageLayout`'s own figures and words.
##
## Every number is PageLayout's - what the contents want is the same sum `measure` makes (`wanted_contents`
## plus the padding, read off the `ScrollContainer` when there is one) - and the verdict words are its own
## `FITS`, `SCROLLS` and `UNKNOWN`. The room is the page's **actual** rectangle rather than the size it
## declares, because the question asked of a page that is up is whether what is inside it is showing.
##
## The order of the test is said again in these few lines for one reason: `PageLayout.measure` shows a page
## and waits two frames for the containers to settle, and a console command has to answer in the frame it is
## typed in. A page that is already up has already settled, so the same sum can be made at once - and the
## words are PageLayout's, not a second set, so the two cannot describe a page differently.
func _how_the_contents_stand(page: Window) -> String:
	var root: Control = PageLayoutScript.content_root(page)
	if root == null:
		return "%s: this page has no contents to measure" % PageLayoutScript.UNKNOWN
	var scrolling: ScrollContainer = PageLayoutScript.scroll_of(root)
	var scrolls: bool = scrolling != null \
		and scrolling.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
	var wanted: Vector2 = PageLayoutScript.wanted_contents(root) \
		+ PageLayoutScript.padding_of(root, scrolling)
	var room: Vector2 = page.size
	var across: bool = wanted.x <= room.x
	var down: bool = wanted.y <= room.y
	var verdict: String = PageLayoutScript.UNKNOWN
	if across and down:
		verdict = PageLayoutScript.FITS
	elif across and scrolls:
		verdict = PageLayoutScript.SCROLLS
	return "contents want %.0f x %.0f in the %.0f x %.0f it has  ->  %s" % [
		wanted.x, wanted.y, room.x, room.y, verdict]


## `:probe` - say what is on the screen, in the words a phone prints.
##
## The block is the `Hud`'s own composition and is not written again here: this calls the very method that
## says it whenever a page lands, so the desk report and the phone report are the same text by construction
## and cannot drift apart. That method waits a couple of frames first, because a control's rectangle is only
## true once the containers have settled - so the block follows this answer by a frame or two, rather than
## being printed inside it.
func _probe(_first: String = "", _second: String = "", _third: String = "") -> String:
	var hud: Node = _somewhere("Hud")
	if hud == null:
		return "there is no board to report on - run this scene, which puts the program up"
	hud.call(&"_the_screen_said")
	return "the screen's own report follows above, a line at a time, in the same words a phone prints (PROBE ...)"


## `:mode` - the view, the tool in hand, the layer under it, and the line the drawing is showing.
##
## Each figure is the thing that owns it: the view's mode is the view's own enum, the tool's name is the
## tool's own label, the layer's purpose is the document's own words for it, and the status line is the
## controller's own. Nothing here looks at the screen, because `:probe` already reports what the screen says.
func _mode(_first: String = "", _second: String = "", _third: String = "") -> String:
	var view: Node = _somewhere("ViewController")
	var draft: Node = _somewhere("DraftController")
	if view == null and draft == null:
		return "there is no drawing to ask about - run this scene, which puts the program up"
	var lines := PackedStringArray()
	if view != null:
		lines.append("view    %s" % ViewController.ViewMode.keys()[int(view.get(&"mode"))])
	if draft != null:
		lines.append("tool    %s%s" % [
			DraftTool.label_for(int(draft.call(&"current_tool"))),
			"" if bool(draft.get(&"drawing")) else "   (the drawing tools are not armed)"])
		lines.append("layer   %s" % _the_layer_in_hand(draft))
		lines.append("status  %s" % String(draft.call(&"status")))
	return "\n".join(lines)


## The layer in hand in the document's own words: the code it is called by, and the purpose the document
## gives it. Both halves are needed - "300-NEW-HARD" is a code, and the purpose is what a person chose.
func _the_layer_in_hand(draft: Node) -> String:
	var layer: StringName = StringName(draft.call(&"current_layer"))
	for choice: Dictionary in draft.call(&"layer_choices"):
		if StringName(choice["name"]) == layer:
			return "%s - %s" % [layer, choice["purpose"]]
	return String(layer)


## `:doc` - the drawing itself: how much is in it, which layers it has, where it lives, and whether what is
## in it has been written to that file.
##
## The count, the layers and the file are the controller's own, and the state of the file is its `dirty` flag
## said as a sentence, because "no unsaved changes" is a thing a person reads rather than a flag they decode.
func _doc(_first: String = "", _second: String = "", _third: String = "") -> String:
	var draft: Node = _somewhere("DraftController")
	if draft == null:
		return "there is no drawing to ask about - run this scene, which puts the program up"
	var layers := PackedStringArray()
	for choice: Dictionary in draft.call(&"layer_choices"):
		layers.append(String(choice["name"]))
	var path: String = String(draft.get(&"drawing_path"))
	return "\n".join([
		"entities  %d" % int(draft.call(&"entity_count")),
		"layers    %d: %s" % [layers.size(), ", ".join(layers)],
		"file      %s" % (path if not path.is_empty() else "not saved yet"),
		"unsaved   %s" % (
			"yes - there are changes the file does not have"
			if bool(draft.get(&"dirty"))
			else "no - the file has everything the drawing has"),
	])