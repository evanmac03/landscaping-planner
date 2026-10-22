class_name YardExporter
extends RefCounted
## The garden as a model file: the yard a client walks through, written out as glTF.
##
## ## Why a model at all
##
## The still (§10) is a picture of the yard, and the proposal page (§11) puts that picture on a
## sheet. Both are things a client *looks at*. Neither is a thing anybody can *use*. The builder who
## wants to set the new paving into their own site drawing, the lighting contractor working out a
## run from the planting, and the designer who takes the garden on next season all want the model
## itself - and it already exists, because it is what this program draws every frame.
##
## ## What is in it
##
## The design is **two nodes** of this project, and `design_roots` is the one place that says which:
## the `Yard` - the ground, the lawn, the house, the paving, the fence and every planted prop - and
## the `Derived` builder, which is where the patios, the decks and the beds the *drawing* implies
## become solids (§8). Both go in, so what a person sees in the preview and what they are handed are
## the same garden.
##
## They are found by **type** rather than by name: a node called `Yard` that is not one is not the
## yard, and a builder that has been renamed still derives the drawing.
##
## The player, the cameras, the sun and the HUD are not in it. They belong to the program rather than
## to the garden, and a model of somebody's back garden has no business carrying the person who was
## walking round it.
##
## Those two nodes are **siblings** in the scene, and the file is written with **one** root holding both
## of them. That is not tidiness. glTF's single scene holds a *list* of root nodes, and a reader is
## entitled to instantiate the first and no more - Godot's own reader does exactly that - so a model
## written as the yard beside the builder comes back, in Godot, as the yard: the garden without the
## paving, the deck and the beds the drawing implies. One root is also the shape every other program
## draws as one tree, and it is what makes "the whole garden is in this file" true of the file rather
## than of this report. `_one_root` is where that happens, and why it copies rather than reparents.
##
## ## What that leaves out
##
## **No light.** The sun here is a presentation setting (§6.1) with a day of the year and an hour
## attached to it, not a lamp standing in the garden, so it is not a thing the garden *has*. A model
## opened in another program is therefore unlit until that program lights it, and `report_lines` says
## so out loud: "why is it dark" is not a question a person should have to answer by reading this
## file.
##
## **Collision goes with it, in an extension.** glTF has no physics of its own, but Godot writes what
## the player walks on as `OMI_physics_body`/`OMI_physics_shape` - so the paving's collider is in the
## file. An extension is exactly that, though, and a program that does not know it will ignore it.
## That is a fact about the format rather than about any particular export, which is why it is stated
## here and not counted in the report.
##
## **A picture Godot cannot get an image out of is written as no picture at all.** This project draws
## its lawn, its ground and its fence timber with `NoiseTexture2D`s, which are generated on a thread
## rather than loaded from a file, and a texture that has not been drawn yet has no image to write. The
## material then goes out in the material's own colour, which is close to right and not right. It is
## rare - the yard is on screen whenever somebody is at the desk - which is exactly why it is counted
## rather than assumed away, in **both** formats.
##
## ## The two formats are not interchangeable
##
## A **`.glb`** is one file with its pictures inside it. A **`.gltf`** is a text file with its buffer
## in a `.bin` beside it - and its pictures are **named rather than carried**: Godot writes them as
## `"uri": "textures/..."`, a path derived from where the picture lives *inside this project*, which
## is not a path that resolves beside the file that was written. A `.gltf` therefore opens in another
## program with its geometry, its colours and none of its textures.
##
## It is still offered, because a text file is the one a person can diff - which is the reason
## Godot's own documentation suggests `.gltf` for version control - and because the loss is **counted
## and named** in the report rather than left to be discovered by whoever was handed the file. A
## `.glb` is the default for the opposite reason: a model going to somebody else should be one file.
##
## ## It is a snapshot, not a promise
##
## What goes out is what is **standing**: the yard as it is this frame, including however many derived
## solids the drawing has produced so far. That is the same rule the still follows (§10.3), and it is
## why the report counts the meshes rather than claiming a number the drawing implies.

const YardScript := preload("res://scripts/yard.gd")
const DerivedScript := preload("res://scripts/vis/derived_builder.gd")

## The two formats glTF has, in the order a menu offers them.
const GLB := "glb"
const GLTF := "gltf"
const FORMATS: Array[String] = [GLB, GLTF]

## What each format is, in words a person choosing between them reads. The difference is not
## cosmetic, so it is stated where the choice is made rather than in a footnote.
const FORMAT_WORDS := {
	GLB: "one file, with its pictures inside it",
	GLTF: "a text file with a .bin beside it, and its pictures named rather than carried",
}

## The name of the one node the garden is written under. It is a word for the whole garden rather than
## for either half of it, so a person who opens the file and expands the root is not being told that
## the derived paving is part of "the yard".
const ROOT_NAME := "Garden"

## How a design root is copied on its way into the file: everything a deep copy carries **except**
## re-instancing the scene a node came from.
##
## That exception is the point. What is written is the garden as it stands *this frame*, and part of
## what stands there - a plant's scale, a prop turned to face the house - was set while the program was
## running and is not in any `.tscn`. A copy that went back to each node's scene file for its shape
## would write the garden as it was authored rather than as it is being looked at.
const COPY_FLAGS := Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS


# --- what the design is ---------------------------------------------------------------


## Every node of this scene whose geometry *is* the design, in the order they stand in it.
##
## Found by walking **up** from `from` and looking at each ancestor's children, stopping at the first
## level that holds one of these two types. That is not the same as walking to the top of the tree and
## looking there, and the difference is the whole point: a tool that instances `main.tscn` - the demos,
## and the audit - puts the game's root node *below* a node of its own, so "the top of the tree" is the
## tool and the yard is one level down from it. Looking at every level on the way up finds the yard
## wherever the game happens to be nested, and a node with no game above it is simply a node with no
## design in it.
##
## Two **types** rather than two names: a node called `Yard` that is not one is not the yard, and a
## builder that has been renamed still derives the drawing.
static func design_roots(from: Node) -> Array[Node]:
	var node: Node = from
	while node != null:
		var found: Array[Node] = []
		for child: Node in node.get_children():
			if child is YardScript or child is DerivedScript:
				found.append(child)
		if not found.is_empty():
			return found
		node = node.get_parent()
	return [] as Array[Node]


## The format a path asks for, or "" when it asks for neither. The extension is the only thing that
## decides: `.glb` and `.gltf` are the same data in two containers, and a second setting for it
## would be a setting that can disagree with the file name.
static func format_for(path: String) -> String:
	var lower := path.strip_edges().to_lower()
	if lower.ends_with("." + GLB):
		return GLB
	if lower.ends_with("." + GLTF):
		return GLTF
	return ""


# --- writing ---------------------------------------------------------------------------


## The whole design of the scene `from` belongs to, written to `path`.
##
## The door a menu wants: it finds the yard itself, so the caller does not have to.
static func export_scene(from: Node, path: String) -> Dictionary:
	var roots := design_roots(from)
	if roots.is_empty():
		return _refused("there is no yard in this scene, so there is no model to write")
	return export_roots(roots, path)


## The nodes named here, and everything under them, written to `path` as glTF.
##
## Returns `{ok, reason, path, format, roots, files, bytes, meshes, materials, pictures, undrawn,
## left_out}`. A refusal is a reason rather than a raised error, because the path is one a person
## typed and the reason is the message they need.
##
## `roots` names the design nodes that went in - the same nodes `design_roots` found - while the file
## itself is written under one root holding both of them; see `_one_root`. The counts are of the
## design, not of the file, for the reason `_survey` gives.
##
## Nothing here is an edit: the drawing is read, the yard is read, and a file is written. There is no
## gesture and no undo step, the same as plotting a sheet or writing a DXF.
static func export_roots(roots: Array[Node], path: String) -> Dictionary:
	var format := format_for(path)
	if format.is_empty():
		return _refused(
			"a model is written as .%s or .%s, and \"%s\" is neither" % [GLB, GLTF, path.get_file()]
		)
	var survey := _survey(roots)
	if int(survey["meshes"]) == 0:
		return _refused("there is no geometry standing in the yard yet, so there is no model to write")

	# What is in the folder *before* anything is written, so the report can name what this made
	# rather than guess at it. A `.gltf` puts a `.bin` beside itself, and the name of that buffer is
	# the exporter's business rather than something to work out from the file name.
	var before := _listing(path.get_base_dir())
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var garden := _one_root(roots)
	var appended := document.append_from_scene(garden, state)
	if appended != OK:
		garden.free()
		return _refused("the yard could not be read into a model: %s" % error_string(appended))
	var written := document.write_to_filesystem(state, path)
	# The copies are only ever a way of getting the garden into one file, so they go as soon as the file
	# exists - whether it was written or not.
	garden.free()
	if written != OK:
		return _refused("that file could not be written: %s" % error_string(written))

	var report := {
		"ok": true,
		"reason": "",
		"path": path,
		"format": format,
		"roots": _root_names(roots),
		"files": _files_made(path, before, format),
		"bytes": 0,
		"meshes": int(survey["meshes"]),
		"materials": int(survey["materials"]),
		"pictures": int(survey["pictures"]),
		"undrawn": int(survey["undrawn"]),
		"left_out": [] as Array[String],
	}
	report["bytes"] = _total_size(path, report["files"])
	report["left_out"] = _left_out(report)
	return report


## The whole garden gathered under one node, because the file has to have one root.
##
## glTF's scene holds a *list* of root nodes, and a reader may instantiate the first and no more:
## Godot's own reader does, so a file written as the yard beside the builder opens as the garden
## without the paving, the deck and the beds the drawing implies - the half of it a person would
## notice was missing. One root is also the shape another program draws as one tree.
##
## The gathered nodes are **copies**. Reparenting the real ones would take the yard out of the game it
## is standing in, and an export is not an edit; a copy costs a few hundred nodes for the moment the
## write takes and touches nothing. Each copy is put back at the place in the world its original
## stands, because the node gathering them is not the node they were standing under.
static func _one_root(roots: Array[Node]) -> Node3D:
	var garden := Node3D.new()
	garden.name = ROOT_NAME
	for root: Node in roots:
		if root == null:
			continue
		var copy: Node = root.duplicate(COPY_FLAGS)
		garden.add_child(copy)
		if copy is Node3D and root is Node3D:
			(copy as Node3D).transform = _world_transform(root as Node3D)
	return garden


## Where a node stands in the world, worked out by walking up its parents rather than by asking for
## `global_transform`.
##
## Asking a node that is **not in a tree** for its global transform is no answer at all: Godot logs an
## error and hands back an identity transform. A design can be off-tree and still be perfectly real -
## the tests build their gardens that way, so that no `_ready` runs and no fence is built - and a door
## that worked only on gardens that happened to be standing in a running game would be a door nobody
## could test. Multiplying each ancestor's own transform gives the same answer as `global_transform`
## for a node that is in a tree, and an answer at all for one that is not.
static func _world_transform(node: Node3D) -> Transform3D:
	var place := node.transform
	var parent: Node = node.get_parent()
	while parent != null:
		if parent is Node3D:
			place = (parent as Node3D).transform * place
		parent = parent.get_parent()
	return place


## What a `MeshInstance3D` is drawn with, when its mesh has surfaces of its own.
##
## Both doors are read, because the two kinds of material arrive by different ones: a material written
## into the mesh resource is how an imported plant model carries its colour, and `material_override`
## is how this project's own props - the fence timber, the lawn, the derived paving - carry theirs. A
## survey that looked at one of them would report a garden with no materials in it.
static func _gather_materials(instance: MeshInstance3D, into: Array[Material]) -> void:
	_add_material(instance.material_override, into)
	var mesh: Mesh = instance.mesh
	for surface in mesh.get_surface_count():
		_add_material(instance.get_surface_override_material(surface), into)
		_add_material(mesh.surface_get_material(surface), into)


static func _add_material(material: Material, into: Array[Material]) -> void:
	if material != null and not into.has(material):
		into.append(material)


## How many pictures a material stands for, and how many of them can actually be written.
##
## Counted per map slot rather than per material, because the number that matters is how many *images*
## the file has to carry - and a paving material with an albedo, a normal and an ORM map is three of
## them, which is the same three the exporter writes.
##
## The split is the exporter's own test rather than a guess about texture classes: Godot has to be able
## to **get an image** out of a texture to write it, and a texture it cannot get one out of is written
## as no texture at all - the material keeps its colour and loses its picture. The case that makes this
## worth counting is the procedural one: this project's lawn, ground and timber are `NoiseTexture2D`s,
## which generate on a thread, so one that has never been drawn has no image yet. It is rare - the yard
## is on screen whenever somebody is at the desk - and it is exactly the kind of loss that otherwise
## shows up as "why is the lawn flat in the model" a week later.
static func _material_pictures(material: Material) -> Dictionary:
	var standard := material as StandardMaterial3D
	if standard == null:
		return {"pictures": 0, "undrawn": 0}
	var written := 0
	var waiting := 0
	for field: String in ["albedo_texture", "normal_texture", "orm_texture"]:
		var texture: Texture2D = standard.get(field)
		if texture == null:
			continue
		if texture.get_image() != null:
			written += 1
		else:
			waiting += 1
	return {"pictures": written, "undrawn": waiting}


## What is in the roots: how much geometry, how many materials, and how many pictures between them.
##
## Counted **here**, off the live nodes, rather than read back out of the written file. The report is
## about the *design* - "276 meshes went out" is a statement about the yard - and a count taken off a
## GLB would be a statement about the writer instead, which is the wrong thing to be reporting when
## the writer is the part that might be wrong.
##
## The walk is iterative rather than recursive: a yard is a few hundred nodes today and there is no
## reason for its depth to be a limit.
static func _survey(roots: Array[Node]) -> Dictionary:
	var meshes := 0
	var materials: Array[Material] = []
	var stack: Array[Node] = []
	for root: Node in roots:
		if root != null:
			stack.append(root)
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var instance := node as MeshInstance3D
			if instance.mesh != null:
				meshes += 1
				_gather_materials(instance, materials)
		for child: Node in node.get_children():
			stack.append(child)
	var pictures := 0
	var undrawn := 0
	for material: Material in materials:
		var counted := _material_pictures(material)
		pictures += int(counted["pictures"])
		undrawn += int(counted["undrawn"])
	return {
		"meshes": meshes, "materials": materials.size(),
		"pictures": pictures, "undrawn": undrawn,
	}


# --- saying what was written ----------------------------------------------------------


## One line saying what went out, and what could not.
##
## The same shape as `DxfWriter.describe`, and for the same reason: this is the sentence a status line
## shows, so anything the export could not carry has to be in it. A report a person has to ask for is
## a report nobody reads.
static func describe(report: Dictionary) -> String:
	if not bool(report.get("ok", false)):
		return String(report.get("reason", "the yard could not be written"))
	var meshes := int(report.get("meshes", 0))
	var materials := int(report.get("materials", 0))
	var files: Array = report.get("files", [])
	var words := "the yard went out as a .%s: %d mesh%s, %d material%s, %s in %d file%s" % [
		String(report.get("format", GLB)),
		meshes, "" if meshes == 1 else "es",
		materials, "" if materials == 1 else "s",
		String.humanize_size(int(report.get("bytes", 0))),
		files.size(), "" if files.size() == 1 else "s",
	]
	var left: Array = report.get("left_out", [])
	if not left.is_empty():
		words += "; left out: " + ", ".join(_as_strings(left))
	return words


## Everything a person needs to accept a model, one line each. The mirror of
## `DxfWriter.report_lines`, and read the same way.
static func report_lines(report: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if not bool(report.get("ok", false)):
		lines.append(String(report.get("reason", "the yard could not be written")))
		return lines
	lines.append(describe(report))
	var files: Array = report.get("files", [])
	if not files.is_empty():
		lines.append("files: " + ", ".join(_as_strings(files)))
	var meshes := int(report.get("meshes", 0))
	var materials := int(report.get("materials", 0))
	lines.append("what is in it: %d mesh%s and %d material%s" % [
		meshes, "" if meshes == 1 else "es",
		materials, "" if materials == 1 else "s",
	])
	# Said on every export rather than only when something is wrong, because it is not a fault: it is
	# what the garden is. A model of a garden has no sun in it, and a person who opened it and found
	# it dark should have been told that here.
	lines.append(
		"a model carries the garden and none of the program: no camera and no sun, so whatever "
		+ "opens it lights it"
	)
	return lines


## The losses this particular export could not avoid, counted and named.
##
## Two, and they are different kinds of loss. The first is the format's: a `.gltf` names its pictures
## instead of carrying them, whatever the picture is. The second is the moment's: a picture Godot
## cannot get an image out of is written as no picture at all, in *either* format, and the material
## keeps only its colour.
##
## Each is counted only when it has something to count, so a `.gltf` of a plain-colour garden is not
## told about a loss it does not have.
static func _left_out(report: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var undrawn := int(report.get("undrawn", 0))
	if undrawn > 0:
		out.append(
			"%d picture%s not drawn yet, so %s went out as plain colour" % [
				undrawn, "" if undrawn == 1 else "s",
				"it" if undrawn == 1 else "they",
			]
		)
	var pictures := int(report.get("pictures", 0))
	if String(report.get("format", GLB)) == GLTF and pictures > 0:
		out.append(
			"%d picture%s named rather than carried (a .gltf points at them where they live in this "
			% [pictures, "" if pictures == 1 else "s"]
			+ "project)"
		)
	return out


# --- the folder the file went into ----------------------------------------------------


## Every file in a folder and its size, as `name -> bytes`. An unreadable folder is an empty
## dictionary rather than a failure: the sweep is how the report names what was made, and not being
## able to look is not a reason to refuse to write.
static func _listing(folder: String) -> Dictionary:
	var out := {}
	if folder.strip_edges().is_empty():
		return out
	var dir := DirAccess.open(folder)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			out[entry] = _size_of(folder.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	return out


## The names of the files this export made: the one that was asked for, anything that appeared beside
## it, and anything the written file says belongs to it.
##
## The named one is stated rather than diffed, because writing over a model that is already there makes
## no new file and is still an export. The last of the three is what `_companions` is for, and it is the
## case that catches people out: a `.gltf` written over yesterday's `.gltf` leaves its buffer exactly
## where it was, so a sweep for what appeared finds one file and the model is two.
static func _files_made(path: String, before: Dictionary, format: String) -> Array[String]:
	var mine := path.get_file()
	var made: Array[String] = [mine]
	var folder := path.get_base_dir()
	for entry: String in _appeared(before, _listing(folder)):
		if entry != mine:
			made.append(entry)
	for entry: String in _companions(path, format):
		if not made.has(entry) and FileAccess.file_exists(folder.path_join(entry)):
			made.append(entry)
	return made


## The files beside a written model that the model itself names.
##
## A `.gltf` keeps its binary buffer in a file next to itself and writes down which one in its own
## `buffers` list, so what belongs to the model is **read out of the model** rather than worked out
## from its name - which is the same rule the rest of this file follows, and the reason it holds for a
## buffer Godot chose to call something else. A `.glb` carries its buffer inside itself and names
## nothing.
static func _companions(path: String, format: String) -> Array[String]:
	var out: Array[String] = []
	if format != GLTF:
		return out
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	var words := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(words)
	if not parsed is Dictionary:
		return out
	for buffer: Variant in (parsed as Dictionary).get("buffers", []):
		if not buffer is Dictionary:
			continue
		var uri := String((buffer as Dictionary).get("uri", ""))
		if uri.is_empty() or uri.begins_with("data:"):
			continue
		var entry := uri.uri_decode().get_file()
		if not entry.is_empty() and not out.has(entry):
			out.append(entry)
	return out


static func _appeared(before: Dictionary, after: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for entry: Variant in after:
		if not before.has(entry):
			out.append(String(entry))
	out.sort()
	return out


static func _total_size(path: String, files: Array[String]) -> int:
	var folder := path.get_base_dir()
	var total := 0
	for entry: String in files:
		total += _size_of(folder.path_join(entry))
	return total


static func _size_of(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return size


static func _root_names(roots: Array[Node]) -> Array[String]:
	var out: Array[String] = []
	for root: Node in roots:
		if root != null:
			out.append(String(root.name))
	return out


static func _as_strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value: Variant in values:
		out.append(String(value))
	return out


static func _refused(reason: String) -> Dictionary:
	return {
		"ok": false, "reason": reason, "path": "", "format": "",
		"roots": [] as Array[String], "files": [] as Array[String], "bytes": 0,
		"meshes": 0, "materials": 0, "pictures": 0, "undrawn": 0,
		"left_out": [] as Array[String],
	}