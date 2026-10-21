extends Node
## The depth row on the takeoff tab: how a person states the depth that turns an area into a volume.
##
## The takeoff can measure a volume, and the desk can be told a depth, but a capability nobody can
## reach is not a feature - so this is the surface, driven the way a click drives it: `build()`, then
## the same methods the controls call (`choose_depth`, `_on_depth_stated`), on a `Window` a test never
## has to look at.
##
## The rules under test:
##
## * the chooser offers only layers measured by the **square metre**, because a depth cannot be stated
##   for a count - an offered choice must always be one the takeoff can act on;
## * stating a depth changes the takeoff's own line for that layer, from m² to m³, in the same gesture;
## * each test puts the layer table back the way it found it, because the depth lives on the practice's
##   layer rather than in a document and outlives the window - and it does so **before** it starts and
##   not only when it ends, because an assertion that throws skips the rest of its own test, and a leak
##   from one test must not decide the answer of the next.

const WindowScript := preload("res://scripts/estimate_window.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const TakeoffScript := preload("res://scripts/biz/takeoff.gd")
const WorkUnitScript := preload("res://scripts/biz/work_unit.gd")

const HARDSCAPE := &"300-NEW-HARD"
const PLANTING := &"401-NEW-PLANT"


## A drawing with a 6 x 4 m patio on it, which is 24 m² - or 1.2 m³ at 50 mm.
func _drawing() -> DraftDocument:
	var document: DraftDocument = Document.new()
	document.add(Entity.make_rectangle(Vector2(0, 0), Vector2(6, 4)), LayerSet.NEW_HARDSCAPE)
	document.add(Entity.make_circle(Vector2(20, 0), 1.5), LayerSet.NEW_PLANTING)
	return document


func _window(document: DraftDocument = null) -> EstimateWindow:
	var window: EstimateWindow = WindowScript.new()
	window.build()
	window.bind(document if document != null else _drawing())
	return window


## Put the hardscape layer back to measuring as an area, whether or not this test got that far.
func _forget_the_depth() -> void:
	TakeoffScript.clear_depth(HARDSCAPE)


## The row's own words for a layer, rather than an index: which entry is first is the chooser's own
## business, and a test that assumed an order would break the day the layer set gains a layer.
func _words_for(window: EstimateWindow, layer_name: StringName) -> String:
	var choices: Array[StringName] = window.depth_choices()
	var words: Array[String] = window.depth_texts()
	for index in choices.size():
		if choices[index] == layer_name:
			return words[index]
	return ""


# --- what the row offers ---------------------------------------------------------------------


func test_the_depth_row_offers_only_the_layers_measured_by_the_square_metre() -> void:
	# A planting is counted, and a count has no area to be deep: offering it would be offering a choice
	# the takeoff would then refuse, which is a row that cannot do what it says.
	_forget_the_depth()
	var window: EstimateWindow = _window()
	assert(window.depth_row_enabled(), "there is something to state a depth for")
	var offered: Array[StringName] = window.depth_choices()
	assert(offered.has(HARDSCAPE), "the hardscape layer is offered: %s" % str(offered))
	assert(not offered.has(PLANTING), "the planting layer is not, because it is counted")
	for layer_name: StringName in offered:
		var measure: StringName = TakeoffScript.measure_for(layer_name)
		assert(measure == WorkUnitScript.AREA or measure == WorkUnitScript.VOLUME,
			"%s is bought by a surface: %s" % [String(layer_name), String(measure)])
	window.free()


func test_each_choice_shows_how_deep_that_layer_is_bought() -> void:
	# The row is the only place on the panel where a depth is visible, so a layer already bought by the
	# volume has to say so - otherwise the row reads as though the decision had been forgotten.
	_forget_the_depth()
	var window: EstimateWindow = _window()
	var words: Array[String] = window.depth_texts()
	assert(words.size() == window.depth_choices().size(), "one line per choice")
	assert(window.depth_choices()[0] != &"", "and each line is about a layer")
	assert(_words_for(window, HARDSCAPE) == String(HARDSCAPE),
		"a layer with no depth says nothing about one: %s" % _words_for(window, HARDSCAPE))

	# Stated through the row's own gesture: choosing the layer, setting the depth, pressing the button.
	assert(window.choose_depth(HARDSCAPE), "the hardscape layer is chosen")
	window.set_depth_mm(50)
	window._on_depth_stated()
	assert(_words_for(window, HARDSCAPE).contains("50 mm"),
		"now it says how deep: %s" % _words_for(window, HARDSCAPE))
	assert(window.depth_mm() == 50, "and the box shows the layer's own depth: %d" % window.depth_mm())
	assert(window.depth_choice() == HARDSCAPE, "and the row is still pointed where a person pointed it")
	_forget_the_depth()
	window.free()


func test_a_drawing_with_nothing_measured_by_the_m2_has_a_dead_depth_row() -> void:
	# Refused where it is offered rather than at the point of use: a row that looks usable and then does
	# nothing is worse than a row that is greyed out.
	var bare: DraftDocument = Document.new()
	bare.layers = LayerSet.new()
	var window: EstimateWindow = _window(bare)
	assert(not window.depth_row_enabled(), "there is nothing to state a depth for")
	assert(window.depth_choices().is_empty(), "and nothing is offered")
	assert(window.depth_texts() == ["no layer here is bought by the square metre"], str(window.depth_texts()))
	window.free()


# --- stating one -------------------------------------------------------------------------------


func test_stating_a_depth_turns_the_layers_outlines_into_a_volume() -> void:
	_forget_the_depth()
	var window: EstimateWindow = _window()
	window.take_off()
	var before: String = " | ".join(window.takeoff_texts())
	assert(before.contains("24.000 m²"), "the patio is an area to begin with: %s" % before)

	assert(window.choose_depth(HARDSCAPE), "the hardscape layer is chosen")
	window.set_depth_mm(50)
	window._on_depth_stated()

	var after: String = " | ".join(window.takeoff_texts())
	assert(after.contains("1.200 m³"), "24 m² at 50 mm is 1.2 m³: %s" % after)
	assert(not after.contains("24.000 m²"), "and the area line is gone, so nothing is billed twice: %s" % after)
	assert(window.status_text().contains("300-NEW-HARD"), "the status names the layer: %s" % window.status_text())
	assert(window.status_text().contains("50 mm"), "and the depth: %s" % window.status_text())
	_forget_the_depth()
	window.free()


func test_the_depth_the_row_shows_is_the_one_the_takeoff_reads() -> void:
	# One answer to "how deep is this layer", read in exactly one place - the window shows it, the desk
	# reports it and the takeoff measures it, and none of the three keeps a copy of its own.
	_forget_the_depth()
	var window: EstimateWindow = _window()
	assert(window.choose_depth(HARDSCAPE), "the hardscape layer is chosen")
	window.set_depth_mm(150)
	window._on_depth_stated()
	var window_says: int = window.depth_mm()
	var desk_says: int = window.desk.layer_depth(HARDSCAPE)
	var takeoff_says: int = TakeoffScript.depth_of(HARDSCAPE)
	assert(window_says == 150, "the box shows 150: %d" % window_says)
	assert(desk_says == window_says, "the desk agrees: %d" % desk_says)
	assert(takeoff_says == window_says, "and so does the table the takeoff reads: %d" % takeoff_says)
	assert(TakeoffScript.is_volume_layer(HARDSCAPE), "and the layer is now bought by the cubic metre")
	_forget_the_depth()
	window.free()


func test_a_layer_the_takeoff_cannot_measure_has_no_depth_to_state() -> void:
	# The desk refuses and says so, in the words of the thing that decides: a depth that could be stated
	# for a layer no takeoff measures would be a switch wired to nothing.
	_forget_the_depth()
	var window: EstimateWindow = _window()
	assert(not window.desk.set_layer_depth(&"710-TEXT", 50), "an annotation is not work")
	assert(window.desk.layer_depth(&"710-TEXT") == 0, "and has no depth")
	assert(not window.desk.clear_layer_depth(&"710-TEXT"), "nor one to forget")
	assert(not window.desk.set_layer_depth(HARDSCAPE, 0), "and a depth of nothing is not a depth")
	assert(TakeoffScript.depth_of(HARDSCAPE) == 0, "nothing was stated")
	window.free()


func test_the_way_back_is_the_same_decision_taken_again() -> void:
	# A depth stated is a decision about the layer, and the way back is the same decision the other
	# way: forget the depth and the layer measures as the areas it always was.
	_forget_the_depth()
	TakeoffScript.set_depth(HARDSCAPE, 50)
	assert(TakeoffScript.is_volume_layer(HARDSCAPE), "the layer is a volume layer")
	var window: EstimateWindow = _window()
	window.take_off()
	assert(" | ".join(window.takeoff_texts()).contains("1.200 m³"), "and the patio is a volume")
	assert(window.desk.clear_layer_depth(HARDSCAPE), "the depth is forgotten")
	assert(not TakeoffScript.is_volume_layer(HARDSCAPE), "and the layer is an area layer again")
	assert(TakeoffScript.depth_of(HARDSCAPE) == 0, "with no depth")
	assert(window.desk.layer_depth(HARDSCAPE) == 0, "which the desk agrees with")
	assert(not window.desk.clear_layer_depth(HARDSCAPE), "and there is nothing left to forget")
	window.free()


# --- announcing it -----------------------------------------------------------------------------

var _announced: int = 0


func _note_the_change() -> void:
	_announced += 1


func test_stating_a_depth_tells_the_rest_of_the_program_the_estimate_moved() -> void:
	# The HUD's Estimate menu carries one line about where the job stands, in the desk's own words. A
	# depth changes the measurement, so it changes that line, so the change has to be announced - the
	# same announcement taking off, re-taxing, sending and revising each make.
	_forget_the_depth()
	_announced = 0
	var window: EstimateWindow = _window()
	window.estimate_changed.connect(_note_the_change)
	assert(window.choose_depth(HARDSCAPE), "the hardscape layer is chosen")
	window.set_depth_mm(50)
	window._on_depth_stated()
	assert(_announced == 1, "the change was announced once: %d" % _announced)
	_forget_the_depth()
	window.free()


# --- the guard on the shipped layer table ------------------------------------------------------


func test_forgetting_a_depth_leaves_the_shipped_layer_exactly_as_it_was() -> void:
	# `clear_depth` has to restore the shipped **shape** and not merely the measurement: a stale
	# `depth_mm` left on a layer measured as an area is a fact nothing reads until something does, and
	# then it is a layer that says it is two things at once.
	_forget_the_depth()
	var plan: Dictionary = TakeoffScript.measure_plan(HARDSCAPE)
	assert(StringName(plan["measure"]) == WorkUnitScript.AREA,
		"the shipped hardscape layer measures as an area: %s" % String(plan["measure"]))
	assert(not plan.has("depth_mm"), "and records no depth: %s" % str(plan.keys()))
	assert(TakeoffScript.depth_of(HARDSCAPE) == 0, "which is what depth_of reports")
	assert(not TakeoffScript.is_volume_layer(HARDSCAPE),
		"and the layer is not bought by the cubic metre: %s" % String(TakeoffScript.measure_for(HARDSCAPE)))