extends Node
## The example garden's shapes (`res://scripts/example_garden.gd`), held without a drawing in sight.
##
## The rules that matter here are the ones a plan can be wrong about on its own: a shape the drawing cannot
## hold, a garden built out of one shape, an example that is a dot or a county rather than a backyard. How
## those shapes reach the drawing is the controller's, and is proved by `tools/start_door_demo.gd`'s cousin
## in `docs/` - the menu entry that loads this.

const ExampleScript := preload("res://scripts/example_garden.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")

## The kinds a drafting tool can make, which is the whole vocabulary a plan is written in.
const KINDS: Array[int] = [
	EntityScript.Kind.LINE, EntityScript.Kind.CIRCLE, EntityScript.Kind.ARC,
	EntityScript.Kind.POLYLINE, EntityScript.Kind.POLYGON, EntityScript.Kind.RECT,
	EntityScript.Kind.REGULAR_POLY, EntityScript.Kind.DIMENSION, EntityScript.Kind.TEXT,
]


## An example of nothing is not an example: the plan has enough shapes to be a garden, and every one of them
## is a shape the drawing tools can make, so nothing on it is geometry the program cannot edit.
func test_the_example_is_made_of_shapes_the_drawing_can_hold() -> void:
	var parts: Array[DraftEntity] = ExampleScript.parts()
	assert(parts.size() >= 8, "a garden is more than a few shapes: %d" % parts.size())
	for entity: DraftEntity in parts:
		assert(KINDS.has(int(entity.kind)), "kind %d is one of the drawing's own" % int(entity.kind))
		assert(entity.params.size() > 0, "and it carries the definition its kind needs")


## A plan is not one kind of thing: the example has to show closed outlines, an open one, a canopy circle, a
## measurement and words - otherwise it teaches nothing about what a plan is.
func test_the_example_shows_more_than_one_kind_of_shape() -> void:
	var kinds: Dictionary = {}
	for entity: DraftEntity in ExampleScript.parts():
		kinds[int(entity.kind)] = true
	assert(kinds.size() >= 5, "the example is a mixture, not a pile of one shape: %d kinds" % kinds.size())
	assert(kinds.has(int(EntityScript.Kind.RECT)), "with a rectangular bed in it")
	assert(kinds.has(int(EntityScript.Kind.CIRCLE)), "a tree's canopy")
	assert(kinds.has(int(EntityScript.Kind.POLYGON)), "the site's own boundary")
	assert(kinds.has(int(EntityScript.Kind.DIMENSION)), "and a measurement, which is what a drawing is for")
	assert(kinds.has(int(EntityScript.Kind.TEXT)), "and words saying what it is")


## The garden is the size of a garden. A shape at the origin only, or one a kilometre across, would both be
## an example of nothing anybody has a backyard like.
func test_the_example_is_the_size_of_a_backyard() -> void:
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	for entity: DraftEntity in ExampleScript.parts():
		for corner: Vector2 in _corners(entity):
			low = Vector2(minf(low.x, corner.x), minf(low.y, corner.y))
			high = Vector2(maxf(high.x, corner.x), maxf(high.y, corner.y))
	var across: float = high.x - low.x
	var deep: float = high.y - low.y
	assert(across >= 5.0 and across <= 60.0, "a backyard is metres across, not %s" % String.num(across, 1))
	assert(deep >= 5.0 and deep <= 60.0, "and metres deep, not %s" % String.num(deep, 1))
	assert(
		absf(across - ExampleScript.SITE.x) < 3.0,
		"and the shapes stay inside the site the example states: %s by %s" % [
			String.num(across, 1), String.num(deep, 1),
		]
	)


## The example names itself, because a menu entry and a status line both need a name and neither may invent
## one. And its one line counts its own shapes rather than a number typed twice.
func test_the_example_names_and_counts_itself() -> void:
	assert(not ExampleScript.NAME.is_empty(), "it has a name")
	var said: String = ExampleScript.describe()
	assert(said.contains(ExampleScript.NAME), "and the line begins with it: %s" % said)
	assert(
		said.contains(str(ExampleScript.parts().size())),
		"and counts the shapes it actually has: %s" % said
	)


## The corners a shape reaches, near enough for a check on the size of a garden: a rectangle's own box, a
## circle's four sides, a polyline's vertices, and the two ends of a dimension.
func _corners(entity: DraftEntity) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var params: PackedFloat64Array = entity.params
	match int(entity.kind):
		int(EntityScript.Kind.RECT):
			var centre := Vector2(params[0], params[1])
			var half := Vector2(params[2], params[3]) * 0.5
			out.append_array([
				centre - half, centre + Vector2(half.x, -half.y),
				centre + half, centre + Vector2(-half.x, half.y),
			])
		int(EntityScript.Kind.CIRCLE):
			var centre := Vector2(params[0], params[1])
			var radius: float = params[2]
			out.append_array([
				centre + Vector2(-radius, -radius), centre + Vector2(radius, radius),
			])
		int(EntityScript.Kind.LINE):
			out.append(Vector2(params[0], params[1]))
			out.append(Vector2(params[2], params[3]))
		int(EntityScript.Kind.DIMENSION):
			out.append(Vector2(params[0], params[1]))
			out.append(Vector2(params[2], params[3]))
		int(EntityScript.Kind.POLYLINE), int(EntityScript.Kind.POLYGON):
			var count: int = int(params[0])
			for i: int in count:
				out.append(Vector2(params[1 + i * 2], params[2 + i * 2]))
		int(EntityScript.Kind.TEXT):
			out.append(Vector2(params[0], params[1]))
	return out