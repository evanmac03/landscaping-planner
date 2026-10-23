class_name RotationWindow
extends Window
## What to grow here next, and what grows well together: the food garden's other question.
##
## `CropRotation` is the arithmetic - the family a crop belongs to, the family that grew in a bed
## before it, and the companion pairings. This is the screen: a bed to choose, what grew in it last, a
## crop to try, and the whole plant list ranked against the bed's history.
##
## Five things are true of this page, and each is a decision:
##
## * **It holds no arithmetic and no records.** Every verdict comes from `CropRotation` and every line
##   from a species' own `family_name`, so the page cannot disagree with the check.
## * **The beds come in from outside.** Like the food page, it is handed a list of `{name}` places - the
##   ground's own beds - and does not read a drawing: how the beds are found is the caller's business.
## * **The history is stated here, not drawn.** *What grew here last* is not a fact about the plan: it
##   is a thing the person standing in the garden knows. So this page keeps it, per bed and in memory,
##   rather than pretending the document remembers a season it was never told about.
## * **A bed whose history nobody has stated is checked and reported unknown**, grey and never green -
##   the same honesty `PlantSuitability`, `CropSun` and `CropRotation` keep, because a green ring for a
##   question that could not run is the one thing this must not give.
## * **Nothing here takes the drawing's keyboard**, and nothing here writes anything: it is a page you
##   read, choose on and close.

## A page wide enough for the crop list and a couple of sentences of verdict.
const SIZE := Vector2i(940, 780)

const CropRotationScript := preload("res://scripts/crop_rotation.gd")

const EXPLANATION := ("Choose a bed and say what grew in it last. A crop belongs to a family - a "
	+ "brassica, a nightshade, a legume - and the one law of crop rotation is that the same family "
	+ "shall not follow itself: a brassica after a brassica shares its pests and its diseases. A "
	+ "legume before it is a gift, because beans leave the ground richer than they found it. The page "
	+ "also says what each crop grows well beside.")

const NO_PLACES := "no ground has been described yet: draw or state a bed in the ground window"
const NO_CROPS := "this plant list has no food in it yet"
const NOT_STATED := "not stated"

signal closed

var catalogue: PlantCatalogue = null
## The beds, as `{name}`. Given in, not found here.
var _places: Array[Dictionary] = []
## What grew in each bed last, by bed name. Kept here and nowhere else: the plan was never told a
## season, and the person standing in the garden is the one who knows it.
var _previous: Dictionary = {}
var _built: bool = false
var _status: String = ""

var _heading: Label = null
var _explanation: Label = null
var _place_label: Label = null
var _place_option: OptionButton = null
var _turn_label: Label = null
var _turn_option: OptionButton = null
var _crop_label: Label = null
var _crop_option: OptionButton = null
var _place_line: Label = null
var _crop_line: Label = null
var _turn_line: Label = null
var _company_line: Label = null
var _crops_label: Label = null
var _crops_list: ItemList = null
var _summary_label: Label = null
var _hint_label: Label = null
var _close_button: Button = null
var _status_label: Label = null


# --- building -----------------------------------------------------------------------------


## Build the controls, once. Idempotent, and callable off-tree, so a test drives the same controls the
## program shows.
func build() -> void:
	if _built:
		return
	_built = true
	title = "What to grow here next"
	hide()
	size = SIZE
	close_requested.connect(_on_close_requested)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 16.0
	column.offset_top = 12.0
	column.offset_right = -16.0
	column.offset_bottom = -12.0
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	_heading = Label.new()
	_heading.name = "Heading"
	_heading.text = "What to grow here next"
	column.add_child(_heading)

	_explanation = Label.new()
	_explanation.name = "Explanation"
	_explanation.text = EXPLANATION
	_explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_explanation)

	var place_row := HBoxContainer.new()
	place_row.name = "PlaceRow"
	_place_label = Label.new()
	_place_label.name = "PlaceLabel"
	_place_label.text = "Bed"
	place_row.add_child(_place_label)
	_place_option = _option(place_row, "Place", "The bed to plant")
	_place_option.item_selected.connect(func(index: int) -> void: _on_place_selected(index))
	column.add_child(place_row)

	var turn_row := HBoxContainer.new()
	turn_row.name = "TurnRow"
	_turn_label = Label.new()
	_turn_label.name = "TurnLabel"
	_turn_label.text = "Last grown here"
	turn_row.add_child(_turn_label)
	_turn_option = _option(turn_row, "Turn", "The family that grew in this bed last")
	_turn_option.item_selected.connect(func(index: int) -> void: _on_turn_selected(index))
	column.add_child(turn_row)

	var crop_row := HBoxContainer.new()
	crop_row.name = "CropRow"
	_crop_label = Label.new()
	_crop_label.name = "CropLabel"
	_crop_label.text = "Crop"
	crop_row.add_child(_crop_label)
	_crop_option = _option(crop_row, "Crop", "The crop to try here")
	_crop_option.item_selected.connect(func(index: int) -> void: _on_crop_selected(index))
	column.add_child(crop_row)

	_place_line = Label.new()
	_place_line.name = "PlaceLine"
	_place_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_place_line)

	_crop_line = Label.new()
	_crop_line.name = "CropLine"
	_crop_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_crop_line)

	_turn_line = Label.new()
	_turn_line.name = "Verdict"
	_turn_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_turn_line)

	_company_line = Label.new()
	_company_line.name = "Company"
	_company_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_company_line)

	_crops_label = Label.new()
	_crops_label.name = "CropsLabel"
	column.add_child(_crops_label)
	_crops_list = ItemList.new()
	_crops_list.name = "Crops"
	_crops_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_crops_list.custom_minimum_size = Vector2(0.0, 240.0)
	# A list a person reads is not a list a person types into: the keyboard belongs to the drawing.
	_crops_list.focus_mode = Control.FOCUS_NONE
	_crops_list.select_mode = ItemList.SELECT_SINGLE
	column.add_child(_crops_list)

	_summary_label = Label.new()
	_summary_label.name = "Summary"
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_summary_label)

	_hint_label = Label.new()
	_hint_label.name = "Hint"
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hint_label)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	_close_button = _button(buttons, "CloseButton", "Close")
	_close_button.pressed.connect(request_close)
	column.add_child(buttons)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)

	_rebuild_turn_choices()
	_refresh()


func _option(row: Node, node_name: String, tip: String) -> OptionButton:
	var made := OptionButton.new()
	made.name = node_name
	# The HUD's own rule: a control in the HUD never takes the keyboard from the drawing.
	made.focus_mode = Control.FOCUS_NONE
	made.tooltip_text = tip
	made.custom_minimum_size = Vector2(360.0, 0.0)
	row.add_child(made)
	return made


func _button(row: Node, node_name: String, caption: String) -> Button:
	var made := Button.new()
	made.name = node_name
	made.text = caption
	made.focus_mode = Control.FOCUS_NONE
	row.add_child(made)
	return made


# --- binding ------------------------------------------------------------------------------


## Point the page at what it is about: the plant list and the beds. Both can be absent, and each
## absence is a state the page reports rather than fails on. The stated history is cleared here,
## because it is about the beds being replaced.
func bind(new_catalogue: PlantCatalogue, places: Array = []) -> void:
	build()
	catalogue = new_catalogue
	_previous.clear()
	set_places(places)
	_rebuild_crop_choices()
	_refresh()


func set_places(places: Array) -> void:
	build()
	_places.clear()
	for place: Variant in places:
		if place is Dictionary:
			_places.append(place)
	_rebuild_place_choices()
	_refresh()


func place_count() -> int:
	return _places.size()


func place_at(index: int) -> Dictionary:
	if index < 0 or index >= _places.size():
		return {}
	return _places[index]


## The bed in hand, or an empty dictionary when there is none.
func selected_place() -> Dictionary:
	if _place_option == null or _place_option.selected < 0:
		return {}
	return place_at(_place_option.selected)


func choose_place(index: int) -> bool:
	if _place_option == null or index < 0 or index >= _places.size():
		return false
	# Selecting does not emit `item_selected`, which is right: choosing what to look at is not a
	# request to do anything.
	_place_option.select(index)
	_refresh()
	return true


## What grew in the bed in hand last, or `FAMILY_NONE` when nobody has said.
func previous_family() -> StringName:
	var place: Dictionary = selected_place()
	if place.is_empty():
		return CropRotationScript.FAMILY_NONE
	return StringName(_previous.get(String(place.get("name", "")), CropRotationScript.FAMILY_NONE))


## Say what grew in the bed in hand last, and check again. Refused for a family nobody has; a word
## that is not a family would be a history the module could not rotate.
func choose_previous_family(family: StringName) -> bool:
	var place: Dictionary = selected_place()
	if place.is_empty():
		return false
	if not family.is_empty() and not CropRotationScript.families().has(family):
		return false
	_previous[String(place.get("name", ""))] = family
	_refresh()
	return true


## The crops the page offers: every edible species in the catalogue, by botanical order.
func crop_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	if catalogue == null:
		return out
	for plant: PlantSpecies in catalogue.all():
		if plant.is_edible():
			out.append(plant.id)
	return out


func selected_crop() -> PlantSpecies:
	if catalogue == null or _crop_option == null or _crop_option.selected < 0:
		return null
	return catalogue.get_species(StringName(_crop_option.get_item_metadata(_crop_option.selected)))


func choose_crop(species_id: StringName) -> bool:
	if _crop_option == null:
		return false
	for index in _crop_option.item_count:
		if StringName(_crop_option.get_item_metadata(index)) == species_id:
			_crop_option.select(index)
			_refresh()
			return true
	return false


## Rebuild the bed dropdown, keeping the bed in hand when it is still there: a bed stated on the
## drawing while this page is up must not throw the person back to the first bed.
func _rebuild_place_choices() -> void:
	if _place_option == null:
		return
	var chosen: String = _place_name() if _place_option.item_count > 0 else ""
	_place_option.clear()
	for place: Dictionary in _places:
		_place_option.add_item(String(place.get("name", "a bed")))
	for index in _place_option.item_count:
		if _place_option.get_item_text(index) == chosen:
			_place_option.selected = index
			return
	if _place_option.item_count > 0:
		_place_option.selected = 0


## The "last grown here" dropdown: the nine families, with "not stated" first. The metadata is the
## family the row stands for, so the words shown and the family chosen cannot drift apart.
func _rebuild_turn_choices() -> void:
	if _turn_option == null:
		return
	_turn_option.clear()
	_turn_option.add_item(NOT_STATED)
	_turn_option.set_item_metadata(0, "")
	for family: StringName in CropRotationScript.families():
		_turn_option.add_item(CropRotationScript.family_words(family))
		_turn_option.set_item_metadata(_turn_option.item_count - 1, String(family))
	_turn_option.selected = 0


func _rebuild_crop_choices() -> void:
	if _crop_option == null:
		return
	var chosen: StringName = &""
	var held: PlantSpecies = selected_crop()
	if held != null:
		chosen = held.id
	_crop_option.clear()
	for id: StringName in crop_ids():
		var plant: PlantSpecies = catalogue.get_species(id)
		var caption: String = plant.common_name if not plant.common_name.strip_edges().is_empty() \
			else plant.botanical_name
		_crop_option.add_item(caption)
		_crop_option.set_item_metadata(_crop_option.item_count - 1, String(id))
		if id == chosen:
			_crop_option.selected = _crop_option.item_count - 1
	# The first food crop in the list, so the page has something to check before anyone chooses.
	if _crop_option.selected < 0 and _crop_option.item_count > 0:
		_crop_option.selected = 0


# --- the check, as the page shows it ------------------------------------------------------


func _place_name() -> String:
	var place: Dictionary = selected_place()
	if place.is_empty():
		return "this spot"
	return String(place.get("name", "this spot"))


## What already stands beside the crop in this bed, if the caller stated any. Empty is the ordinary
## case: the page is asked what to put *in* a bed, not what is beside a plant in it.
func _beside() -> Array:
	var place: Dictionary = selected_place()
	var raw: Variant = place.get("beside", [])
	return raw if raw is Array else []


## The verdict for the crop and bed in hand. The whole page is read off this.
func verdict() -> Dictionary:
	return CropRotationScript.check(
		selected_crop(), previous_family(), _beside(), _place_name()
	)


## The bed in hand and what grew there last.
func place_line() -> String:
	if _places.is_empty():
		return NO_PLACES
	var before: String = CropRotationScript.family_words(previous_family())
	if before.is_empty():
		return "%s: what grew here last is not stated" % _place_name()
	return "%s: %s %s grew here last" % [
		_place_name(), CropRotationScript.article(before), before
	]


## The crop's own facts: what of it is eaten, when it is harvested, the family, the sun and the days.
func crop_line() -> String:
	var crop: PlantSpecies = selected_crop()
	if crop == null:
		return NO_CROPS
	return "%s - %s" % [crop.display_name(), crop.crop_text()]


## What the turn comes to, in one sentence.
func turn_line() -> String:
	if selected_crop() == null:
		return "choose a crop to try here"
	return CropRotationScript.summary_of(verdict())


## What the crop grows well beside and should be kept from, from the module's own table.
func company_line() -> String:
	var crop: PlantSpecies = selected_crop()
	if crop == null:
		return "choose a crop to see what it grows well beside"
	var line: String = CropRotationScript.companion_line(crop.family)
	if line.is_empty():
		return "nothing is stated about what this plant grows beside"
	return line


## One line per crop in the list, best first: what would follow the bed's history.
func row_texts() -> Array[String]:
	if catalogue == null:
		return [] as Array[String]
	return CropRotationScript.row_texts(catalogue, previous_family(), _beside(), _place_name())


func row_count() -> int:
	return row_texts().size()


func summary_text() -> String:
	if catalogue == null:
		return NO_CROPS
	return CropRotationScript.describe_rows(
		CropRotationScript.rows(catalogue, previous_family(), _beside(), _place_name())
	)


## What the page is waiting for, or - once it can answer - what to try next. Deliberately not the
## verdict again: the verdict is on its own line, and a page that says the same sentence twice reads as
## a page that has lost track of which line is which.
func hint() -> String:
	if catalogue == null or crop_ids().is_empty():
		return NO_CROPS
	if _places.is_empty():
		return NO_PLACES
	if selected_crop() == null:
		return "choose a crop to try here"
	match int(verdict()["verdict"]):
		CropRotationScript.UNSUITABLE:
			return "choose another crop for this bed, or leave it a season"
		CropRotationScript.UNKNOWN:
			return "state what grew in this bed last and it can be checked"
	return "this one follows on well; try another crop to compare"


# --- what it says -------------------------------------------------------------------------


func say(text: String) -> void:
	_status = text
	if _status_label != null:
		_status_label.text = text


func said() -> String:
	return _status


func status_text() -> String:
	return _status


## True when nothing on the page can take the drawing's keyboard: no text field is here, and the
## three dropdowns, the list and the buttons are all focus-free.
func lists_are_keyboard_free() -> bool:
	return _crops_list != null and _crops_list.focus_mode == Control.FOCUS_NONE


func request_close() -> void:
	hide()
	closed.emit()


# --- the refresh --------------------------------------------------------------------------


func _refresh() -> void:
	if not _built:
		return
	_sync_turn_choice()
	_place_line.text = place_line()
	_crop_line.text = crop_line()
	_turn_line.text = turn_line()
	_company_line.text = company_line()
	_crops_label.text = "What would follow in %s \u2014 %d" % [_place_name(), row_count()]
	var texts: Array[String] = row_texts()
	_crops_list.clear()
	for text: String in texts:
		_crops_list.add_item(text)
	_summary_label.text = summary_text()
	_hint_label.text = hint()


## Point the "last grown here" dropdown at the bed in hand, without emitting a choice: showing what is
## stored is not a request to change it.
func _sync_turn_choice() -> void:
	if _turn_option == null:
		return
	var family: String = String(previous_family())
	for index in _turn_option.item_count:
		if String(_turn_option.get_item_metadata(index)) == family:
			_turn_option.selected = index
			return


func _on_place_selected(index: int) -> void:
	if not choose_place(index):
		return
	var place: Dictionary = place_at(index)
	say("%s: %s" % [String(place.get("name", "a bed")), String(place.get("summary", "chosen"))])


func _on_turn_selected(index: int) -> void:
	var family: StringName = StringName(_turn_option.get_item_metadata(index))
	if not choose_previous_family(family):
		return
	if family.is_empty():
		say("what grew in %s last is not stated" % _place_name())
	else:
		var word: String = CropRotationScript.family_words(family)
		say("%s %s grew in %s last" % [CropRotationScript.article(word), word, _place_name()])


func _on_crop_selected(_index: int) -> void:
	var crop: PlantSpecies = selected_crop()
	if crop == null:
		return
	_refresh()
	say("trying %s" % crop.display_name())


func _on_close_requested() -> void:
	request_close()