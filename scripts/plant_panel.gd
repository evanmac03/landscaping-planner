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
const LIST_HEIGHT := 150


var _header: HBoxContainer = null
var _library_button: Button = null
var _tag_row: HBoxContainer = null
var _tag_option: OptionButton = null
var _list: ItemList = null
var _status: Label = null
var _actions: HBoxContainer = null
var _place_button: Button = null
var _stop_button: Button = null

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

	_sync_tag_choices()
	_rebuild_list()
	_refresh_detail()


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
	# What is in hand is shown as chosen, so the panel always says what a click would plant.
	if not _planting.is_empty():
		select(_planting)
	_status.text = status_text()


func status_text() -> String:
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


func library_label() -> String:
	return _library_button.text if _library_button != null else ""


func list_is_keyboard_free() -> bool:
	if _list == null or _tag_option == null or _place_button == null or _stop_button == null:
		return false
	return _list.focus_mode == Control.FOCUS_NONE \
		and _tag_option.focus_mode == Control.FOCUS_NONE \
		and _place_button.focus_mode == Control.FOCUS_NONE \
		and _stop_button.focus_mode == Control.FOCUS_NONE