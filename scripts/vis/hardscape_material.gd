class_name HardscapeMaterial
extends RefCounted
## Builds a hardscape material from a texture set (§5.1).
##
## `StandardMaterial3D`, not a spatial shader, wherever it will do: that is what the
## Compatibility renderer is tuned for, it already supports ORM packing and triplanar
## projection, and it can be inspected and tweaked by hand in the editor — which a
## customer-facing material library has to be (REQ-V5.3). §5.3 lists the only three
## cases where a shader is justified, and paving is not one of them.
##
## `tile_m` is how many metres one repeat of the texture covers, and it is a property of
## the **set** rather than of the material: texel density that lives only in an
## inspector is a number that drifts, and a paver texture stretched across a patio reads
## as wallpaper (REQ-V5.2).
##
## **The textures are generated, not bought.** The specification's §16 asked whether
## texture sets would be bought or generated and this is the answer the build took: a
## generated set is seamless by construction, is version-controlled as a small image
## rather than as a licence, and can be re-derived at a different tile size without
## asking anybody. The albedo tiles are made once and committed; `normal` and `orm` are
## **derived from the albedo** by `TextureSetBuilder`, so a set cannot have a normal map
## that disagrees with the picture it normal-maps.
##
## Water is deliberately absent, though §5.1 lists it: this project has no water layer
## to draw a pond on (`SolidTable.MISSING` records the same finding), and a texture set
## nothing can use is a setting that does nothing.

## One entry per texture set. Files are relative to `TEXTURE_DIR`.
const SETS := {
	# A granite paver: the densest tile of the five, because paving is the surface a
	# viewer is closest to and the one where a stretched texture is most obvious.
	"paver_granite": {
		"albedo": "paver_granite_albedo.png",
		"normal": "paver_granite_normal.png",
		"orm": "paver_granite_orm.png",
		"tile_m": 1.6, "roughness": 0.82, "metallic": 0.0,
	},
	"paver_sandstone": {
		"albedo": "paver_sandstone_albedo.png",
		"normal": "paver_sandstone_normal.png",
		"orm": "paver_sandstone_orm.png",
		"tile_m": 1.6, "roughness": 0.88, "metallic": 0.0,
	},
	"deck_timber": {
		"albedo": "deck_timber_albedo.png",
		"normal": "deck_timber_normal.png",
		"orm": "deck_timber_orm.png",
		"tile_m": 0.9, "roughness": 0.74, "metallic": 0.0,
	},
	"mulch_bark": {
		"albedo": "mulch_bark_albedo.png",
		"normal": "mulch_bark_normal.png",
		"orm": "mulch_bark_orm.png",
		"tile_m": 0.8, "roughness": 0.95, "metallic": 0.0,
	},
	# Render is the smoothest of the five and the only one on a vertical face at household
	# scale, which is why its tile is the largest: stucco grain is finer than it looks.
	"render_stucco": {
		"albedo": "render_stucco_albedo.png",
		"normal": "render_stucco_normal.png",
		"orm": "render_stucco_orm.png",
		"tile_m": 1.2, "roughness": 0.92, "metallic": 0.0,
	},
}

const TEXTURE_DIR := "res://resources/textures/hardscape/"


## A material for a set name, or null and an error for one that does not exist.
##
## Loud, per REQ-V5.4: a paving texture that is silently grey is a bug nobody reports,
## and a caller that receives a default material cannot tell it apart from a set that
## happened to load.
static func build(set_name: String, world_triplanar: bool = true) -> StandardMaterial3D:
	var spec: Dictionary = SETS.get(set_name, {})
	if spec.is_empty():
		push_error("HardscapeMaterial: no texture set named '%s'" % set_name)
		return null
	var material := StandardMaterial3D.new()
	material.resource_name = String(set_name)
	material.albedo_texture = _load(String(spec["albedo"]))
	material.normal_enabled = true
	material.normal_texture = _load(String(spec["normal"]))
	# One texture, three channels: Godot reads occlusion from R, roughness from G and
	# metallic from B, which is exactly what a bought ORM map already is.
	material.orm_texture = _load(String(spec["orm"]))
	material.roughness = float(spec["roughness"])
	material.metallic = float(spec["metallic"])
	var tile: float = float(spec["tile_m"])
	material.uv1_scale = Vector3.ONE / tile
	if world_triplanar:
		# §5.2: geometry extruded from an outline has positional data and nothing else.
		# Triplanar projects from world axes and blends by normal, so any geometry gets a
		# correctly scaled texture with no UV work — and getting "which axis is up the
		# wall" wrong on a rotated patio is exactly the bug that appears only in a render.
		material.uv1_world_triplanar = true
		# A soft blend: a hard triplanar seam is very visible on a low-poly slab, and
		# every slab here is low-poly.
		material.uv1_triplanar_sharpness = 1.4
	return material


## Whether a set exists.
static func has_set(set_name: String) -> bool:
	return SETS.has(set_name)


## The file names of one set, in load order.
static func files_for(set_name: String) -> Array[String]:
	var out: Array[String] = []
	var spec: Dictionary = SETS.get(set_name, {})
	if spec.is_empty():
		return out
	for key: String in ["albedo", "normal", "orm"]:
		out.append(String(spec[key]))
	return out


## Every file any set names, as project paths.
static func all_paths() -> Array[String]:
	var out: Array[String] = []
	for set_name: String in SETS:
		for file_name: String in files_for(set_name):
			out.append(TEXTURE_DIR + file_name)
	return out


## The paths a set names that are not on disk.
##
## A diagnostic rather than a guard, because `build()` already errors loudly on a
## missing texture: this is what a test or a status line asks so a broken set is found
## before somebody renders a grey patio.
static func missing_paths() -> Array[String]:
	var out: Array[String] = []
	for path: String in all_paths():
		if not ResourceLoader.exists(path):
			out.append(path)
	return out


## The set names, in a stable order.
static func set_names() -> Array[String]:
	var out: Array[String] = []
	for set_name: String in SETS:
		out.append(set_name)
	out.sort()
	return out


static func _load(file_name: String) -> Texture2D:
	var path := TEXTURE_DIR + file_name
	var texture: Texture2D = load(path) as Texture2D
	if texture == null:
		push_error("HardscapeMaterial: missing texture %s" % path)
	return texture