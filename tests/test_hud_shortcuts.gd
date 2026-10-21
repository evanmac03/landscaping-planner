extends Node
## The keys: which command each one reaches, and that no two commands share one.
##
## The five commands that had none - the nursery order, the sun and the shadows, and the ground's three
## tools - are checked here for the two things a key can be wrong about: not being the same act as the
## button that does the same job, and being a key something else is already on.
##
## Nothing enters a tree: no `_ready` runs and no window is ever shown, which is why the ark reaches the
## tool through the door the button uses rather than by pressing a key.

const HudScript := preload("res://scripts/hud.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const ToolScript := preload("res://scripts/draft/draft_tool.gd")
const GradingScript := preload("res://scripts/draft/grading.gd")

## What a page's button says, the action the key is on, the entry the bar shows, and the tool it must
## put in hand.
const GROUND_TOOLS: Array = [
	["Spot level here", "grade_spot", "_menu_grade_spot", ToolScript.Kind.GRADE_SPOT, GradingScript.SPOT],
	["Draw a contour", "grade_contour", "_menu_grade_contour", ToolScript.Kind.GRADE_CONTOUR,
		GradingScript.CONTOUR],
	["Draw a slope arrow", "grade_slope", "_menu_grade_slope", ToolScript.Kind.GRADE_SLOPE,
		GradingScript.SLOPE],
]

## Every command that gained a key, and where it is: the menu it lives in, its id in that menu, and the
## action the key is bound to.
const NEW_KEYS: Array = [
	["Plant", "plant.order", "plant_order", "order the plants"],
	["Present", "present.sun_study", "present_sun_study", "the sun and the shadows"],
	["Site", "site.grade.spot", "grade_spot", "spot a level"],
	["Site", "site.grade.contour", "grade_contour", "draw a contour"],
	["Site", "site.grade.slope", "grade_slope", "draw a slope arrow"],
]


func _drawn() -> DraftController:
	var controller := ControllerScript.new()
	controller.document = DocumentScript.new()
	controller.document.changed.connect(controller._on_document_changed)
	controller.snap = SnapScript.new()
	controller.snap.bind(controller.document.entities())
	controller.tool = ToolScript.new()
	return controller


func _press(page: Node, caption: String) -> bool:
	for found: Node in page.find_children("*", "Button", true, false):
		if (found as Button).text == caption:
			(found as Button).pressed.emit()
			return true
	return false


func test_no_key_is_two_commands() -> void:
	# A key two commands share is a key that does both, which nobody ever means. This is what the five
	# new keys were chosen against, and it is worth keeping for the next one; Godot's own `ui_*` actions
	# are left out, because they are there for any control to use.
	var owners: Dictionary = {}
	var clashes: Array[String] = []
	for action: StringName in InputMap.get_actions():
		var name := String(action)
		if name.begins_with("ui_"):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			var key := event as InputEventKey
			if key == null:
				continue
			var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
			var signature := "%s %s%s%s" % [
				OS.get_keycode_string(code), key.ctrl_pressed, key.shift_pressed, key.alt_pressed
			]
			if owners.has(signature) and String(owners[signature]) != name:
				clashes.append("%s and %s are both on %s" % [owners[signature], name, signature])
			owners[signature] = name
	assert(clashes.is_empty(), "two commands on one key: " + ", ".join(clashes))


func test_every_command_that_had_no_key_is_on_one_and_the_bar_says_which() -> void:
	for pair: Array in NEW_KEYS:
		var menu := String(pair[0])
		var wanted := String(pair[1])
		var action := String(pair[2])
		var entry: Dictionary = {}
		for listed: Dictionary in HudScript.items_for(menu):
			if String(listed.get("id", "")) == wanted:
				entry = listed
		assert(not entry.is_empty(), "%s is in the %s menu" % [wanted, menu])
		assert(String(entry.get("action", "")) == action,
			"%s is on %s, not %s" % [wanted, action, entry.get("action", "")])
		# And the bar prints the key it is on, which is the whole of what a key is for.
		var label := HudScript.menu_label(entry)
		assert(label != String(entry["label"]), "%s shows its key: %s" % [wanted, label])
		assert(label.contains(HudScript._key_label(StringName(action))), label)
	# Bound at all: an action nobody bound is a key that does nothing.
	for pair: Array in NEW_KEYS:
		assert(InputMap.has_action(StringName(pair[2])), "%s is an action" % pair[2])


func test_the_key_and_the_button_put_the_same_tool_in_hand() -> void:
	# The claim the whole feature rests on: a key is not a second way of doing something, it is the
	# button's own act reached from the keyboard. Pressing the page's button and running the menu entry
	# must leave the controller holding the same tool.
	for pair: Array in GROUND_TOOLS:
		var caption := String(pair[0])
		var method := String(pair[2])
		var kind: int = int(pair[3])

		var by_button := _drawn()
		var hud_by_button := HudScript.new()
		hud_by_button._draft = by_button
		hud_by_button._build_grading_window()
		assert(_press(hud_by_button._grading_window, caption), "the page has a button: %s" % caption)
		assert(by_button.tool.kind == kind, "%s armed the tool" % caption)
		by_button.free()
		hud_by_button.free()

		var by_menu := _drawn()
		var hud_by_menu := HudScript.new()
		hud_by_menu._draft = by_menu
		hud_by_menu._build_grading_window()
		hud_by_menu.call(method, {})
		assert(by_menu.tool.kind == kind, "%s armed the same tool" % method)
		by_menu.free()
		hud_by_menu.free()


func test_the_reference_lists_the_keys_it_never_used_to() -> void:
	# Help > Drawing keys is where a key is looked up, so a key that is not in it is a key nobody can
	# find. The five rows are written from the same table the bar's entries are.
	var hud := HudScript.new()
	var text := hud.keys_text()
	assert(text.contains("Elsewhere"), "the reference has the section for them")
	for pair: Array in NEW_KEYS:
		var row: String = "%s %s" % [HudScript._key_label(StringName(pair[2])), pair[3]]
		assert(text.contains(row), "the reference has the row: %s" % row)
	hud.free()