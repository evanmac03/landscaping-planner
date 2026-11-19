extends Node
## A dev tool: **the program's own vocabulary** - every name a person and an agent need in order to talk about this
## screen, and the module each name is read from.
##
## The problem it exists for is a conversation, not a measurement. Two people - or a person and an agent - looking
## at the same window have no shared words for it: one says "the panel with the plants", the other says "the
## palette", and the third name for it is the one the code uses. Every one of these instruments is a way of
## *reaching* the names the program already has; this one is the list of them, so that a name can be agreed on once
## and used from then on.
##
## **Nothing here invents a name, and nothing here derives one.** Each section asks the module that already owns
## that vocabulary - `PageIndex` for the pages, the standing `MenuBar` for the menus, `DraftTool`'s one table for
## the drawing tools, `Hud.drafting_rows` for the keys, the controller's own list for the layers - so this cannot
## come to describe a page the program does not have or a key that is not bound. A second list would be a second
## answer, which is the fault this project spends most of its effort avoiding.
##
## **The menus are read off the bar that is standing** rather than off the plan the bar was built from. A plan is
## what a bar was made of; the bar is what a person can read, and the two are allowed to differ once the fold has
## had its say.
##
## **And what no module owns is said to be unowned**, with where to read it instead, rather than left out in
## silence: a vocabulary that quietly omitted the probe's line kinds would read as if there were none.
##
## Run it:
##
##     run_scene res://tools/vocabulary.tscn
##     GODOT_MCP_RUNTIME=0 <godot> --headless --path . res://tools/vocabulary.tscn
##
## It prints and ends by itself, so a scripted run wants no `timeout`. Not part of the game: the export excludes
## `tools/*`, so nothing here ships.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const PageIndexScript := preload("res://scripts/page_index.gd")
const HudScript := preload("res://scripts/hud.gd")
const DraftToolScript := preload("res://scripts/draft/draft_tool.gd")

## How long the program is given before anything is named. The same count every tool that photographs or reads this
## program waits, and for the same reason: the front door is built during `_ready` and the menu bar folds over the
## first twenty frames, so a bar read before that is a bar mid-rebuild.
const FRAMES_FOR_THE_PROGRAM := 40


func _ready() -> void:
	var main: Node = MainScene.instantiate()
	add_child(main)
	for _i: int in FRAMES_FOR_THE_PROGRAM:
		await get_tree().process_frame
	var hud: Node = main.get_node_or_null("Hud")
	if hud == null:
		print("VOCABULARY there is no Hud in the program, so there is nothing here to name")
		get_tree().quit()
		return
	for line: String in the_vocabulary(hud, main.get_node_or_null("DraftController")):
		print(line)
	get_tree().quit()


## The whole vocabulary, section by section.
static func the_vocabulary(hud: Node, controller: Node) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("=== the program's own vocabulary ===")
	lines.append("  a module  is named for each section, because that module is where the words come from")
	lines.append_array(page_lines())
	# The bar is found **by name rather than by a path**, which is how the console reaches the program's own nodes:
	# the path under the HUD has moved before now, and a guessed path answers "no menu bar is standing" about a bar
	# that is plainly on the screen - which is exactly what this section did on its first run.
	lines.append_array(menu_lines(hud.find_child("MenuBar", true, false) as MenuBar))
	lines.append_array(tool_lines())
	lines.append_array(key_lines())
	lines.append_array(layer_lines(controller))
	lines.append_array(no_list_lines())
	return lines


## Every page this project has, each under **the name the program reports it by** - `PageIndex`'s own list, which is
## the same list the console's `:pages`, the layout checks and the manual's page table are built from.
static func page_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var pages: Array[String] = PageIndexScript.scripts()
	lines.append("")
	lines.append("the pages        %d, from PageIndex - the name first, then the script that is the page" % pages.size())
	for path: String in pages:
		lines.append("  %-30s %s" % [PageIndexScript.page_name(path), path])
	return lines


## Every menu and every entry in it, read off **the bar that is standing**.
##
## A submenu's own entries are not descended into: a submenu is a popup of its own and a name in its own right, and
## the entry that opens it is printed as `(more)`. Godot draws a bar's titles itself rather than on a node, so the
## titles come from the bar's own API - which is also why nothing else in this project can report them.
static func menu_lines(bar: MenuBar) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("")
	if bar == null:
		lines.append("the menus        no menu bar is standing, so there is nothing to name")
		return lines
	var menus: int = bar.get_menu_count()
	if menus <= 0:
		lines.append("the menus        the bar is standing with no menus in it")
		return lines
	lines.append("the menus        %d menu(s), from the MenuBar itself" % menus)
	var entries: int = 0
	for menu: int in menus:
		lines.append("  %s" % bar.get_menu_title(menu))
		var popup: PopupMenu = bar.get_menu_popup(menu)
		if popup == null:
			continue
		for index: int in popup.item_count:
			if popup.is_item_separator(index):
				continue
			var said: String = popup.get_item_text(index)
			if said.is_empty():
				lines.append("      (more)  a submenu, whose own entries are a popup of their own")
				continue
			lines.append("      %s" % said)
			entries += 1
	lines.append("  %d entry(ies) a person can read off the bar" % entries)
	return lines


## The drawing tools, in the order the number keys select them - **`DraftTool.DRAFTING_TOOLS`**, the one table the
## key legend and the tool palette are both built from.
##
## The table states the action that selects a tool and the wording it is introduced by. The **key** is not here,
## because it is not in the table either: it is read from the input map, which is the half that can be derived, and
## `key_lines` below is where the derived form is printed.
static func tool_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var tools: Array = DraftToolScript.DRAFTING_TOOLS
	lines.append("")
	lines.append("the tools        %d, from DraftTool - the wording, then the action it is bound to" % tools.size())
	for one: Array in tools:
		lines.append("  %-18s %s" % [String(one[1]), String(one[0])])
	return lines


## Every key the drawing tools answer to, in **`Hud.drafting_rows`' own words** - the very rows the Keys reference
## page shows, so the vocabulary and the page cannot come to describe a key differently.
static func key_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("")
	lines.append("the keys         from Hud.drafting_rows - the rows the Keys reference is built from")
	for row: String in HudScript.drafting_rows():
		lines.append("  %s" % row)
	return lines


## The layers a drawing can be drawn on, **the controller's own list** - what the layer picker offers and what the
## console's `:mode` reads.
##
## A program with no drawing open has no layers to name, and that is said rather than shown as an empty list: a
## section that answered with nothing reads exactly like a section that had been forgotten.
static func layer_lines(controller: Node) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("")
	if controller == null or not controller.has_method("layer_choices"):
		lines.append("the layers       no drawing is open, so there are no layers to name")
		return lines
	var choices: Array[Dictionary] = controller.layer_choices()
	if choices.is_empty():
		lines.append("the layers       the drawing is open and holds no layer this program can draw on")
		return lines
	lines.append("the layers       %d, from the drawing itself" % choices.size())
	for one: Dictionary in choices:
		lines.append("  %s" % str(one))
	return lines


## **What owns no list, said to be unowned.** The probe's block has a vocabulary of its own - the kinds of line it
## publishes - and no module states the set of them: each is worded where it is written, in `HudProbe` for the
## board's own and in the two tools that read a block for theirs. Naming the set here would be a second answer to a
## question that has none, and a wrong one the day a line kind is added, so what is printed is where to read it.
static func no_list_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("")
	lines.append("no list          the probe's own line kinds: each is worded where it is written and nothing states")
	lines.append("                 the set of them. A whole block is that vocabulary as the program really says it:")
	lines.append("                 the console's `:probe`, or `phone_touch_pass --block` for a block off a device.")
	return lines
