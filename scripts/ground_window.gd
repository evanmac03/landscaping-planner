class_name GroundWindow
extends Window
## What the ground is like: the site's own conditions, and the conditions of each area of the plan.
##
## A `Window`, like the plant library, and for the same reason: `Root` is built focus-free so nothing
## in this HUD can take the drawing keys, and a window is the one boundary at which controls are
## allowed to hold the keyboard. This one has dropdowns in it, so it has to be that kind of thing.
##
## ## Why a window rather than the menu it replaced
##
## The Site menu used to offer four sets of radios - the site's light, moisture, soil and zone - which
## is enough to describe **one** place. That cannot describe a garden: the strip under the eaves is
## dry, the far corner is wet all spring, and the bed on the north side of the house never sees the
## sun. Those are all statements about *areas*, and a menu has nowhere to put them.
##
## So the site's four facts are here as dropdowns, and the plan's own areas are listed underneath,
## each one stating whatever it wants to. Nothing is inferred from the designer's choice: the list of
## areas is simply every piece of ground the drawing encloses (see `ZoneMap.AREAS`), and the designer
## decides which of them mean something.
##
## ## What it does not do
##
## It does not draw the areas of the plan itself: a bed, a lawn or the paving is drawn with the
## drafting tools, and then appears here. A **ground zone** is the one outline this window's subject
## owns rather than borrows - ground nothing on the plan encloses, like a frost pocket or a strip of
## shade - and that is drawn with the polygon tool from the Site menu, because a zone floating in a
## dialog could not be seen on the plan it describes.

const TerrainProfileScript := preload("res://scripts/terrain_profile.gd")
const ZoneMapScript := preload("res://scripts/zone_map.gd")
const GeomScript := preload("res://scripts/draft/geom2d.gd")

## The ground changed, or an area was stated or unstated: the borders and the Site menu are stale.

## The ground changed, or an area was stated or unstated: the borders and the Site menu are stale.
signal ground_changed()
## "Check the planting" was asked for. The HUD answers it, because the yard and the plant list are
## its to know about and this window only knows about the ground.
signal check_requested()
## The window was closed by its own close button.
signal closed()

## Big enough for everything in it at once. Measured rather than guessed: the first version was 640
## tall and the row with "Read the ground from the drawing" on it fell off the bottom edge, which is a
## button that exists and cannot be pressed.
const SIZE := Vector2i(760, 850)

## What the ground of an area falls back to, in words, for a line that has to name it.
const SITE_WORDS := "the site's own conditions"

## One label per attribute, in the order a person reads them, and the sets each offers.
##
## Drainage is here beside the rest because a *place* drains one way and a plant tolerates a set of
## ways: a boggy corner and a fast-draining bank in one garden are the whole reason a designer states
## conditions per area rather than once for the site.
const SETS: Array[String] = ["sun", "moisture", "soil", "drainage", "zone"]

var document: DraftDocument = null

var _site_rows: Dictionary[String, Dictionary] = {}
var _area_rows: Dictionary[String, Dictionary] = {}
var _areas: Array[Dictionary] = []
var _selected_key: String = ""
var _area_list: ItemList = null
var _area_status: Label = null
var _status: Label = null


func _init() -> void:
	title = "What the ground is like"
	min_size = SIZE
	exclusive = false
	close_requested.connect(_on_close_requested)


func _ready() -> void:
	if _area_list == null:
		build()


# --- building --------------------------------------------------------------------------------


## Build the whole window by hand. Idempotent, and callable off-tree so a test can drive the same
## controls the program shows. The HUD calls it before the window is ever shown, because a window
## that builds itself on its first `_ready` shows an empty frame for one frame.
func build() -> void:
	if _area_list != null:
		return
	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	column.add_child(_heading("The whole site"))
	var site := VBoxContainer.new()
	site.name = "Site"
	site.add_theme_constant_override("separation", 2)
	column.add_child(site)
	for key: String in SETS:
		var row: Dictionary = _attribute_row(key, "_on_site_changed")
		_site_rows[key] = row
		site.add_child(row["row"])
	column.add_child(_note(
		"A place nobody has stated is drawn grey rather than green: the plan has not said what the "
		+ "ground is like there, and a check that guessed would be inventing a garden."
	))

	column.add_child(_separator())
	column.add_child(_heading("Areas on the plan"))
	column.add_child(_note(
		"Every bed, lawn, paving and building the drawing encloses, and any ground zone you have "
		+ "drawn by hand. State what the ground is like in the ones that are not like the rest of "
		+ "the site."
	))

	_area_list = ItemList.new()
	_area_list.name = "Areas"
	_area_list.custom_minimum_size = Vector2(0, 150)
	_area_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_area_list.select_mode = ItemList.SELECT_SINGLE
	_area_list.item_selected.connect(_on_area_selected)
	column.add_child(_area_list)

	_area_status = Label.new()
	_area_status.name = "AreaStatus"
	_area_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_area_status.custom_minimum_size = Vector2(0, 34)
	column.add_child(_area_status)

	var area_editor := VBoxContainer.new()
	area_editor.name = "AreaEditor"
	area_editor.add_theme_constant_override("separation", 2)
	column.add_child(area_editor)
	for key: String in SETS:
		var row: Dictionary = _attribute_row(key, "_on_area_changed")
		_area_rows[key] = row
		area_editor.add_child(row["row"])

	var area_actions := HBoxContainer.new()
	area_actions.name = "AreaActions"
	area_actions.add_theme_constant_override("separation", 6)
	column.add_child(area_actions)
	area_actions.add_child(_button("State these conditions", "_on_state_area"))
	area_actions.add_child(_button("Take them back", "_on_clear_area"))

	column.add_child(_separator())
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 6)
	column.add_child(actions)
	actions.add_child(_button("Read the ground from the drawing", "_on_read_drawing"))
	actions.add_child(_button("Check the planting", "_on_check_planting"))

	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 44)
	column.add_child(_status)


func _heading(words: String) -> Label:
	var label := Label.new()
	label.name = "Heading%s" % words.replace(" ", "")
	label.text = words
	label.add_theme_font_size_override("font_size", 15)
	return label


func _note(words: String) -> Label:
	var label := Label.new()
	label.name = "Note%s" % str(words.hash())
	label.text = words
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color(0.75, 0.76, 0.78)
	label.add_theme_font_size_override("font_size", 11)
	return label


func _separator() -> HSeparator:
	var line := HSeparator.new()
	line.name = "Separator%d" % get_child_count()
	return line


func _button(words: String, method: String) -> Button:
	var button := Button.new()
	button.name = words.replace(" ", "")
	button.text = words
	button.pressed.connect(Callable(self, method))
	return button


## One attribute as a label, a dropdown and a unit word. The dropdown's item order **is** the order
## of `values_for`, because the option's index is what a choice is read back by.
func _attribute_row(key: String, method: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.name = "%sRow" % key.capitalize()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.name = "Label"
	label.text = String(TerrainProfileScript.KEY_LABELS.get(key, key))
	label.custom_minimum_size = Vector2(110, 0)
	row.add_child(label)
	var option := OptionButton.new()
	option.name = "Option"
	option.custom_minimum_size = Vector2(220, 0)
	for value: Variant in values_for(key):
		option.add_item(text_for(key, value))
	option.item_selected.connect(_on_option_chosen.bind(key, method))
	row.add_child(option)
	return {"row": row, "option": option}


# --- what each dropdown offers -----------------------------------------------------------


## Every value an attribute can be set to, **starting with "not stated"** - which is not padding: the
## truth about a plan nobody has described is that nobody has described it, and a dropdown with no way
## back to that would make the first choice a claim about the site that could never be withdrawn.
static func values_for(key: String) -> Array:
	if key == "sun":
		return [TerrainProfileScript.no_value(key)] + TerrainProfileScript.SUN_LEVELS.duplicate()
	if key == "moisture":
		return [TerrainProfileScript.no_value(key)] + TerrainProfileScript.MOISTURE_LEVELS.duplicate()
	if key == "soil":
		var soils: Array = [TerrainProfileScript.no_value(key)]
		soils.append_array(TerrainProfileScript.SOILS.keys())
		return soils
	if key == "drainage":
		var drains: Array = [TerrainProfileScript.no_value(key)]
		drains.append_array(TerrainProfileScript.DRAINAGE_NAMES.keys())
		return drains
	var zones: Array = [TerrainProfileScript.no_value(key)]
	zones.append_array(range(1, 14))
	return zones


## What a dropdown entry says for a value: "not stated" for the missing one, and the model's own
## words for everything else.
static func text_for(key: String, value: Variant) -> String:
	if not TerrainProfileScript.value_stated(key, value):
		return "not stated"
	if key == "soil":
		return String(TerrainProfileScript.SOILS.get(StringName(value), String(value)))
	if key == "zone":
		return "zone %d" % int(value)
	if key == "sun":
		return String(TerrainProfileScript.SUN_NAMES.get(int(value), str(value)))
	if key == "drainage":
		return String(TerrainProfileScript.DRAINAGE_NAMES.get(int(value), str(value)))
	return String(TerrainProfileScript.MOISTURE_NAMES.get(int(value), str(value)))


## Where a value sits in its dropdown, or -1 when it is not one of the offered values.
##
## A value of the wrong kind is **not** a value: a soil name is not a light level, and a light level is
## not a soil name. Comparing them by `int()` alone would read a nonsense value as whatever the zero
## sentinel happens to mean in that set - and for moisture, whose missing value is -1, that would be
## **low water**, which is a real condition to claim by accident.
static func index_of(key: String, value: Variant) -> int:
	var values: Array = values_for(key)
	var named: bool = key == "soil"
	var numeric: bool = value is int or value is float
	for index in values.size():
		var candidate: Variant = values[index]
		if named:
			if (value is String or value is StringName) and StringName(value) == StringName(candidate):
				return index
		elif numeric and int(candidate) == int(value):
			return index
	return -1


static func value_at(key: String, index: int) -> Variant:
	var values: Array = values_for(key)
	if index < 0 or index >= values.size():
		return TerrainProfileScript.no_value(key)
	return values[index]


# --- what it is showing ----------------------------------------------------------------------


## Read the document again: the site's conditions and the plan's areas. Called when the window is
## opened and after anything here changes the ground, so the two halves cannot disagree.
func refresh() -> void:
	if _area_list == null:
		return
	if document == null:
		_set_status("there is no drawing open, so there is no ground to describe")
		_area_list.clear()
		_areas.clear()
		for key: String in SETS:
			var option: OptionButton = _site_rows[key]["option"]
			option.select(0)
			option.disabled = true
		return
	var map: ZoneMap = document.environment
	for key: String in SETS:
		var option: OptionButton = _site_rows[key]["option"]
		option.disabled = false
		option.select(maxi(index_of(key, map.base.stated(key)), 0))
	# The areas the drawing encloses, then the ground zones somebody drew by hand - which have no
	# entity behind them, so they come from the map rather than from the document.
	var rows: Array[Dictionary] = ZoneMapScript.areas_of(document)
	rows.append_array(_hand_zone_rows(document, map))
	_areas = ZoneMapScript.describe_areas(rows, map)
	_fill_area_list()
	if _selected_key.is_empty() and not _areas.is_empty():
		_area_list.select(0)
		_on_area_selected(0)
	else:
		_show_area(_selected_key)
	_set_status(_describe_state(map))


## The ground zones somebody has drawn by hand, in draw order, as rows the area list can hold.
##
## A hand zone has no entity behind it, so it is not in `areas_of`: it comes from the map itself. It is
## told apart from an area of the plan by its key - both are keyed under `HAND_PREFIX`, but a hand
## zone's "layer" token is the literal `zone`, which is not one of the AREAS the plan encloses.
##
## The drawing comes in only so the area can be written in its units: a row carries the words, so
## nothing that lists areas has to know what a square metre is. It is named `drawing` rather than
## `document` because the window already has a `document` member and a parameter of that name
## shadows it - which GDScript warns about, and a warning in this project is a defect.
static func _hand_zone_rows(drawing: DraftDocument, map: ZoneMap) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if map == null:
		return out
	for zone: ZoneMapScript.Zone in map.zones:
		var source := String(zone.source)
		if not source.begins_with(ZoneMapScript.HAND_PREFIX):
			continue
		var rest := source.substr(ZoneMapScript.HAND_PREFIX.length())
		var hash_at := rest.find("#")
		if hash_at <= 0 or ZoneMapScript.AREAS.has(StringName(rest.substr(0, hash_at))):
			continue
		var outline: PackedVector2Array = zone.outline
		var area: float = absf(GeomScript.polygon_area(outline))
		out.append({
			"entity_id": 0,
			"layer": &"",
			"key": source,
			"label": "zone",
			"name": zone.name if not zone.name.is_empty() else "zone",
			"outline": outline,
			"area_m2": area,
			"area_text": ZoneMapScript.area_words(drawing, area),
		})
	return out


## The list of areas, with what is already known about each one beside it.
func _fill_area_list() -> void:
	_area_list.clear()
	for row: Dictionary in _areas:
		_area_list.add_item("%s   %s   %s" % [
			String(row["name"]), ZoneMapScript.row_area_text(row), _area_note(row)
		])
		_area_list.set_item_metadata(_area_list.item_count - 1, String(row["key"]))


## What is known about one area, for the list: **what the area states**, or what answers for it and
## where that came from. One column, so never both at once - the line under the list is where the two
## are put side by side.
##
## A stated area reports the statement and not the effect, because "stated: full shade, low water" for
## a bed that was only ever called dry would read as though somebody had claimed the shade on its
## behalf.
func _area_note(row: Dictionary) -> String:
	if bool(row.get("stated", false)):
		return "stated: %s" % (row["stated_profile"] as TerrainProfile).describe()
	var source: String = String(row.get("source", ""))
	var profile: TerrainProfile = row["profile"]
	if profile.is_empty():
		return "nothing stated"
	return "%s (%s)" % [profile.describe(), _source_words(source)]


## The selected area in full: what it states by hand and what that comes to, which are two different
## answers and the second is the one a designer came for.
func _area_detail(row: Dictionary) -> String:
	var stated: TerrainProfile = row.get("stated_profile", TerrainProfile.make())
	var effect: TerrainProfile = row["profile"]
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%s   %s" % [String(row["name"]), ZoneMapScript.row_area_text(row)])
	parts.append("states %s" % (stated.describe() if not stated.is_empty() else "nothing itself"))
	if effect.is_empty():
		parts.append("and nothing is known about the ground here yet")
	else:
		parts.append("so the ground here is %s (%s)" % [
			effect.describe(), _source_words(String(row.get("source", "")))
		])
	return "|  ".join(parts)


## Where a condition came from, in words. A derived zone says so: a verdict read off the drawing is
## an inference, and presenting it as somebody's statement would be the software claiming credit for
## a guess.
static func _source_words(source: String) -> String:
	if source.begins_with("layer:"):
		return "read from the drawing"
	if source.begins_with(ZoneMapScript.HAND_PREFIX):
		return "stated by hand"
	return SITE_WORDS


func _describe_state(map: ZoneMap) -> String:
	var areas := 0
	for row: Dictionary in _areas:
		if bool(row.get("stated", false)):
			areas += 1
	if map.base.is_empty() and map.zones.is_empty():
		if _areas.is_empty():
			return "Nothing is stated about the ground yet, so every plant is drawn grey - and there is no area on the plan to state it for either: draw a bed, a lawn or the paving with the drafting tools and it will appear above. The site's own conditions can be set here."
		return "Nothing is stated about the ground yet, so every plant is drawn grey. State the site's conditions above, state an area, or read what the drawing already implies."
	if _areas.is_empty():
		return "%s. Nothing on the plan encloses ground yet." % map.describe()
	return "%s. %d area%s stated by hand." % [
		map.describe(), areas, "" if areas == 1 else "s"
	]


func _selected_area() -> Dictionary:
	for row: Dictionary in _areas:
		if String(row["key"]) == _selected_key:
			return row
	return {}


func _show_area(key: String) -> void:
	_selected_key = key
	var row: Dictionary = _selected_area()
	if row.is_empty():
		for attribute: String in SETS:
			var option: OptionButton = _area_rows[attribute]["option"]
			option.select(0)
			option.disabled = true
		_area_status.text = "No area of the plan is selected."
		return
	# The boxes show **what the area itself states**, not the effect of the site's conditions on it: a
	# box pre-filled with an inherited value would store the whole site's conditions on the area the
	# moment somebody changed one of them, and the area would stop following the site it sits in.
	var stated: TerrainProfile = row.get("stated_profile", TerrainProfile.make())
	for attribute: String in SETS:
		var option: OptionButton = _area_rows[attribute]["option"]
		option.disabled = false
		option.select(maxi(index_of(attribute, stated.stated(attribute)), 0))
	_area_status.text = _area_detail(row)


func _set_status(words: String) -> void:
	if _status != null:
		_status.text = words


func status_text() -> String:
	return _status.text if _status != null else ""


## What the selected area's line says: what it is, how big it is, and what answers for it.
func area_status_text() -> String:
	return _area_status.text if _area_status != null else ""


func area_list_texts() -> Array[String]:
	var out: Array[String] = []
	if _area_list == null:
		return out
	for index in _area_list.item_count:
		out.append(_area_list.get_item_text(index))
	return out


func selected_key() -> String:
	return _selected_key


func area_count() -> int:
	return _areas.size()


# --- what it does ------------------------------------------------------------------------------


## The site's own conditions, as the dropdowns show them.
func site_choice() -> TerrainProfile:
	var profile: TerrainProfile = TerrainProfile.make()
	for key: String in SETS:
		var option: OptionButton = _site_rows[key]["option"]
		profile.with_stated(key, value_at(key, option.selected))
	return profile


## The conditions of the selected area, as its dropdowns show them.
func area_choice() -> TerrainProfile:
	var profile: TerrainProfile = TerrainProfile.make()
	for key: String in SETS:
		var option: OptionButton = _area_rows[key]["option"]
		profile.with_stated(key, value_at(key, option.selected))
	return profile


func _on_option_chosen(_index: int, key: String, method: String) -> void:
	callv(method, [key])


func _on_site_changed(_key: String) -> void:
	if document == null:
		return
	var map: ZoneMap = document.environment.copy()
	map.base = site_choice()
	if document.set_environment(map):
		ground_changed.emit()
	refresh()


## An area's dropdown was changed. **Nothing is stated yet**, and that is the design: the site's
## conditions are one statement each and apply as they are chosen, while an area's four attributes are
## set and then committed together by the button below them - one commit is one undo step, rather than
## four, and a designer changing their mind about the light does not put three zones in the history.
##
## What this does is say what is about to be stated, so the line above the boxes is never stale.
## An area's dropdown was changed: state it now, the same way the site's conditions are stated.
##
## Applied as they are chosen rather than held back until a button is pressed, because the ground a
## designer is describing is the ground they are looking at, and a "chosen but not yet stated"
## half-state is a state nobody asked for. Choosing "not stated" for the last stated attribute is
## **not** a statement that says nothing: it is no statement at all, and the area goes back to
## following the site it sits in.
func _on_area_changed(_key: String) -> void:
	var row: Dictionary = _selected_area()
	if row.is_empty():
		return
	var choice: TerrainProfile = area_choice()
	if choice.is_empty():
		if _clear_statement(row):
			ground_changed.emit()
		refresh()
		_set_status("%s follows %s again." % [String(row["name"]), SITE_WORDS])
		return
	_state_choice(row, choice)
	refresh()
	_set_status("%s is stated as %s." % [String(row["name"]), choice.describe()])


## State conditions for the selected area, which is what the dropdowns have already done - this is the
## button that says "yes, that one", and it is honest about the case where nothing is chosen.
##
## The conditions are held **in addition to** whatever the map already says about that ground: a zone
## states only what it changes (see `TerrainProfile.merged_over`), so stating "dry" about a bed does
## not also claim to know its light. And it is keyed by the area, so stating one twice edits it.
func _on_state_area() -> void:
	if document == null:
		return
	var row: Dictionary = _selected_area()
	if row.is_empty():
		_set_status("Choose an area of the plan first.")
		return
	var choice: TerrainProfile = area_choice()
	if choice.is_empty():
		_set_status(
			"%s states nothing yet: choose one of the conditions above, or take the area back."
			% String(row["name"])
		)
		return
	_state_choice(row, choice)
	refresh()
	_set_status("Stated: %s is %s." % [String(row["name"]), choice.describe()])


## Put a statement on one area. One undo step, through the document, like everything else here.
func _state_choice(row: Dictionary, choice: TerrainProfile) -> bool:
	var map: ZoneMap = document.environment.copy()
	map.state_zone(
		String(row["key"]), String(row["name"]), row["outline"] as PackedVector2Array, choice
	)
	if not document.set_environment(map):
		return false
	ground_changed.emit()
	return true


## Take a hand-stated area back, so the site's own conditions answer for it again. Answers whether
## there was anything to take back.
func _clear_statement(row: Dictionary) -> bool:
	var map: ZoneMap = document.environment.copy()
	var zone: ZoneMapScript.Zone = map.zone_by_source(String(row["key"]))
	if zone == null:
		return false
	map.zones.erase(zone)
	if not document.set_environment(map):
		return false
	ground_changed.emit()
	return true


## Take a hand-stated area back, which is the same act as choosing "not stated" for everything.
func _on_clear_area() -> void:
	if document == null:
		return
	var row: Dictionary = _selected_area()
	if row.is_empty():
		_set_status("Choose an area of the plan first.")
		return
	if not _clear_statement(row):
		_set_status("%s has nothing stated by hand to take back." % String(row["name"]))
		return
	refresh()
	_set_status("%s is back to %s." % [String(row["name"]), document.environment.describe()])


func _on_read_drawing() -> void:
	if document == null:
		return
	var read: int = document.read_environment_from_drawing()
	ground_changed.emit()
	refresh()
	if read <= 0:
		_set_status(
			"The drawing has no buildings or hard surfaces on it, so it says nothing about the ground. "
			+ "It cannot say anything about shade, soil or the fall of the land: those are site visits."
		)
		return
	_set_status("Read %d area%s of ground from the drawing." % [read, "" if read == 1 else "s"])


func _on_check_planting() -> void:
	check_requested.emit()


func _on_area_selected(index: int) -> void:
	_show_area(String(_area_list.get_item_metadata(index)))


func _on_close_requested() -> void:
	hide()
	closed.emit()


# --- what a test needs, without a window on screen ---------------------------------------------


## Choose a value on one of the site's dropdowns, the way a click would.
func choose_site(key: String, value: Variant) -> bool:
	if not _site_rows.has(key):
		return false
	var option: OptionButton = _site_rows[key]["option"]
	var index: int = index_of(key, value)
	if index < 0:
		return false
	option.select(index)
	_on_site_changed(key)
	return true


## Choose a value on the selected area's dropdowns, the way a click does - which states it.
func choose_area(key: String, value: Variant) -> bool:
	if not _area_rows.has(key):
		return false
	var option: OptionButton = _area_rows[key]["option"]
	var index: int = index_of(key, value)
	if index < 0:
		return false
	option.select(index)
	_on_area_changed(key)
	return true


## Select an area by name, the way clicking its row would.
func select_area_by_name(wanted: String) -> bool:
	for index in _areas.size():
		if String(_areas[index]["name"]) == wanted:
			_area_list.select(index)
			_on_area_selected(index)
			return true
	return false


func apply_area() -> void:
	_on_state_area()


func clear_area() -> void:
	_on_clear_area()


func read_drawing() -> void:
	_on_read_drawing()