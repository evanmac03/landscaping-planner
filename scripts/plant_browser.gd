class_name PlantBrowser
extends Control
## The plant browser: the catalogue as something a designer looks through.
##
## Built in code rather than in a scene, for the same reason the palette and the menu bar are: every
## control in it is derived from a table that already exists - the categories, the sun bits, the
## water needs, the zones, the months, the tags in the catalogue and the collections a person has
## made - and a scene file holding a copy of those would be a second place for them to live, one
## that no test can hold against the first. The one exception is the node tree itself, which is here
## where you can read it:
##
##     PlantBrowser                 (Control, fills its window)
##     └ Margin                     (MarginContainer)
##       └ Column                   (VBoxContainer)
##         ├ Search                 (HBoxContainer)
##         │  ├ Query               (LineEdit - the one box)
##         │  ├ Sort                (OptionButton)
##         │  ├ Category            (OptionButton)
##         │  ├ Light               (OptionButton)
##         │  ├ Water               (OptionButton)
##         │  ├ Zone                (OptionButton)
##         │  ├ Bloom               (OptionButton)
##         │  └ Collection          (OptionButton)
##         ├ Tags                   (HFlowContainer of CheckBoxes, one per tag in the catalogue)
##         ├ Body                   (HSplitContainer)
##         │  ├ Grid                (ItemList, ICON_MODE_TOP: the thumbnails)
##         │  └ Detail              (ScrollContainer)
##         │     └ DetailColumn     (VBoxContainer: what the species is, and its collections)
##         └ Footer                 (HBoxContainer)
##            ├ Place               (Button)
##            ├ Import / Export     (Buttons)
##            └ Status              (Label)
##
## The browser owns no design state: it answers questions about the catalogue and it emits what the
## person chose. Placing the plant is the caller's business, which is what keeps this file free of
## the yard, the plan and the view controller.

signal plant_chosen(species_id: StringName)
signal selection_changed(species_id: StringName)
## Import and export are asked for rather than done: the file dialogs belong to whoever owns the
## window, and a browser that opened its own would be a second place that knows about files.
signal import_requested()
signal export_requested()
signal note(text: String)

const PlanStyleScript := preload("res://scripts/plan_style.gd")

const ANY := -1

# --- the controls, made by `build()` -----------------------------------------------------
var _margin: MarginContainer = null
var _column: VBoxContainer = null
var _search_row: HBoxContainer = null
## The horticultural filters, on a line of their own: one row of eight controls does not fit a
## readable width, and a filter that has been squeezed into a 60-pixel drop-down is a filter nobody
## can read the state of.
var _filter_row: HBoxContainer = null
var _query: LineEdit = null
var _sort_option: OptionButton = null
var _category_option: OptionButton = null
var _light_option: OptionButton = null
var _water_option: OptionButton = null
var _zone_option: OptionButton = null
var _bloom_option: OptionButton = null
var _collection_option: OptionButton = null
var _tags_row: HFlowContainer = null
var _body: HSplitContainer = null
var _grid: ItemList = null
var _detail_scroll: ScrollContainer = null
var _detail_column: VBoxContainer = null
var _detail_label: Label = null
var _collections_box: VBoxContainer = null
var _new_collection_name: LineEdit = null
var _footer: HBoxContainer = null
var _place_button: Button = null
var _import_button: Button = null
var _export_button: Button = null
var _status_label: Label = null

var catalogue: PlantCatalogue = null
var _built: bool = false
var _selected_id: StringName = &""
var _results: Array[PlantSpecies] = []
## Tag name -> its chip. Kept so a refresh does not throw away what is ticked.
var _chips: Dictionary = {}
## Tag name -> how many species carry it, so a chip says how much it will leave.
var _chip_counts: Dictionary = {}


func _ready() -> void:
	build()


## Build the controls. Called by `_ready`, and callable directly so a test can build a browser
## without a scene tree - a bare `PlantBrowser.new()` never gets `_ready`, and a browser whose
## children only exist once it is in a tree is a browser that cannot be tested.
func build() -> void:
	if _built:
		return
	_built = true

	mouse_filter = Control.MOUSE_FILTER_PASS

	_margin = MarginContainer.new()
	_margin.name = "Margin"
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin.add_theme_constant_override("margin_left", 12)
	_margin.add_theme_constant_override("margin_top", 12)
	_margin.add_theme_constant_override("margin_right", 12)
	_margin.add_theme_constant_override("margin_bottom", 12)
	add_child(_margin)

	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.add_theme_constant_override("separation", 8)
	_margin.add_child(_column)

	_build_search_row()
	_build_tags_row()
	_build_body()
	_build_footer()
	set_status("no plant list open")


func _build_search_row() -> void:
	_search_row = HBoxContainer.new()
	_search_row.name = "Search"
	_search_row.add_theme_constant_override("separation", 6)
	_column.add_child(_search_row)

	_query = LineEdit.new()
	_query.name = "Query"
	_query.placeholder_text = "Search by name, cultivar or tag"
	_query.clear_button_enabled = true
	_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_query.custom_minimum_size = Vector2(220.0, 0.0)
	_query.text_changed.connect(func(_text: String) -> void: refresh())
	_search_row.add_child(_query)

	_sort_option = _add_option(_search_row, "Sort", sort_labels(), 130.0)
	_sort_option.item_selected.connect(func(_index: int) -> void: refresh())

	_collection_option = _add_option(_search_row, "In", ["Any plant"], 130.0)
	_collection_option.item_selected.connect(func(_index: int) -> void: refresh())

	# The horticultural filters, on a line of their own: eight controls in one row do not fit a
	# readable width, and a filter squeezed into a sixty-pixel drop-down is one nobody can read.
	_filter_row = HBoxContainer.new()
	_filter_row.name = "Filters"
	_filter_row.add_theme_constant_override("separation", 6)
	_column.add_child(_filter_row)

	_category_option = _add_option(_filter_row, "Type", ["Any type"], 110.0)
	for kind: int in PlantSpecies.CATEGORY_NAMES.keys():
		_add_choice(_category_option, String(PlantSpecies.CATEGORY_NAMES[kind]), kind)
	_category_option.item_selected.connect(func(_index: int) -> void: refresh())

	_light_option = _add_option(
		_filter_row, "Light", ["Any light", "Full sun", "Part shade", "Full shade"], 110.0
	)
	_set_choice_value(_light_option, 1, PlantSpecies.FULL_SUN)
	_set_choice_value(_light_option, 2, PlantSpecies.PART_SHADE)
	_set_choice_value(_light_option, 3, PlantSpecies.FULL_SHADE)
	_light_option.item_selected.connect(func(_index: int) -> void: refresh())

	_water_option = _add_option(
		_filter_row, "Water", ["Any water", "Low or less", "Medium or less", "High"], 110.0
	)
	_set_choice_value(_water_option, 1, PlantSpecies.WATER_LOW)
	_set_choice_value(_water_option, 2, PlantSpecies.WATER_MEDIUM)
	_set_choice_value(_water_option, 3, PlantSpecies.WATER_HIGH)
	_water_option.item_selected.connect(func(_index: int) -> void: refresh())

	_zone_option = _add_option(_filter_row, "Zone", ["Any zone"], 100.0)
	for zone: int in range(PlantSpecies.ZONE_MIN, PlantSpecies.ZONE_MAX + 1):
		_add_choice(_zone_option, "Zone %d" % zone, zone)
	_zone_option.item_selected.connect(func(_index: int) -> void: refresh())

	_bloom_option = _add_option(_filter_row, "Bloom", ["Any month"], 110.0)
	for month: int in range(1, 13):
		_add_choice(_bloom_option, String(PlantSpecies.MONTH_NAMES[month - 1]), month)
	_bloom_option.item_selected.connect(func(_index: int) -> void: refresh())


## One filter as a labelled drop-down. Every one of them is built the same way, because they differ
## only in their choices, and seven copies of the same eight lines are seven chances to forget a
## `item_selected`. The row it goes on is a parameter, so where a filter sits is a layout decision
## rather than something the builder has to be told twice.
func _add_option(row: HBoxContainer, control_name: String, choices: Array, width: float) -> OptionButton:
	var label := Label.new()
	label.name = control_name + "Label"
	label.text = control_name
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var option := OptionButton.new()
	option.name = control_name
	option.focus_mode = Control.FOCUS_NONE
	option.custom_minimum_size = Vector2(width, 0.0)
	for choice: Variant in choices:
		option.add_item(String(choice))
	option.selected = 0
	row.add_child(option)
	return option


## One choice in a filter, carrying what it *stands for* rather than where it sits.
##
## The value goes in the item's metadata, because an item's id is its own numbering and reading a
## filter out of the position of a row is how a filter comes to mean something the label does not
## say. `criteria()` reads these back, so a drop-down and the filter it drives cannot disagree.
func _add_choice(option: OptionButton, label: String, value: Variant) -> void:
	option.add_item(label)
	option.set_item_metadata(option.item_count - 1, value)


func _set_choice_value(option: OptionButton, at: int, value: Variant) -> void:
	option.set_item_metadata(at, value)


## What a filter is set to, or `ANY` for the "any" row at the top of it.
func _choice_value(option: OptionButton) -> Variant:
	if option == null or option.selected <= 0:
		return null
	return option.get_item_metadata(option.selected)


## Empty a container for a rebuild. `remove_child` then `free` rather than `queue_free`, because a
## deferred free leaves the old children in place until the end of the frame - so a rebuilt pane
## holds both the new controls and the old ones, and anything reading `get_child(0)` reads a label
## that is on its way out. It is only safe where the rebuild is not triggered by one of the children
## itself, which is why the collection boxes are not rebuilt from a box's own signal.
func _clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.free()


func _build_tags_row() -> void:
	_tags_row = HFlowContainer.new()
	_tags_row.name = "Tags"
	_tags_row.add_theme_constant_override("h_separation", 6)
	_column.add_child(_tags_row)


func _build_body() -> void:
	_body = HSplitContainer.new()
	_body.name = "Body"
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.split_offset = 700
	_column.add_child(_body)

	_grid = ItemList.new()
	_grid.name = "Grid"
	_grid.custom_minimum_size = Vector2(380.0, 260.0)
	_grid.icon_mode = ItemList.ICON_MODE_TOP
	_grid.fixed_icon_size = Vector2i(48, 48)
	_grid.fixed_column_width = 180
	_grid.max_text_lines = 2
	_grid.max_columns = 0
	_grid.wraparound_items = true
	_grid.same_column_width = true
	_grid.select_mode = ItemList.SELECT_SINGLE
	_grid.allow_reselect = true
	_grid.item_selected.connect(_on_item_selected)
	_grid.item_activated.connect(_on_item_selected)
	_body.add_child(_grid)

	_detail_scroll = ScrollContainer.new()
	_detail_scroll.name = "Detail"
	_detail_scroll.custom_minimum_size = Vector2(320.0, 260.0)
	_detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_detail_scroll)

	_detail_column = VBoxContainer.new()
	_detail_column.name = "DetailColumn"
	_detail_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_column.add_theme_constant_override("separation", 8)
	_detail_scroll.add_child(_detail_column)

	_detail_label = Label.new()
	_detail_label.name = "Facts"
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_column.add_child(_detail_label)

	var collections_title := Label.new()
	collections_title.name = "CollectionsTitle"
	collections_title.text = "Collections"
	_detail_column.add_child(collections_title)

	_collections_box = VBoxContainer.new()
	_collections_box.name = "Collections"
	_detail_column.add_child(_collections_box)

	var new_row := HBoxContainer.new()
	new_row.name = "NewCollection"
	new_row.add_theme_constant_override("separation", 6)
	_detail_column.add_child(new_row)
	_new_collection_name = LineEdit.new()
	_new_collection_name.name = "CollectionName"
	_new_collection_name.placeholder_text = "New collection"
	_new_collection_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_row.add_child(_new_collection_name)
	var make_button := Button.new()
	make_button.name = "MakeCollection"
	make_button.text = "Make"
	make_button.pressed.connect(_on_make_collection)
	new_row.add_child(make_button)


func _build_footer() -> void:
	_footer = HBoxContainer.new()
	_footer.name = "Footer"
	_footer.add_theme_constant_override("separation", 8)
	_column.add_child(_footer)

	_place_button = Button.new()
	_place_button.name = "Place"
	_place_button.text = "Place on the plan"
	_place_button.disabled = true
	_place_button.pressed.connect(place_selected)
	_footer.add_child(_place_button)

	_import_button = Button.new()
	_import_button.name = "Import"
	_import_button.text = "Import a list..."
	_import_button.pressed.connect(func() -> void: import_requested.emit())
	_footer.add_child(_import_button)

	_export_button = Button.new()
	_export_button.name = "Export"
	_export_button.text = "Export the list..."
	_export_button.pressed.connect(func() -> void: export_requested.emit())
	_footer.add_child(_export_button)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_footer.add_child(_status_label)


# --- the catalogue ------------------------------------------------------------------------


## Point the browser at a catalogue. The tag chips and the collection list are made here rather than
## on every refresh: they come from the catalogue and the person's own collections, and rebuilding
## them on each keystroke would throw away every tick.
func bind(new_catalogue: PlantCatalogue) -> void:
	build()
	catalogue = new_catalogue
	# The pictures are not cleared here: they belong to `PlantIcons`, keyed by the form a species is
	# drawn as, and a second catalogue drawn as the same three props wants the same three pictures.
	_rebuild_chips()
	_rebuild_collection_choices()
	refresh()


func _rebuild_chips() -> void:
	_clear_children(_tags_row)
	_chips.clear()
	_chip_counts.clear()
	if catalogue == null:
		return
	_chip_counts = catalogue.tag_counts()
	for tag_name: String in catalogue.tag_names():
		var chip := CheckBox.new()
		chip.name = "Tag_" + tag_name.replace(" ", "_")
		chip.text = "%s (%d)" % [tag_name, int(_chip_counts.get(tag_name, 0))]
		chip.focus_mode = Control.FOCUS_NONE
		chip.toggled.connect(func(_pressed: bool) -> void: refresh())
		_tags_row.add_child(chip)
		_chips[tag_name] = chip


func _rebuild_collection_choices() -> void:
	_collection_option.clear()
	_collection_option.add_item("Any plant")
	_collection_option.set_item_metadata(0, "")
	for collection_name: String in collection_names():
		_add_choice(_collection_option, collection_name, collection_name)
	_collection_option.selected = 0
	_build_collection_boxes()


## Keep the collection drop-down in step with the catalogue.
##
## A person's collections can arrive from somewhere other than this browser - read from their own
## file when the project opens, or made by a script - so the drop-down is checked against the
## catalogue rather than built once and trusted. It only rebuilds when the list has really changed,
## and it puts the filter back afterwards, so it cannot quietly reset what somebody was looking at.
func _sync_collection_choices() -> void:
	var offered: Array[String] = []
	for index in range(1, _collection_option.item_count):
		offered.append(String(_collection_option.get_item_metadata(index)))
	var wanted: Array[String] = collection_names()
	if offered == wanted:
		return
	var chosen: String = chosen_collection()
	_rebuild_collection_choices()
	if not chosen.is_empty():
		set_collection_filter(chosen)


## The collections of the plant in hand: a box each, ticked when it is in. Unlike the tag chips
## these are rebuilt whenever the selection changes, because they answer a different question -
## not "which plants" but "is this one in it".
func _build_collection_boxes() -> void:
	_clear_children(_collections_box)
	var species: PlantSpecies = selected_species()
	if species == null:
		var hint := Label.new()
		hint.name = "CollectionsHint"
		hint.text = "Choose a plant to put it in a collection."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_collections_box.add_child(hint)
		return
	var mine: Array[String] = catalogue.collections_of(species.id)
	if collection_names().is_empty():
		var empty := Label.new()
		empty.name = "CollectionsHint"
		empty.text = "No collections yet."
		_collections_box.add_child(empty)
		return
	for collection_name: String in collection_names():
		var box := CheckBox.new()
		box.name = "In_" + collection_name.replace(" ", "_")
		box.text = collection_name
		box.focus_mode = Control.FOCUS_NONE
		box.set_pressed_no_signal(mine.has(collection_name))
		box.toggled.connect(_on_collection_toggled.bind(collection_name))
		_collections_box.add_child(box)


# --- filtering ----------------------------------------------------------------------------


## The filter the controls describe, in the shape `PlantCatalogue.filter` takes. Only what is
## actually set is named, so an unfiltered browser asks for everything rather than for everything
## matching a pile of sentinels.
func criteria() -> Dictionary:
	var out: Dictionary = {"text": _query.text if _query != null else ""}
	if _sort_option != null:
		var orders: Array[Dictionary] = sort_orders()
		var chosen: int = clampi(_sort_option.selected, 0, orders.size() - 1)
		out["sort"] = String(orders[chosen]["sort"])
		out["descending"] = bool(orders[chosen]["descending"])
	if _choice_value(_category_option) != null:
		out["category"] = int(_choice_value(_category_option))
	if _choice_value(_light_option) != null:
		out["sun"] = int(_choice_value(_light_option))
	if _choice_value(_water_option) != null:
		out["water_max"] = int(_choice_value(_water_option))
	if _choice_value(_zone_option) != null:
		out["zone"] = int(_choice_value(_zone_option))
	if _choice_value(_bloom_option) != null:
		out["bloom_month"] = int(_choice_value(_bloom_option))
	var wanted: Array = ticked_tags()
	if not wanted.is_empty():
		out["tags"] = wanted
	return out


## The tags currently ticked, so a browser can be read as well as driven.
func ticked_tags() -> Array:
	var wanted: Array = []
	for tag_name: Variant in _chips.keys():
		var chip: CheckBox = _chips[tag_name]
		if chip.button_pressed:
			wanted.append(String(tag_name))
	wanted.sort()
	return wanted


func query_text() -> String:
	return _query.text if _query != null else ""


func set_query_text(text: String) -> void:
	build()
	if _query.text == text:
		refresh()
		return
	_query.text = text
	refresh()


## Look up what is chosen in the collection drop-down, or "" for all of them.
func chosen_collection() -> String:
	if _collection_option == null or _collection_option.selected <= 0:
		return ""
	return String(_collection_option.get_item_metadata(_collection_option.selected))


## The species the controls currently find, in the order the sort asked for. The one part of the
## browser that is a question rather than a picture.
func results() -> Array[PlantSpecies]:
	build()
	if catalogue == null:
		return []
	var found: Array[PlantSpecies] = catalogue.filter(criteria())
	var collection_name: String = chosen_collection()
	if collection_name.is_empty():
		return found
	# A collection is a person's own list, so it narrows whatever the filters found rather than
	# replacing them: "trees I have put in the front bed" is the useful question.
	var inside: Array[String] = []
	for plant: PlantSpecies in catalogue.collection(collection_name):
		inside.append(String(plant.id))
	var out: Array[PlantSpecies] = []
	for plant: PlantSpecies in found:
		if inside.has(String(plant.id)):
			out.append(plant)
	return out


## Re-read the catalogue and rebuild the grid and the detail pane. What every control calls.
func refresh() -> void:
	build()
	_sync_collection_choices()
	_results = results()
	_selected_id = _keep_selection()
	_rebuild_grid()
	_rebuild_detail()
	if catalogue == null:
		set_status("no plant list open")
		return
	set_status(summary_text())


## The selection survives a filter that still contains it, and is dropped by one that does not: a
## detail pane describing a plant the grid is not showing is the one thing this pane must not do.
func _keep_selection() -> StringName:
	if _selected_id.is_empty():
		return &""
	for plant: PlantSpecies in _results:
		if plant.id == _selected_id:
			return _selected_id
	return &""


func _rebuild_grid() -> void:
	_grid.clear()
	for plant: PlantSpecies in _results:
		var title: String = plant.common_name if not plant.common_name.strip_edges().is_empty() \
			else plant.botanical_name
		var cell: int = _grid.add_item(title, icon_for(plant.id))
		_grid.set_item_metadata(cell, String(plant.id))
		_grid.set_item_tooltip(cell, plant.display_name())
		# Shape from the form, colour from the species. The swatch is the symbol the plan draws, so
		# every tree in the catalogue is one picture; a species' own bloom colour is a tint on that
		# picture rather than a fourth copy of it, which is the difference between thirty textures
		# and one per species.
		_grid.set_item_icon_modulate(cell, PlantIcons.tint(plant))
		if plant.id == _selected_id:
			_grid.select(cell, true)


func _rebuild_detail() -> void:
	var species: PlantSpecies = selected_species()
	_detail_label.text = detail_text()
	_place_button.disabled = species == null
	_build_collection_boxes()


# --- the selection ------------------------------------------------------------------------


func select(species_id: StringName) -> bool:
	build()
	for cell in _grid.item_count:
		if StringName(_grid.get_item_metadata(cell)) == species_id:
			_grid.select(cell, true)
			_on_item_selected(cell)
			return true
	# A plant can be selected before the grid has been filtered down to it, which is how importing a
	# list and then chosing the plant that arrived works.
	if catalogue != null and catalogue.has(species_id):
		_selected_id = species_id
		_rebuild_grid()
		_rebuild_detail()
		selection_changed.emit(_selected_id)
		return true
	return false


func _on_item_selected(cell: int) -> void:
	var chosen: StringName = StringName(_grid.get_item_metadata(cell))
	if chosen == _selected_id:
		return
	_selected_id = chosen
	_rebuild_detail()
	selection_changed.emit(_selected_id)


func selected_id() -> StringName:
	return _selected_id


func selected_species() -> PlantSpecies:
	if catalogue == null or _selected_id.is_empty():
		return null
	return catalogue.get_species(_selected_id)


## What happens when the person chooses the plant: the browser says which one and stops. Putting it
## on the plan needs a yard, a plan and a view, and this file has none of them.
func place_selected() -> bool:
	var species: PlantSpecies = selected_species()
	if species == null:
		set_status("choose a plant first")
		return false
	plant_chosen.emit(species.id)
	return true


# --- collections --------------------------------------------------------------------------


func collection_names() -> Array[String]:
	var out: Array[String] = []
	if catalogue != null:
		out = catalogue.collection_names()
	return out


func _on_collection_toggled(pressed: bool, collection_name: String) -> void:
	build()
	var species: PlantSpecies = selected_species()
	if species == null:
		return
	if pressed:
		catalogue.add_to_collection(collection_name, species.id)
	else:
		catalogue.remove_from_collection(collection_name, species.id)
	# The boxes are deliberately **not** rebuilt here. This runs from a box's own `toggled` signal,
	# and a rebuild would free the control that is in the middle of emitting - so the box that was
	# clicked stays as it is, which is also what it already says.
	set_status("%s %s %s" % [
		species.display_name(), "is in" if pressed else "is out of", collection_name
	])


func _on_make_collection() -> void:
	build()
	var wanted: String = _new_collection_name.text.strip_edges()
	if create_collection_named(wanted):
		_new_collection_name.text = ""
		return
	if wanted.is_empty():
		set_status("a collection needs a name")
	else:
		set_status("there is already a collection called %s" % wanted)


## Make a collection, and say so. A name that is empty is refused, and so is one already taken: two
## lists silently becoming one is not a new list.
func create_collection_named(collection_name: String) -> bool:
	build()
	var wanted: String = collection_name.strip_edges()
	if catalogue == null or wanted.is_empty() or not catalogue.create_collection(wanted):
		return false
	_rebuild_collection_choices()
	set_status("made the collection %s" % wanted)
	note.emit("made the collection %s" % wanted)
	return true


## One tag's chip, on or off. The chips are the catalogue's own tags, so a tag cannot be a filter
## here and a different set of plants everywhere else.
func set_tag_filter(tag_name: String, on: bool) -> bool:
	build()
	if not _chips.has(tag_name):
		return false
	var chip: CheckBox = _chips[tag_name]
	chip.set_pressed_no_signal(on)
	refresh()
	return true


func set_category_filter(category: int) -> bool:
	return _set_filter(_category_option, category)


func set_light_filter(kind: int) -> bool:
	return _set_filter(_light_option, kind)


func set_water_filter(worst: int) -> bool:
	return _set_filter(_water_option, worst)


func set_zone_filter(zone: int) -> bool:
	return _set_filter(_zone_option, zone)


func set_bloom_filter(month: int) -> bool:
	return _set_filter(_bloom_option, month)


func set_collection_filter(collection_name: String) -> bool:
	return _set_filter(_collection_option, collection_name)


## Point a drop-down at the choice that stands for `value`, or at the "any" row when it is `ANY`.
## Named rather than counted, so nothing outside this file has to know that "Full sun" is the second
## row: which row a choice sits in is a layout decision, and the value is what the filter means.
##
## `ANY` is `-1`, so it cannot be confused with a real choice - `0` is a real category, a real water
## need and a real water bound, and a filter that treated zero as "no filter" would silently answer a
## different question from the one that was asked.
func _set_filter(option: OptionButton, value: Variant) -> bool:
	build()
	# Before looking for a choice, make sure the choices are the catalogue's: a collection can be
	# made by something other than this browser, and setting the filter to one that has just been
	# made has to work rather than being refused because the drop-down is a step behind.
	_sync_collection_choices()
	if value == null or (value is int and int(value) == ANY):
		option.selected = 0
		refresh()
		return true
	for index in option.item_count:
		if option.get_item_metadata(index) == value:
			option.selected = index
			refresh()
			return true
	return false


## The sort as a name rather than a row number, so a caller asks for "the tallest first" and the
## table of orders stays in here with the drop-down it describes.
func set_sort(by: String, descending: bool = false) -> bool:
	build()
	for index in _sort_option.item_count:
		if sort_orders()[index]["sort"] == by and sort_orders()[index]["descending"] == descending:
			_sort_option.selected = index
			refresh()
			return true
	return false


## The order each row of the sort drop-down asks for, read by both the control's labels and
## `set_sort`, so a row cannot be labelled "Tallest first" and sort by something else.
static func sort_orders() -> Array[Dictionary]:
	return [
		{"label": "Botanical A-Z", "sort": "botanical", "descending": false},
		{"label": "Botanical Z-A", "sort": "botanical", "descending": true},
		{"label": "Shortest first", "sort": "height", "descending": false},
		{"label": "Tallest first", "sort": "height", "descending": true},
		{"label": "Earliest bloom", "sort": "bloom", "descending": false},
		{"label": "Widest first", "sort": "spread", "descending": true},
	]


static func sort_labels() -> Array[String]:
	var out: Array[String] = []
	for order: Dictionary in sort_orders():
		out.append(String(order["label"]))
	return out


# --- what it says -------------------------------------------------------------------------


## The chosen plant, as a nursery label plus the two things a label leaves out: which collections it
## is in, and what the designer wrote about it.
func detail_text() -> String:
	var species: PlantSpecies = selected_species()
	if species == null:
		return "Nothing chosen.\nSearch the list, or tick a tag to narrow it down."
	var lines: PackedStringArray = PackedStringArray()
	lines.append(species.display_name())
	lines.append("")
	lines.append("Type:      %s" % species.category_name())
	if species.zone_min == species.zone_max:
		lines.append("Hardy:     zone %d" % species.zone_min)
	else:
		lines.append("Hardy:     zones %d to %d" % [species.zone_min, species.zone_max])
	lines.append("Size:      %.1f m tall, %.1f m across" % [species.height_m(), species.spread_m()])
	lines.append("Light:     %s" % species.sun_text())
	lines.append("Water:     %s" % species.water_text())
	var bloom: String = species.bloom_text()
	lines.append("Bloom:     %s" % (bloom if not bloom.is_empty() else "nothing - grown for its foliage"))
	lines.append("Drawn as:  %s" % _drawn_as(species))
	if not species.tags.is_empty():
		lines.append("Tags:      %s" % ", ".join(species.tags))
	if not species.note.is_empty():
		lines.append("")
		lines.append(species.note)
	return "\n".join(lines)


## Which scene a species is planted as, said the way a person asks it: its own model, or the prop
## whose symbol stands in for it.
func _drawn_as(species: PlantSpecies) -> String:
	if not species.model_scene.is_empty():
		return species.model_scene.get_file()
	var spec: Dictionary = PlanStyleScript.spec_for(species.form)
	var symbol: int = int(spec["symbol"])
	match symbol:
		PlanStyleScript.Symbol.TREE:
			return "%s (a tree symbol)" % species.form.get_file()
		PlanStyleScript.Symbol.SHRUB:
			return "%s (a shrub symbol)" % species.form.get_file()
		PlanStyleScript.Symbol.BED:
			return "%s (a planted bed)" % species.form.get_file()
	return "%s (a generic marker)" % species.form.get_file()


func summary_text() -> String:
	if catalogue == null:
		return "no plant list open"
	var shown: int = _results.size()
	var total: int = catalogue.count()
	if shown == total:
		return "%d species" % total
	return "%d of %d species" % [shown, total]


## The text of every cell in the grid, in order, which is what a test reads to know what the
## browser is showing.
func row_titles() -> Array[String]:
	build()
	var out: Array[String] = []
	for cell in _grid.item_count:
		out.append(_grid.get_item_text(cell))
	return out


func set_status(text: String) -> void:
	build()
	if _status_label != null:
		_status_label.text = text


func status_text() -> String:
	return _status_label.text if _status_label != null else ""


func focus_search() -> void:
	build()
	if _query != null:
		_query.grab_focus()


# --- the pictures -------------------------------------------------------------------------


## The picture for a species: its own thumbnail when the catalogue has one, and otherwise the swatch
## the plan's own table draws for the prop it is planted as.
##
## Both are `PlantIcons`' business rather than this file's, because the palette's plants section shows
## the same picture, and two copies of a pixel loop are two chances for the browser and the palette to
## disagree about what a plant looks like. What tells two trees apart in the grid is
## `PlantIcons.tint`, applied per cell - not another texture.
func icon_for(species_id: StringName) -> Texture2D:
	build()
	return PlantIcons.textured(catalogue, species_id)


## Whether two species are drawn as the same picture. The browser keeps no cache of its own: the
## picture belongs to `PlantIcons`, keyed by the form and category a species is drawn as.