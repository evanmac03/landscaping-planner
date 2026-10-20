class_name DraftEntity
extends RefCounted
## One piece of drafted geometry.
##
## Geometry is a **definition**, held in a flat double array, not a list of
## sampled points: an `ARC` stores its centre, radius and angles, so editing it
## means changing a parameter rather than moving points around its circumference.
## A flat array keeps a 5,000-vertex bed outline in one allocation instead of
## 5,000 objects, and it serialises directly
## (docs/drafting-subsystem-spec.md §4, drafting-module.md §7).
##
## Param layouts, per kind:
##
##     LINE          x0, y0, x1, y1
##     CIRCLE        cx, cy, r
##     ARC           cx, cy, r, start_angle, sweep_angle
##     POLYLINE      n, x0, y0, x1, y1, ...
##     POLYGON       n, x0, y0, x1, y1, ...
##     RECT          cx, cy, w, h, rotation
##     REGULAR_POLY  cx, cy, circumradius, n, rotation
##     DIMENSION     x0, y0, x1, y1, offset, dimension_kind
##     TEXT          x, y, rotation           (the string lives in meta)
##
## Sibling modules are reached by preload rather than by global class name: the
## global registry is rewritten by the editor's scan, so a reference to a newly
## added script resolves sometimes and not others.

const Geom := preload("res://scripts/draft/geom2d.gd")
const LineStyleScript := preload("res://scripts/draft/line_style.gd")

enum Kind {
	LINE,
	CIRCLE,
	ARC,
	POLYLINE,
	POLYGON,
	RECT,
	REGULAR_POLY,
	DIMENSION,
	TEXT,
}

enum DimensionKind {
	LINEAR,
	ALIGNED,
	ANGULAR,
	RADIUS,
}

## Chord tolerance used when an arc is sampled for drawing or hit-testing, in
## metres. Two millimetres is invisible at any plot scale a garden plan uses.
const DEFAULT_TOLERANCE := 0.002

var id: int = 0
var kind: Kind = Kind.LINE
var layer: StringName = &""
var params := PackedFloat64Array()
## One bulge per polyline or polygon vertex; 0 is a straight segment. Bulge is
## the DXF convention, tan(sweep / 4), and is what lets a rounded bed corner live
## inside a flat vertex array without a second entity.
var bulges := PackedFloat64Array()
## Optional per-entity override of the layer's style.
var style: LineStyleScript = null
var meta: Dictionary = {}


# --- construction -------------------------------------------------------------------


## Instantiate this script by path.
##
## `DraftEntity.new()` cannot be used here: the global class registry is rewritten
## by the editor's file-system scan, so a class_name that has not been registered
## yet is not resolvable as a *value* — type annotations are fine, values are not.
## On a fresh clone .godot/ is absent entirely, so a headless run hits the same
## wall. Resolving by path always works.
static func _new() -> DraftEntity:
	return (load("res://scripts/draft/draft_entity.gd") as GDScript).new()


static func make_line(a: Vector2, b: Vector2) -> DraftEntity:
	var entity := _new()
	entity.kind = Kind.LINE
	entity.params = PackedFloat64Array([a.x, a.y, b.x, b.y])
	return entity


static func make_circle(centre: Vector2, radius: float) -> DraftEntity:
	var entity := _new()
	entity.kind = Kind.CIRCLE
	entity.params = PackedFloat64Array([centre.x, centre.y, radius])
	return entity


static func make_arc(centre: Vector2, radius: float, start: float, sweep: float) -> DraftEntity:
	var entity := _new()
	entity.kind = Kind.ARC
	entity.params = PackedFloat64Array([centre.x, centre.y, radius, start, sweep])
	return entity


static func make_polyline(vertices: PackedVector2Array, close: bool = false) -> DraftEntity:
	var entity := _new()
	entity.kind = Kind.POLYGON if close else Kind.POLYLINE
	entity.params = _flatten(vertices)
	return entity


static func make_rectangle(centre: Vector2, size: Vector2, rotation: float = 0.0) -> DraftEntity:
	var entity := _new()
	entity.kind = Kind.RECT
	entity.params = PackedFloat64Array([centre.x, centre.y, size.x, size.y, rotation])
	return entity


static func make_regular_polygon(centre: Vector2, circumradius: float, sides: int, rotation: float = 0.0) -> DraftEntity:
	var entity := _new()
	entity.kind = Kind.REGULAR_POLY
	entity.params = PackedFloat64Array([centre.x, centre.y, circumradius, float(maxi(sides, 3)), rotation])
	return entity


static func make_text(at: Vector2, text: String, rotation: float = 0.0) -> DraftEntity:
	var entity := _new()
	entity.kind = Kind.TEXT
	entity.params = PackedFloat64Array([at.x, at.y, rotation])
	entity.meta = {"text": text}
	return entity


static func _flatten(vertices: PackedVector2Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.append(float(vertices.size()))
	for vertex: Vector2 in vertices:
		out.append(vertex.x)
		out.append(vertex.y)
	return out


# --- definition points --------------------------------------------------------------


## Number of definition points, i.e. the ones a grip edits.
func point_count() -> int:
	match kind:
		Kind.LINE:
			return 2
		Kind.CIRCLE, Kind.RECT, Kind.REGULAR_POLY:
			return 1
		Kind.ARC:
			return 3   # centre, start end, finish end
		Kind.POLYLINE, Kind.POLYGON:
			return int(params[0])
		Kind.DIMENSION:
			return 2
		_:
			return 1


## A definition point, in model XZ.
func point(index: int) -> Vector2:
	match kind:
		Kind.LINE, Kind.DIMENSION:
			return Vector2(params[index * 2], params[index * 2 + 1])
		Kind.CIRCLE:
			return Vector2(params[0], params[1])
		Kind.ARC:
			match index:
				0:
					return Vector2(params[0], params[1])
				1:
					return Geom.arc_point(Vector2(params[0], params[1]), params[2], params[3], params[4], 0.0)
				_:
					return Geom.arc_point(Vector2(params[0], params[1]), params[2], params[3], params[4], 1.0)
		Kind.POLYLINE, Kind.POLYGON:
			return Vector2(params[1 + index * 2], params[1 + index * 2 + 1])
		Kind.RECT, Kind.REGULAR_POLY:
			return Vector2(params[0], params[1])
		Kind.TEXT:
			return Vector2(params[0], params[1])
	return Vector2.ZERO


func set_point(index: int, value: Vector2) -> void:
	match kind:
		Kind.LINE, Kind.DIMENSION:
			params[index * 2] = value.x
			params[index * 2 + 1] = value.y
		Kind.CIRCLE, Kind.TEXT:
			params[0] = value.x
			params[1] = value.y
		Kind.ARC:
			if index == 0:
				var start := point(1)
				var finish := point(2)
				params[0] = value.x
				params[1] = value.y
				# Keep the ends fixed by recomputing radius and angles.
				var radius := value.distance_to(start)
				params[2] = radius
				params[3] = Geom.angle_of(start - value)
				var sweep := Geom.angle_of(finish - value) - params[3]
				params[4] = wrapf(sweep, -PI, PI)
		Kind.POLYLINE, Kind.POLYGON:
			params[1 + index * 2] = value.x
			params[1 + index * 2 + 1] = value.y
		Kind.RECT, Kind.REGULAR_POLY:
			params[0] = value.x
			params[1] = value.y


func points() -> PackedVector2Array:
	var out := PackedVector2Array()
	for index in point_count():
		out.append(point(index))
	return out


# --- outline ------------------------------------------------------------------------


## The entity as a polyline in model XZ, arcs sampled. This is what gets drawn,
## hit-tested and measured.
func outline(tolerance: float = DEFAULT_TOLERANCE) -> PackedVector2Array:
	match kind:
		Kind.LINE:
			return PackedVector2Array([point(0), point(1)])
		Kind.DIMENSION:
			return PackedVector2Array([point(0), point(1)])
		Kind.CIRCLE:
			return Geom.arc_points(Vector2(params[0], params[1]), params[2], 0.0, TAU, tolerance)
		Kind.ARC:
			return Geom.arc_points(Vector2(params[0], params[1]), params[2], params[3], params[4], tolerance)
		Kind.RECT:
			return _rectangle_corners()
		Kind.REGULAR_POLY:
			return _regular_polygon_corners()
		Kind.POLYLINE, Kind.POLYGON:
			return _polyline_outline(tolerance)
		_:
			return PackedVector2Array()


func is_closed() -> bool:
	return kind == Kind.POLYGON or kind == Kind.CIRCLE \
		or kind == Kind.RECT or kind == Kind.REGULAR_POLY


func _rectangle_corners() -> PackedVector2Array:
	var centre := Vector2(params[0], params[1])
	var half := Vector2(params[2] * 0.5, params[3] * 0.5)
	var rotation := params[4]
	var local := PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	var out := PackedVector2Array()
	for corner: Vector2 in local:
		out.append(centre + corner.rotated(rotation))
	return out


func _regular_polygon_corners() -> PackedVector2Array:
	var centre := Vector2(params[0], params[1])
	var radius := params[2]
	var sides := int(params[3])
	var rotation := params[4]
	var out := PackedVector2Array()
	for index in sides:
		var angle := rotation + TAU * float(index) / float(sides)
		out.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return out


## Vertices with any bulge expanded into sampled arc points.
func _polyline_outline(tolerance: float) -> PackedVector2Array:
	var count := int(params[0])
	if count == 0:
		return PackedVector2Array()
	var out := PackedVector2Array()
	var segments := count if is_closed() else count - 1
	for index in segments:
		var a := point(index)
		var b := point((index + 1) % count)
		var bulge := 0.0
		if index < bulges.size():
			bulge = bulges[index]
		if absf(bulge) <= Geom.EPS:
			out.append(a)
			continue
		var arc := Geom.arc_from_bulge(a, b, bulge)
		if not arc.get("ok", false):
			out.append(a)
			continue
		var sampled := Geom.arc_points(
			arc["centre"], arc["radius"], arc["start"], arc["sweep"], tolerance
		)
		# Drop the last point of each arc: it is the next segment's first point.
		for sample_index in maxi(sampled.size() - 1, 0):
			out.append(sampled[sample_index])
	if not is_closed():
		out.append(point(count - 1))
	return out


func aabb(tolerance: float = DEFAULT_TOLERANCE) -> Rect2:
	if kind == Kind.ARC:
		return Geom.arc_aabb(Vector2(params[0], params[1]), params[2], params[3], params[4])
	return Geom.points_aabb(outline(tolerance))


# --- measurement --------------------------------------------------------------------


func length() -> float:
	match kind:
		Kind.LINE, Kind.DIMENSION:
			return point(0).distance_to(point(1))
		Kind.CIRCLE:
			return TAU * params[2]
		Kind.ARC:
			return Geom.arc_length(params[2], params[4])
		Kind.RECT:
			return 2.0 * (params[2] + params[3])
		Kind.REGULAR_POLY:
			return Geom.polygon_perimeter(_regular_polygon_corners(), true)
		Kind.POLYLINE, Kind.POLYGON:
			return Geom.polygon_perimeter(outline(), is_closed())
		_:
			return 0.0


func area() -> float:
	match kind:
		Kind.CIRCLE:
			return PI * params[2] * params[2]
		Kind.RECT:
			return absf(params[2] * params[3])
		Kind.REGULAR_POLY:
			return Geom.polygon_area(_regular_polygon_corners())
		Kind.POLYGON:
			return Geom.polygon_area(outline())
		_:
			return 0.0


# --- bulk edits ---------------------------------------------------------------------


## Move every definition point by an offset. This is how a drag commits.
func translate(offset: Vector2) -> void:
	var count := point_count()
	if kind == Kind.POLYLINE or kind == Kind.POLYGON:
		for index in count:
			var p := point(index)
			set_point(index, p + offset)
		return
	# Circles, rectangles and regular polygons store a centre; the rest store
	# every point, so shifting the stored values is uniform.
	if kind == Kind.CIRCLE or kind == Kind.RECT or kind == Kind.REGULAR_POLY:
		params[0] += offset.x
		params[1] += offset.y
		return
	if kind == Kind.TEXT:
		params[0] += offset.x
		params[1] += offset.y
		return
	if kind == Kind.ARC:
		params[0] += offset.x
		params[1] += offset.y
		return
	for index in count:
		var p := point(index)
		set_point(index, p + offset)


## Rotate every point about a centre, for the rotate tool.
func rotate_about(centre: Vector2, angle: float) -> void:
	if kind == Kind.RECT or kind == Kind.REGULAR_POLY:
		params[4] += angle
	elif kind == Kind.TEXT:
		params[2] += angle
	var count := point_count()
	for index in count:
		var p := point(index)
		set_point(index, centre + (p - centre).rotated(angle))


func copy() -> DraftEntity:
	var other := _new()
	other.id = id
	other.kind = kind
	other.layer = layer
	other.params = params.duplicate()
	other.bulges = bulges.duplicate()
	other.style = null if style == null else style.copy()
	other.meta = meta.duplicate(true)
	return other


# --- serialisation ------------------------------------------------------------------


## JSON-safe representation. Packed arrays become plain arrays.
func to_dict() -> Dictionary:
	var style_dict := {}
	if style != null:
		style_dict = {
			"plot_weight_mm": style.plot_weight_mm,
			"linetype": String(style.linetype),
			"plot_colour": style.plot_colour.to_html(),
			"screen_colour": style.screen_colour.to_html(),
		}
	return {
		"id": id,
		"kind": int(kind),
		"layer": String(layer),
		"params": Array(params),
		"bulges": Array(bulges),
		"style": style_dict,
		"meta": meta.duplicate(true),
	}


static func from_dict(data: Dictionary) -> DraftEntity:
	var entity := _new()
	entity.id = int(data.get("id", 0))
	@warning_ignore("int_as_enum_without_cast")
	entity.kind = int(data.get("kind", Kind.LINE))
	entity.layer = StringName(data.get("layer", ""))
	var raw: Array = data.get("params", [])
	var values := PackedFloat64Array()
	for value in raw:
		values.append(float(value))
	entity.params = values
	var raw_bulges: Array = data.get("bulges", [])
	var bulge_values := PackedFloat64Array()
	for value in raw_bulges:
		bulge_values.append(float(value))
	entity.bulges = bulge_values
	var style_dict: Dictionary = data.get("style", {})
	if not style_dict.is_empty():
		var line := LineStyleScript.new()
		line.plot_weight_mm = float(style_dict.get("plot_weight_mm", 0.25))
		line.linetype = StringName(style_dict.get("linetype", "continuous"))
		line.plot_colour = Color.html(String(style_dict.get("plot_colour", "000000")))
		line.screen_colour = Color.html(String(style_dict.get("screen_colour", "000000")))
		entity.style = line
	entity.meta = data.get("meta", {}).duplicate(true)
	return entity


func kind_name() -> String:
	return Kind.keys()[kind]