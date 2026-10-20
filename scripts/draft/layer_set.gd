class_name DraftLayerSet
extends RefCounted
## The preset layer convention, and the named layer states built on it.
##
## A new document starts with this set, so a conventional drawing comes out of
## the box without anyone assigning weights by hand. The numeric prefix of each
## name doubles as draw order and plotting band: lower sorts underneath and plots
## first (docs/drafting-subsystem-spec.md §5.1).
##
## Sibling modules are reached by preload rather than by global class name: the
## global registry is rewritten by the editor's scan, so a reference to a newly
## added script resolves sometimes and not others.

const DraftLayerScript := preload("res://scripts/draft/draft_layer.gd")

# Well-known names, so code and tests never spell a layer by hand.
const SURVEY_PROPERTY := &"010-SURVEY-PROP"
const SURVEY_ANNOTATION := &"011-SURVEY-ANNO"
const SETBACK_EASEMENT := &"020-SETBACK-EASE"
const EXISTING_STRUCTURE := &"100-EXIST-STRUCT"
const EXISTING_HARDSCAPE := &"101-EXIST-HARD"
const EXISTING_PLANTING := &"110-EXIST-PLANT"
const GRADING_CONTOUR := &"200-GRADE-CONT"
const GRADING_SPOT := &"201-GRADE-SPOT"
const NEW_HARDSCAPE := &"300-NEW-HARD"
const NEW_STRUCTURE := &"301-NEW-STRUCT"
const NEW_BED := &"400-NEW-BED"
const NEW_PLANTING := &"401-NEW-PLANT"
const NEW_TURF := &"402-NEW-TURF"
const IRRIGATION := &"500-IRRIGATION"
const LIGHTING := &"501-LIGHTING"
const HATCH := &"600-HATCH"
const DIMENSION := &"700-DIMENSION"
const TEXT := &"710-TEXT"
const CALLOUT := &"720-CALLOUT"
const SHEET_BORDER := &"900-SHEET-BORDER"
const SHEET_VIEWPORT := &"901-SHEET-VPORT"
const UNDERLAY := &"950-UNDERLAY"
const GUIDES := &"960-GUIDES"

## Conventional drafting colours.
const BLUE := Color(0.15, 0.35, 0.85)
const MAGENTA := Color(0.78, 0.22, 0.78)
const CYAN := Color(0.10, 0.60, 0.72)
const GREEN := Color(0.18, 0.60, 0.28)
const YELLOW := Color(0.80, 0.66, 0.10)
const RED := Color(0.83, 0.22, 0.20)
const GREY := Color(0.52, 0.52, 0.52)
## The "white" pen of a pen table is the black one on paper.
const INK := Color(0.10, 0.10, 0.12)

## name, purpose, colour, weight (mm), linetype, plots.
const PRESETS: Array[Dictionary] = [
	{
		"name": SURVEY_PROPERTY, "purpose": "Property lines",
		"colour": BLUE, "weight": 0.35, "linetype": &"continuous", "plots": true,
	},
	{
		"name": SURVEY_ANNOTATION, "purpose": "Bearings, distances, stated area",
		"colour": BLUE, "weight": 0.18, "linetype": &"continuous", "plots": true,
	},
	{
		"name": SETBACK_EASEMENT, "purpose": "Setbacks, easements, zoning",
		"colour": MAGENTA, "weight": 0.18, "linetype": &"dashed", "plots": true,
	},
	{
		"name": EXISTING_STRUCTURE, "purpose": "Existing buildings",
		"colour": CYAN, "weight": 0.50, "linetype": &"continuous", "plots": true,
	},
	{
		"name": EXISTING_HARDSCAPE, "purpose": "Existing paving, walls, drives",
		"colour": CYAN, "weight": 0.25, "linetype": &"continuous", "plots": true,
	},
	{
		"name": EXISTING_PLANTING, "purpose": "Existing plant material",
		"colour": GREEN, "weight": 0.13, "linetype": &"continuous", "plots": true,
	},
	{
		"name": GRADING_CONTOUR, "purpose": "Contours",
		"colour": YELLOW, "weight": 0.25, "linetype": &"continuous", "plots": true,
	},
	{
		"name": GRADING_SPOT, "purpose": "Spot elevations",
		"colour": YELLOW, "weight": 0.18, "linetype": &"continuous", "plots": true,
	},
	{
		"name": NEW_HARDSCAPE, "purpose": "New paving, walls, steps",
		"colour": RED, "weight": 0.50, "linetype": &"continuous", "plots": true,
	},
	{
		"name": NEW_STRUCTURE, "purpose": "Deck, pergola, structure",
		"colour": RED, "weight": 0.50, "linetype": &"continuous", "plots": true,
	},
	{
		"name": NEW_BED, "purpose": "Bed outlines and edging",
		"colour": RED, "weight": 0.35, "linetype": &"continuous", "plots": true,
	},
	{
		"name": NEW_PLANTING, "purpose": "Plant symbols and labels",
		"colour": GREEN, "weight": 0.13, "linetype": &"continuous", "plots": true,
	},
	{
		"name": NEW_TURF, "purpose": "Lawn and seeding areas",
		"colour": GREEN, "weight": 0.25, "linetype": &"continuous", "plots": true,
	},
	{
		"name": IRRIGATION, "purpose": "Heads, zones, pipe runs",
		"colour": CYAN, "weight": 0.18, "linetype": &"continuous", "plots": true,
	},
	{
		"name": LIGHTING, "purpose": "Fixtures, cable runs",
		"colour": YELLOW, "weight": 0.18, "linetype": &"continuous", "plots": true,
	},
	{
		"name": HATCH, "purpose": "Paving, mulch, grading patterns",
		"colour": GREY, "weight": 0.13, "linetype": &"continuous", "plots": true,
	},
	{
		"name": DIMENSION, "purpose": "Dimensions",
		"colour": MAGENTA, "weight": 0.18, "linetype": &"continuous", "plots": true,
	},
	{
		"name": TEXT, "purpose": "Notes and labels",
		"colour": INK, "weight": 0.18, "linetype": &"continuous", "plots": true,
	},
	{
		"name": CALLOUT, "purpose": "Leaders, keys, plant tags",
		"colour": INK, "weight": 0.18, "linetype": &"continuous", "plots": true,
	},
	{
		"name": SHEET_BORDER, "purpose": "Border and title block",
		"colour": INK, "weight": 0.70, "linetype": &"continuous", "plots": true,
	},
	{
		"name": SHEET_VIEWPORT, "purpose": "Viewport frames",
		"colour": INK, "weight": 0.13, "linetype": &"continuous", "plots": true,
	},
	{
		"name": UNDERLAY, "purpose": "Imported survey raster (tracing aid)",
		"colour": GREY, "weight": 0.13, "linetype": &"continuous", "plots": false,
	},
	{
		"name": GUIDES, "purpose": "Construction lines and guides",
		"colour": GREY, "weight": 0.13, "linetype": &"dotted", "plots": false,
	},
]

## Named layer states, each listing the layers it shows.
const STATES := {
	"Base plan": [
		SURVEY_PROPERTY, SURVEY_ANNOTATION, SETBACK_EASEMENT,
		EXISTING_STRUCTURE, EXISTING_HARDSCAPE, EXISTING_PLANTING,
		GRADING_CONTOUR, GRADING_SPOT, UNDERLAY,
	],
	"Layout / hardscape": [
		SURVEY_PROPERTY, SURVEY_ANNOTATION, SETBACK_EASEMENT,
		EXISTING_STRUCTURE, EXISTING_HARDSCAPE, EXISTING_PLANTING,
		GRADING_CONTOUR, GRADING_SPOT, NEW_HARDSCAPE, NEW_STRUCTURE,
		DIMENSION, TEXT, CALLOUT, HATCH, UNDERLAY,
	],
	"Planting plan": [
		SURVEY_PROPERTY, SURVEY_ANNOTATION, EXISTING_STRUCTURE, EXISTING_HARDSCAPE,
		NEW_HARDSCAPE, NEW_BED, NEW_PLANTING, NEW_TURF, TEXT, CALLOUT, DIMENSION,
	],
	"Irrigation plan": [
		SURVEY_PROPERTY, SURVEY_ANNOTATION, EXISTING_STRUCTURE, EXISTING_HARDSCAPE,
		NEW_HARDSCAPE, NEW_BED, NEW_TURF, IRRIGATION, TEXT, CALLOUT,
	],
}

var _layers: Dictionary = {}
var _order: Array[StringName] = []


## Instantiate this script by path, for the reason given in line_style.gd.
static func _new() -> DraftLayerSet:
	return (load("res://scripts/draft/layer_set.gd") as GDScript).new()


## A fresh document's layer set.
static func default_set() -> DraftLayerSet:
	var layer_set := _new()
	for entry: Dictionary in PRESETS:
		var layer := DraftLayerScript.new()
		layer.name = entry["name"]
		layer.purpose = entry["purpose"]
		layer.screen_colour = entry["colour"]
		layer.plot_colour = entry["colour"]
		layer.plot_weight_mm = entry["weight"]
		layer.linetype = entry["linetype"]
		layer.plots = entry["plots"]
		layer_set.add(layer)
	return layer_set


func add(layer: DraftLayerScript) -> void:
	_layers[layer.name] = layer
	_rebuild_order()


func has(layer_name: StringName) -> bool:
	return _layers.has(layer_name)


func get_layer(layer_name: StringName) -> DraftLayerScript:
	return _layers.get(layer_name, null)


## Layers sorted by prefix, which is also plot and draw order.
func layers() -> Array[DraftLayerScript]:
	var out: Array[DraftLayerScript] = []
	for name: StringName in _order:
		out.append(_layers[name])
	return out


func names() -> Array[StringName]:
	return _order.duplicate()


func size() -> int:
	return _order.size()


## Layer names that actually plot, in draw order.
func plotting_names() -> Array[StringName]:
	var out: Array[StringName] = []
	for name: StringName in _order:
		if _layers[name].plots:
			out.append(name)
	return out


func set_visible(layer_name: StringName, visible: bool) -> void:
	var layer: DraftLayerScript = _layers.get(layer_name, null)
	if layer != null:
		layer.visible = visible


func set_locked(layer_name: StringName, locked: bool) -> void:
	var layer: DraftLayerScript = _layers.get(layer_name, null)
	if layer != null:
		layer.locked = locked


func visible_names() -> Array[StringName]:
	var out: Array[StringName] = []
	for name: StringName in _order:
		if _layers[name].visible:
			out.append(name)
	return out


## Show exactly the layers a state names, and hide the rest.
func apply_state(state_name: String) -> bool:
	if not STATES.has(state_name):
		return false
	var shown: Array = STATES[state_name]
	for name: StringName in _order:
		_layers[name].visible = shown.has(name)
	return true


static func state_names() -> Array[String]:
	var out: Array[String] = []
	for key: String in STATES:
		out.append(key)
	return out


## What a state shows, without applying it.
static func state_layers(state_name: String) -> Array:
	return STATES.get(state_name, []).duplicate()


## A deep copy, for the undo stack.
func copy() -> DraftLayerSet:
	var other := _new()
	for name: StringName in _order:
		other.add(_layers[name].copy())
	return other


func _rebuild_order() -> void:
	_order.clear()
	for name: StringName in _layers:
		_order.append(name)
	# The comparator is bound to a local first: a multi-line lambda written
	# directly inside the call trips the parser.
	var by_prefix := func(a: StringName, b: StringName) -> bool: return _layers[a].sort_key() < _layers[b].sort_key()
	_order.sort_custom(by_prefix)