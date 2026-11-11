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
##
## ## Reading the photograph, and where the name came from
##
## The page can ask a model to read the photograph, and **whether it can is the person's decision**: the
## four ways are `PlantIdChoice`'s, the sentence describing the chosen one is the seam's own, and with
## nothing chosen the page still sends nothing anywhere - which is the program this has always been.
##
## What a record has to be able to say is *where the name came from*. A name typed by hand is read as
## certain, because somebody standing in front of the plant said so. A name a model offered is read at
## **the model's own confidence, with the model's own name beside it**, through
## `PlantIdentifier.capture_from` - the one path from an answer to a record. Editing the name makes it
## the person's own again. That is decided by comparing the field with what the model said, never by
## remembering that a model was once asked, because the remembering is what goes stale.

const FieldCaptureScript := preload("res://scripts/field_capture.gd")
const PhotoStoreScript := preload("res://scripts/field_photo_store.gd")
const IdentifierScript := preload("res://scripts/plant_identifier.gd")
const PlantIdChoiceScript := preload("res://scripts/plant_id_choice.gd")
const ExporterScript := preload("res://scripts/io/field_manifest_exporter.gd")
const WatcherScript := preload("res://scripts/survey_watcher.gd")
const PhoneFilesScript := preload("res://scripts/phone_files.gd")
const CameraWindowScript := preload("res://scripts/camera_window.gd")

signal captured(capture: Dictionary, result: Dictionary)
signal closed()

## This page's own camera has stood up or gone away.
##
## Said out loud because the question "is a camera up" is asked in one place by the HUD, and there are two
## doors onto a camera: the HUD's own, and this page's. The rule that makes the window follow the phone has to
## be true of whichever one a person opened, and only this page knows about this one.
signal camera_changed(open: bool)

## A reading that had to wait for a model has answered.
##
## Emitted when the answer lands, which for a model on this machine is seconds or minutes after the button
## was pressed - so a caller that wants the answer waits on this rather than on the call that started it.
signal reading_finished(answer: Dictionary)

## Wide enough for the fields and the notes beside them, and tall enough for all of it: measured, the
## contents want 774 px. The first 680 cut the page's last row off the bottom edge and 730, which replaced
## it, left the reading section to scroll by 44 - so 780 is the room the page asks for now. A screen with
## less room than this still clamps it, and the column scrolls the rest of itself into view.
const SIZE := Vector2i(760, 780)

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
const READING_CAPTION := "Reading the photograph"
const READING_QUESTION := "How is it read?"

## What the page says while a model is thinking about a photograph.
##
## The reading is a refusal-shaped answer until it is not, so a caller reading `ok` and `reason` needs no
## case of its own for "not yet": it is simply not `ok`.
const READING_NOW := "Reading the photograph..."

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
## The camera page, made when somebody presses for it and kept while this page is open: a page that built a
## viewfinder at startup would start a camera for nobody.
var _camera: CameraWindow = null

## Which model reads a photograph and what it needs told - `PlantIdChoice`'s own record, kept for the
## session and written to `id_settings_path` when a person changes it.
var _id_settings: Dictionary = PlantIdChoiceScript.default_settings()
## Where that choice is kept. A member rather than the seam's own constant, so a test keeps its choice in
## a file of its own and never rewrites the one somebody is using.
var id_settings_path: String = PlantIdChoiceScript.FILE_PATH
var _id_mode_option: OptionButton = null
var _id_settings_row: VBoxContainer = null
## The keys of the settings rows currently built and the boxes they are typed into, in that same order:
## which rows exist depends on the mode, so the two cannot be read back off the tree by name alone.
var _id_field_keys: Array[StringName] = []
var _id_fields: Array[LineEdit] = []
var _candidate_row: HFlowContainer = null
## The plants the last reading offered, in the order their buttons were built: what `choose_candidate`
## reads. The answer's own entries, rather than a second word for a plant.
var _candidates: Array[Dictionary] = []
## The answer the name in the field came from, or empty when the person typed the name themselves.
var _model_answer: Dictionary = {}
## The reader a reading is in flight in, and the button that started it.
##
## Both are what a frame needs to finish a reading that had to wait for a model: which machine to step, and
## which button to let be pressed again once it has answered.
var _reader: PlantIdentifier = null
var _read_button: Button = null
## The reader this page asks, or null to make one when somebody presses for a reading - a page that built
## one at startup would ask a model for nothing. A test hands over one whose transport it controls, so the
## page's whole reading path is driven with no network and no model.
var identifier: PlantIdentifier = null


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
	# Longer than the screen this page is sized for once a mode is chosen, so what does not fit scrolls
	# into view rather than being cut off at the foot of the page - and on a tall phone screen nothing
	# scrolls at all.
	var column := PageChrome.scrolling_column(self, 6)

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
	# The other door onto a photograph, and the one a person standing at the plant actually wants: the
	# device's own camera, which needs no file of its own and no trip through a folder.
	var take := _button(photo_row, "TakePhoto", "Take a photo...")
	take.pressed.connect(take_photo)

	column.add_child(_prompt("Anything worth writing down"))
	_note_field = _line(column, "NoteField", "")
	_note_field.placeholder_text = "for example: by the gate, half-eaten"

	# After the note, because the note is evidence a model is given: somebody writing "half-eaten" before
	# pressing the button is telling it something worth knowing.
	_reading(column)

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

	_show_id_settings()
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
	load_id_settings()
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


## The capture the fields currently describe, with the name put through the identity rules. A name the
## list cannot place comes back as an unidentified capture carrying that name, which is the whole point of
## those rules living in one class.
##
## **Where the name came from decides how it is read.** A name a person typed is read as certain: they
## said it, they are not reporting a classifier's guess, and whether the *list* knows the plant is a
## different question that `identify` answers. A name a model offered goes through
## `PlantIdentifier.capture_from` instead, so the record carries the model's own confidence and the
## model's own name - a reading that was 88% sure is never filed as a certainty, and somebody reading the
## record later can see what it was and disagree with it.
func capture() -> Dictionary:
	var point := Vector3(_number_of(_x_field), 0.0, _number_of(_z_field))
	var offered: String = _name_field.text.strip_edges()
	var answer: Dictionary = {}
	if _from_a_model(offered):
		answer = IdentifierScript.capture_from(
			_model_answer,
			_catalogue,
			point,
			photo_path(),
			_note_field.text.strip_edges(),
			_part()
		)
	else:
		answer = FieldCaptureScript.identify(
			offered, 1.0, _catalogue, point, photo_path(), _note_field.text.strip_edges(), _part()
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


## The camera: the device's own, pointed at the plant in front of you. The camera page files the frame
## itself, through the same photograph store this page uses, and hands back where it was kept - so the two
## doors onto a photograph leave this page in one state rather than two.
## This page's camera, or null - asked by the HUD, which places it and asks whether it is up.
func camera_window() -> CameraWindow:
	return _camera


## Whether this page's own camera is standing up, so the one place that answers "is a camera up" can say so.
func camera_is_open() -> bool:
	return _camera != null and _camera.visible


func take_photo() -> void:
	if _camera == null:
		_camera = CameraWindowScript.new()
		_camera.name = "CameraWindow"
		_camera.folder = photo_folder
		_camera.photo_taken.connect(took_photo)
		_camera.closed.connect(_the_camera_went_away)
		# **Not a child of this page.** Godot embeds a subwindow inside the window it lives in - "centered
		# inside its embedder", sized "a ratio of embedder's size" - so a camera parented here could never be
		# bigger than this form, whatever the placing asked for. It is kept alive by this page and freed with
		# it. `get_tree()` is null for a page that was built and never shown, which is how a test holds one.
		var tree: SceneTree = get_tree()
		var room: Node = tree.root if tree != null else self
		CameraWindowScript.home_for(_camera, room).add_child(_camera)
		tree_exiting.connect(_forget_camera)
	# The camera's own door, the same one the HUD's menu opens it through. On a phone the viewfinder is the
	# whole of what a person is looking at, and a camera placed by its caller here came up a small window over
	# the survey it was being filled in from.
	CameraWindowScript.place(_camera)
	_camera.open()
	camera_changed.emit(true)


## The camera has been put away, so what the window is asked for is asked again: the phone follows itself
## while a camera is up, and the drawing's own answer is asked for again afterwards.
func _the_camera_went_away() -> void:
	camera_changed.emit(false)


## The camera does not live inside this page, so it does not go away with it: this is what does.
func _forget_camera() -> void:
	if _camera != null:
		_camera.queue_free()
		_camera = null


## What the camera kept, in the same field the picker fills.
func took_photo(kept_path: String) -> void:
	if kept_path.is_empty():
		return
	_photo_field.text = kept_path
	_say("Took the photograph and kept it as %s." % kept_path)


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


# --- reading the photograph ----------------------------------------------------------


## Whether a person can read a photograph, and what the chosen way needs told.
##
## **Off is a mode, not an absence**: it is the program this has always been, where a photograph is kept
## and the name is typed by a person, and it is what the page opens on. The four ways, the words each is
## offered under and the sentence each is described by are all `PlantIdChoice`'s, so this page cannot
## come to say something the seam does not say.
func _reading(column: VBoxContainer) -> void:
	column.add_child(PageChrome.subheading(READING_CAPTION))
	column.add_child(_prompt(READING_QUESTION))
	_id_mode_option = OptionButton.new()
	_id_mode_option.name = "IdModeOption"
	# "way" rather than "mode", which is a property a `Window` already has: a local shadowing it is a
	# warning, and a warning is an error in this project.
	for way: StringName in PlantIdChoiceScript.MODES:
		_id_mode_option.add_item(PlantIdChoiceScript.word(way))
		_id_mode_option.set_item_metadata(_id_mode_option.item_count - 1, way)
	_id_mode_option.item_selected.connect(_on_id_mode_chosen)
	column.add_child(_id_mode_option)

	# What the chosen way will do with a photograph, or what it is still missing. Both come from the
	# seam's own words and they are one line, because they are one question: what happens if I press it?
	_photo_hint = _small(column, "PhotoHint", "")
	_photo_hint.add_theme_color_override("font_color", PageChrome.HINT_COLOR)

	_id_settings_row = VBoxContainer.new()
	_id_settings_row.name = "IdSettings"
	_id_settings_row.add_theme_constant_override("separation", 2)
	column.add_child(_id_settings_row)

	_read_button = _button(column, "ReadPhoto", "Read the photograph")
	_read_button.pressed.connect(identify_photo)

	# The plants a reading came back with. A flow rather than a row: the mixed mode's shortlist can run
	# to ten names, and a row too wide for its page is a fault this page has no excuse for.
	_candidate_row = HFlowContainer.new()
	_candidate_row.name = "Candidates"
	_candidate_row.add_theme_constant_override("h_separation", 6)
	_candidate_row.add_theme_constant_override("v_separation", 2)
	column.add_child(_candidate_row)


## Read the photograph with the model the chosen way names, and put what it says on the page.
##
## The name goes into the field, so adding the capture records it like any other name - and what the
## record says about **who read it** is decided by `capture()`, which is where the difference between a
## name a model offered and a name a person typed belongs.
##
## ## Started, and only sometimes finished, in this call
##
## **A vision model may think for minutes, and this used to spend them here**: the program drew no frame at
## all while it waited, so the page looked hung for as long as the model took. The reading is now begun and
## then *stepped by the frame* (`_process`), and the answer is put on the page when it lands - which is
## when `reading_finished` says so.
##
## A reading that never has to wait for a wire is finished here, and that is deliberate rather than a
## convenience: a `transport` a test handed over answers inside a step, and a way that cannot be used
## refuses without asking anybody, so both of those answer in the call that asked. What is answered then is
## the reading's own answer; what is answered otherwise is `READING_NOW`, which is simply not `ok` yet.
func identify_photo() -> Dictionary:
	_clear_candidates()
	# Cleared with the candidates, and for the same reason: while a new reading is in flight the last one
	# is no longer what is on the page, and a capture filed from it would name a model that has not spoken.
	_model_answer = {}
	var reader: PlantIdentifier = identifier
	if reader == null:
		reader = IdentifierScript.new(_id_settings)
	# The page's own mode wins over whatever the reader was made with, so a reader handed over by a test
	# and the dropdown cannot come to describe two different ways of reading.
	reader.settings = _id_settings
	_reader = reader
	var verdict: StringName = reader.begin_read(
		_photo_image(), _part(), _note_field.text.strip_edges(), _catalogue
	)
	while verdict == IdentifierScript.WORKING and not reader.waiting_on_the_wire():
		verdict = reader.step_read()
	if verdict == IdentifierScript.WORKING:
		_reading_in_progress()
		return _still_reading()
	return _apply_the_reading(reader.read_result())


## Whether a model is being waited for right now.
func is_reading() -> bool:
	return _reader != null and _reader.reading_in_flight()


## What the last reading answered, or `READING_NOW` when one is still in flight and nothing has been read.
##
## A caller that wants the answer rather than the state should wait on `reading_finished`, which carries
## the same record and only ever carries a finished one.
func the_reading() -> Dictionary:
	if _model_answer.is_empty():
		return _still_reading()
	return _model_answer


## Step a reading that is waiting on a model, and put its answer on the page the moment it lands.
##
## **This is what keeps a slow model from freezing the program.** One look at the socket per frame costs
## nothing, and the page - with the drawing behind it and every other page - goes on drawing while a vision
## model thinks. A page with no reading in flight does nothing here at all, which is every frame of the
## program except the ones somebody is waiting through.
func _process(_delta: float) -> void:
	if _reader == null or not _reader.reading_in_flight():
		return
	if _reader.step_read() == IdentifierScript.WORKING:
		return
	_apply_the_reading(_reader.read_result())


## Put what a reading says on the page: the plant it named, the plants it offered, and which model said so.
func _apply_the_reading(answer: Dictionary) -> Dictionary:
	_model_answer = answer
	var plants: Array = answer["candidates"]
	if bool(answer["ok"]):
		set_name_text(String(answer["raw_taxon"]))
		if plants.size() > 1:
			_show_candidates(plants)
		_photo_hint.text = _read_words(answer)
		_say("Read the photograph. %s" % _photo_hint.text)
	else:
		# **A refusal can carry a shortlist**, and this is the one place a person is shown both why
		# nothing was identified and something to choose: the mixed mode's first half worked and its
		# second did not. Showing the plants without the reason, or the reason without the plants, would
		# hide half of what happened.
		if not plants.is_empty():
			_show_candidates(plants)
		_photo_hint.text = String(answer["reason"])
		_say(String(answer["reason"]))
	_the_button_may_be_pressed_again()
	reading_finished.emit(answer)
	return answer


## Say that a model is thinking, and stop the button being pressed a second time while it does.
##
## The button is disabled rather than left live because a second press would start a second reading over
## the first, and two models thinking about one photograph is a queue nobody asked for. What a person needs
## while they wait is the screen saying so, which is what the status line and the hint are for.
func _reading_in_progress() -> void:
	if _read_button != null:
		_read_button.disabled = true
	_say(READING_NOW)
	_photo_hint.text = READING_NOW


func _the_button_may_be_pressed_again() -> void:
	if _read_button != null:
		_read_button.disabled = false


## What the page answers while a model is thinking.
##
## A refusal-shaped reading rather than an empty one, because that is what it is: not `ok`, with the reason
## saying what is happening. A page of its own that had to special-case "not yet" would be a page with two
## ways to read one answer.
func _still_reading() -> Dictionary:
	return {
		"ok": false,
		"reason": READING_NOW,
		"raw_taxon": "",
		"confidence": 0.0,
		"candidates": [],
		"answer": "",
		"model_id": "",
		"model_version": "",
	}


## What a reading says: the plant, how sure the model was, and which model it was.
##
## Which model matters because two of them answer in the mixed mode, and somebody weighing a name should
## be able to see who gave it - so a model that did not name itself says exactly that, rather than
## leaving a gap where its name would have been.
func _read_words(answer: Dictionary) -> String:
	var percent: int = int(round(float(answer.get("confidence", 0.0)) * 100.0))
	var who: String = String(answer.get("model_id", ""))
	if who.is_empty():
		who = "a model that did not say which one it was"
	return "That reads as %s, %d%% sure, from %s." % [String(answer.get("raw_taxon", "")), percent, who]


## The photograph the field names, read back as pixels - or null when there is not one, which the pipeline
## refuses by name rather than this page guessing at what it could not open.
##
## What is read is the **kept** copy rather than whatever the picture was chosen from: that is the file
## the record points at, and on a phone it is the only one of the two this program can open.
func _photo_image() -> Image:
	var path: String = photo_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	return Image.load_from_file(path)


## Put the plants a model offered on the page, one button each. The name on the button is the model's own
## and so is the number beside it, because somebody choosing between two names needs both.
func _show_candidates(plants: Array) -> void:
	_clear_candidates()
	for item: Variant in plants:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		var index: int = _candidates.size()
		_candidates.append(entry)
		var button := PageChrome.button(_candidate_words(entry))
		button.name = "Candidate%d" % index
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(choose_candidate.bind(index))
		_candidate_row.add_child(button)
	if _candidate_row.get_child_count() > 0:
		# Buttons built while the page is open: somebody who reached the page with the keyboard has to be
		# able to reach these too.
		PageChrome.takes_the_keyboard_if_up(self)


func _candidate_words(entry: Dictionary) -> String:
	var percent: int = int(round(float(entry.get("confidence", 0.0)) * 100.0))
	return "%s (%d%% sure)" % [String(entry.get("raw_taxon", "")), percent]


func _clear_candidates() -> void:
	_candidates.clear()
	if _candidate_row == null:
		return
	for child in _candidate_row.get_children():
		# Freed rather than queued, so that a reading taken off-tree replaces the last one rather than
		# being added to: a queued free happens a frame later, and a test never reaches that frame.
		_candidate_row.remove_child(child)
		child.free()


## Choose one of the plants a model offered. It goes into the name field, and the record will carry the
## model's own confidence and the model's own name rather than this page's certainty about a guess.
func choose_candidate(index: int) -> bool:
	if index < 0 or index >= _candidates.size():
		return false
	var entry: Dictionary = _candidates[index]
	# "plant" rather than "name", which is a property every `Node` has.
	var plant: String = String(entry.get("raw_taxon", ""))
	if plant.is_empty():
		return false
	# Who said it is read from the answer *before* it is replaced: in the mixed mode these plants came
	# from the first model even when the second was never reached, and a record naming neither, or the
	# wrong one, would be telling a person less than the truth about how the name was arrived at.
	_model_answer = {
		"ok": true,
		"raw_taxon": plant,
		"confidence": float(entry.get("confidence", 0.0)),
		"model_id": String(_model_answer.get("model_id", "")),
		"model_version": String(_model_answer.get("model_version", "")),
	}
	set_name_text(plant)
	_say("Chose %s." % plant)
	return true


## Whether the name in the field is still the one a model gave.
##
## A name somebody has edited is theirs: they have looked at what the model said and disagreed with it,
## and filing their own name at the model's confidence would be recording a guess as a decision. This is
## asked by comparing the field with the answer rather than by remembering that a model was once asked,
## because the remembering is exactly what goes stale.
func _from_a_model(offered: String) -> bool:
	if _model_answer.is_empty() or not bool(_model_answer.get("ok", false)):
		return false
	return offered == String(_model_answer.get("raw_taxon", "")).strip_edges()


## Point the page at the way of reading that is kept, and at the file it is kept in.
##
## Public because a test points it at a file of its own before binding: a test that wrote to the choice
## somebody is really using would change their program in order to run its own.
func load_id_settings(path: String = "") -> void:
	if not path.strip_edges().is_empty():
		id_settings_path = path
	_id_settings = PlantIdChoiceScript.stored(id_settings_path)
	_show_id_settings()


## Keep the choice where the next run will find it. What is written is what **may** be kept, so a key
## typed for a service is held for this session and typed again the next one rather than written down.
func save_id_settings() -> bool:
	return PlantIdChoiceScript.remember(_id_settings, id_settings_path)


func id_settings() -> Dictionary:
	return _id_settings


func id_mode() -> StringName:
	return PlantIdChoiceScript.mode_of(_id_settings)


## Choose a way for a photograph to be read: the dropdown moves, the rows that way asks for are rebuilt,
## and the choice is kept. A way nobody has heard of is the off one, because that is the one that sends
## nothing.
func set_id_mode(way: StringName) -> bool:
	var chosen: StringName = PlantIdChoiceScript.mode_for(way)
	_id_settings[PlantIdChoiceScript.MODE] = String(chosen)
	save_id_settings()
	_show_id_settings()
	return true


## The field for one of a mode's settings, or null when that mode does not ask for it.
func id_field(key: String) -> LineEdit:
	var index: int = _id_field_keys.find(StringName(key))
	if index < 0:
		return null
	return _id_fields[index]


## Type into one of a mode's fields. A `LineEdit` set in code does not announce itself, so the setting is
## written by the same call the signal would have made.
func set_id_field(key: String, words: String) -> bool:
	var box: LineEdit = id_field(key)
	if box == null:
		return false
	box.text = words
	_on_id_field_changed(words, key)
	return true


func candidate_count() -> int:
	return _candidates.size()


func photo_hint() -> String:
	return _photo_hint.text if _photo_hint != null else ""


## Whatever the mode says, shown: which rows it needs, which of them is the secret one, and the sentence
## describing what it does. One call, so the three cannot come apart.
func _show_id_settings() -> void:
	_select_id_mode(id_mode())
	_rebuild_id_settings()
	_refresh_photo_hint()
	_clear_candidates()


func _select_id_mode(way: StringName) -> void:
	if _id_mode_option == null:
		return
	for index: int in _id_mode_option.item_count:
		if PlantIdChoiceScript.mode_for(_id_mode_option.get_item_metadata(index)) == way:
			_id_mode_option.select(index)
			return


## The rows the chosen way asks for, built from `PlantIdChoice`'s own list: which fields a mode needs, and
## which of them is a secret, is decided in one place and not here. Rebuilt rather than shown and hidden,
## because a mode asks only for what it uses - and somebody using a local model is never shown a box for
## a key they have no use for.
func _rebuild_id_settings() -> void:
	if _id_settings_row == null:
		return
	for child in _id_settings_row.get_children():
		# Freed rather than queued, for the same reason the candidates are.
		_id_settings_row.remove_child(child)
		child.free()
	_id_field_keys.clear()
	_id_fields.clear()
	for field: Dictionary in PlantIdChoiceScript.fields_for(id_mode()):
		var key: String = String(field.get("key", ""))
		if key.is_empty():
			continue
		var box := LineEdit.new()
		box.name = key
		# `str` rather than the `String` constructor, which does not take an int: a shortlist size comes
		# back from a file as a whole number and a person has to be able to read it and type it back.
		box.text = str(_id_settings.get(key, ""))
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# `LineEdit`'s own mask, and which fields want it comes from the seam: a page cannot decide on its
		# own to show somebody's key in the clear.
		box.secret = bool(field.get("secret", false))
		box.text_changed.connect(_on_id_field_changed.bind(key))
		# Leaving the field keeps what was typed, which is when somebody has finished with it - and Enter
		# does the same for anybody who never leaves it.
		box.focus_exited.connect(_on_id_field_left)
		box.text_submitted.connect(_on_id_field_submitted)
		_id_settings_row.add_child(PageChrome.labelled(String(field.get("label", key)), box))
		_id_field_keys.append(StringName(key))
		_id_fields.append(box)


func _on_id_mode_chosen(index: int) -> void:
	set_id_mode(PlantIdChoiceScript.mode_for(_id_mode_option.get_item_metadata(index)))


func _on_id_field_changed(words: String, key: String) -> void:
	_id_settings[key] = words
	_refresh_photo_hint()


func _on_id_field_left() -> void:
	save_id_settings()


func _on_id_field_submitted(_words: String) -> void:
	save_id_settings()


## What the line under the dropdown says before anything has been read: what the chosen way will do with a
## photograph, or what it is still missing. Both are the seam's own sentence, so this page cannot come to
## describe a way that is not the one in force.
func _refresh_photo_hint() -> void:
	if _photo_hint == null:
		return
	_photo_hint.text = IdentifierScript.photo_hint_for(_id_settings)


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
