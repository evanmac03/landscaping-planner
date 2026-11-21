@tool
extends Control
## The phone's arrangement of the HUD, stood up by hand so the whole of it can be looked at and pushed about
## with a mouse, rather than worked out from a probe block or a screenshot.
##
## **It fills in the 2D workspace, and that is the point of `TouchFurniture`'s shape.** This file builds the
## furniture itself out of the scene's own nodes: the scene is `scenes/ui/hud.tscn`, every control in it is real
## - the four words in the top bar, the five tabs along the dock, the strip between them - and every one of them
## is built by the furniture module's own `build`, dressed by its own `apply_the_plates`, shown by its own
## `show_the_furniture` and placed by its own `place_the_dock`.
##
## **Why it cannot go through the HUD's own script, in one measurement.** A script that is not `@tool` gets no
## script *instance* in the editor, so the HUD's plain and `@onready` members do not exist in a 2D view to be
## assigned: `node_get_property_list("Hud", mask:"script")` returns exactly the three `@export`s
## (`view_controller`, `presentation`, `painted_plan`), and the first hand-over throws
## `Invalid assignment of property or key 'top_bar' ... on a base object of type 'CanvasLayer (PlannerHud)'`.
## A **`RefCounted`**, though, does get an instance in an editor - the `@tool` rule is about *nodes in a scene* -
## so the furniture can be built here while the HUD's own `_ready` stays out of the editor entirely, which
## matters because that `_ready` arms autosave, starts the survey watcher's timer and opens the document.
##
## **A finger is stated rather than asked.** `on_a_finger = true` is the same door `Hud` itself answers
## `shows_touch_controls()` with; here there is no device to ask and no HUD to ask, so the view says so. Every
## door the furniture connects is left **empty**: the buttons are built, sized and dressed and simply press
## nothing, which is the honest arrangement for a view with nothing to run. That is also why three pieces are
## absent rather than wrong - **the sheet is not open, because nothing here has opened one**; and
## the six panels that stand over the board keep their desk rectangles, because the band they were to be given
## was measured wrong and withdrawn (`hud.gd`'s `_place_the_overlay_panels` says why).
##
## **The density is different, and is why this file states a number.** `PhoneHud.dpi()` reads the real screen,
## and a desk monitor's 96 is not a phone's 450, so left alone every control would come out a fifth of the
## height a thumb needs. The density is stated around the building and put back the moment it is made: a control
## keeps the height it was made with, and a static left standing would be read by whatever asked next.
##
## **The strip's buttons are stand-ins, and they are the one thing here that is a view's own.** In the running
## program the strip **borrows the palette's own buttons** - one tool, one button, wherever it is reached from -
## but this panel's script gets no instance in an editor, so there are no buttons to borrow and none to reparent.
## The view makes one set for itself, and **it words nothing**: the name is `PalettePanel.label`'s, the sentence a
## tool explains itself with is `PalettePanel.tooltip_for`'s or the edit table's own fourth column, the size and
## the focus rule are the furniture's own `a_button`, and which tools a tab wants is the furniture's own
## `tool_indices_for_a_tab` read off the palette's own table. A view has no keys and no drawing, so each button
## draws its name alone and presses nothing - which is what the palette's own doc says the handed-in key is for.
##
## **The first tab is pressed for the person**, so the view opens showing what a thumb would meet first rather
## than an empty strip, and so the strip's own fitting is exercised the moment the scene is loaded.
##
## **Run it as well as open it.** In 2D there is no frame loop of the scene's own, so the placement is asked for
## two frames later - the same frames `phone_hud_demo` waits, and the same reason `Hud` defers its own
## `_place_the_touch_dock`: a control asked for its size before it has laid out answers the size it had before.
## Asked from `_ready` the dock came out with its foot 908 px up a 900 px room and the probe named all eight of
## its controls as off the screen.

const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const TouchFurnitureScript := preload("res://scripts/touch_furniture.gd")
## The two other halves of stating a device, because a density alone is not one.
##
## **This is the fault that made the 2D space and F6 look different, and it was measured rather than reasoned.**
## `PhoneHud`'s floor for a target is only applied when the program believes a finger is here - its own
## `on_a_finger_here` asks a touchscreen **and** a density - and an editor process has no touchscreen and states no
## device, so every control came out at this desk's 31 px while the same scene run with F6 came out at the phone's
## 97. Stating the density alone was not enough and could not be: this project's rule is that **a screen and its
## safe area are one fact, and a density is one of three**, so the view states the same three the running program
## states - the A16W's glass, its camera cutout, and a finger.
const TouchInputScript := preload("res://scripts/touch_input.gd")

## The A16W's own glass: 1080 by 2340 with its camera cut into the top 100 px. The same numbers `PhoneHud`
## keeps for that device, stated here because a view that wants a phone's furniture has to say which phone.
const PHONE_SCREEN := Vector2i(1080, 2340)
const PHONE_SAFE_AREA := Rect2i(0, 100, 1080, 2240)
## The palette's own tables and its own wording for a tool, which is what a stand-in button borrows rather than
## restates. Its *script* is preloaded and never instanced: a panel in no scene gets no `_ready` and no editor
## instance, so nothing here calls into one - it asks the statics.
const PalettePanelScript := preload("res://scripts/palette_panel.gd")

## The reading the two sides share, and where an editor leaves its own for a run to compare with.
const WorkspaceReportScript := preload("res://tools/workspace_report.gd")
const EDITOR_READING := "user://touch_workspace_editor_reading.txt"

## The tab whose tools are a different list rather than a selection of the drawing tools. Named so the one
## comparison below reads as the fact it is.
const EDIT_TAB := "Edit"

## The phone this program is aimed at: the A16W's own glass, which reports 450 dots to the inch. Stated in the
## words the other device tools state it in, because it is the device and not this file's choice.
const PHONE_DPI := 450.0

## The frames the placement waits for before the dock is put where a finger would find it: one for the layout,
## and the second for the dock's own height before the sheet may stand on it.
const FRAMES_BEFORE_PLACING := 2

## And one more for the strip's own fitting, which the furniture defers for the reason every fitting here is - a
## control asked for its size before it has laid out answers the size it had before.
const FRAMES_BEFORE_SAYING := 1

## The nodes the furniture is given, by the paths the scene carries them under.
const NODES := {
	"row": "Root/TopBar/Row/TouchRow",
	"dock": "Root/TouchDock",
	"strip": "Root/TouchDock/Column/ToolStrip",
	"strip_row": "Root/TouchDock/Column/ToolStrip/StripScroll/Strip",
	"tabs": "Root/TouchDock/Column/Tabs",
	"sheet": "Root/TouchSheet",
	"sheet_title": "Root/TouchSheet/Column/Header/Title",
	"sheet_close": "Root/TouchSheet/Column/Header/Close",
	"palette_column": "Root/Palette/PaletteScroll/PaletteColumn",
	"hints": "Root/Hints",
	"menu_bar": "Root/TopBar/Row/MenuBar",
	"top_bar": "Root/TopBar",
	"overlay": "Root/Overlay",
}


## Whether the arrangement has been stood up already, so the two doors below cannot do it twice.
var _stood_up: bool = false

## How many frames have gone by since the arrangement was built, or -1 when there is nothing left to wait for.
## **The frames are counted here rather than awaited**, and the reason is a fault that was measured: see
## `_keep_counting_the_frames`.
var _frames_waited: int = -1


func _ready() -> void:
	_stand_it_up_once()


## **Asked on every editor frame as well as from `_ready`, and that is the fix for a fault measured three times.**
##
## A `@tool` script's `_ready` runs when Godot *instantiates* the scene - and the editor does not re-instantiate a
## scene it already has open when a script changes. It keeps its nodes and reloads the script onto them, so
## `_ready` never fires again, and the 2D workspace stayed a picture of the scene's own nodes - no bar words, no
## strip, no tabs - while the very same scene run with F6 stood the whole phone arrangement up. Closing and
## reopening the tab did not cure it either, which is the measurement that settled it. `_process` *is* called for
## the edited scene, so the build is asked for from there too, once, behind a guard - and after this the
## workspace stands itself up whether or not the tab has ever been closed.
func _process(_delta: float) -> void:
	if not _stood_up:
		_stand_it_up_once()
		return
	_keep_counting_the_frames()


## The frames the placement waits for, counted on `_process` instead of awaited - and that is a fault measured.
##
## The room a control reports is the room it had *before* it laid out, so placing the dock has to wait until the
## layout has run, which is why this file awaited `get_tree().process_frame` twice. **In an edited scene that
## frame signal never came back.** A 2D view is not a running game: the arrangement reached `show_the_furniture`
## and stopped there, so the dock was never placed, the strip was never filled and the closing report never
## printed - and the editor's own console held not one `TOUCH WORKSHOP` line while F6 printed all three. Counting
## on `_process`, which an editor does call (it is already how the build itself is asked for), takes the same road
## in both places and depends on nothing a view may not deliver.
func _keep_counting_the_frames() -> void:
	if _frames_waited < 0:
		return
	_frames_waited += 1
	if _frames_waited == FRAMES_BEFORE_PLACING:
		_furniture.place_the_dock()
		_furniture.press_a_tab("Draw")
	if _frames_waited < FRAMES_BEFORE_PLACING + FRAMES_BEFORE_SAYING:
		return
	_frames_waited = -1
	_say_what_was_stood_up(_furniture)


func _stand_it_up_once() -> void:
	if _stood_up:
		return
	_stood_up = true
	_stand_the_phone_arrangement()


## Build the phone's furniture out of this scene's own nodes, say a finger is here, and stand it where a finger
## would find it.
func _stand_the_phone_arrangement() -> void:
	# Said first, and before anything can refuse: a view that stops part-way names itself, so the line below is
	# the difference between "nothing happened" and "this much happened, and then it stopped".
	print("TOUCH WORKSHOP: standing the phone's arrangement up from this scene's own nodes")
	var furniture: TouchFurnitureScript = TouchFurnitureScript.new()
	var missing: PackedStringArray = PackedStringArray()
	for key: String in NODES:
		var node: Node = get_node_or_null(NodePath("Hud/" + String(NODES[key])))
		if node == null:
			missing.append(key)
			continue
		furniture.set(key, node)
	# The scene moves; this file does not guess. A path that no longer resolves is named rather than left to the
	# builders, each of which would return at its own guard and say nothing about why.
	if not missing.is_empty():
		print("TOUCH WORKSHOP: the scene has moved - no node for: %s" % ", ".join(missing))
		return
	_clear_what_was_built(furniture)
	furniture.on_a_finger = true
	furniture.app_window = get_window()
	# The two doors that make the view answerable. `press_a_tab` is the furniture's own, bound rather than
	# rewritten, so pressing a tab in the editor runs the same arrangement the running program runs - it marks the
	# tab, borrows the tools and fits them - and only the buttons it borrows are the view's instead of the
	# palette's.
	_furniture = furniture
	furniture.tab_door = Callable(furniture, &"press_a_tab")
	furniture.tools_for_door = Callable(self, &"_tools_for_a_tab")
	# The phone's density for exactly as long as it takes to make the furniture, then the machine's own back - and
	# the other two halves of stating a device with it. See the note on `TouchInputScript` for the measurement.
	PhoneHudScript.force_density(PHONE_DPI)
	PhoneHudScript.force_display(PHONE_SCREEN, PHONE_SAFE_AREA)
	TouchInputScript.force(TouchInputScript.Answer.FINGER)
	furniture.build()
	# **The palette's own controls, built here for the same reason the strip's stand-ins are.** `PalettePanel` is a
	# plain node script, so in an editor nothing calls its `build` and the column stands empty: no arm toggle, no
	# grid of tools, no layer row, no commands. A null controller is the case its own doc allows - the rows are drawn
	# from the tables alone and every button does nothing - and no keys are handed in, because the input map is the
	# HUD's to read and a view that read it would be a second answer to what a key does.
	#
	# **Inside the phone's density, and kept where a phone keeps it.** Built outside this it came out a desk's
	# height - 31 px rows against the bar's 98 - and showing it then drew it across the bar's own rows, which
	# `PROBE reach` named at once: a tap meant for `Menu` would have reached the palette instead. That is the fault
	# the running arrangement avoids by putting the palette away on a finger, and this view is the phone's
	# arrangement. The column is built because the scene holds it and because the strip's stand-ins are handed back
	# to it; it is left hidden for the reason a phone leaves it hidden.
	# **Only where the column's own script has an instance, which is never in an editor.** That guard is not
	# decoration: `PalettePanel` is a plain node script, so in a 2D view the node is there but none of its methods
	# are, and calling one is a runtime error - and a runtime error stops this whole function. That is exactly how
	# the furniture came to *exist* in the editor and stay *invisible*: the four words and the five tabs were
	# built, and then this call stopped the arrangement before `show_the_furniture` could show any of it. In the
	# running program the script has an instance and the whole palette is built.
	if furniture.palette_column != null and furniture.palette_column.has_method(&"build"):
		furniture.palette_column.build(null, { })
	PhoneHudScript.force_density(0.0)
	PhoneHudScript.force_display(Vector2i.ZERO, Rect2i())
	TouchInputScript.force(TouchInputScript.Answer.AUTO)
	furniture.show_the_furniture(true)
	# **Read straight back, and that is the measurement the closing report cannot make.** That one is three frames
	# later, so it cannot tell "never shown" apart from "shown and then hidden" - and which of the two it is decides
	# where to look next. This line is between the call and the first frame that follows it, which is the only place
	# the difference can be seen: the closing line said `=false/false` while `on_a_finger` read `true`, and
	# `show_the_furniture` cannot produce that.
	print(
		"TOUCH WORKSHOP: shown, and the row/dock read straight back as shown=%s/%s"
		% [str(furniture.row.visible), str(furniture.dock.visible)]
	)
	# **Nothing below waits on a frame signal; the frames are counted in `_process`.** See
	# `_keep_counting_the_frames` for the fault that put it there.
	_frames_waited = 0


## Empty the three rows the furniture builds into, so it can be asked for again at a phone's density.
##
## **A copy that has already built itself has to be asked a second time, and asking is not repeating**: run in
## the Game tab, the HUD's own `_ready` has already made these buttons at whatever density this machine has, and
## every builder returns early when its row is not empty - so without this the workshop would show a desk's
## buttons under a phone's furniture and say nothing about it. In 2D there is nothing here to clear, and this is
## the line that does nothing.
func _clear_what_was_built(furniture: TouchFurnitureScript) -> void:
	# The stand-ins go with them: they are the view's own buttons, and one that had been left in the dictionary
	# while its node was freed would be handed back to the strip on the next press.
	_strip_tools.clear()
	for row: Control in [furniture.row, furniture.tabs, furniture.strip_row]:
		if row == null:
			continue
		for made: Node in row.get_children():
			row.remove_child(made)
			made.queue_free()


## The furniture this view built, kept only so that the stand-ins below can be made by the same builder the
## running program's own buttons are made by: their height, their type size and their focus rule are the
## furniture's, and a second builder here would be a second answer to how tall a target is.
var _furniture: TouchFurnitureScript = null

## The stand-in buttons, one list per tab, made once and handed back on every later press for the reason
## `press_a_tab` gives: it asks the door again on each press, and it is the *same* buttons that must come back.
var _strip_tools: Dictionary = { }


## The buttons a tab would show, made here because in an editor there is no palette to borrow them from.
##
## **This is the one place a view makes its own furniture, and it words none of it.** Every string is asked of
## whoever already owns it - `PalettePanel.label` for the words on the face, the palette's `tooltip_for` or the
## edit table's own fourth column for the sentence behind it - and every number is the furniture's own
## `a_button`'s. What a tab wants is the furniture's own answer for the two tabs it answers for, and this file
## adds the third, because the editing commands are a whole different list rather than a selection of the first:
## that is the same split the HUD's own door makes, and it is stated here rather than guessed by the module.
func _tools_for_a_tab(tab: String) -> Array[Button]:
	if _strip_tools.has(tab):
		return _strip_tools[tab]
	var made: Array[Button] = []
	for pair: Array in _pairs_for_a_tab(tab):
		# Named after the action it stands for rather than left to the engine's numbering, so the node tree says
		# what each button does - the same reason the palette's own buttons are named that way.
		var button: Button = _furniture.a_button(PalettePanelScript.label(pair, ""), _tooltip_for(pair), Callable())
		button.name = String(pair[0])
		# Given a home in the palette's own column, which is where the running program's buttons stand. It is not
		# decoration: a node with no parent cannot be reparented into the strip at all - `press_a_tab` says so in
		# as many words - and `put_the_tools_back` hands every tool back to this column when a tab is put away, so
		# a button standing nowhere would be left in the strip for the next tab to sit beside.
		if _furniture.palette_column != null:
			_furniture.palette_column.add_child(button)
		made.append(button)
	_strip_tools[tab] = made
	return made


## The table rows one tab's strip is made of.
func _pairs_for_a_tab(tab: String) -> Array:
	var pairs: Array = []
	for index: int in TouchFurnitureScript.tool_indices_for_a_tab(tab):
		pairs.append(PalettePanelScript.DRAFTING_TOOLS[index])
	if tab == EDIT_TAB:
		pairs.append_array(PalettePanelScript.EDIT_TOOLS)
	return pairs


## What a stand-in explains when the pointer rests on it: the palette's own sentence for a drawing tool, and the
## table's own for an editing command. The two lists are shaped differently - three columns against four - and
## that difference is the whole of what this function decides.
func _tooltip_for(pair: Array) -> String:
	return String(pair[3]) if pair.size() > 3 else PalettePanelScript.tooltip_for(pair)


## What was stood up, in the numbers that decide whether a thumb could hit it - the whole reason a view like this
## is worth having beside the arithmetic it is made of.
func _say_what_was_stood_up(furniture: TouchFurnitureScript) -> void:
	if furniture.row == null or furniture.row.get_child_count() == 0:
		print("TOUCH WORKSHOP: the furniture did not build - the scene and the module have parted company")
		return
	var made: Button = furniture.row.get_child(0) as Button
	# The room the dock stands in, which is the whole canvas - read off the dock's own parent rather than the
	# bar's row, whose parent is the bar and comes back a tenth of the size.
	var room: Vector2 = furniture.dock.get_parent_area_size()
	print(
		(
			"TOUCH WORKSHOP: %d words in the bar and %d tabs, each %.0f px tall with %.0f px of type"
			+ ", at %.0f dpi; the dock's foot is %.0f px up a %.0f px room; %d tools in the strip"
			+ "; on_a_finger=%s, built_at=%.0f dpi, row/dock shown=%s/%s"
		)
		% [
			furniture.row.get_child_count(),
			furniture.tabs.get_child_count(),
			made.custom_minimum_size.y,
			float(made.get_theme_font_size(&"font_size")),
			# The density the furniture was *built* at, not the one this machine reports now - the point of the
			# line is what is on the screen, and a density of 144 beside 97 px buttons would read as a puzzle.
			PHONE_DPI,
			absf(furniture.dock.offset_bottom),
			room.y,
			furniture.strip_row.get_child_count(),
			# **The two readings that tell a view apart from a run**, said beside the sizes because they are the
			# same question: `on_a_finger` is what `show_the_furniture` reads to decide whether the phone's
			# furniture belongs on the glass at all, and `built_at` is the density it was made at - 450 on the
			# device, this desk's 144 otherwise.
			str(furniture.on_a_finger),
			furniture.built_at,
			str(furniture.row.visible),
			str(furniture.dock.visible),
		]
	)
	print("TOUCH WORKSHOP: the aids' clearance - %s" % furniture.foot_clearance_words())
	_say_the_report()


## The same reading on both sides, and the comparison when both are to hand.
##
## **An editor and a run are two different processes, so this is the only way the two can be held against each
## other.** Each states the same block for the same nodes; an editor leaves its own in `user://`, and a run reads
## that back and names what does not match - which is precisely the question a person asking "why does this not
## look like F6" is asking, answered by a reading rather than by two pictures.
##
## `looks_built_for_a_finger` is said beside it because it is the fault that caused all of this: an editor states
## no device, so its furniture is built at a desk's size and every control comes out under the floor a thumb needs.
func _say_the_report() -> void:
	# **The density the furniture was *built* at, not the one this machine reports now.** A view that stated a phone
	# has already handed the desk's own density back by the time this is said, so `PhoneHud.dpi()` answers 144 beside
	# furniture made at 450 - and 144 would measure every one of those buttons against a desk's floor and report a
	# phone's screen clean. `built_at` is the density the sizes below were made at, so it is the only one a floor can
	# honestly be measured against.
	var density: float = PhoneHudScript.dpi() if _furniture == null else _furniture.built_at
	var mine: Dictionary = WorkspaceReportScript.read(self, density)
	var which: String = "an editor" if Engine.is_editor_hint() else "a run"
	print("TOUCH WORKSHOP: the reading from %s" % which)
	for line: String in WorkspaceReportScript.lines(mine):
		print("  ", line)
	for told: String in WorkspaceReportScript.looks_built_for_a_finger(mine):
		print("  ! ", told)
	if Engine.is_editor_hint():
		_leave_the_reading_for_a_run(mine)
		return
	var theirs: Dictionary = WorkspaceReportScript.from_lines(_read_what_the_editor_left())
	if theirs.is_empty():
		print("TOUCH WORKSHOP: no editor reading to compare with - open this scene in the editor once first")
		return
	var named: Array[String] = WorkspaceReportScript.differences(theirs, mine)
	if named.is_empty():
		print("TOUCH WORKSHOP: the editor's own copy and this run agree on every node read")
		return
	print("TOUCH WORKSHOP: %d difference(s) from the editor's own copy:" % named.size())
	for one: String in named:
		print("  - ", one)


## Leave this side's reading where a run can find it, through a temporary file and a rename - the house rule for
## every write, so a write that fails never leaves a shorter file where the real one was.
func _leave_the_reading_for_a_run(mine: Dictionary) -> void:
	var temporary := EDITOR_READING + ".writing"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		print("TOUCH WORKSHOP: the reading could not be left for a run: ", FileAccess.get_open_error())
		return
	for line: String in WorkspaceReportScript.lines(mine):
		file.store_line(line)
	file.close()
	DirAccess.rename_absolute(temporary, EDITOR_READING)


## What an editor left, or nothing at all when it has never been opened there.
func _read_what_the_editor_left() -> PackedStringArray:
	if not FileAccess.file_exists(EDITOR_READING):
		return PackedStringArray()
	var file := FileAccess.open(EDITOR_READING, FileAccess.READ)
	if file == null:
		return PackedStringArray()
	var out: PackedStringArray = PackedStringArray()
	while not file.eof_reached():
		var line := file.get_line()
		if not line.is_empty():
			out.append(line)
	file.close()
	return out
