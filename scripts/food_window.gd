class_name FoodWindow
extends Window
## The food garden, as a page: what will crop in a bed, and which beds suit which crops.
##
## `CropSun` is the arithmetic - the hours a stated light level stands for, the crop's own requirement
## and the site's day length. This is the screen: a bed to choose, a crop to choose, and the whole
## plant list checked against the bed so a designer can see what the ground will carry.
##
## Five things are true of this page, and each is a decision:
##
## * **It holds no arithmetic and no records.** Every figure comes from `CropSun` or from a species'
##   own `crop_text`, so the page cannot disagree with the check.
## * **The beds come in from outside.** This page does not read a drawing or a zone map: it is handed
##   a list of `{name, profile}` places, which is what lets it be built and driven with no drawing and
##   no screen. How the places are found is the caller's business.
## * **A place nobody described is a real answer.** A bed with no stated light is checked and reported
##   **unknown**, grey and never green - the same honesty `PlantSuitability` keeps, because a green
##   ring for a question that could not run is the one thing this must not give.
## * **The crop list is food only.** A question about what will crop has no row for a boxwood.
## * **Nothing here takes the drawing's keyboard**, and nothing here writes anything: it is a page you
##   read, choose on and close.

## A page wide enough for the crops list and a couple of sentences of verdict.
const SIZE := Vector2i(940, 720)

const CropSunScript := preload("res://scripts/crop_sun.gd")
const PlantSuitabilityScript := preload("res://scripts/plant_suitability.gd")

const EXPLANATION := ("Choose a bed and a crop. The light a bed is stated in stands for a span of "
	+ "hours - full sun is six or more, part shade three to six - and a crop wants a number of them; "
	+ "the site's own longest day is the ceiling no bed can beat. Nothing here measures the shade of "
	+ "a wall or a tree: it reads what the ground is stated to be.")

const NO_PLACES := "no ground has been described yet: state a bed's light in the ground window"
const NO_CROPS := "this plant list has no food in it yet"
const NO_SITE := "there is no site, so the season cannot be checked"

signal closed

var catalogue: PlantCatalogue = null
## The beds, as `{name, profile}`. Given in, not found here.
var _places: Array[Dictionary] = []
## The site, for the day-length ceiling. Empty means nobody has stated one.
var _site: Dictionary = {}
var _built: bool = false
var _status: String = ""

var _heading: Label = null
var _explanation: Label = null
var _place_label: Label = null
var _place_option: OptionButton = null
var _crop_label: Label = null
var _crop_option: OptionButton = null
var _crop_line: Label = null
var _place_line: Label = null
var _verdict_line: Label = null
var _crops_label: Label = null
var _crops_list: ItemList = null
var _season_label: Label = null
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
	title = "Food garden"
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
	_heading.text = "Food garden"
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
	_place_option = _option(place_row, "Place", "Where the crop would go")
	_place_option.item_selected.connect(func(index: int) -> void: _on_place_selected(index))
	column.add_child(place_row)

	var crop_row := HBoxContainer.new()
	crop_row.name = "CropRow"
	_crop_label = Label.new()
	_crop_label.name = "CropLabel"
	_crop_label.text = "Crop"
	crop_row.add_child(_crop_label)
	_crop_option = _option(crop_row, "Crop", "The crop to check")
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

	_verdict_line = Label.new()
	_verdict_line.name = "Verdict"
	_verdict_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_verdict_line)

	_crops_label = Label.new()
	_crops_label.name = "CropsLabel"
	column.add_child(_crops_label)
	_crops_list = ItemList.new()
	_crops_list.name = "Crops"
	_crops_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_crops_list.custom_minimum_size = Vector2(0.0, 220.0)
	# A list a person reads is not a list a person types into: the keyboard belongs to the drawing.
	_crops_list.focus_mode = Control.FOCUS_NONE
	_crops_list.select_mode = ItemList.SELECT_SINGLE
	column.add_child(_crops_list)

	_season_label = Label.new()
	_season_label.name = "Season"
	_season_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_season_label)

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

	_refresh()


func _option(row: Node, node_name: String, tip: String) -> OptionButton:
	var made := OptionButton.new()
	made.name = node_name
	# The HUD's own rule: a control in the HUD never takes the keyboard from the drawing.
	made.focus_mode = Control.FOCUS_NONE
	made.tooltip_text = tip
	made.custom_minimum_size = Vector2(420.0, 0.0)
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


## Point the page at what it is about: the plant list, the beds, and the site. All three can be
## absent, and each absence is a state the page reports rather than fails on.
func bind(new_catalogue: PlantCatalogue, places: Array = [], site: Dictionary = {}) -> void:
	build()
	catalogue = new_catalogue
	set_places(places)
	set_site(site)
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


func set_site(site: Dictionary) -> void:
	build()
	_site = site.duplicate()
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


func _rebuild_place_choices() -> void:
	if _place_option == null:
		return
	_place_option.clear()
	for place: Dictionary in _places:
		_place_option.add_item(String(place.get("name", "a bed")))
	if _place_option.item_count > 0:
		_place_option.selected = 0


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


## The profile of the bed in hand, or an empty one when there is none.
func _profile() -> TerrainProfile:
	var place: Dictionary = selected_place()
	var profile: Variant = place.get("profile", null)
	return profile if profile is TerrainProfile else TerrainProfile.make()


func _place_name() -> String:
	var place: Dictionary = selected_place()
	if place.is_empty():
		return "this spot"
	return String(place.get("name", "this spot"))


## The verdict for the crop and bed in hand. The whole page is read off this.
func verdict() -> Dictionary:
	return CropSunScript.check(selected_crop(), _profile(), _site, _place_name())


## The bed's conditions, as stated.
func place_line() -> String:
	if _places.is_empty():
		return NO_PLACES
	return "%s: %s" % [_place_name(), _profile().describe()]


## The crop's own facts: what of it is eaten, when it is harvested, the family, the sun and the days.
func crop_line() -> String:
	var crop: PlantSpecies = selected_crop()
	if crop == null:
		return NO_CROPS
	return "%s - %s" % [crop.display_name(), crop.crop_text()]


## What the check comes to, in one sentence.
func verdict_line() -> String:
	if selected_crop() == null:
		return "choose a crop to check"
	return CropSunScript.summary_of(verdict())


## One line per crop in the list, best first: what will crop in this bed.
func row_texts() -> Array[String]:
	if catalogue == null:
		return [] as Array[String]
	return CropSunScript.row_texts(catalogue, _profile(), _site, _place_name())


func row_count() -> int:
	return row_texts().size()


## The site's own ceiling, in words, or what is missing.
func season_line() -> String:
	if _site.is_empty():
		return NO_SITE
	return CropSunScript.season_line(_site)


func summary_text() -> String:
	if catalogue == null:
		return NO_CROPS
	return CropSunScript.describe_rows(CropSunScript.rows(catalogue, _profile(), _site, _place_name()))


## What the page is waiting for, or - once it can answer - what to try next. Deliberately not the
## verdict again: the verdict is on its own line, and a page that says the same sentence twice reads as
## a page that has lost track of which line is which.
func hint() -> String:
	if catalogue == null or crop_ids().is_empty():
		return NO_CROPS
	if _places.is_empty():
		return NO_PLACES
	if selected_crop() == null:
		return "choose a crop to check"
	match int(verdict()["verdict"]):
		CropSunScript.UNSUITABLE:
			return "choose another bed, or a crop that wants less sun"
		CropSunScript.UNKNOWN:
			return "state this bed's light in the ground window and it can be checked"
	return "change the bed or the crop to ask again"


# --- what it says -------------------------------------------------------------------------


func say(text: String) -> void:
	_status = text
	if _status_label != null:
		_status_label.text = text


func said() -> String:
	return _status


func status_text() -> String:
	return _status


## True when nothing on the page can take the drawing's keyboard: no text field is here, and the two
## lists and the buttons are all focus-free.
func lists_are_keyboard_free() -> bool:
	return _crops_list != null and _crops_list.focus_mode == Control.FOCUS_NONE


func request_close() -> void:
	hide()
	closed.emit()


# --- the refresh --------------------------------------------------------------------------


func _refresh() -> void:
	if not _built:
		return
	_place_line.text = place_line()
	_crop_line.text = crop_line()
	_verdict_line.text = verdict_line()
	_crops_label.text = "What would crop in %s \u2014 %d" % [_place_name(), row_count()]
	var texts: Array[String] = row_texts()
	_crops_list.clear()
	for text: String in texts:
		_crops_list.add_item(text)
	_season_label.text = season_line()
	_summary_label.text = summary_text()
	_hint_label.text = hint()


func _on_place_selected(index: int) -> void:
	if not choose_place(index):
		return
	var place: Dictionary = place_at(index)
	say("%s: %s" % [String(place.get("name", "a bed")), String(place.get("summary", "chosen"))])


func _on_crop_selected(_index: int) -> void:
	var crop: PlantSpecies = selected_crop()
	if crop == null:
		return
	_refresh()
	say("checking %s" % crop.display_name())


func _on_close_requested() -> void:
	request_close()