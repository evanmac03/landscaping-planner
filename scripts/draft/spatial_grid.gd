class_name DraftSpatialGrid
extends RefCounted
## A uniform-grid AABB index over a drafting document.
##
## Chosen over an R-tree because a residential plan holds hundreds to low
## thousands of entities and edits are incremental: a grid rebuilds in
## microseconds, while an R-tree needs rebalancing on every insert. Revisit past
## roughly fifty thousand entities.
##
## Used by the snap engine to find what is near the cursor without walking the
## whole drawing (docs/drafting-subsystem-spec.md §5.1 step 3).

const DEFAULT_CELL_SIZE := 4.0

## An entity whose box spans more buckets than this goes on an overflow list and
## is checked on every query instead. Without this, one site-sized polygon (a
## 600 m boundary with a 4 m cell) would be inserted into tens of thousands of
## buckets and make every edit quadratic.
const MAX_BUCKETS_PER_ENTITY := 64

var cell_size: float = DEFAULT_CELL_SIZE

var _buckets: Dictionary = {}          # Vector2i -> PackedInt32Array
var _boxes: Dictionary = {}            # id -> Rect2
var _overflow: PackedInt32Array = PackedInt32Array()


## Rebuild from scratch. Keyed by entity id.
func rebuild(entities: Array) -> void:
	clear()
	for entry in entities:
		var entity = entry
		insert(entity.id, entity.aabb())


func clear() -> void:
	_buckets.clear()
	_boxes.clear()
	_overflow = PackedInt32Array()


func insert(id: int, box: Rect2) -> void:
	_boxes[id] = box
	# Test the span before building any cell list: the whole point of the cap is
	# to avoid materialising the thousands of cells a site-sized box touches.
	if cell_span(box) > MAX_BUCKETS_PER_ENTITY:
		_overflow.append(id)
		return
	for cell: Vector2i in cells_for(box):
		if not _buckets.has(cell):
			_buckets[cell] = PackedInt32Array()
		_buckets[cell].append(id)


func remove(id: int) -> void:
	if not _boxes.has(id):
		return
	var box: Rect2 = _boxes[id]
	_boxes.erase(id)
	var position := _overflow.find(id)
	if position >= 0:
		_overflow.remove_at(position)
		return
	for cell: Vector2i in cells_for(box):
		if not _buckets.has(cell):
			continue
		var bucket: PackedInt32Array = _buckets[cell]
		var at := bucket.find(id)
		if at >= 0:
			bucket.remove_at(at)


## Ids whose stored box overlaps `box`.
func query(box: Rect2) -> PackedInt32Array:
	var found: Dictionary = {}
	for cell: Vector2i in cells_for(box):
		if not _buckets.has(cell):
			continue
		for id: int in _buckets[cell]:
			var entity_box: Rect2 = _boxes[id]
			if entity_box.intersects(box):
				found[id] = true
	for id: int in _overflow:
		if (_boxes[id] as Rect2).intersects(box):
			found[id] = true
	var out := PackedInt32Array()
	for id in found:
		out.append(id)
	return out


func box_of(id: int) -> Rect2:
	return _boxes.get(id, Rect2())


func count() -> int:
	return _boxes.size()


func bucket_count() -> int:
	return _buckets.size()


func overflow_count() -> int:
	return _overflow.size()


static func cell_of(point: Vector2, size: float) -> Vector2i:
	return Vector2i(int(floor(point.x / size)), int(floor(point.y / size)))


## How many cells a box touches, computed without allocating them.
static func cell_span_for(box: Rect2, size: float) -> int:
	var low := cell_of(box.position, size)
	var high := cell_of(box.end, size)
	return (high.x - low.x + 1) * (high.y - low.y + 1)


func cell_span(box: Rect2) -> int:
	return cell_span_for(box, cell_size)


## Every cell a box touches, capped by the caller's overflow test.
func cells_for(box: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if box.size.x < 0.0 or box.size.y < 0.0:
		return out
	var low := cell_of(box.position, cell_size)
	var high := cell_of(box.end, cell_size)
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			out.append(Vector2i(x, y))
	return out