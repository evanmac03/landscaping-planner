extends Node
## A picture under the drawing, joined to the menu and to the page.
##
## The reader is tested in `test_raster_underlay.gd`, the drawing in `test_underlay_tools.gd` and the
## page in `test_underlay_window.gd`; this is the part that only exists when the three are put
## together - that the File menu offers the one import that is not linework, that choosing a file reads
## it and keeps a copy *before* anything reaches the drawing, that the page's button is what puts it
## there, and that closing the page forgets what was in hand.
##
## Neither node is added to the tree, so no `_ready` runs: no dialog is built, no button is focused and
## no window is ever shown - `popup_centered` needs a screen and a test does not have one, which is why
## the filling of the page is its own function.

const HudScript := preload("res://scripts/hud.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")
const RasterUnderlayScript := preload("res://scripts/draft/raster_underlay.gd")
const UnitsScript := preload("res://scripts/draft/units.gd")

const PREFIX := "test-"
const SCRATCH := "user://drawings/test-hud-underlay.json"


# --- helpers --------------------------------------------------------------------------


## A picture on disk, under a name this file owns: 64 by 32, so a width of 12 lies 6 deep.
func _source(name: String, width: int = 64, height: int = 32) -> String:
	RasterUnderlayScript.ensure_dir()
	var path := RasterUnderlayScript.DIR.path_join(PREFIX + name + ".png")
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.4, 0.6, 1.0))
	image.save_png(path)
	return path


func _notes(name: String) -> String:
	RasterUnderlayScript.ensure_dir()
	var path := RasterUnderlayScript.DIR.path_join(PREFIX + name + ".txt")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("a list of things to buy, long enough to have a header worth reading")
		file.close()
	return path


## A drawing with `count` shapes on it and no scene around it.
func _drawn(count: int = 1) -> DraftController:
	var controller := ControllerScript.new()
	controller.document = DocumentScript.new()
	controller.document.changed.connect(controller._on_document_changed)
	controller.snap = SnapScript.new()
	controller.snap.bind(controller.document.entities())
	for index in count:
		controller.document.add(
			EntityScript.make_line(Vector2(0, index), Vector2(4, 2 + index)), LayerSetScript.NEW_HARDSCAPE
		)
	return controller


func _hud_for(controller: DraftController) -> Node:
	var hud := HudScript.new()
	hud._draft = controller
	return hud


func _mine() -> Array[String]:
	var out: Array[String] = []
	for path: String in RasterUnderlayScript.list():
		if path.get_file().begins_with(PREFIX):
			out.append(path)
	return out


func _clean() -> void:
	for path: String in _mine():
		DirAccess.remove_absolute(path)
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(SCRATCH)


# --- the menu --------------------------------------------------------------------------


func test_the_file_menu_offers_a_picture_under_the_drawing() -> void:
	var entries: Array[Dictionary] = HudScript.file_items()
	var found: Dictionary = {}
	for entry: Dictionary in entries:
		if String(entry.get("id", "")) == "file.picture":
			found = entry
	assert(not found.is_empty(), "the File menu carries the one import that is not linework")
	assert(String(found["label"]) == "Put a picture under the drawing...", String(found["label"]))
	assert(String(found["method"]) == "_menu_import_picture", String(found["method"]))
	assert(StringName(found["needs"]) == HudScript.NEEDS_DRAFT, "and it needs a drawing to put it under")
	var hud := HudScript.new()
	assert(hud.has_method("_menu_import_picture"), "and the method it names is there")
	assert(hud.has_method("_menu_import_dxf"), "beside the three imports that read linework")
	hud.free()


# --- the page --------------------------------------------------------------------------


func test_the_page_is_built_and_filled_without_a_window_server() -> void:
	_clean()
	var controller := _drawn(1)
	var hud := _hud_for(controller)
	hud._build_underlay_window()
	assert(hud._underlay_window != null, "the page is built")
	assert(not hud.is_underlay_window_open(), "and not shown: a form nobody opened must not be over the drawing")
	hud._fill_underlay_window()
	assert(hud._underlay_window.report_text() == "no picture has been read", hud._underlay_window.report_text())
	assert(hud._underlay_window.file_text() == HudScript.UnderlayWindowScript.NO_PICTURE, "")
	assert(not hud._underlay_window.place_enabled(), "nothing read, nothing to place")
	# The drawing has a 4 by 2 metre shape on it, so that is the size a picture should start at.
	assert(is_equal_approx(hud._picture_suggested_width(), 4.0), str(hud._picture_suggested_width()))
	assert(is_equal_approx(hud._underlay_window.width_m(), 4.0), hud._underlay_window.across_text())
	hud.free()
	controller.free()
	_clean()


func test_a_picture_chosen_is_read_and_kept_before_anything_reaches_the_drawing() -> void:
	_clean()
	var controller := _drawn(1)
	var hud := _hud_for(controller)
	var source := _source("chosen")
	hud._on_underlay_chosen(source)
	assert(not hud._pending_picture.is_empty(), "the picture is in hand")
	var path := String(hud._pending_picture["path"])
	assert(path.begins_with(RasterUnderlayScript.DIR), "as a copy in the drawing's own folder: " + path)
	assert(FileAccess.file_exists(path), "which is really there")
	assert(path != source, "and is not where the file was found")
	assert(FileAccess.file_exists(source), "the file it came from is left where it was")
	assert(controller.underlays().is_empty(), "**and nothing is on the drawing yet**")
	assert(hud._underlay_window.place_enabled(), "though it is ready to go on")
	assert(hud._underlay_window.file_text() == PREFIX + "chosen", hud._underlay_window.file_text())
	assert(
		hud._underlay_window.report_text().contains("64 x 32 pixels"),
		hud._underlay_window.report_text()
	)
	assert(
		hud._underlay_window.report_text().contains("ready to go under the drawing"),
		hud._underlay_window.report_text()
	)
	assert(String(hud._underlay_window.said_text()).contains("m across"), hud._underlay_window.said_text())
	controller.free()
	hud.free()
	_clean()


func test_a_file_that_is_not_a_picture_is_shown_with_its_reason() -> void:
	_clean()
	var controller := _drawn(1)
	var hud := _hud_for(controller)
	hud._on_underlay_chosen(_notes("notes"))
	assert(hud._pending_picture.is_empty(), "nothing is in hand")
	assert(hud._picture_refusal.contains("is not a picture this can read"), hud._picture_refusal)
	assert(hud._underlay_window.report_text() == hud._picture_refusal, "and the page says why")
	assert(hud._underlay_window.file_text() == HudScript.UnderlayWindowScript.NO_PICTURE, "no file is named")
	assert(not hud._underlay_window.place_enabled(), "so the button that lays one down stays off")
	assert(controller.underlays().is_empty(), "and a refused file never reaches the drawing")
	assert(_mine().size() == 1, "and it copied nothing: it made only the notes file itself: %s" % str(_mine()))
	controller.free()
	hud.free()
	_clean()


# --- the two acts ------------------------------------------------------------------------


func test_the_buttons_put_change_and_take_off_the_picture() -> void:
	_clean()
	var controller := _drawn(1)
	var hud := _hud_for(controller)
	hud._on_underlay_chosen(_source("placed"))
	hud.place_the_picture()
	assert(controller.underlays().size() == 1, "the picture is under the drawing")
	var picture: Dictionary = controller.underlays()[0]
	assert(is_equal_approx(float(picture["width_m"]), 4.0), "at the size the drawing suggested: %s" % str(picture["width_m"]))
	assert(hud._pending_picture.is_empty(), "and nothing is in hand any more")
	assert(not hud._underlay_window.place_enabled(), "so the button goes off")
	assert(hud._underlay_window.underlay_texts().size() == 2, str(hud._underlay_window.underlay_texts()))
	assert(String(hud._underlay_window.said_text()).contains("under the drawing"), hud._underlay_window.said_text())
	# And the same page is how it is changed and how it comes off again.
	hud._underlay_window.choose_underlay(1)
	assert(hud._underlay_window.chosen_id() == int(picture["id"]), str(hud._underlay_window.chosen_id()))
	hud._underlay_window.set_across_text("30")
	hud._underlay_window.set_turn(45.0)
	hud._underlay_window.set_see_through(40.0)
	hud.apply_to_the_picture()
	var changed: Dictionary = controller.underlays()[0]
	assert(is_equal_approx(float(changed["width_m"]), 30.0), str(changed["width_m"]))
	assert(is_equal_approx(float(changed["rotation_deg"]), 45.0), str(changed["rotation_deg"]))
	assert(is_equal_approx(float(changed["opacity"]), 0.4), str(changed["opacity"]))
	assert(String(hud._underlay_window.said_text()).contains("turned 45.0 degrees"), hud._underlay_window.said_text())
	hud.take_the_picture_off()
	assert(controller.underlays().is_empty(), "and off it comes")
	assert(hud._underlay_window.underlay_texts() == [HudScript.UnderlayWindowScript.NOTHING_UNDER], str(hud._underlay_window.underlay_texts()))
	controller.free()
	hud.free()
	_clean()


func test_closing_the_page_forgets_the_picture_in_hand() -> void:
	_clean()
	var controller := _drawn(1)
	var hud := _hud_for(controller)
	hud._on_underlay_chosen(_source("forgotten"))
	assert(not hud._pending_picture.is_empty(), "the picture is in hand")
	hud.close_underlay_window()
	assert(hud._pending_picture.is_empty(), "and closing the page drops it")
	assert(hud._picture_refusal == "", "along with anything that was wrong with a file")
	assert(controller.underlays().is_empty(), "the drawing is untouched by any of it")
	# And a page that has been closed and filled again says nothing has been read rather than offering
	# the picture it was showing a moment ago.
	hud._fill_underlay_window()
	assert(hud._underlay_window.file_text() == HudScript.UnderlayWindowScript.NO_PICTURE, hud._underlay_window.file_text())
	assert(not hud._underlay_window.place_enabled(), "and has nothing to lay down")
	controller.free()
	hud.free()
	_clean()


func test_the_width_reads_in_the_drawings_own_units() -> void:
	_clean()
	var controller := _drawn(1)
	controller.document.units.system = UnitsScript.System.IMPERIAL
	var hud := _hud_for(controller)
	hud._fill_underlay_window()
	assert(hud._underlay_window._across_caption.text == "Across the ground (ft)", hud._underlay_window._across_caption.text)
	hud._on_underlay_chosen(_source("imperial"))
	assert(hud._underlay_window.across_text() == "13.12", hud._underlay_window.across_text())
	# Twelve feet, typed by somebody working in feet, is 3.6576 m on the drawing.
	hud._underlay_window.set_across_text("12")
	assert(is_equal_approx(hud._underlay_window.width_m(), 3.6576), str(hud._underlay_window.width_m()))
	hud.place_the_picture()
	var picture: Dictionary = controller.underlays()[0]
	assert(is_equal_approx(float(picture["width_m"]), 3.6576), str(picture["width_m"]))
	assert(String(hud._underlay_window.said_text()).contains("ft across"), hud._underlay_window.said_text())
	controller.free()
	hud.free()
	_clean()


func test_a_drawing_with_nothing_on_it_still_has_a_size_to_offer() -> void:
	# An empty sheet is exactly what somebody traces a scan onto on the first day, so the width starts
	# at a plain number on a form rather than at nothing.
	_clean()
	var controller := _drawn(0)
	var hud := _hud_for(controller)
	hud._fill_underlay_window()
	assert(
		is_equal_approx(hud._picture_suggested_width(), RasterUnderlayScript.SUGGESTED_WIDTH),
		str(hud._picture_suggested_width())
	)
	hud._on_underlay_chosen(_source("empty-sheet"))
	assert(hud._underlay_window.place_enabled(), "and a picture can be laid at it")
	hud.place_the_picture()
	assert(controller.underlays().size() == 1, "which is what tracing onto a blank sheet is")
	controller.free()
	hud.free()
	_clean()


# --- the keyboard -------------------------------------------------------------------------


func test_the_guard_that_keeps_the_drawings_keys_believes_the_picture_chooser() -> void:
	# A file dialog holds the keyboard while it is up, and the drawing's own keys - Ctrl+Z among them -
	# must not be taken while somebody is choosing a file.
	_clean()
	var controller := _drawn(1)
	var hud := _hud_for(controller)
	hud._build_file_dialogs()
	assert(not hud._file_dialog_open(), "with no dialog up the guard is open")
	hud._underlay_dialog.visible = true
	assert(hud._file_dialog_open(), "the picture chooser holds it while it is up")
	hud._underlay_dialog.visible = false
	assert(not hud._file_dialog_open(), "and lets go of it when it is not")
	controller.free()
	hud.free()
	_clean()