extends Node
## The map window on its own: the coordinates it shows and reads back, the buttons it arms, and the
## intents it announces.
##
## Built off-tree and never shown, the way the sheet window is tested: a window popped up needs a
## screen, and what is under test is the controls a person would be pressing rather than the frame
## around them.

const OsmWindowScript := preload("res://scripts/osm_window.gd")
const OsmFetchScript := preload("res://scripts/draft/osm_fetch.gd")


func _window():
	var window = OsmWindowScript.new()
	window.build()
	return window


func _done(window) -> void:
	window.free()


# --- the form --------------------------------------------------------------------------


func test_the_window_builds_the_controls_and_says_where_to_start() -> void:
	var window = _window()
	assert(window.get_node_or_null(^"Column/SiteRow/Latitude/LatitudeField") != null, "a latitude")
	assert(window.get_node_or_null(^"Column/SiteRow/Longitude/LongitudeField") != null, "a longitude")
	assert(window.get_node_or_null(^"Column/SiteRow/Radius/RadiusSpin") != null, "a radius")
	assert(window.get_node_or_null(^"Column/ReportBox/Report") != null, "and somewhere to read the report")
	assert(window.get_node_or_null(^"Column/Buttons/FetchButton") != null, "and the way to ask")
	assert(window.get_node_or_null(^"Column/Buttons/ImportButton") != null, "and the way to take it")
	assert(String(window.title).contains("OpenStreetMap"), String(window.title))
	_done(window)


func test_a_window_builds_itself_once_and_only_once() -> void:
	var window = _window()
	var before: int = window.get_node(^"Column").get_child_count()
	window.build()
	assert(window.get_node(^"Column").get_child_count() == before, "no second set of controls")
	_done(window)


func test_the_window_opens_on_the_site_it_is_told() -> void:
	var window = _window()
	window.show_site(43.7, -79.4)
	var centre: Dictionary = window.centre()
	assert(is_equal_approx(float(centre["latitude"]), 43.7), str(centre))
	assert(is_equal_approx(float(centre["longitude"]), -79.4), str(centre))
	assert(window.fetch_enabled(), "and a place is something that can be asked about")
	_done(window)


func test_the_fetch_button_is_dead_until_the_form_describes_a_place() -> void:
	var window = _window()
	assert(not window.fetch_enabled(), "an empty form is not a place")
	window.show_site(43.7, -79.4)
	assert(window.fetch_enabled())
	window.show_site(91.0, 0.0)
	assert(not window.fetch_enabled(), "and a latitude past the pole is not either")
	_done(window)


func test_coordinates_that_do_not_read_are_refused_rather_than_taken_as_nothing() -> void:
	var window = _window()
	window.show_site(43.7, -79.4)
	var field: LineEdit = window.get_node(^"Column/SiteRow/Latitude/LatitudeField")
	field.text = "north-ish"
	# A programmatic `text =` does not emit `text_changed`, so a test that types into a field has to
	# send the same signal a keystroke sends. Without this the form never hears the bad number.
	field.text_changed.emit(field.text)
	assert(is_nan(float(window.centre()["latitude"])), str(window.centre()))
	assert(not window.fetch_enabled(), "and the button says so rather than asking for the equator")
	var line: String = window.get_node(^"Column/Buttons/FetchButton").tooltip_text
	assert(not line.is_empty(), "with the reason on it: %s" % line)
	_done(window)


func test_the_radius_is_the_one_the_form_shows() -> void:
	var window = _window()
	assert(is_equal_approx(window.radius_m(), OsmFetchScript.DEFAULT_RADIUS_M), str(window.radius_m()))
	window.get_node(^"Column/SiteRow/Radius/RadiusSpin").value = 250.0
	assert(is_equal_approx(window.radius_m(), 250.0), str(window.radius_m()))
	_done(window)


# --- the intents it announces -----------------------------------------------------------


func test_asking_for_the_map_says_where_and_how_much() -> void:
	var window = _window()
	window.show_site(43.7, -79.4)
	var asked: Array = []
	window.fetch_requested.connect(func(centre: Dictionary, radius_m: float) -> void:
		asked.append([centre, radius_m])
	)
	window.get_node(^"Column/Buttons/FetchButton").pressed.emit()
	assert(asked.size() == 1, "once")
	assert(is_equal_approx(float(asked[0][0]["latitude"]), 43.7), str(asked))
	assert(is_equal_approx(float(asked[0][1]), OsmFetchScript.DEFAULT_RADIUS_M), str(asked))
	_done(window)


func test_opening_a_saved_map_and_putting_it_on_the_drawing_are_their_own_intents() -> void:
	var window = _window()
	# Counted in an array rather than an int: a GDScript lambda captures a local by value, so `opened += 1`
	# inside one would move a copy and leave the outer count at zero. An array is captured by reference.
	var opened: Array = []
	var imported: Array = []
	window.open_file_requested.connect(func() -> void: opened.append(true))
	window.import_requested.connect(func() -> void: imported.append(true))
	window.get_node(^"Column/Buttons/OpenButton").pressed.emit()
	window.get_node(^"Column/Buttons/ImportButton").pressed.emit()
	assert(opened.size() == 1, "opening is not importing")
	assert(imported.size() == 1)
	_done(window)


func test_closing_it_says_so_whether_it_was_the_button_or_the_frame() -> void:
	var window = _window()
	var closes: Array = []
	window.closed.connect(func() -> void: closes.append(true))
	window.get_node(^"Column/Buttons/CloseButton").pressed.emit()
	window.close_requested.emit()
	assert(closes.size() == 2, "the button and the window frame both mean closed: %d" % closes.size())
	_done(window)


# --- what it says ----------------------------------------------------------------------


func test_the_report_and_the_status_line_are_readable_without_looking_at_a_label() -> void:
	var window = _window()
	window.show_report("line one\nline two")
	assert(window.report_text() == "line one\nline two", window.report_text())
	assert(window.report_text().contains("line two"))
	window.say("asking OpenStreetMap...")
	assert(window.said_text() == "asking OpenStreetMap...", window.said_text())
	_done(window)


func test_the_import_button_is_dead_until_it_is_told_there_is_a_map() -> void:
	var window = _window()
	assert(not window.import_enabled(), "nothing in hand")
	window.set_import_enabled(true)
	assert(window.import_enabled())
	window.set_import_enabled(false)
	assert(not window.import_enabled())
	_done(window)


func test_the_window_explains_what_a_map_is_for_here() -> void:
	# The subject is not obvious - a person might reasonably think an OSM import is a survey - so the
	# window says, in its own words, that this lands on the layer that does not plot.
	var window = _window()
	var explanation: String = window.get_node(^"Column/Explanation").text
	assert(explanation.contains("OpenStreetMap"), explanation)
	assert(explanation.contains("underlay"), "it says where the map lands: %s" % explanation)
	_done(window)