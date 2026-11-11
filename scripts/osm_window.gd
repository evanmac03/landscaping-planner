class_name OsmWindow
extends Window
## The OpenStreetMap import: where the site is, how much map to ask for, and what came back.
##
## A `Window`, like the sheet setup and the plant library, and it has to be: this is a surface a person
## types coordinates into, and the drawing's keys belong to the drawing. A window is the boundary at
## which the keyboard is allowed to be somewhere else.
##
## ## What it does and what it does not
##
## It shows the site's coordinates, a radius, and the report of whatever map is in hand. It reads
## nothing from the disk, asks nothing of the network and puts nothing on the drawing: every action is
## an intent it announces (`fetch_requested`, `open_file_requested`, `import_requested`, `closed`) and
## the HUD answers with the modules that own the reading and the controller that owns the drawing.
## That is the same arrangement the hatch panel and the sheet window have, and it is what lets the
## whole window be driven by a test with no drawing, no network and no screen.
##
## ## Why the fields start where they do
##
## A site's coordinates are already a fact about the drawing - the sun study reads them - so the window
## opens showing the drawing's own site rather than a placeholder. A designer who has set the site once
## imports its map without typing anything, and one who has not is typing the one number that makes
## every shadow and every map agree.

signal fetch_requested(centre: Dictionary, radius_m: float)
signal open_file_requested()
signal import_requested()
signal closed()

const OsmFetchScript := preload("res://scripts/draft/osm_fetch.gd")

## Big enough for the form, the report and the four buttons at once, measured the way the sheet
## window's was: a button that exists and cannot be pressed is not a button.
const SIZE := Vector2i(780, 620)

## What the window says about itself, above the form. A page whose subject is "import a map" has to
## say what a map is *for* here, because the answer is not obvious: it is context to draw over, not
## survey data to trust.
const EXPLANATION := (
	"The streets, buildings, walls and trees around this site, from OpenStreetMap. They land on the "
	+ "underlay - the layer that does not plot - so they are drawn over rather than built on. The "
	+ "site is the centre of the map: put the drawing's origin where the site is."
)

var _latitude: LineEdit = null
var _longitude: LineEdit = null
var _radius: SpinBox = null
var _report: Label = null
var _status: Label = null
var _fetch_button: Button = null
var _open_button: Button = null
var _import_button: Button = null
var _close_button: Button = null
var _said: String = ""


func _init() -> void:
	title = "Site context from OpenStreetMap"
	min_size = SIZE
	exclusive = false
	close_requested.connect(_on_close_requested)


func _ready() -> void:
	if _latitude == null:
		build()


# --- building -----------------------------------------------------------------------


## Build the whole window by hand, idempotent, and callable off-tree so a test can drive the same
## controls the program shows.
func build() -> void:
	if _latitude != null:
		return
	var column := PageChrome.column(self)

	column.add_child(PageChrome.subheading("Site context from OpenStreetMap"))

	var explanation := PageChrome.note(EXPLANATION)
	explanation.name = "Explanation"
	column.add_child(explanation)

	# The site. Typed here or left as the drawing's own - the window opens on the drawing's site, so
	# the common case needs no typing at all.
	var site_row := HBoxContainer.new()
	site_row.name = "SiteRow"
	site_row.add_theme_constant_override("separation", 6)
	column.add_child(site_row)
	_latitude = _number_field(site_row, "Latitude", 120.0)
	_longitude = _number_field(site_row, "Longitude", 120.0)
	_radius = _number_spin(site_row, "Radius", 130.0)

	var report_box := ScrollContainer.new()
	report_box.name = "ReportBox"
	report_box.custom_minimum_size = Vector2(0.0, 260.0)
	report_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(report_box)
	_report = PageChrome.text()
	_report.name = "Report"
	_report.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_box.add_child(_report)

	_status = PageChrome.status()
	column.add_child(_status)

	var buttons := PageChrome.button_row()
	column.add_child(buttons)
	_fetch_button = _button(buttons, "FetchButton", "Fetch from OpenStreetMap")
	_fetch_button.pressed.connect(_on_fetch_pressed)
	_open_button = _button(buttons, "OpenButton", "Open a saved map file...")
	_open_button.pressed.connect(func() -> void: open_file_requested.emit())
	_import_button = _button(buttons, "ImportButton", "Put it on the drawing")
	_import_button.pressed.connect(func() -> void: import_requested.emit())
	_close_button = _button(buttons, "CloseButton", "Close")
	_close_button.pressed.connect(_on_close_requested)

	_radius.value_changed.connect(func(_value: float) -> void: _refresh())
	for field: LineEdit in [_latitude, _longitude]:
		field.text_changed.connect(func(_text: String) -> void: _refresh())
	_refresh()
	set_import_enabled(false)


# --- what the window knows ------------------------------------------------------------


## Point the window at a place: what the drawing already says the site is.
func show_site(latitude: float, longitude: float) -> void:
	if _latitude == null:
		return
	# A programmatic `text =` does not emit `text_changed`, so the buttons are told by hand.
	_latitude.text = String.num(latitude, 5)
	_longitude.text = String.num(longitude, 5)
	_refresh()


## Show a report - what a reader found, or why it found nothing.
func show_report(text: String) -> void:
	if _report != null:
		_report.text = text


## Whether what is in hand may go on the drawing. The page shows the reason either way; the button is
## what says "not this".
func set_import_enabled(enabled: bool) -> void:
	if _import_button != null:
		_import_button.disabled = not enabled


## Say something on the status line.
func say(text: String) -> void:
	_said = text
	if _status != null:
		_status.text = text


func said_text() -> String:
	return _said


func report_text() -> String:
	return _report.text if _report != null else ""


## The place the form is showing, in the shape the projection and the query both take. Coordinates
## that do not read come back as NAN rather than as a guessed zero, so `OsmFetch.can_fetch` is what
## refuses them and the window does not have to.
func centre() -> Dictionary:
	return {
		"latitude": _number_of(_latitude),
		"longitude": _number_of(_longitude),
	}


func radius_m() -> float:
	return float(_radius.value) if _radius != null else 0.0


func fetch_enabled() -> bool:
	return _fetch_button != null and not _fetch_button.disabled


func import_enabled() -> bool:
	return _import_button != null and not _import_button.disabled


func _on_fetch_pressed() -> void:
	fetch_requested.emit(centre(), radius_m())


func _on_close_requested() -> void:
	closed.emit()


## The fetch button is live only while the form describes a place on the earth, and it says why when
## it does not - a button that is there and cannot be pressed is a button that explains itself.
func _refresh() -> void:
	if _fetch_button == null:
		return
	var askable := OsmFetchScript.can_fetch(centre(), radius_m())
	var can := bool(askable["ok"])
	_fetch_button.disabled = not can
	_fetch_button.tooltip_text = (
		"ask OpenStreetMap for the map around this site" if can else String(askable["reason"])
	)


static func _number_of(field: LineEdit) -> float:
	if field == null:
		return NAN
	var text := field.text.strip_edges()
	if text.is_empty():
		return NAN
	return text.to_float() if text.is_valid_float() else NAN


# --- furniture ------------------------------------------------------------------------


func _number_field(parent: HBoxContainer, caption: String, width: float) -> LineEdit:
	var holder := VBoxContainer.new()
	holder.name = caption
	holder.add_child(_caption(caption))
	var field := LineEdit.new()
	field.name = caption + "Field"
	field.custom_minimum_size = Vector2(width, 0.0)
	field.placeholder_text = "degrees"
	holder.add_child(field)
	parent.add_child(holder)
	return field


func _number_spin(parent: HBoxContainer, caption: String, width: float) -> SpinBox:
	var holder := VBoxContainer.new()
	holder.name = caption
	holder.add_child(_caption(caption))
	var spin := SpinBox.new()
	spin.name = caption + "Spin"
	spin.custom_minimum_size = Vector2(width, 0.0)
	spin.min_value = 10.0
	spin.max_value = OsmFetchScript.MAX_RADIUS_M
	spin.step = 10.0
	spin.value = OsmFetchScript.DEFAULT_RADIUS_M
	spin.suffix = " m"
	holder.add_child(spin)
	parent.add_child(holder)
	return spin


## The small word naming the box under it, in the chrome's own body size. The name stays the page's,
## because these captions have always been named for the field they sit above.
func _caption(text: String) -> Label:
	var label := PageChrome.text(text)
	label.name = text + "Caption"
	return label


## A button in the page's own row, made by the shared chrome so that its caption and what it does with
## the keyboard are the project's rather than this page's. The node name is given explicitly rather than
## taken from the caption: these captions are written for a person - one ends in an ellipsis - and are
## not the names this window's own tests read.
func _button(parent: HBoxContainer, node_name: String, text: String) -> Button:
	var made := PageChrome.button(text)
	made.name = node_name
	parent.add_child(made)
	return made