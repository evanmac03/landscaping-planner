class_name FieldCaptureWindow
extends Window
## Recording what is standing on site: the page a person opens with a plant in front of them and a
## photograph of it in hand.
##
## A `Window`, like every other page here, and it is the **person's** door rather than the classifier's.
## It asks for what somebody standing in the garden can actually answer - which plant, where, what the
## ground is like there, and which photograph it came from - and it writes one record into the same
## survey file a phone writes, so nothing downstream can tell which of the two doors a capture came
## through.
##
## ## It writes, and it says what it wrote
##
## Unlike the underlay page, which announces intents and leaves every file to the HUD, this page's whole
## job is one record in one file: `FieldManifestExporter.append` is the model that writes it and the page
## calls it. What the page does **not** do is decide anything: `FieldCapture` owns the rules about a name
## that cannot be placed and a bit that means nothing, so a page cannot disagree with a manifest.
##
## ## The two fields that are not text
##
## The sun and the drainage are dropdowns over `PlantSpecies`' own bits, so the light level of a place
## here is the same bit a plant's need is measured in - and each starts with "not stated", because the
## truth about a spot nobody described is that nobody described it.

const FieldCaptureScript := preload("res://scripts/field_capture.gd")
const PhotoStoreScript := preload("res://scripts/field_photo_store.gd")
const IdentifierScript := preload("res://scripts/plant_identifier.gd")
const ExporterScript := preload("res://scripts/io/field_manifest_exporter.gd")
const WatcherScript := preload("res://scripts/survey_watcher.gd")
const PhoneFilesScript := preload("res://scripts/phone_files.gd")

signal captured(capture: Dictionary, result: Dictionary)
signal closed()

## Wide enough for the fields and the notes beside them, and tall enough for all of it: measured, the
## contents want 720 px, so the first 680 cut the page's last row off the bottom edge.
const SIZE := Vector2i(760, 730)

const EXPLANATION := (
	"Record what is standing on site. What you record here goes into the drawing's own survey file, "
	+ "so it is planted with the rest of the field captures and filed in the same collection."
)
const NOT_STATED := "not stated"
const NO_LIST := "There is no plant list here to check a name against."
const NO_PHOTO := "no photograph chosen"
const NOTHING_TO_RECORD := (
	"Say which plant it is, or choose a photograph of it: a position on its own is not a record."
)

## The order the light levels are offered in. The **words** are `PlantSpecies`' own, so the page cannot
## come to say "semi-shade" about the bit the model calls part shade.
const SUN_ORDER := [0, PlantSpecies.FULL_SUN, PlantSpecies.PART_SHADE, PlantSpecies.FULL_SHADE]
const DRAINAGE_ORDER := [
	0, PlantSpecies.DRAINS_FAST, PlantSpecies.DRAINS_MEDIUM, PlantSpecies.DRAINS_SLOW,
]

var _catalogue: PlantCatalogue = null
var _manifest_path: String = WatcherScript.DEFAULT_MANIFEST_PATH
var _site_name: String = "Field survey"
## Where a chosen picture is kept. A member rather than the constant, so a test can point the page at a
## folder of its own and leave the photographs somebody really took alone.
var photo_folder: String = PhotoStoreScript.DIR

var _name_field: LineEdit = null
var _species_line: Label = null
var _part_option: OptionButton = null
var _sun_option: OptionButton = null
var _drainage_option: OptionButton = null
var _x_field: LineEdit = null
var _z_field: LineEdit = null
var _photo_field: LineEdit = null
var _photo_hint: Label = null
var _height_field: LineEdit = null
var _spread_field: LineEdit = null
var _note_field: LineEdit = null
var _survey_line: Label = null
var _status: Label = null
var _dialog: FileDialog = null


func _init() -> void:
	title = "Record what is on site"
	min_size = SIZE
	exclusive = false
	close_requested.connect(request_close)


func _ready() -> void:
	if _name_field == null:
		build()


# --- building -----------------------------------------------------------------------


## Build the whole page by hand, idempotent, and callable off-tree so a test can drive the same
## controls the program shows.
func build() -> void:
	if _name_field != null:
		return
	var column := PageChrome.column(self, 6)

	column.add_child(PageChrome.heading("Record what is on site"))

	column.add_child(_explanation())

	column.add_child(_prompt("Which plant is it?"))
	_name_field = _line(column, "NameField", "")
	_name_field.placeholder_text = "for example: Thymus serpyllum, or creeping thyme"
	_name_field.text_changed.connect(_on_name_changed)
	_species_line = _small(column, "SpeciesLine", "")
	_species_line.add_theme_color_override("font_color", Color(0.72, 0.78, 0.70))

	column.add_child(_prompt("What was photographed?"))
	_part_option = OptionButton.new()
	_part_option.name = "PartOption"
	_fill_from_names(_part_option, FieldCaptureScript.PART_NAMES.keys(), FieldCaptureScript.PART_NAMES)
	column.add_child(_part_option)

	var ground := HBoxContainer.new()
	ground.name = "Ground"
	ground.add_theme_constant_override("separation", 6)
	column.add_child(ground)
	_sun_option = OptionButton.new()
	_sun_option.name = "SunOption"
	_fill_from_bits(_sun_option, SUN_ORDER, PlantSpecies.SUN_NAMES)
	_labelled(ground, "Sun here", _sun_option)
	_drainage_option = OptionButton.new()
	_drainage_option.name = "DrainageOption"
	_fill_from_bits(_drainage_option, DRAINAGE_ORDER, PlantSpecies.DRAINAGE_NAMES)
	_labelled(ground, "Drainage here", _drainage_option)

	column.add_child(_prompt("Where is it, in metres from the drawing's origin?"))
	var place := HBoxContainer.new()
	place.name = "Position"
	place.add_theme_constant_override("separation", 6)
	column.add_child(place)
	_x_field = _line(place, "XField", "0.0")
	_z_field = _line(place, "ZField", "0.0")

	column.add_child(_prompt("Photograph"))
	var photo_row := HBoxContainer.new()
	photo_row.name = "PhotoRow"
	photo_row.add_theme_constant_override("separation", 6)
	column.add_child(photo_row)
	_photo_field = _line(photo_row, "PhotoField", "")
	_photo_field.placeholder_text = NO_PHOTO
	var choose := _button(photo_row, "ChoosePhoto", "Choose a picture...")
	choose.pressed.connect(choose_photo)
	# What the program does and does not do with a photograph, in the seam's own words rather than in
	# this page's: the day a model is installed, this line changes without the page being touched.
	_photo_hint = _small(column, "PhotoHint", IdentifierScript.photo_hint())
	_photo_hint.add_theme_color_override("font_color", Color(0.68, 0.72, 0.62))

	column.add_child(_prompt("Anything worth writing down"))
	_note_field = _line(column, "NoteField", "")
	_note_field.placeholder_text = "for example: by the gate, half-eaten"

	# What a person with a tape measure can add, and the one thing on this page that is deliberately
	# allowed to be zero: nought here means "I did not measure it", and the plant is then the size the
	# list says - not a plant of no size.
	column.add_child(_prompt("How big is it, in metres? Leave 0 for the size the list states."))
	var size_row := HBoxContainer.new()
	size_row.name = "SizeRow"
	size_row.add_theme_constant_override("separation", 6)
	column.add_child(size_row)
	_height_field = _line(size_row, "HeightField", "0.0")
	_spread_field = _line(size_row, "SpreadField", "0.0")

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)
	var add_button := _button(buttons, "AddButton", "Add to the survey")
	add_button.pressed.connect(add_capture)
	var close_button := _button(buttons, "CloseButton", "Close")
	close_button.pressed.connect(request_close)

	_survey_line = _small(column, "SurveyLine", "")
	_survey_line.add_theme_color_override("font_color", Color(0.68, 0.72, 0.62))
	_status = _small(column, "Status", "")

	refresh()


## What the page is for, in the shared chrome's own note - whose colour is the very one this sentence
## was already drawn in. The page's own name for it is kept: the page's test reads it by name.
func _explanation() -> Label:
	var label := PageChrome.note(EXPLANATION)
	label.name = "Explanation"
	return label


## A question over the field that answers it. Every prompt shares the name "Prompt", which is what this
## page has always called them; `wrap_text` is false because a prompt is one line, and one allowed to wrap
## would report a minimum width of its longest word.
func _prompt(words: String) -> Label:
	var label := PageChrome.text(words, false)
	label.name = "Prompt"
	return label


## A line the page says under the thing it is about. The caller tints it: the species line, the photo hint
## and the survey line are each the colour of their own kind of remark.
func _small(parent: Node, node_name: String, words: String) -> Label:
	var label := PageChrome.text(words)
	label.name = node_name
	parent.add_child(label)
	return label


func _line(parent: Node, node_name: String, words: String) -> LineEdit:
	var field := LineEdit.new()
	field.name = node_name
	field.text = words
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(field)
	return field


## A button on this page, from the shared chrome and named by the page: the names are what the page's own
## test holds it by. The chrome is also what gives it a keyboard of its own to give back - a button here
## used to take the drawing's keyboard at the moment it was built, which is the one thing the HUD's rule
## does not allow. The two at the foot share their row evenly, which is this page's own layout.
func _button(parent: Node, node_name: String, words: String) -> Button:
	var button := PageChrome.button(words)
	button.name = node_name
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	return button


## A caption **above** the control it names, which is this page's own shape - the shared `labelled` puts
## its caption beside it, in a row. The caption is the chrome's, so it is the one body size and the one
## colour; and it is a word, so it does not wrap.
func _labelled(parent: Node, words: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(PageChrome.text(words, false))
	box.add_child(control)
	parent.add_child(box)
	return box


## Fill a dropdown from a vocabulary of **words** ("the whole plant", "a leaf"), with the key itself as
## the item's metadata: what a person reads and what the record holds are then the same table.
func _fill_from_names(option: OptionButton, keys: Array, names: Dictionary) -> void:
	for index: int in keys.size():
		var key: Variant = keys[index]
		option.add_item(String(names.get(key, String(key))))
		option.set_item_metadata(index, key)
	option.select(0)


## Fill a dropdown from a set of **bits**, starting with "not stated": zero is not a value here, it is
## a question nobody answered, and the way back to that has to exist.
func _fill_from_bits(option: OptionButton, bits: Array, names: Dictionary) -> void:
	for index: int in bits.size():
		var bit: int = int(bits[index])
		option.add_item(NOT_STATED if bit == 0 else String(names.get(bit, str(bit))))
		option.set_item_metadata(index, bit)
	option.select(0)


# --- what it is pointed at ----------------------------------------------------------


## Hand the page what it needs: the one plant list and where the survey is. The list is the HUD's own,
## so a capture is checked against the catalogue the browser shows.
func bind(catalogue: PlantCatalogue, manifest_path: String = "", site_name: String = "") -> void:
	_catalogue = catalogue
	if not manifest_path.strip_edges().is_empty():
		_manifest_path = manifest_path
	if not site_name.strip_edges().is_empty():
		_site_name = site_name
	refresh()


## Rewrite the two readouts that depend on the world rather than on a keystroke.
func refresh() -> void:
	if _survey_line == null:
		return
	_refresh_species_line()
	_survey_line.text = survey_line()


func species_line() -> String:
	return _species_line.text if _species_line != null else ""


func survey_line() -> String:
	if _manifest_path.is_empty():
		return "No survey file is named, so nothing can be recorded."
	if not FileAccess.file_exists(_manifest_path):
		return "The survey is empty: nothing has been recorded for this site yet."
	var read: Dictionary = ExporterScript.read_manifest(_manifest_path)
	if not bool(read["ok"]):
		return "The survey at %s cannot be read: %s" % [_manifest_path, String(read["reason"])]
	var features: Variant = (read["data"] as Dictionary).get("features", [])
	var count: int = (features as Array).size() if features is Array else 0
	return "The survey holds %d record%s." % [count, "" if count == 1 else "s"]


func status_text() -> String:
	return _status.text if _status != null else ""


# --- what the fields say ------------------------------------------------------------


## The capture the fields currently describe, with the name put through `FieldCapture.identify`. A name
## the list cannot place comes back as an unidentified capture carrying that name, which is the whole
## point of the identity rules living in one class.
##
## A person typing a name is read as certain about it: they are not reporting a classifier's guess, and
## whether the *list* knows the plant is a different question that `identify` answers.
func capture() -> Dictionary:
	var point := Vector3(_number_of(_x_field), 0.0, _number_of(_z_field))
	var answer: Dictionary = FieldCaptureScript.identify(
		_name_field.text.strip_edges(),
		1.0,
		_catalogue,
		point,
		_photo_field.text.strip_edges(),
		_note_field.text.strip_edges(),
		_part()
	)
	var made: Dictionary = answer["capture"]
	made["sun_mask"] = _bit_of(_sun_option)
	made["drainage_mask"] = _bit_of(_drainage_option)
	made["measured_height_m"] = _number_of(_height_field)
	made["measured_spread_m"] = _number_of(_spread_field)
	return made


## Record the capture in the survey. Returns the append's own result: `{ok, reason, added, total}`.
func add_capture() -> Dictionary:
	var trouble: String = _trouble()
	if not trouble.is_empty():
		_say(trouble)
		return {"ok": false, "reason": trouble, "added": 0, "total": 0}
	var made: Dictionary = capture()
	var result: Dictionary = ExporterScript.append(_site_name, [made], _manifest_path)
	if not bool(result["ok"]):
		_say("It could not be recorded: %s" % String(result["reason"]))
		return result
	if int(result["added"]) == 0:
		_say("That record is already in the survey, so nothing was added.")
	else:
		_say("Recorded %s. %s" % [
			FieldCaptureScript.words(made, _catalogue), survey_line(),
		])
	captured.emit(made, result)
	refresh()
	return result


## Keep a photograph and point the field at it. The store's own refusal - which is the picture reader's
## sentence - is what a person is told, so the two doors into this program say the same thing.
func keep_photo(source_path: String) -> Dictionary:
	var kept: Dictionary = PhotoStoreScript.add(source_path, photo_folder)
	if not bool(kept["ok"]):
		_say(String(kept["reason"]))
		return kept
	_photo_field.text = String(kept["path"])
	if bool(kept["duplicate"]):
		_say("That photograph is already kept as %s." % String(kept["path"]))
	else:
		_say("Kept the photograph as %s." % String(kept["path"]))
	return kept


## The door to a picture. The dialog is made only when somebody presses the button: a test has no screen
## and never gets here, and a page that built a file dialog at startup would build one for nobody.
func choose_photo() -> void:
	if _dialog == null:
		_dialog = FileDialog.new()
		_dialog.name = "PhotoDialog"
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		# On a phone a photograph is not at a path this program can open - it is handed over, once,
		# through the phone's own picker, and copied into the app's pictures before anything else
		# happens to it. On a computer this changes nothing at all.
		PhoneFilesScript.prepare(_dialog)
		_dialog.add_filter("*.png,*.jpg,*.jpeg,*.webp,*.bmp", "Pictures")
		_dialog.file_selected.connect(keep_photo)
		add_child(_dialog)
	_dialog.popup_centered_ratio(0.6)


# --- what is wrong, in words --------------------------------------------------------


## What stops this being a record at all, or "" when nothing does. Every refusal names the thing that is
## wrong rather than the field's number.
func _trouble() -> String:
	if _manifest_path.is_empty():
		return "There is no survey file to record this in."
	if not _x_field.text.strip_edges().is_valid_float():
		return "The east-west position is not a number, so there is nowhere to put this plant."
	if not _z_field.text.strip_edges().is_valid_float():
		return "The north-south position is not a number, so there is nowhere to put this plant."
	if not _height_field.text.strip_edges().is_valid_float():
		return "How tall it is has to be a number of metres, or 0 for the size the list states."
	if not _spread_field.text.strip_edges().is_valid_float():
		return "How wide it is has to be a number of metres, or 0 for the size the list states."
	var made: Dictionary = capture()
	if (
		not FieldCaptureScript.identified(made)
		and String(made["raw_taxon"]).is_empty()
		and String(made["photo_path"]).is_empty()
	):
		return NOTHING_TO_RECORD
	return ""


func _on_name_changed(_words: String) -> void:
	_refresh_species_line()


func _refresh_species_line() -> void:
	if _species_line == null:
		return
	var offered: String = _name_field.text.strip_edges() if _name_field != null else ""
	if offered.is_empty():
		_species_line.text = "No name yet: this will be recorded as an unidentified capture."
		return
	if _catalogue == null:
		_species_line.text = NO_LIST
		return
	var answer: Dictionary = FieldCaptureScript.identify(offered, 1.0, _catalogue)
	if bool(answer["ok"]):
		var species_id: String = String((answer["capture"] as Dictionary)["species_id"])
		var species: PlantSpecies = _catalogue.get_species(StringName(species_id))
		if species == null:
			_species_line.text = "Recorded as %s." % species_id
		else:
			_species_line.text = "Recorded as %s (%s)." % [
				species.common_name, species.botanical_name,
			]
		return
	_species_line.text = (
		"That name is not in the list, so it is recorded as unidentified with the name kept: %s"
		% String(answer["reason"])
	)


# --- the doors a test and the HUD use ------------------------------------------------


## Put the page away and say so once, however it was asked for - the window's own close button, the
## Close button, or Escape (which `PageEscape` turns into `close_requested`).
func request_close() -> void:
	hide()
	closed.emit()


# --- typing for a test ---------------------------------------------------------------


func set_name_text(words: String) -> void:
	_name_field.text = words
	# A `LineEdit` set in code does not announce itself, so the readout is written by the same call the
	# signal would have made.
	_refresh_species_line()


## Where the plant is, as the two numbers a person types. Named `set_place` rather than `set_position`
## because a `Window` already has a `set_position` and it is the one the engine calls.
func set_place(x_metres: String, z_metres: String) -> void:
	_x_field.text = x_metres
	_z_field.text = z_metres


func set_photo_path(path: String) -> void:
	_photo_field.text = path


func set_note(words: String) -> void:
	_note_field.text = words


## What a person measured, in metres. "0.0" is the honest default: nobody measured it, so the plant is
## the size the list states. Named `set_measured_size` rather than `set_size` because a `Window` already
## has a `set_size` and it is the one the engine calls.
func set_measured_size(height_metres: String, spread_metres: String) -> void:
	_height_field.text = height_metres
	_spread_field.text = spread_metres


## Choose a light level or a drainage by the words the dropdown shows, which is how a person chooses.
func set_choice(option: OptionButton, words: String) -> bool:
	for index: int in option.item_count:
		if option.get_item_text(index) == words:
			option.select(index)
			return true
	return false


func sun_option() -> OptionButton:
	return _sun_option


func drainage_option() -> OptionButton:
	return _drainage_option


func part_option() -> OptionButton:
	return _part_option


func set_part(words: String) -> bool:
	return set_choice(_part_option, words)


func photo_path() -> String:
	return _photo_field.text.strip_edges() if _photo_field != null else ""


func photo_hint() -> String:
	return _photo_hint.text if _photo_hint != null else ""


func _part() -> StringName:
	return StringName(String(_part_option.get_item_metadata(_part_option.selected)))


func _bit_of(option: OptionButton) -> int:
	if option.selected < 0:
		return 0
	return int(option.get_item_metadata(option.selected))


func _number_of(field: LineEdit) -> float:
	var words: String = field.text.strip_edges()
	if words.is_valid_float():
		return float(words)
	return 0.0


func _say(line: String) -> void:
	if _status != null:
		_status.text = line