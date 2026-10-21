class_name DerivedBuilder
extends Node3D
## Builds the solids the drawing implies, and keeps one mesh per entity (§8.7).
##
## The 2D plan is not an import: it is *the* design, and this is its derivation into 3D
## (REQ-V8.1). The mapping is deliberately one-to-one in both directions — a mesh knows
## the id of the entity it pictures, and an entity's edit **replaces** its mesh rather
## than adding a second one — because that is what makes "the mesh is a picture of the
## entity" true over time and not only at first build.
##
## **Nothing here is edited in place.** A mesh edited by hand is a design fact living in
## two places, which is the failure the whole visualization specification exists to
## prevent; so a rebuild throws its meshes away and derives them again.
##
## Rebuilding is on the document's own change signal, debounced. Dragging a patio's
## corner emits a change per frame, and a mesh per frame is what turns a smooth drag into
## a stutter (REQ-V8.8), so the signal only raises a flag and `_process` decides when.

const CadSolidScript := preload("res://scripts/vis/cad_solid.gd")
const SolidTableScript := preload("res://scripts/vis/solid_table.gd")
const HardscapeScript := preload("res://scripts/vis/hardscape_material.gd")

## At most one rebuild per this many seconds.
const REBUILD_INTERVAL := 0.15

## Emitted after a rebuild: how many solids stand, and how many entities were refused.
signal rebuilt(solids: int, refusals: int)
## Emitted when an entity cannot become a solid, with the reason. A named refusal is a
## two-minute fix in the plan; a silently missing patio is a support call (REQ-V8.2).
signal refused(entity_id: int, layer_name: StringName, reason: String)

## The scene's view controller, which owns the drafting controller and so the document.
##
## A plain `Node` rather than a typed export, so this file does not have to preload the
## controller and drag its dependencies into a builder that only needs one property off
## it. `_ready()` asks; if there is no answer, it says so rather than deriving nothing
## quietly.
@export var view_controller: Node = null

## The drafting document. Set by `bind_document()`, which is also what connects the
## change signal — binding is the caller's whole job, as it is for `DraftOverlay`.
var document = null

var _dirty: bool = false
var _timer: float = 0.0

## Entity id -> the MeshInstance3D picturing it. Also what makes a delete a removal.
var _built: Dictionary[int, Node] = {}
## Entity id -> why it is not standing, so a refusal survives until it is fixed.
var _refusals: Dictionary[int, String] = {}
## Material set name -> the built material, so fifty patio slabs share one material.
var _materials: Dictionary[String, StandardMaterial3D] = {}
## What the last rebuild did, for a status line.
var _last: Dictionary = {}


func _ready() -> void:
	set_process(true)
	if view_controller == null:
		# No controller named at all: this builder is being driven by hand, which is how a
		# test uses it. Nothing to warn about.
		return
	var controller: Node = null
	if view_controller.has_method("draft_controller"):
		controller = view_controller.draft_controller()
	if controller == null:
		push_warning(
			"DerivedBuilder: the view controller has no drafting controller, so the "
			+ "drawing has nothing to derive into solids."
		)
		return
	bind_document(controller.document)
	# Opening a drawing - or restoring a revision of it, or recovering a copy - *replaces* the
	# document rather than editing it, and the controller says so. Without this the builder keeps
	# deriving the drawing that was replaced: the working plan and the 3D linework follow the new
	# one, and the solids (which are where the buildings, the paving and the decks come from)
	# quietly do not, so a presentation comes out with the planting standing in an empty garden.
	#
	# Through `connect()` by name rather than a typed property access, because `controller` is a
	# plain `Node` here on purpose - see `view_controller`.
	if controller.has_signal(&"document_replaced"):
		controller.connect(&"document_replaced", _on_document_replaced)


## Follow the drawing that just replaced the one in hand.
func _on_document_replaced(opened) -> void:
	bind_document(opened)


## Follow a document, and rebuild when it changes.
func bind_document(doc) -> void:
	if document != null and document.changed.is_connected(mark_dirty):
		document.changed.disconnect(mark_dirty)
	document = doc
	if document != null:
		document.changed.connect(mark_dirty)
	mark_dirty()


## Called from the document's change signal. Deliberately cheap: it raises a flag, so a
## drag costs a flag per frame rather than a mesh.
func mark_dirty() -> void:
	_dirty = true


func _process(delta: float) -> void:
	if not _dirty:
		return
	_timer += delta
	if _timer < REBUILD_INTERVAL:
		return
	_dirty = false
	_timer = 0.0
	rebuild()


## Derive every solid the drawing implies, replacing what stood before.
func rebuild() -> void:
	if document == null:
		_refusals.clear()
		_last = {"solids": 0, "refusals": 0, "reason": "no document"}
		return
	var refusal_ids: Dictionary[int, String] = {}
	var standing: Dictionary[int, bool] = {}
	var drawn := 0
	# `entities()` is the document's own draw order — the layer bands, heaviest first —
	# which is the same order the working plan and the plotted sheet draw in. There is no
	# separate list to keep in step, which is the point of deriving from the document.
	for entity in document.entities():
		var layer = document.layers.get_layer(entity.layer)
		if layer == null:
			continue
		var spec: Dictionary = SolidTableScript.solid_for(layer.name)
		if spec.is_empty() or not layer.plots:
			continue
		var id := int(entity.id)
		var mesh: ArrayMesh = mesh_for(entity, spec)
		if mesh == null:
			# Already said why, in a message naming the problem. Recorded as well so the
			# report can count it and a status line can show it.
			refusal_ids[id] = "the outline could not be made solid"
			refused.emit(id, layer.name, refusal_ids[id])
			continue
		standing[id] = true
		_place(id, mesh, bool(spec["collide"]), String(spec["material_set"]))
		drawn += 1
	_refusals = refusal_ids
	_remove_gone(standing)
	_last = {
		"solids": drawn,
		"refusals": refusal_ids.size(),
		"entities": document.count(),
	}
	rebuilt.emit(drawn, refusal_ids.size())


## The mesh for one entity, or null.
##
## Static, and pure in the two arguments that matter — this is REQ-V8.9: the same entity
## and the same table entry give the same mesh, so two builds can be compared by vertex
## count and bounds, which is what the test does.
static func mesh_for(entity, spec: Dictionary) -> ArrayMesh:
	if entity == null or spec.is_empty():
		return null
	if entity.is_closed():
		var outline: PackedVector2Array = CadSolidScript.outline_of(entity)
		if outline.size() < CadSolidScript.MIN_RING_POINTS:
			return null
		return CadSolidScript.slab(
			outline, float(spec["base_m"]), float(spec["height_m"])
		)
	# Open linework: a centreline, so it becomes a ribbon of the layer's width. An
	# annotation has no linework to give, and `outline()` answers empty for one.
	var line: PackedVector2Array = entity.outline()
	if line.size() < 2:
		return null
	if not SolidTableScript.wants_ribbon(false, float(spec["width_m"])):
		# A layer whose width is zero is a surface, and an open line has no inside. Not an
		# error: a line drawn on a paving layer is a kerb that nobody has given a width to
		# yet. Note the `false`: this branch is only reached by linework that is *not*
		# closed, and asking the table whether a closed shape wants a ribbon — which it
		# never does — would refuse every kerb in the drawing.
		return null
	return CadSolidScript.ribbon(
		line, float(spec["width_m"]), float(spec["base_m"]), float(spec["height_m"])
	)


## Every texture set this builder has been asked for, so a diagnostic can check them.
func material_sets() -> Array[String]:
	var out: Array[String] = []
	for set_key: String in _materials:
		out.append(set_key)
	return out


## What the last rebuild did, for a status line or a test.
func report() -> Dictionary:
	return _last.duplicate()


## How many solids are standing.
func loft_count() -> int:
	return _built.size()


## Why an entity is not standing, or "" when it is.
func refusal_for(entity_id: int) -> String:
	return String(_refusals.get(entity_id, ""))


## Every entity that could not be made solid, as id-and-reason pairs.
func refusals() -> Dictionary:
	return _refusals.duplicate()


## Throw the derived world away. Used when the drawing is emptied, and by a test.
func clear() -> void:
	for id: int in _built:
		var node: Node = _built[id]
		if is_instance_valid(node):
			node.queue_free()
	_built.clear()
	_refusals.clear()


# --- placing ---------------------------------------------------------------------------


## Put one mesh in the world, replacing whatever stood for that entity.
func _place(id: int, mesh: ArrayMesh, collide: bool, material_set: String) -> void:
	var node: MeshInstance3D = _built.get(id, null)
	if node != null and not is_instance_valid(node):
		node = null
	if node == null:
		node = MeshInstance3D.new()
		node.name = "Solid%d" % id
		add_child(node)
		_built[id] = node
	node.mesh = mesh
	node.material_override = _material_for(material_set)
	# A collider is rebuilt with its mesh rather than kept, because a collider that no
	# longer matches its mesh is a wall in a place the drawing does not have one
	# (REQ-V8.7). Only where the table says so: a bed the player trips over is a bug.
	_clear_collision(node)
	if collide:
		node.create_trimesh_collision()


func _material_for(material_set: String) -> StandardMaterial3D:
	if _materials.has(material_set):
		return _materials[material_set]
	var material: StandardMaterial3D = HardscapeScript.build(material_set)
	# Cached whether or not it built: an unknown set errors once per rebuild otherwise,
	# and the cache is also the record of what has been asked for.
	_materials[material_set] = material
	return material


static func _clear_collision(node: MeshInstance3D) -> void:
	for child: Node in node.get_children():
		if child is StaticBody3D or child is CollisionShape3D or child is Area3D:
			node.remove_child(child)
			child.queue_free()


## Free the meshes whose entities are gone, so a deleted patio does not keep standing.
func _remove_gone(standing: Dictionary) -> void:
	for id: int in _built.keys():
		if standing.has(id):
			continue
		var node: Node = _built[id]
		if is_instance_valid(node):
			node.queue_free()
		_built.erase(id)


## The builder in one line, for a status bar.
func describe() -> String:
	if document == null:
		return "no drawing is bound to the solids"
	if _last.is_empty():
		return "the solids have not been rebuilt yet"
	return "%d solid%s from %d drawn, %d refused" % [
		int(_last.get("solids", 0)),
		"" if int(_last.get("solids", 0)) == 1 else "s",
		int(_last.get("entities", 0)),
		int(_last.get("refusals", 0)),
	]