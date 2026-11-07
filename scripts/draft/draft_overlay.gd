class_name DraftOverlay
extends Node3D
## Draws the drafting document flat on the ground, so the design is visible in
## the 3D views and not only in the flat plan.
##
## Godot has no line primitive with a width, so a stroke becomes a ribbon: each
## segment is extruded sideways into a quad and the quads are lit as unshaded
## vertex colours. That keeps every layer in one surface, drawn in its own
## colour, with one material.
##
## The committed linework and the ghost of the shape in progress are separate
## meshes. The document only changes when an entity is added, so it is rebuilt
## there, while the ghost follows the cursor every frame and must not force a
## rebuild of the whole drawing.

const DraftRenderScript := preload("res://scripts/draft/draft_render.gd")

## Height above the ground, clear of both z-fighting with the lawn and the
## paving and path meshes, which sit a few centimetres up.
var ground_y: float = 0.10
## Width of a stroke on the ground, in metres. Line weights are paper
## properties and mean nothing to a perspective view, so 3D gets one readable
## width and the plan keeps the authoring-accurate one. A 0.25 mm hairline at
## 1:100 is well under two pixels on the ground and effectively invisible,
## which is why this is centimetres rather than millimetres.
var ribbon_width: float = 0.08
var display_scale: float = 100.0

var document: DraftDocument = null

var _committed: MeshInstance3D = null
var _ghost: MeshInstance3D = null
var _material: StandardMaterial3D = null


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	# A ribbon seen from below as well as above has to draw either way, or a
	# winding-order mistake shows up as linework that vanishes from one side.
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_committed = _make_layer("DraftLinework")
	_ghost = _make_layer("DraftGhost")


func _make_layer(layer_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = layer_name
	instance.mesh = ImmediateMesh.new()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func bind_document(doc) -> void:
	if document != null and document.changed.is_connected(_on_document_changed):
		document.changed.disconnect(_on_document_changed)
	document = doc
	if document != null:
		document.changed.connect(_on_document_changed)
	rebuild()


func _on_document_changed() -> void:
	rebuild()


## Rebuild the committed linework. Only call this when the document changed.
func rebuild() -> void:
	if _committed == null:
		return
	var quads: Array = []
	if document != null:
		_collect_entities(document.visible_entities(), quads)
	_emit(_committed, quads)


## The shape as it would be if the user picked at the cursor. Separate from the
## document so following the mouse does not rebuild the whole drawing.
func set_ghost(entity, layer) -> void:
	if _ghost == null:
		return
	var quads: Array = []
	if entity != null and not DraftRenderScript.is_annotation(entity):
		var colour: Color = DraftRenderScript.screen_colour(layer)
		# Half transparent, so a ghost is unmistakably not yet committed.
		colour.a = 0.5
		_collect_stroke(quads, DraftRenderScript.strokes(entity, layer, display_scale), colour)
	_emit(_ghost, quads)


func clear_ghost() -> void:
	set_ghost(null, null)


func _collect_entities(entities: Array, quads: Array) -> void:
	for entity in entities:
		# Dimensions and notes annotate the sheet, not the garden. They are drawn
		# in the flat plan and plotted on the sheet, but nothing stands on the
		# ground for them.
		if DraftRenderScript.is_annotation(entity):
			continue
		var layer = document.layers.get_layer(entity.layer)
		_collect_stroke(
			quads,
			DraftRenderScript.strokes(entity, layer, display_scale),
			DraftRenderScript.screen_colour(layer)
		)


## One record per segment, so the pieces are all known before any surface is
## begun and an empty drawing is detectable.
func _collect_stroke(quads: Array, strokes: Array, colour: Color) -> void:
	for stroke: PackedVector2Array in strokes:
		for index in stroke.size() - 1:
			var a: Vector2 = stroke[index]
			var b: Vector2 = stroke[index + 1]
			if (b - a).length_squared() < 1e-12:
				continue
			quads.append({"a": a, "b": b, "colour": colour})


## Godot raises an error for a surface with no vertices, so an empty drawing
## leaves the mesh with no surface at all rather than an empty one.
func _emit(instance: MeshInstance3D, quads: Array) -> void:
	var mesh := ImmediateMesh.new()
	if not quads.is_empty():
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
		for quad: Dictionary in quads:
			_add_ribbon_segment(mesh, quad["a"], quad["b"], quad["colour"])
		mesh.surface_end()
	instance.mesh = mesh


func _add_ribbon_segment(mesh: ImmediateMesh, a: Vector2, b: Vector2, colour: Color) -> void:
	var delta := b - a
	var normal := Vector2(-delta.y, delta.x).normalized() * (ribbon_width * 0.5)
	_add_quad(mesh, a - normal, a + normal, b + normal, b - normal, colour)


func _add_quad(
	mesh: ImmediateMesh,
	p0: Vector2,
	p1: Vector2,
	p2: Vector2,
	p3: Vector2,
	colour: Color
) -> void:
	mesh.surface_set_color(colour)
	mesh.surface_add_vertex(_to_world(p0))
	mesh.surface_set_color(colour)
	mesh.surface_add_vertex(_to_world(p1))
	mesh.surface_set_color(colour)
	mesh.surface_add_vertex(_to_world(p2))
	mesh.surface_set_color(colour)
	mesh.surface_add_vertex(_to_world(p0))
	mesh.surface_set_color(colour)
	mesh.surface_add_vertex(_to_world(p2))
	mesh.surface_set_color(colour)
	mesh.surface_add_vertex(_to_world(p3))


## Model XZ lies on the world XZ plane, with model +y going to world +z: the
## same convention the flat plan draws with.
func _to_world(point: Vector2) -> Vector3:
	return Vector3(point.x, ground_y, point.y)