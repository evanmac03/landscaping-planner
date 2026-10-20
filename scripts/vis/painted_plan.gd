class_name PaintedPlan
extends Node
## The painted plan: the design washed in colour over paper, at a plot scale.
##
## This is the *painted* path of §2.3. It bakes the drawing's layers to textures,
## composites them over paper and hands back an image. It is slow and it is
## deterministic; the working plan stays instant, unwobbled and unpainted, and the two
## must agree about the geometry, because both read the same entities through the same
## renderer (REQ-V2.3).
##
## Nothing here knows what a bed is: the wash comes from the layer table, the regions
## from the entities, and the colours from `PlanStyle`. This node's whole job is the
## order of operations and the framing.

## The image is ready. `report` is what it is a picture of, for a caption.
signal painted(image: Image, report: Dictionary)
## It could not be made, and the reason is for a person rather than a log.
signal paint_failed(reason: String)

const WashPainterScript := preload("res://scripts/vis/wash_painter.gd")
const SketchBakerScript := preload("res://scripts/vis/sketch_baker.gd")
const StillExporterScript := preload("res://scripts/vis/still_exporter.gd")
const SidecarScript := preload("res://scripts/vis/still_sidecar.gd")
const PlanCanvasScript := preload("res://scripts/plan_canvas.gd")

## The drawing the painted path reads its entities from, and the 3D node that holds
## the planted props.
@export var view_controller: ViewController
@export var yard: Node3D
## The scale the drawing is painted at. Every wash length and every line weight is
## authored in paper millimetres, so this is the number that makes them mean
## something (drafting spec §3).
@export var plot_scale: float = 100.0
## The sheet: A3 landscape unless somebody wants another.
@export var paper_mm: Vector2 = SketchBakerScript.PAPER_A3
## The bake's resolution. High enough that the paper texture has something to work
## with, low enough that a bake is a fraction of a second.
@export var texels_per_mm: float = SketchBakerScript.TEXELS_PER_MM
## Air left around the drawing, as a share of its own size. A plan that ends exactly
## at the fence line looks cropped rather than framed.
@export var margin: float = 0.12

## One render at a time. Two overlapping bakes would fight over the paper, and the
## second one would silently win.
var _busy: bool = false
## What the last image was a picture of.
var _report: Dictionary = {}


func is_busy() -> bool:
	return _busy


## What the last render was a picture of, for a caption or a test.
func last_report() -> Dictionary:
	return _report.duplicate()


## The drafting document, or null when the scene has no drafting controller.
func document():
	if view_controller == null:
		return null
	var controller = view_controller.draft_controller()
	return controller.document if controller != null else null


## The planted props, by the same rule the working plan uses to find them: the
## children of the yard's `Plants` subtree. One rule, so a prop cannot be in the flat
## plan and missing from the painted one.
func props() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if yard == null:
		return out
	var plants: Node = yard.get_node_or_null(NodePath(PlanCanvasScript.PLANTS))
	if plants == null:
		return out
	for child in plants.get_children():
		if child is Node3D:
			out.append(child)
	return out


## The ground the painting has to cover: everything drawn, plus every canopy, grown
## by the margin.
##
## Canopies are included because a tree's wash is wider than the bed it stands in,
## and a drawing framed by its entities alone would crop the trees at the edge of the
## plan.
func paint_bounds() -> Rect2:
	var box := Rect2()
	var empty := true
	var doc = document()
	if doc != null and int(doc.count()) > 0:
		box = doc.bounds()
		empty = false
	for node: Node3D in props():
		var radius: float = PlanStyle.footprint_radius(node)
		var centre := Vector2(node.global_position.x, node.global_position.z)
		var footprint := Rect2(centre - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
		box = footprint if empty else box.merge(footprint)
		empty = false
	if empty:
		return Rect2()
	return box.grow(maxf(box.size.x, box.size.y) * margin)


## Why the plan cannot be painted at this moment, or "" when it can.
##
## A function rather than a branch inside `render()`, because this is the part a
## caller wants to ask *before* pressing anything - a button that greys itself out
## and says why is better than one that does nothing - and because it is a sentence
## that can be asserted without a renderer.
func refusal() -> String:
	if _busy:
		return "a painted plan is already being made."
	if paint_bounds().size.x <= 0.0 or paint_bounds().size.y <= 0.0:
		# Nothing drawn and nothing planted is a state a person can be in - they have
		# just opened a new document - so it is reported, not logged as an error.
		return "there is nothing to paint yet: draw something, or plant something."
	return ""


## Paint the plan. Returns the image, or null when there is nothing to paint or the
## bake could not be read.
##
## Asynchronous, and it says what happened by signal as well as by return value: the
## caller is a status line as often as it is a caller, and a function that blocks the
## frame it was pressed in would stall the view it is drawing.
func render() -> Image:
	var reason := refusal()
	if reason != "":
		paint_failed.emit(reason)
		return null
	var bounds := paint_bounds()
	_busy = true
	var doc = document()
	var painter := WashPainterScript.new(doc, plot_scale, props())
	# Made per render rather than kept: it carries this render's paper size, and a
	# bake's settings that outlive the bake are settings somebody will change and
	# then wonder why nothing happened.
	var baker := SketchBakerScript.new()
	baker.name = "SketchBaker"
	baker.paper_mm = paper_mm
	baker.texels_per_mm = texels_per_mm
	add_child(baker)
	var baked: Dictionary = await baker.bake([painter], bounds, plot_scale)
	var textures: Array = baked.get("textures", [])
	if textures.is_empty():
		_busy = false
		baker.queue_free()
		paint_failed.emit("the bake came back empty.")
		return null
	var layer: Image = (textures[0] as Texture2D).get_image()
	baker.queue_free()
	_busy = false
	if layer == null or layer.is_empty():
		paint_failed.emit("the bake could not be read.")
		return null

	# Paper under the pigment, in one pass, by the same function the still path uses:
	# a transparent layer read into an image viewer shows as black, and a proposal
	# that opens as a black rectangle has failed at the last step (REQ-V10.4).
	var image: Image = StillExporterScript.flatten_over(layer, paper_colour())
	_report = _make_report(image, bounds)
	painted.emit(image, _report)
	return image


## Write a painted plan into the proposals folder, with the record that says how it
## was made. Returns the absolute path, or "" when it could not be written.
##
## Separate from `render()` on purpose: looking at the painted plan and filing it are
## two decisions, and the second one should not happen because somebody pressed a key
## to look.
func save(image: Image, base_name: String = "painted-plan") -> String:
	if image == null or image.is_empty():
		paint_failed.emit("there is no painted plan to save.")
		return ""
	var file_name := StillExporterScript.timestamp_name(base_name)
	var path: String = StillExporterScript.write_png(image, file_name)
	if path == "":
		paint_failed.emit("the painted plan could not be written.")
		return ""
	SidecarScript.write(path, _record_for_file(image))
	return path


## The paper. The working plan draws on the same colour, so switching between the
## two views does not change the sheet under the drawing.
func paper_colour() -> Color:
	return PlanCanvasScript.PAPER


## What this image is a picture of: the sheet, the scale, and how much of the drawing
## reached the paper.
func _make_report(image: Image, bounds: Rect2) -> Dictionary:
	var by_layer: Dictionary = {}
	var regions := 0
	var doc = document()
	if doc != null:
		var painter := WashPainterScript.new(doc, plot_scale, props())
		for entry: Dictionary in painter.regions():
			regions += 1
			var what := String(entry["what"])
			by_layer[what] = int(by_layer.get(what, 0)) + 1
		painter.free()
	return {
		"view": "Painted plan",
		"pixels": [image.get_width(), image.get_height()],
		"mm": [paper_mm.x, paper_mm.y],
		"plot_scale": plot_scale,
		"metres": [bounds.size.x, bounds.size.y],
		"regions": regions,
		"washes": by_layer,
		"props": props().size(),
	}


## A sidecar in the shape the still path writes, minus the parts a flat plan has not
## got: there is no sun and no camera in a drawing of the ground.
func _record_for_file(image: Image) -> Dictionary:
	return {
		"app": ProjectSettings.get_setting("application/config/name", "Backyard Design"),
		"view": "Painted plan",
		"rendered": Time.get_datetime_string_from_system(false, true),
		"output_px": [image.get_width(), image.get_height()],
		"paper_mm": [paper_mm.x, paper_mm.y],
		"texels_per_mm": texels_per_mm,
		"plot_scale": plot_scale,
		"document": {"entities": _entity_count()},
		"props": props().size(),
		"godot": Engine.get_version_info()["string"],
	}


func _entity_count() -> int:
	var doc = document()
	return int(doc.count()) if doc != null else 0