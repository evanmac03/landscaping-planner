class_name MenuBarPlan
extends RefCounted
## What the bar is made of, menu by menu: the entry table, and the vocabulary an entry is written in.
##
## This is the whole of what a menu bar *is* here - every menu, in the order a person learned them, and
## every entry with the label it carries, the action behind it and the method that runs it. An entry names
## its handler and **never holds a `Callable`**, so the bar can be read, listed and tested with no scene, no
## node and no file; that is also why the table can live away from the HUD at all.
##
## The HUD keeps the other half: how the bar is measured against the room it has, how each entry is drawn
## and checked against the live scene, and its own doors onto this table - so nothing outside has to know
## which file the table is in.
##
## Moved here from `hud.gd`, where it was 810 lines of data in a 9,700-line script.

const DraftToolScript := preload("res://scripts/draft/draft_tool.gd")
const PlotScaleScript := preload("res://scripts/draft/plot_scale.gd")
const SelectScript := preload("res://scripts/draft/draft_select.gd")
const DraftControllerScript := preload("res://scripts/draft/draft_controller.gd")
const OrientationChoiceScript := preload("res://scripts/orientation_choice.gd")
const ReadingSizeScript := preload("res://scripts/reading_size.gd")
const TierScript := preload("res://scripts/vis/presentation_tier.gd")

## The tables the menus list from, which live beside the thing they describe rather than here: the
## drawing tools with `DraftTool`, the editing commands with `DraftController`, and the sizes a still can
## be asked for with the tiers. The names are the same arrays rather than copies of them.
const DRAFTING_TOOLS: Array = DraftToolScript.DRAFTING_TOOLS
const EDIT_TOOLS: Array = DraftControllerScript.EDIT_TOOLS
const STILL_SIZES: Array = TierScript.STILL_SIZES


## What an entry needs from the scene before it means anything. `NEEDS_NOTHING` is the common
## case: the command works in any scene this HUD is in.
const NEEDS_NOTHING := &""
const NEEDS_DRAFT := &"draft"
const NEEDS_PRESENTATION := &"presentation"
const NEEDS_PRESENCE := &"presence"
## The window can be turned at all: a desktop's window cannot be asked which way up to be, so the three
## orientation choices are shown switched off there rather than doing nothing when they are pressed.
const NEEDS_CAN_TURN := &"can_turn"
## A device answered with a finger. A reading size multiplies the fitting done for one, and a computer is
## never fitted at all - its panels are the ones this program was drawn for - so the three sizes are shown
## switched off there rather than doing nothing when they are pressed.
const NEEDS_A_FINGER := &"finger"
const KNOWN_NEEDS: Array[StringName] = [
	NEEDS_NOTHING,
	NEEDS_DRAFT,
	NEEDS_PRESENTATION,
	NEEDS_PRESENCE,
	NEEDS_CAN_TURN,
	NEEDS_A_FINGER,
]


## One entry that runs a command.
static func _command(
	id: String,
	label: String,
	action: StringName,
	method: StringName,
	needs: StringName = NEEDS_NOTHING,
	enabled_when: StringName = &"",
) -> Dictionary:
	return {
		"kind": &"command",
		"id": id,
		"label": label,
		"action": action,
		"method": method,
		"needs": needs,
		"enabled_when": enabled_when,
		"value": null,
	}


## One entry of a set: choosing it chooses that value, and exactly one of the set is shown as on.
## `state` names what it is checked against, and `value` is the value it stands for.
static func _radio(
	id: String,
	label: String,
	action: StringName,
	method: StringName,
	state: StringName,
	value: Variant,
	needs: StringName = NEEDS_NOTHING,
) -> Dictionary:
	return {
		"kind": &"radio",
		"id": id,
		"label": label,
		"action": action,
		"method": method,
		"state": state,
		"value": value,
		"needs": needs,
	}


## One entry that is on or off, and means the state it names. It carries a null value so that
## every checkable entry has the same shape, and a reader of the plan does not have to know which
## kind it is before asking what it stands for.
static func _check(id: String, label: String, action: StringName, method: StringName, state: StringName) -> Dictionary:
	return {
		"kind": &"check",
		"id": id,
		"label": label,
		"action": action,
		"method": method,
		"state": state,
		"value": null,
		"needs": NEEDS_NOTHING,
	}


## A menu inside a menu, for the sets that would otherwise be ten entries long.
static func _submenu(id: String, label: String, items: Array[Dictionary]) -> Dictionary:
	return { "kind": &"submenu", "id": id, "label": label, "items": items, "action": &"", "needs": NEEDS_NOTHING }


static func _separator() -> Dictionary:
	return { "kind": &"separator", "id": "", "action": &"", "needs": NEEDS_NOTHING }


## A line that says something rather than doing something: shown switched off, because a menu
## entry that looks pressable and is not is the thing this whole file is trying not to build.
static func _info(id: String, label: String) -> Dictionary:
	return { "kind": &"info", "id": id, "label": label, "action": &"", "needs": NEEDS_NOTHING, "value": null }


## The words the bar uses to report its own fold: written by `Hud`, read back by `tools/phone_touch_pass.gd`, and
## round-tripped by a test beside this - so the writer and the reader cannot come apart.
##
## Both numbers in it are the **bar's own**: `room` is what the fold was given and `bar_min` what the bar needs.
## That is what makes them a comparison, and it is why the line exists - `room=349 bar_min=272` is a bar that fits,
## while the probe's `row` line names the room the *menus* were given beside the whole *row*'s minimum, which is
## not a comparison at all and was misread as an overflowing bar twice.
const MENUBAR_MARK := "MENUBAR "

## The five numbers the line carries, in the order it writes them.
const MENUBAR_KEYS: Array[String] = ["room", "bar_min", "row", "shown", "titles"]


## What the bar says about itself after a fold: the room it was given, what it needs, the row it sits in, the
## screen it is on, and how many titles it is drawing.
static func menubar_line(room: float, bar_min: float, row: float, shown: float, titles: int) -> String:
	return (MENUBAR_MARK + "room=%.0f bar_min=%.0f row=%.0f shown=%.0f titles=%d" % [room, bar_min, row, shown, titles])


## That line read back, wherever it appears - a logcat line carries it behind the time, the pid and the tag.
##
## An empty dictionary when the bar has said nothing, which is the honest answer for a release build (this is a
## debug print) and for a run that never laid the bar out: a caller says *that*, rather than showing a zero. A
## line missing any of the five numbers is not a reading either, and is passed over in favour of the next one.
static func read_menubar_line(text: String) -> Dictionary:
	for raw: String in text.split("\n"):
		var line: String = raw.strip_edges()
		var at: int = line.find(MENUBAR_MARK)
		if at < 0:
			continue
		var said: String = line.substr(at)
		var read := { }
		for field: String in said.replace(MENUBAR_MARK, "").strip_edges().split(" "):
			var equals: int = field.find("=")
			if equals <= 0:
				continue
			read[field.substr(0, equals)] = field.substr(equals + 1)
		var whole: bool = true
		for key: String in MENUBAR_KEYS:
			if not read.has(key):
				whole = false
		if not whole:
			continue
		return {
			"line": said,
			"room": String(read["room"]).to_float(),
			"bar_min": String(read["bar_min"]).to_float(),
			"row": String(read["row"]).to_float(),
			"shown": String(read["shown"]).to_float(),
			"titles": int(String(read["titles"])),
		}
	return { }


## Whether the bar had finished folding when it said that: the room it was given took what it needed.
##
## Both numbers are the bar's own, so this is a fair comparison - and it is the question a reading taken mid-fold
## gets wrong when it is asked of anything else.
static func bar_had_finished(folded: Dictionary) -> bool:
	if folded.is_empty():
		return false
	return float(folded["bar_min"]) <= float(folded["room"])


## The same fact in words, because a report is read by a person: a bar that fits, a bar that was still folding, or
## a bar that said nothing at all.
static func bar_words(folded: Dictionary) -> String:
	if folded.is_empty():
		return "the bar said nothing about its fold, so nothing here is a reading of it"
	if bar_had_finished(folded):
		return (
			"the bar had finished folding: %.0f px of bar in a %.0f px room"
			% [float(folded["bar_min"]), float(folded["room"])]
		)
	return (
		"the bar was still folding when this was printed: %.0f px needed in a %.0f px room"
		% [float(folded["bar_min"]), float(folded["room"])]
	)


## The whole bar, menu by menu.
static func menu_plan() -> Array[Dictionary]:
	var menus: Array[Dictionary] = []
	menus.append({ "title": "File", "items": file_items() })
	menus.append({ "title": "Edit", "items": edit_items() })
	menus.append({ "title": "View", "items": view_items() })
	menus.append({ "title": "Draft", "items": draft_items() })
	menus.append({ "title": "Site", "items": site_items() })
	menus.append({ "title": "Plant", "items": plant_items() })
	menus.append({ "title": "Water", "items": water_items() })
	menus.append({ "title": "Light", "items": light_items() })
	menus.append({ "title": "Pipeline", "items": pipeline_items() })
	menus.append({ "title": "Jobs", "items": jobs_items() })
	menus.append({ "title": "Estimate", "items": estimate_items() })
	menus.append({ "title": "Present", "items": present_items() })
	menus.append({ "title": "Team", "items": team_items() })
	menus.append({ "title": "Help", "items": help_items() })
	return menus


## Everything the drawing can be sent to: the sheet it is plotted on, the picture of it at the
## chosen size, and how the sheet itself is set up.
static func file_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	# The drawing is named at the top of the menu, where a person looks to find out what is open.
	# A menu is also the last place something silent should live, so whether the screen and the
	# file agree is stated rather than implied by a greyed-out Save.
	items.append(_info(&"file.info", "no drawing"))
	items.append(_separator())
	items.append(_command(&"file.new", "New drawing", &"file_new", &"_menu_new_drawing", NEEDS_DRAFT))
	items.append(_command(&"file.open", "Open drawing...", &"file_open", &"_menu_open_drawing", NEEDS_DRAFT))
	items.append(_submenu(&"file.recent", "Open recent", []))
	# A drawing to look at rather than a file to open: the example garden laid out on the sheet, so a
	# person who has nothing yet has something to build from. It stands with New and Open for the same
	# reason - it is a way of getting a drawing - and unlike them it needs nothing open first.
	items.append(
		_submenu(
			&"file.examples",
			"Examples",
			[_command(&"file.examples.garden", "The example garden", &"", &"_menu_example_garden")],
		)
	)
	# A way of getting a drawing, so it stands with New and Open rather than with Save. It is *shown*
	# switched off in the ordinary case rather than hidden, for the same reason the bar greys out what
	# the scene cannot do: an entry that comes and goes cannot teach anybody that it exists.
	items.append(
		_command(&"file.recover", "Recover unsaved work...", &"", &"_menu_recover_unsaved", NEEDS_DRAFT, &"recovery")
	)
	items.append(_command(&"file.survey", "Import a survey...", &"", &"_menu_import_survey", NEEDS_DRAFT))
	items.append(_command(&"file.dxf", "Import a DXF underlay...", &"", &"_menu_import_dxf", NEEDS_DRAFT))
	items.append(_command(&"file.osm", "Import a site map (OpenStreetMap)...", &"", &"_menu_import_osm", NEEDS_DRAFT))
	items.append(_command(&"file.landxml", "Import a LandXML plat...", &"", &"_menu_import_landxml", NEEDS_DRAFT))
	# The fourth import, and the only one that is not a file of linework: a raster picture, which is
	# kept beside the drawing and laid under everything rather than read into entities.
	items.append(
		_command(&"file.picture", "Put a picture under the drawing...", &"", &"_menu_import_picture", NEEDS_DRAFT)
	)
	# And the way out. It stands with the imports rather than beside Save, because what it produces is
	# an interchange file for somebody else's program and not this drawing's own saved form.
	items.append(_command(&"file.dxf_out", "Save the drawing as a DXF...", &"", &"_menu_save_dxf", NEEDS_DRAFT))
	# And the other way out, and the one that leaves the drawing behind: a DXF is the design in two
	# dimensions for another drafting program, and a model is the garden in three for a person who
	# wants to build from it or light it. It needs nothing of the drawing to exist - the yard stands
	# whatever is on the plan - but it stands *next to* the DXF, because they are the same act.
	items.append(_command(&"file.model_out", "Save the yard as a 3D model...", &"", &"_menu_save_model"))
	items.append(_separator())
	items.append(_command(&"file.save", "Save", &"file_save", &"_menu_save_drawing", NEEDS_DRAFT, &"dirty"))
	items.append(_command(&"file.save_as", "Save as...", &"", &"_menu_save_drawing_as", NEEDS_DRAFT))
	items.append(_separator())
	items.append(_command(&"file.plot", "Plot a sheet...", &"draft_plot", &"_menu_plot", NEEDS_DRAFT))
	items.append(_command(&"file.still", "Render a proposal still", &"", &"_menu_render_still", NEEDS_PRESENTATION))
	items.append(_separator())
	# The set stands above the two submenus that set the *current* sheet, because that is the order the
	# subject goes in: the set is what the drawing goes out as, and the size and the scale are what this
	# sheet of it is drawn on.
	items.append(_command(&"file.sheet_setup", "Sheet setup...", &"", &"_menu_sheet_setup", NEEDS_DRAFT))
	items.append(_submenu(&"file.sheet", "Sheet size", sheet_items()))
	items.append(_submenu(&"file.scale", "Plot scale", scale_items()))
	items.append(_separator())
	items.append(_command(&"file.quit", "Quit", &"", &"_menu_quit"))
	return items


## Every sheet the plotter knows, from the table that measures them.
static func sheet_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	# Not `name`: this is a CanvasLayer, and `name` is the node's own.
	for sheet_name in PlotScaleScript.sheet_names():
		items.append(
			_radio(
				"file.sheet." + String(sheet_name),
				String(sheet_name),
				&"",
				&"_menu_set_sheet",
				&"sheet",
				sheet_name,
				NEEDS_DRAFT,
			)
		)
	return items


## Every scale on the metric ladder. Ten entries, which is why they are behind a submenu: a menu
## that is a list of numbers reads as a table rather than as commands.
static func scale_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	# Not `scale`: this is a CanvasLayer, and `scale` is a property of it.
	for ratio: float in PlotScaleScript.METRIC_LADDER:
		items.append(
			_radio(
				"file.scale.%d" % int(ratio),
				PlotScaleScript.metric_label(ratio),
				&"",
				&"_menu_set_scale",
				&"scale",
				ratio,
				NEEDS_DRAFT,
			)
		)
	return items


## What can be done to the drawing: its history, the shape in hand, and how it is measured.
static func edit_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	items.append(_command(&"edit.undo", "Undo", &"draft_undo", &"_menu_undo"))
	items.append(_command(&"edit.redo", "Redo", &"draft_redo", &"_menu_redo"))
	items.append(_separator())
	items.append(_command(&"edit.drop_point", "Drop the last point", &"draft_undo_point", &"_menu_drop_point"))
	items.append(_command(&"edit.cancel", "Cancel the shape", &"draft_cancel", &"_menu_cancel_shape"))
	# Simplify takes no key: it is a whole-drawing pass run once in a while, not something a hand
	# reaches for mid-stroke, and a stray keypress that rewrote every shape would be the worst
	# kind of surprise.
	items.append(_command(&"edit.simplify", "Simplify...", &"", &"_menu_simplify"))
	items.append(_separator())
	items.append(_submenu(&"edit.dimension_style", "Dimension standard", dimension_style_items()))
	items.append(_separator())
	for pair: Array in EDIT_TOOLS:
		items.append(
			_radio("edit.tool." + String(pair[0]), edit_tool_label(pair), pair[0], &"_menu_arm_edit", &"edit", pair[2])
		)
	# Selecting is not editing: it is how a person says *which* shapes before saying
	# what to do with them, and the two modes are the whole of it. They get no key
	# because the select tool has none - it is the one tool with no palette button,
	# since a band needs no settling in the hand.
	items.append(_separator())
	items.append(
		_radio(
			&"edit.select_window",
			"Window selection",
			&"",
			&"_menu_select_mode",
			&"select_mode",
			SelectScript.MODE_WINDOW,
		)
	)
	items.append(
		_radio(
			&"edit.select_crossing",
			"Crossing selection",
			&"",
			&"_menu_select_mode",
			&"select_mode",
			SelectScript.MODE_CROSSING,
		)
	)
	# The history goes at the foot of Edit, under the selection bands and away from the commands: it is
	# not an edit, it is what the drawing was when it was sent, and a person looks for it when they are
	# thinking about the job rather than about the shape under the cursor. It takes no key, as the bands
	# take none: a history is opened to be read, and a stray keypress on the drawing must not open a
	# window that takes the keyboard.
	items.append(_separator())
	items.append(_command(&"edit.revisions", "Revisions...", &"", &"_menu_revisions"))
	# And under that, what the drawing has *said*: the status line under the plan writes over itself, and
	# this is the same answers kept. No key, for the same reason the history takes none - it is opened to
	# be read, and it is the drawing's keys that must not be stolen by a stray press.
	items.append(_command(&"edit.said", "What just happened...", &"", &"_menu_said"))
	return items


## What one editing command is called in the menu: the one word the status line and
## the palette use, capitalised.
static func edit_tool_label(pair: Array) -> String:
	var words := String(pair[1])
	return words.substr(0, 1).to_upper() + words.substr(1)


## The dimension standards the controller offers, from its own table.
static func dimension_style_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for style: StringName in DraftControllerScript.DIMENSION_STYLES:
		var words := String(style)
		items.append(
			_radio(
				"edit.dimension_style." + words,
				words.substr(0, 1).to_upper() + words.substr(1),
				&"draft_dimension_style",
				&"_menu_set_dimension_style",
				&"dimension_style",
				style,
			)
		)
	return items


## Where you can be and what you can look at.
##
## The three views are a set rather than a toggle: the key swaps two of them because that is what
## one key can do, and a menu lists all three because that is what a menu is for.
static func view_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	items.append(
		_radio(&"view.plan", "2D plan", &"toggle_view", &"_menu_show_mode", &"mode", ViewController.ViewMode.PLAN_2D)
	)
	items.append(
		_radio(
			&"view.overhead",
			"3D overhead",
			&"toggle_view",
			&"_menu_show_mode",
			&"mode",
			ViewController.ViewMode.OVERHEAD_3D,
		)
	)
	items.append(
		_radio(
			&"view.ground",
			"Ground view",
			&"toggle_ground",
			&"_menu_show_mode",
			&"mode",
			ViewController.ViewMode.GROUND,
		)
	)
	items.append(_separator())
	items.append(_command(&"view.fit", "Fit the design to the screen", &"fit_view", &"_menu_fit"))
	# The site the plan stands on: put away on a new drawing (a blank page), brought back here. A tick
	# rather than a radio, because it is a thing standing under the drawing and not a view you are in.
	items.append(_check(&"view.site", "Show the site", &"", &"_menu_toggle_site", &"site"))
	items.append(_separator())
	items.append(_command(&"view.painted", "Painted plan", &"vis_painted", &"_menu_painted"))
	items.append(_check(&"view.hints", "Control hints", &"", &"_menu_toggle_hints", &"hints"))
	# Which way up the board is asked to stand. A submenu rather than three more lines, and the same set the
	# views above are: a choice made once and kept, rather than a view you are in.
	items.append(_separator())
	items.append(_submenu(&"view.orientation", "Screen orientation", orientation_items()))
	# How big the words are drawn. The same kind of set as the orientation above - a choice made once and
	# kept - and the one this program has to state itself, because Godot exposes no reading of the text-size
	# setting Android would have scaled the words by.
	items.append(_submenu(&"view.reading_size", "Reading size", reading_size_items()))
	return items


## The three ways the board can be asked to stand up, reached at View > Screen orientation.
##
## The same `_radio` set the three views are, because choosing one is choosing one of a set - and derived
## from `OrientationChoice` rather than written out, so a way added there appears here without a second list
## to keep in step. Each is shown switched off where the window cannot be turned at all (`can_turn`), which
## is what a desktop is: an entry that is not offered beats one that does nothing when it is pressed.
static func orientation_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for choice: StringName in OrientationChoiceScript.CHOICES:
		items.append(
			_radio(
				"view.orientation." + String(choice),
				OrientationChoiceScript.word(choice),
				&"",
				&"_menu_set_orientation",
				&"orientation",
				choice,
				NEEDS_CAN_TURN,
			)
		)
	return items


## The three sizes the words can be drawn at, reached at View > Reading size.
##
## The same `_radio` set the orientation choices are, and derived from `ReadingSize` for the same reason: an
## answer added there appears here without a second list to keep in step. All three are shown switched off on
## a computer, where nothing is fitted and so nothing would change - an entry that is not offered beats one
## that does nothing when it is pressed.
static func reading_size_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for choice: StringName in ReadingSizeScript.CHOICES:
		items.append(
			_radio(
				"view.reading_size." + String(choice),
				ReadingSizeScript.word(choice),
				&"",
				&"_menu_set_reading_size",
				&"reading_size",
				choice,
				NEEDS_A_FINGER,
			)
		)
	return items


## The drawing tools, and what is done with the shape in hand.
##
## The tools come from `DRAFTING_TOOLS` - the same table the legend and the palette are built
## from - so a tool cannot be in the legend and missing from the menu, or in the menu and
## pointing at a different tool from the one the key arms.
static func draft_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	items.append(_check(&"draft.armed", "Drawing tools", &"draft_mode", &"_menu_toggle_drawing", &"drawing"))
	items.append(_separator())
	for pair: Array in DRAFTING_TOOLS:
		items.append(
			_radio("draft.tool." + String(pair[0]), tool_label(pair), pair[0], &"_menu_arm_tool", &"tool", pair[2])
		)
	items.append(_separator())
	items.append(_command(&"draft.finish", "Finish the shape", &"draft_finish", &"_menu_finish"))
	items.append(_command(&"draft.close", "Close the shape", &"draft_close", &"_menu_close_shape"))
	items.append(_command(&"draft.drop_point", "Drop the last point", &"draft_undo_point", &"_menu_drop_point"))
	items.append(_command(&"draft.cancel", "Cancel the shape", &"draft_cancel", &"_menu_cancel_shape"))
	items.append(_separator())
	items.append(_command(&"draft.plot", "Plot a sheet...", &"draft_plot", &"_menu_plot"))
	items.append(
		_command(&"draft.style", "Next dimension standard", &"draft_dimension_style", &"_menu_cycle_dimension_style")
	)
	items.append(_separator())
	items.append(_command(&"draft.hatch", "Hatch a region...", &"", &"_menu_hatch_region"))
	items.append(_command(&"draft.snapping", "Snapping...", &"", &"_menu_snap_window"))
	return items


## A tool as one line of a menu: the word the palette uses, on one line rather than two, because a
## menu row has the key beside the name rather than under it.
static func tool_label(pair: Array) -> String:
	var words := String(pair[1])
	return words.substr(0, 1).to_upper() + words.substr(1)


## The client presentation: what it is rendered at, how the garden is framed, and the sun.
static func present_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	# First, because everything else in this menu is a control on the panel: a person whose phone has
	# cut the panel's last rows off needs the row that gives the panel back, and it is ticked when the
	# panel is on - which is the state it starts in whenever the scene has a director.
	items.append(
		_check(&"present.panel", "Presentation panel", &"", &"_menu_presentation_panel", &"presentation_panel")
	)
	items.append(_check(&"present.running", "Client presentation", &"", &"_menu_toggle_presentation", &"presenting"))
	items.append(_separator())
	items.append(_submenu(&"present.quality", "Quality", tier_items()))
	items.append(_command(&"present.frame", "Frame the garden", &"", &"_menu_frame_yard"))
	items.append(_separator())
	items.append(_submenu(&"present.still_size", "Still size", still_size_items()))
	items.append(_command(&"present.still", "Render a still", &"", &"_menu_render_still"))
	items.append(
		_command(
			&"present.sun_study",
			"Sun and shadow study...",
			&"present_sun_study",
			&"_menu_sun_window",
			NEEDS_PRESENTATION,
		)
	)
	items.append(_command(&"present.walk", "Walk-through...", &"", &"_menu_walk_window", NEEDS_PRESENTATION))
	items.append(_separator())
	items.append(_info(&"present.sun_info", "the sun"))
	items.append(_separator())
	items.append(_command(&"present.save_site", "Save the site to the drawing", &"", &"_menu_save_site"))
	return items


## The rendering budgets, from the table that acts on them.
static func tier_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for tier: int in TierScript.CHOICES:
		items.append(
			_radio("present.quality.%d" % tier, TierScript.name_of(tier), &"", &"_menu_set_tier", &"tier", tier)
		)
	return items


## The sizes a proposal still can be, from the table the render button is built from.
static func still_size_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for index in STILL_SIZES.size():
		items.append(
			_radio(
				"present.still_size.%d" % index,
				String(STILL_SIZES[index][0]),
				&"",
				&"_menu_set_still_size",
				&"still_size",
				index,
			)
		)
	return items


## What the ground is like here: the facts about the place rather than the things drawn on it.
##
## This menu is where the green and red rings around a plant being placed come from. The ring is the
## answer; these entries are the question - the site's light, moisture, soil and hardiness - plus the
## report on the planting that is already in the ground.
##
## Half of it is a set of radios rather than a dialog, because that is what these are: four facts with
## a handful of values each, stated once for the site. A dialog would be a window with a dropdown in
## it to choose between "full sun" and "part shade", and a window is the one thing this HUD may not
## open casually. Each set starts with "not stated", because the truth about a plan nobody has
## described is that nobody has described it, and the way back to that has to exist.
static func site_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	items.append(_info(&"site.ground", "the plan does not say what the ground is like"))
	items.append(_separator())
	items.append(_command(&"site.window", "What the ground is like...", &"", &"_menu_ground_window"))
	items.append(_command(&"site.zone", "Draw a ground zone...", &"", &"_menu_draw_ground_zone"))
	items.append(_command(&"site.read", "Read the ground from the drawing", &"", &"_menu_read_ground"))
	# The drawing's layers: the same list the top bar's dropdown quick-picks from, with the two things
	# a dropdown cannot hold - locking one against editing and reading what each one is for.
	items.append(_command(&"site.layers", "Layers...", &"", &"_menu_layer_window", NEEDS_DRAFT))
	# The growing season: two frost dates that no drawing can supply, stated once for the site and kept
	# with it. Every food crop's "days to maturity" is measured against the season they bound, so this
	# is the one site fact the kitchen garden rests on.
	items.append(_info(&"site.season", "the growing season is not stated"))
	items.append(_command(&"site.season.window", "How long the season is...", &"", &"_menu_season_window", NEEDS_DRAFT))
	# The camera's own door from inside the drawing, and it needs nothing: a person standing at a leaf
	# with a phone in their hand should not have to have a drawing open to photograph it. The survey's
	# door beside it is the one that is *about* the drawing, and says so by needing one.
	items.append(_command(&"site.photograph", "Take a photograph...", &"", &"_menu_take_a_photograph"))
	# Recording what is standing on site: the person's own door into the same survey file a phone
	# writes, so a garden walked round with a notebook and a camera reaches the plan without one.
	items.append(_command(&"site.capture", "Record what is on site...", &"", &"_menu_capture_window", NEEDS_DRAFT))
	items.append(_separator())
	# The ground's own heights. Apart from the conditions above, because a level is a fact about the
	# shape of the land while a condition is a fact about what will grow on it - and a plan can be
	# levelled without anybody having said what the soil is like.
	items.append(_info(&"site.grading", "nothing on this drawing is graded"))
	items.append(
		_command(
			&"site.grade",
			"The ground's heights: levels, contours, slopes...",
			&"",
			&"_menu_grading_window",
			NEEDS_DRAFT,
		)
	)
	# The three tools the page above holds, on their own lines: each is one key away and each is the
	# same act as the button of that name on the page, so a level can be stamped without opening a page
	# and then choosing a tool in it. The keys - Z, B and M - are the three free ones that read as a
	# group, and `_unhandled_input` runs exactly these methods.
	items.append(_command(&"site.grade.spot", "Spot level here", &"grade_spot", &"_menu_grade_spot", NEEDS_DRAFT))
	items.append(
		_command(&"site.grade.contour", "Draw a contour", &"grade_contour", &"_menu_grade_contour", NEEDS_DRAFT)
	)
	items.append(_command(&"site.grade.slope", "Draw a slope arrow", &"grade_slope", &"_menu_grade_slope", NEEDS_DRAFT))
	items.append(_command(&"site.grade.check", "Check the grading", &"", &"_menu_check_grading", NEEDS_DRAFT))
	items.append(_separator())
	# **The nearer half of the same question.** The check beside this looks at the whole drawing and names the
	# plants its own conditions disagree with; this looks at the spot a person is standing on and names what goes
	# in beside them. It sits with the check rather than with the survey because both are about what the plan has
	# already placed - which is also why it is the one Site door that needs one.
	items.append(_command(&"site.nearby", "What is around me...", &"", &"_menu_nearby", NEEDS_DRAFT))
	items.append(_command(&"site.check", "Check the planting", &"", &"_menu_check_planting"))
	items.append(_separator())
	items.append(_command(&"site.report", "Site statistics", &"", &"_menu_site_report"))
	return items


## The sales pipeline: the leads, and the board they move across.
##
## A lead is not a drawing, so this menu is here whatever scene is open - it reaches a board of cards
## rather than anything on the plan. The line at the top is the open pipeline's own words, and the one
## entry opens the board.
static func pipeline_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	items.append(_info(&"pipeline.info", "no open leads"))
	items.append(_separator())
	items.append(_command(&"pipeline.board", "Open the pipeline board...", &"", &"_menu_pipeline_board"))
	return items


## The jobs and the crews: who works when, what clashes, and what it has cost.
##
## Like the pipeline this is business data rather than drawing data, so the menu is here whatever
## scene is open. The line at the top is the desk's own words - including a count of the clashes and
## what the orders have committed, because a board with something wrong on it should say so without
## being opened. The two entries are the two questions about a job: when is it being built, and what
## has it cost.
static func jobs_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	items.append(_info(&"jobs.info", "no crews and no jobs yet"))
	items.append(_separator())
	items.append(_command(&"jobs.board", "Open the schedule board...", &"", &"_menu_schedule_board"))
	items.append(_command(&"jobs.cost", "What the job has cost...", &"", &"_menu_cost_window"))
	items.append(_command(&"jobs.billing", "What has been billed...", &"", &"_menu_billing_window"))
	items.append(_command(&"jobs.outbox", "What has been handed to a ledger...", &"", &"_menu_ledger_window"))
	# The records' sync with the office's service: what is waiting, what wants a person, and where the
	# two copies disagree. Business data like the rest of this menu, so it needs no drawing.
	items.append(_command(&"jobs.sync", "Sync with the office...", &"", &"_menu_sync_window"))
	items.append(
		_command(&"jobs.analytics", "The figures: what the business is doing...", &"", &"_menu_analytics_window")
	)
	# Finishing the job: the punch list walked at the end, the day the garden was handed over, and the
	# warranty that runs from it. Business data like the rest of this menu, so it needs no drawing.
	items.append(_command(&"jobs.closeout", "Finishing the job...", &"", &"_menu_closeout_window"))
	return items


## The takeoff and the estimate: what the plan measures, and what that costs.
##
## The four business engines were built and tested before anything could reach them, so this menu is
## the reach. The line at the top says where the job stands, and the entries are the two things that
## are true whenever a drawing is open: measure it, and check the arithmetic. Everything else about a
## proposal - the prices, the tax, who it goes to - is in the window, because a proposal is a document
## and a menu is a list of commands.
static func estimate_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	items.append(_info(&"estimate.info", "nothing has been taken off the plan yet"))
	items.append(_separator())
	items.append(_command(&"estimate.window", "Takeoff and estimate...", &"", &"_menu_estimate_window", NEEDS_DRAFT))
	items.append(_command(&"estimate.take_off", "Take off the plan", &"", &"_menu_take_off", NEEDS_DRAFT))
	items.append(_command(&"estimate.check", "Check the numbers", &"", &"_menu_check_numbers", NEEDS_DRAFT))
	return items


## The plant list, and the one thing a plant list is for.
##
## Every entry here reaches the catalogue rather than the scene, so this is the same menu in a scene
## with no yard: a plant list is data, and where a plant goes is the plan's business. None of them
## advertises a key, because none of them is done often enough to deserve one.
static func plant_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	items.append(_info(&"plant.info", "no plant list"))
	items.append(_separator())
	items.append(_command(&"plant.library", "Plant library...", &"plant_library", &"_menu_plant_library"))
	# The other way to a name, and the one for a plant you are standing in front of: answer what you can
	# see and the list narrows. It reaches the catalogue and not the scene, so this is the same menu in a
	# scene with no yard.
	items.append(_command(&"plant.key", "Name a plant by answering questions...", &"", &"_menu_plant_key"))
	items.append(_command(&"plant.place", "Place the chosen plant", &"", &"_menu_plant_place"))
	items.append(_command(&"plant.stop", "Stop planting", &"", &"_menu_stop_planting"))
	items.append(_separator())
	items.append(_command(&"plant.label", "Label the planting", &"", &"_menu_label_plants"))
	# The nursery order: the one thing a planting list is for besides being read. It needs the drawing
	# because the plants are in the yard, which is a fact about the plan and not about the list.
	items.append(
		_command(
			&"plant.order",
			"Order the plants for this drawing...",
			&"plant_order",
			&"_menu_plant_order_window",
			NEEDS_DRAFT,
		)
	)
	# The food garden: the same drawing and the same list, asked the other question a garden is for -
	# where the food will actually crop. It needs the drawing because a bed's light is stated on the
	# plan, and a crop's hours are checked against the bed rather than against the list.
	items.append(_command(&"plant.food", "What will crop here...", &"", &"_menu_food_window", NEEDS_DRAFT))
	# What to grow here next: the kitchen gardener's other question - what should follow what, and what
	# grows well together. It needs the drawing for the bed names, and states the bed's history itself,
	# because no drawing was ever told what grew there last season.
	items.append(_command(&"plant.rotation", "What to grow here next...", &"", &"_menu_rotation_window", NEEDS_DRAFT))
	# What is ready when: the same plant list read as a calendar - pick a month and see every crop
	# recorded as ready then. It needs nothing but the list, so it needs no drawing; the entry sits here
	# among its food neighbours rather than in a menu of its own.
	items.append(_command(&"plant.harvest", "What's ready when...", &"", &"_menu_harvest_window", NEEDS_NOTHING))
	# When to sow: the season read as a sowing calendar - a day to sow on and how long a crop can be kept
	# coming. It needs the drawing because the season lives there, and the list because a crop's days to
	# maturity do; what it does not do is write either.
	items.append(_command(&"plant.sow", "When to sow...", &"", &"_menu_sowing_window", NEEDS_DRAFT))
	# How much to plant: the same list asked a household's question - how many plants it takes to feed a
	# given number of people. It needs nothing but the list, so it needs no drawing, and the entry sits
	# here among its food neighbours rather than in a menu of its own.
	items.append(_command(&"plant.yield", "How much to plant...", &"", &"_menu_yield_window", NEEDS_NOTHING))
	items.append(_separator())
	items.append(_command(&"plant.import", "Import a plant list...", &"", &"_menu_plant_import"))
	items.append(_command(&"plant.export", "Export the plant list...", &"", &"_menu_plant_export"))
	return items


## What the drawing is watered by: the supply, the zones, and the page that lays a new one out. A
## menu of its own rather than a corner of Site, because irrigation is a subsystem with its own
## vocabulary - a valve, a zone, a head - and burying it under the ground would put a pump among the
## soil types.
static func water_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	items.append(_info(&"water.info", "nothing on this drawing is watered yet"))
	items.append(_separator())
	items.append(_command(&"water.panel", "Water an area...", &"", &"_menu_water_panel", NEEDS_DRAFT))
	return items


## What the drawing is lit by: the transformer, the circuits, and the page that lays a new one out. A
## menu of its own beside Water, because lighting is the sibling subsystem - a transformer, a circuit,
## a fixture - and its vocabulary is as different from water's as water's is from the soil's.
static func light_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	items.append(_info(&"light.info", "nothing on this drawing is lit yet"))
	items.append(_separator())
	items.append(_command(&"light.panel", "Light an area...", &"", &"_menu_light_panel", NEEDS_DRAFT))
	return items


## The two ways of answering "how do I do this here": the manual, in prose, and the palette, which is
## the commands themselves. They belong together for that reason, and Help is the one menu that is
## there in every scene, which is what a command palette has to be.
##
## The key reference is the third thing the menu can offer that the on-screen hints cannot, because
## the hints are three lines in three corners.
static func help_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	items.append(_command(&"help.palette", "Command palette...", &"command_palette", &"_menu_command_palette"))
	items.append(_command(&"help.manual", "Landscaping Planner help...", &"", &"_menu_help"))
	items.append(_check(&"help.keys", "Drawing keys", &"", &"_menu_keys", &"keys_panel"))
	# Last, because it is the narrowest of the three ways in: the palette reaches any command, the manual
	# is the whole of it, and this one is about the page you happen to have open.
	items.append(_command(&"help.this_page", "What this page is about", &"", &"_menu_page_help"))
	return items


## The shared session. Sharing is started on purpose and the line says who is in the room, so a
## designer can see who is around without turning anything on - and nothing is opened, or billed,
## until Share is chosen.
static func team_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	items.append(_info(&"team.info", "no session"))
	items.append(_command(&"team.start", "Share this drawing...", &"", &"_menu_start_session", NEEDS_PRESENCE))
	items.append(
		_command(&"team.leave", "Leave the session", &"", &"_menu_leave_session", NEEDS_PRESENCE, &"session_on")
	)
	return items


## Every entry in the bar, flattened, each with the menu it sits under. What a test reads.
static func menu_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for menu: Dictionary in menu_plan():
		_collect_entries(String(menu["title"]), menu["items"], out)
	return out


static func _collect_entries(path: String, items: Array, out: Array[Dictionary]) -> void:
	for item: Dictionary in items:
		var entry: Dictionary = item
		entry["menu"] = path
		out.append(entry)
		if StringName(entry.get("kind", &"")) == &"submenu":
			_collect_entries(path + " > " + String(entry["label"]), entry["items"], out)


## The entries of one menu, for a test that wants to talk about the Draft menu.
static func items_for(title: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for menu: Dictionary in menu_plan():
		if String(menu["title"]) == title:
			var items: Array[Dictionary] = menu["items"]
			out = items
	return out
