class_name PlantPanel
extends VBoxContainer
## The plants section of the left palette: the catalogue in reach without a window, a menu or a key.
##
## The library (`PlantBrowser`) is where a catalogue of four thousand species is *searched* - it has
## the one box, the filters, the photographs and the detail pane. This is the other half of that, and
## the reason it exists is reach: a designer planting a bed puts down a dozen of one plant, and going
## through a modal window and a drop-down for every one of them is the sort of thing that makes a
## tool feel slow. Here the plants are simply *there*, beside the drawing tools, and choosing one is
## one click.
##
## It is a plain panel and not a `Window`, so it is built with one rule the browser does not have:
## **nothing in it may hold the keyboard**. The list is `FOCUS_NONE` and so is everything else, which
## is what keeps the arrow keys and the number keys with the drawing. That is also why there is no
## search box here: a text field in this HUD would take the keyboard away from the design, and the
## panel is for *reaching* plants rather than for searching four thousand of them.
##
## Built in code, like the palette and the menu bar, from tables that already exist: the tags in the
## catalogue, the pictures in `PlantIcons`. It owns no design state - it says what was chosen and the
## HUD does the planting.

signal plant_chosen(species_id: StringName)
signal library_requested()
signal stop_requested()
## A bed to fill with the chosen plant. The panel works out none of it: the spacing and the arrangement
## are what its own controls say, and the outline belongs to the drawing.
signal fill_requested(bed_key: String, spacing: float, arrangement: String)

const SpacingScript := preload("res://scripts/plant_spacing.gd")

## How many species the list will show. A palette is a quick picker, not a browser: a person who
## needs the four-thousandth plant wants the library's search box, and a list of four thousand rows
## inside a palette would be slower to use than the window it is trying to save you from. The status
## line says so when it happens rather than pretending the list is the catalogue.
##
## The bound is set high enough that the whole shipped starter list - and a designer's own working
## catalogue - is reachable here without the library: a palette that can only reach the plants whose
## names happen to start with A is not a quick picker, it is a trap. The list scrolls, and the tag
## drop-down narrows it, so a long list costs nothing but a scroll.
const MAX_LISTED := 250

const ICON_SIZE := 26
const LIST_HEIGHT := 110


var _header: HBoxContainer = null
var _library_button: Button = null
var _tag_row: HBoxContainer = null
var _tag_option: OptionButton = null
var _list: ItemList = null
var _status: Label = null
var _actions: HBoxContainer = null
var _place_button: Button = null
var _stop_button: Button = null
## Filling a bed rather than planting it a click at a time: how far apart, how the rows are set, and
## which bed of the drawing.
var _fill_row: HBoxContainer = null
var _spacing_option: OptionButton = null
var _arrangement_option: OptionButton = null
var _bed_row: HBoxContainer = null
var _bed_option: OptionButton = null
var _fill_button: Button = null
## The beds the drawing encloses, in the rows `PlantSpacing.bed_areas` returns them, and the key of the
## one the drop-down is on. Held rather than looked up when the button is pressed, so the bed filled is
## the bed named in the drop-down.
var _beds: Array[Dictionary] = []
var _beds_signature: String = ""
var _bed_key: String = ""
## The last thing this panel did, shown beside the plant count until something newer happens. A report
## written into the plan's own status line would be wiped by the planting verdict a frame later, and a
## line nobody can read is not a message.
var _said: String = ""

var catalogue: PlantCatalogue = null
var _built: bool = false
## The tag the list is narrowed to, or "" for all of them.
var _tag: String = ""
## The species the list is currently showing, in the order it shows them.
var _species: Array[PlantSpecies] = []
## What the list was built from, so a refresh that changes nothing does not rebuild it.
var _list_signature: String = ""
var _planting: StringName = &""
var _planted: int = 0
var _capped: bool = false


## Build the section. Called once by the HUD, and callable directly so a test can build a panel with
## no scene tree - a bare `PlantPanel.new()` never gets `_ready`.
func build(library_words: String = "Library...") -> void:
	if _built:
		return
	_built = true
	# The palette this goes in carries its own background and margins; this is a section of it.
	add_theme_constant_override("separation", 5)
	add_child(HSeparator.new())

	_header = HBoxContainer.new()
	_header.name = "Header"
	add_child(_header)
	var caption := Label.new()
	caption.name = "PlantsCaption"
	caption.text = "Plants"
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_header.add_child(caption)
	_library_button = Button.new()
	_library_button.name = "LibraryButton"
	_library_button.text = library_words
	_library_button.tooltip_text = "Search the whole catalogue, with filters and detail"
	_library_button.focus_mode = Control.FOCUS_NONE
	_library_button.pressed.connect(func() -> void: library_requested.emit())
	_header.add_child(_library_button)

	_tag_row = HBoxContainer.new()
	_tag_row.name = "TagRow"
	add_child(_tag_row)
	var tag_caption := Label.new()
	tag_caption.name = "TagCaption"
	tag_caption.text = "Tag"
	tag_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tag_row.add_child(tag_caption)
	_tag_option = OptionButton.new()
	_tag_option.name = "TagOption"
	_tag_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tag_option.focus_mode = Control.FOCUS_NONE
	_tag_option.tooltip_text = "Narrow the list to one tag"
	_tag_option.item_selected.connect(_on_tag_selected)
	_tag_row.add_child(_tag_option)

	_list = ItemList.new()
	_list.name = "Species"
	_list.icon_mode = ItemList.ICON_MODE_LEFT
	_list.fixed_icon_size = Vector2i(ICON_SIZE, ICON_SIZE)
	_list.custom_minimum_size = Vector2(0.0, float(LIST_HEIGHT))
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.select_mode = ItemList.SELECT_SINGLE
	_list.allow_reselect = true
	# Incremental search is letter keys, and letter keys belong to the drawing.
	_list.allow_search = false
	# The one rule this panel has that the browser does not: nothing in the HUD holds the keyboard.
	_list.focus_mode = Control.FOCUS_NONE
	_list.item_selected.connect(_on_row_selected)
	_list.item_activated.connect(_on_row_activated)
	add_child(_list)

	_status = Label.new()
	_status.name = "Status"
	_status.add_theme_font_size_override("font_size", 12)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	_actions = HBoxContainer.new()
	_actions.name = "Actions"
	add_child(_actions)
	_place_button = _action_button(_actions, "Place", false)
	_place_button.tooltip_text = "Put the chosen plant in hand, then click the plan"
	_place_button.pressed.connect(place_selected)
	_stop_button = _action_button(_actions, "Stop", true)
	_stop_button.tooltip_text = "Put the plant away, so a click on the plan is a click on the plan"
	_stop_button.pressed.connect(func() -> void: stop_requested.emit())

	_build_fill_rows()

	_sync_tag_choices()
	_rebuild_list()
	_refresh_detail()


## The controls that plant a whole bed: how far apart the plants stand, how the rows are set, and which
## bed of the drawing they go in.
##
## These are here rather than in the library because a fill is what a designer reaches for while
## laying out a bed, and the library is a modal window with a search box in it - the one thing this
## palette may not have, and the one thing a fill does not need. Every control is `FOCUS_NONE` like the
## rest of the panel, because the number keys and the arrow keys belong to the drawing.
func _build_fill_rows() -> void:
	_fill_row = HBoxContainer.new()
	_fill_row.name = "FillRow"
	add_child(_fill_row)
	var spacing_caption := Label.new()
	spacing_caption.name = "SpacingCaption"
	spacing_caption.text = "Spacing"
	spacing_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_fill_row.add_child(spacing_caption)
	_spacing_option = OptionButton.new()
	_spacing_option.name = "SpacingOption"
	_spacing_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spacing_option.focus_mode = Control.FOCUS_NONE
	_spacing_option.tooltip_text = "How far apart the plants stand. The first choice is the plant's own spread, so they just touch."
	_fill_row.add_child(_spacing_option)
	# The first choice is the species' own spread: the answer a nursery means by "at the recommended
	# spacing", and the one that needs no thought. Zero is how that is spelled, because the spread is a
	# property of the plant and not of this list.
	for metres: float in SpacingScript.spacing_choices_m():
		_spacing_option.add_item("Its spread" if metres <= 0.0 else SpacingScript.spacing_words(metres))
		_spacing_option.set_item_metadata(_spacing_option.item_count - 1, metres)

	var arrangement_caption := Label.new()
	arrangement_caption.name = "ArrangementCaption"
	arrangement_caption.text = "Rows"
	arrangement_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_fill_row.add_child(arrangement_caption)
	_arrangement_option = OptionButton.new()
	_arrangement_option.name = "ArrangementOption"
	_arrangement_option.focus_mode = Control.FOCUS_NONE
	_arrangement_option.tooltip_text = "Square rows and columns, or staggered rows, which fit more plants into the same ground."
	_fill_row.add_child(_arrangement_option)
	for arrangement: String in SpacingScript.ARRANGEMENTS:
		_arrangement_option.add_item(SpacingScript.arrangement_words(arrangement))
		_arrangement_option.set_item_metadata(
			_arrangement_option.item_count - 1, arrangement
		)
	# Staggered, because that is what a planting plan draws. Square is the arrangement for a hedge or a
	# grid of paving, which is a different job.
	_arrangement_option.selected = SpacingScript.ARRANGEMENTS.find(SpacingScript.TRIANGULAR)

	_bed_row = HBoxContainer.new()
	_bed_row.name = "BedRow"
	add_child(_bed_row)
	var bed_caption := Label.new()
	bed_caption.name = "BedCaption"
	bed_caption.text = "Bed"
	bed_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bed_row.add_child(bed_caption)
	_bed_option = OptionButton.new()
	_bed_option.name = "BedOption"
	_bed_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bed_option.focus_mode = Control.FOCUS_NONE
	_bed_option.tooltip_text = "The beds the drawing encloses. Nothing here draws a new one."
	_bed_option.item_selected.connect(_on_bed_selected)
	_bed_row.add_child(_bed_option)

	_fill_button = Button.new()
	_fill_button.name = "FillButton"
	_fill_button.text = "Fill the bed"
	_fill_button.focus_mode = Control.FOCUS_NONE
	_fill_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill_button.pressed.connect(fill_selected)
	add_child(_fill_button)


## One of the two buttons under the list. Named rather than numbered, so a test can find it and so
## the focus rule is applied in one place rather than remembered twice.
func _action_button(row: HBoxContainer, words: String, secondary: bool) -> Button:
	var button := Button.new()
	button.name = words + "Button"
	button.text = words
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if secondary:
		button.size_flags_stretch_ratio = 0.6
	row.add_child(button)
	return button


func _ready() -> void:
	build()


func bind(new_catalogue: PlantCatalogue) -> void:
	build()
	catalogue = new_catalogue
	_tag = ""
	_list_signature = ""
	_sync_tag_choices()
	_rebuild_list()
	_refresh_detail()


# --- what it shows -------------------------------------------------------------------------


## The tag choices, kept in step with the catalogue rather than built once and trusted: a person's
## catalogue can be replaced by an import, and a tag that is no longer there must not stay in the
## list as a filter that finds nothing.
func _sync_tag_choices() -> void:
	# Built explicitly rather than as a ternary: a ternary with a bare `[]` in it loses the element
	# type, and the tag list is a list of strings.
	var wanted: Array[String] = []
	if catalogue != null:
		wanted = catalogue.tag_names()
	var offered: Array[String] = []
	for index in range(1, _tag_option.item_count):
		offered.append(String(_tag_option.get_item_metadata(index)))
	if offered == wanted:
		return
	_tag_option.clear()
	_tag_option.add_item("Any tag")
	_tag_option.set_item_metadata(0, "")
	var counts: Dictionary = catalogue.tag_counts() if catalogue != null else {}
	for tag_name: String in wanted:
		_tag_option.add_item("%s (%d)" % [tag_name, int(counts.get(tag_name, 0))])
		_tag_option.set_item_metadata(_tag_option.item_count - 1, tag_name)
	# A filter whose tag is gone falls back to every plant rather than to an empty list, so a
	# catalogue replaced by an import cannot leave the panel showing nothing for no reason.
	if not wanted.has(_tag):
		_tag = ""
	_tag_option.selected = 0
	for index in _tag_option.item_count:
		if String(_tag_option.get_item_metadata(index)) == _tag:
			_tag_option.selected = index
	_list_signature = ""


func _on_tag_selected(index: int) -> void:
	set_tag_filter(String(_tag_option.get_item_metadata(index)))


## Narrow the list to one tag, or to all of them with "". The door a test and a caller use; the
## drop-down is one way in and not the only one.
func set_tag_filter(tag_name: String) -> bool:
	build()
	if catalogue != null and not tag_name.is_empty() and not catalogue.tag_names().has(tag_name):
		return false
	for index in _tag_option.item_count:
		if String(_tag_option.get_item_metadata(index)) == tag_name:
			_tag_option.selected = index
			_tag = tag_name
			_list_signature = ""
			if catalogue != null:
				_rebuild_list()
				_refresh_detail()
			return true
	return false


func tag_filter() -> String:
	return _tag


func _rebuild_list() -> void:
	_list.clear()
	_species.clear()
	_capped = false
	if catalogue == null:
		return
	var found: Array[PlantSpecies] = catalogue.tagged(_tag) if not _tag.is_empty() else catalogue.all()
	# By common name, because this is the list a designer picks from rather than the one a nursery
	# sends: "Red maple" is what somebody is looking for, and "Acer rubrum" is what they check.
	found = PlantCatalogue.sort_species(found, "common")
	_capped = found.size() > MAX_LISTED
	for index in mini(found.size(), MAX_LISTED):
		_species.append(found[index])
	for plant: PlantSpecies in _species:
		var cell: int = _list.add_item(_row_title(plant), PlantIcons.textured(catalogue, plant.id))
		_list.set_item_metadata(cell, String(plant.id))
		_list.set_item_tooltip(cell, plant.display_name())
		# Shape from the form, colour from the species: the same rule the browser's grid uses, so the
		# two cannot show one plant two ways.
		_list.set_item_icon_modulate(cell, PlantIcons.tint(plant))


## What a row says: what a person calls the plant.
func _row_title(species: PlantSpecies) -> String:
	if not species.common_name.strip_edges().is_empty():
		return species.common_name
	return species.botanical_name


func _on_row_selected(_index: int) -> void:
	_refresh_detail()


## A double click is a choice and a placement in one: the second click of a double click is not a
## click on the plan, so it means "this one" rather than "put one down here".
func _on_row_activated(_index: int) -> void:
	place_selected()


# --- what it says, and what it does ---------------------------------------------------------


## How many of the catalogue are standing, and what a click on the plan would put down. Cheap: the
## list is only rebuilt when the catalogue or the tag has changed, so this can be called every frame.
func refresh(planting: StringName = &"", planted: int = 0) -> void:
	build()
	# A different plant in hand is a new act, and the report of the last one is not news any more. A
	# plant *count* changing is not: a fill reports itself, and the count is part of what it just said.
	if planting != _planting:
		_said = ""
	_planting = planting
	_planted = planted
	_sync_tag_choices()
	var signature: String = "%s|%d|%s" % [
		_tag, catalogue.count() if catalogue != null else -1, catalogue.source if catalogue != null else ""
	]
	if signature != _list_signature:
		_list_signature = signature
		_rebuild_list()
	_refresh_detail()


func _refresh_detail() -> void:
	if _place_button == null:
		return
	# A button that cannot be used says so rather than doing nothing quietly. There is no transient
	# message to read here: this panel is redrawn every frame, so a line written once would flicker
	# for a frame and be gone.
	_place_button.disabled = selected_species() == null
	_place_button.tooltip_text = "Choose a plant first" if _place_button.disabled \
		else "Put the chosen plant in hand, then click the plan"
	_stop_button.disabled = _planting.is_empty()
	# A fill needs both halves: a plant to plant and a bed to put it in. Whichever is missing is named
	# in the tooltip, because "Fill the bed" greyed out with no explanation is a dead end.
	var species: PlantSpecies = selected_species()
	_fill_button.disabled = species == null or _bed_key.is_empty()
	if species == null:
		_fill_button.tooltip_text = "Choose a plant first, then fill a bed with it"
	elif _bed_key.is_empty():
		_fill_button.tooltip_text = "The drawing encloses no bed yet: draw one on a bed layer, or state the ground for one"
	else:
		_fill_button.tooltip_text = "Plant %s through %s at %s, %s" % [
			_row_title(species), SpacingScript.bed_words(selected_bed()),
			"Its own spread" if spacing_choice() <= 0.0 else SpacingScript.spacing_words(spacing_choice()),
			SpacingScript.arrangement_words(arrangement_choice()).to_lower(),
		]
	# What is in hand is shown as chosen, so the panel always says what a click would plant.
	if not _planting.is_empty():
		select(_planting)
	_status.text = status_text()


func status_text() -> String:
	# What just happened comes first: after a fill the number a person wants is how many plants went
	# in, and the count of species in the catalogue can wait until they have read it.
	if not _said.is_empty():
		return _said
	if catalogue == null:
		return "No plant list open."
	if not _planting.is_empty():
		var species: PlantSpecies = catalogue.get_species(_planting)
		if species != null:
			return "Planting %s. %d standing. Escape puts it away." % [
				_row_title(species), _planted
			]
	var total: int = catalogue.count()
	if _capped:
		return "Showing the first %d of %d. Open the library to search." % [_species.size(), total]
	if _species.size() < total:
		return "%d of %d species." % [_species.size(), total]
	return "%d species." % total


func listed_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for plant: PlantSpecies in _species:
		out.append(plant.id)
	return out


func selected_id() -> StringName:
	var rows: PackedInt32Array = _list.get_selected_items()
	if rows.is_empty():
		return &""
	var row: int = rows[0]
	if row < 0 or row >= _list.item_count:
		return &""
	return StringName(_list.get_item_metadata(row))


func selected_species() -> PlantSpecies:
	if catalogue == null:
		return null
	return catalogue.get_species(selected_id())


## Choose a species, if it is on the list. Returns false when it is not, rather than choosing
## something else: a panel that answers a question about one plant with another is worse than one
## that says no.
func select(species_id: StringName) -> bool:
	build()
	for row in _list.item_count:
		if StringName(_list.get_item_metadata(row)) == species_id:
			if selected_id() != species_id:
				_list.select(row, true)
				_refresh_detail()
			return true
	return false


## What the one button under the list does: this is the whole point of the panel. The panel does not
## plant - it has no yard and no plan - it says which species and the HUD does the rest. Refusing is
## what a disabled button cannot say for itself, so this is the same question asked twice.
func place_selected() -> bool:
	var species: PlantSpecies = selected_species()
	if species == null:
		return false
	plant_chosen.emit(species.id)
	return true


func status_label() -> Label:
	return _status


# --- filling a bed ---------------------------------------------------------------------------


func _on_bed_selected(index: int) -> void:
	if index < 0 or index >= _bed_option.item_count:
		return
	_bed_key = String(_bed_option.get_item_metadata(index))
	_refresh_detail()


## The beds the drawing encloses, as `PlantSpacing.bed_areas` returns them.
##
## Called every refresh and does nothing unless the list has changed, because a bed is drawn, moved and
## deleted with the drawing tools: a list built once would offer beds that are no longer there. Where
## the signature is the same the choice is left alone, so drawing a line in the next bed along does not
## move the drop-down out from under somebody.
func set_beds(rows: Array[Dictionary]) -> bool:
	build()
	var keys: Array[String] = []
	for row: Dictionary in rows:
		keys.append(String(row.get("key", "")))
	var signature := "|".join(keys)
	if signature == _beds_signature:
		return false
	_beds_signature = signature
	_beds = rows.duplicate()
	_bed_option.clear()
	var keep := -1
	for index in _beds.size():
		_bed_option.add_item(SpacingScript.bed_words(_beds[index]))
		_bed_option.set_item_metadata(index, String(_beds[index]["key"]))
		if String(_beds[index]["key"]) == _bed_key:
			keep = index
	if _beds.is_empty():
		# Nothing to fill, and the button says so rather than doing nothing when it is pressed.
		_bed_key = ""
	else:
		var chosen: int = maxi(keep, 0)
		_bed_key = String(_beds[chosen]["key"])
		_bed_option.selected = chosen
	_refresh_detail()
	return true


func beds() -> Array[Dictionary]:
	return _beds


func selected_bed_key() -> String:
	return _bed_key


## The bed the drop-down is on, or an empty dictionary when the drawing encloses none.
func selected_bed() -> Dictionary:
	for row: Dictionary in _beds:
		if String(row.get("key", "")) == _bed_key:
			return row
	return {}


## How far apart the plants will stand, in metres. Zero means the species' own spread, which is a
## question only the plant can answer.
func spacing_choice() -> float:
	if _spacing_option == null or _spacing_option.item_count == 0:
		return 0.0
	var index: int = maxi(_spacing_option.selected, 0)
	return float(_spacing_option.get_item_metadata(index))


func arrangement_choice() -> String:
	if _arrangement_option == null or _arrangement_option.item_count == 0:
		return SpacingScript.SQUARE
	var index: int = maxi(_arrangement_option.selected, 0)
	return String(_arrangement_option.get_item_metadata(index))


## Choose a spacing by value, which is how a caller or a test sets one without knowing its row. Zero
## means the species' own spread.
func set_spacing_choice(metres: float) -> bool:
	build()
	for index in _spacing_option.item_count:
		if absf(float(_spacing_option.get_item_metadata(index)) - metres) < 1e-6:
			_spacing_option.selected = index
			_refresh_detail()
			return true
	return false


func set_arrangement_choice(arrangement: String) -> bool:
	build()
	for index in _arrangement_option.item_count:
		if String(_arrangement_option.get_item_metadata(index)) == arrangement:
			_arrangement_option.selected = index
			_refresh_detail()
			return true
	return false


## Fill the chosen bed with the chosen plant. The panel plants nothing itself - it has no yard and no
## drawing - so this says what was asked for and the HUD does it.
func fill_selected() -> bool:
	if selected_species() == null or _bed_key.is_empty():
		return false
	fill_requested.emit(_bed_key, spacing_choice(), arrangement_choice())
	return true


## Say what just happened. The panel's status line is recomputed every frame, so this is a *field* and
## not a label write: a transient line set once would flicker for a frame and be gone, which is the
## same reason the disabled buttons explain themselves in their tooltips.
func say(text: String) -> void:
	build()
	_said = text
	_refresh_detail()


func said() -> String:
	return _said


func library_label() -> String:
	return _library_button.text if _library_button != null else ""


## The one rule this panel has that the browser does not, checked in one place: every control that can
## take the keyboard, including the ones that fill a bed.
func list_is_keyboard_free() -> bool:
	if _list == null or _tag_option == null or _place_button == null or _stop_button == null:
		return false
	if _spacing_option == null or _arrangement_option == null \
			or _bed_option == null or _fill_button == null:
		return false
	return _list.focus_mode == Control.FOCUS_NONE \
		and _tag_option.focus_mode == Control.FOCUS_NONE \
		and _place_button.focus_mode == Control.FOCUS_NONE \
		and _stop_button.focus_mode == Control.FOCUS_NONE \
		and _spacing_option.focus_mode == Control.FOCUS_NONE \
		and _arrangement_option.focus_mode == Control.FOCUS_NONE \
		and _bed_option.focus_mode == Control.FOCUS_NONE \
		and _fill_button.focus_mode == Control.FOCUS_NONE