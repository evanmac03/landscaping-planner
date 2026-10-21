@tool
extends EditorPlugin
## The presentation dock, as a plugin (specification §11, and §11.2's reason for a plugin of ours living
## in its own directory rather than under `addons/ziva_agent/`: that folder is vendored and gitignored,
## so anything of ours that went in there would be neither version-controlled nor safe from a Ziva
## update).
##
## A dock rather than a toolbar button, because both of its jobs are forms: a batch of stills is a list
## of sizes and views, and a report of missing presentation data is a list a person reads while looking
## at the script it names. A toolbar button would open a dialog that is a worse dock.
##
## **This is the only file in the module that knows it is a plugin.** The dock itself
## (`presentation_dock.gd`) is a plain `Control` holding no editor API, so every one of its decisions is
## driven in a test with the dock never added to a tree; what is left here is the handful of lines that
## could only be tested by running the editor - which is exactly what §15's phase-8 check does.
##
## The one job that is genuinely the editor's is rendering a still: the exporter needs a camera that is
## in a tree, and in the editor that camera is the one in the scene being edited. So this file answers
## `render_requested` by handing the project's own `StillExporter` the presentation camera, and puts the
## answer back through `record_result`. There is no second render path here (REQ-V11.1) - only a camera
## to give the first one.

const DockScript := preload("res://addons/vis_tools/presentation_dock.gd")
const BatchScript := preload("res://scripts/vis/render_batch.gd")
const PresetScript := preload("res://scripts/vis/still_preset.gd")
const ExporterScript := preload("res://scripts/vis/still_exporter.gd")
const StoreScript := preload("res://scripts/draft/drawing_store.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")

## The dock the editor is showing, and the sidebar that holds it. Both are held so `_exit_tree` can
## take away everything this plugin added (REQ-V11.2).
var _sidebar: EditorDock = null
## The dock is held as a plain `Variant` rather than as its own class, so this file does not depend on
## the class cache having picked up a script in a folder the editor has never scanned. The dock's own
## script is what knows what it can do.
var _dock: Variant = null
## The scene root the dock is currently pointed at, so a change of scene is noticed.
var _adopted: Node = null


func _enter_tree() -> void:
	_dock = DockScript.new()
	_dock.build()
	_dock.render_requested.connect(_on_render_requested)
	_sidebar = EditorDock.new()
	# Right-bottom: a working panel, so it does not displace the inspector or the file system while
	# somebody is designing.
	_sidebar.title = "Presentation"
	_sidebar.default_slot = EditorDock.DOCK_SLOT_RIGHT_BL
	_sidebar.available_layouts = EditorDock.DOCK_LAYOUT_VERTICAL | EditorDock.DOCK_LAYOUT_FLOATING
	_sidebar.add_child(_dock)
	add_dock(_sidebar)
	# A batch of the standard four views at the proposal size, made once: it is the set a proposal is
	# made of, and changing the edited scene must not throw away a list somebody has built.
	var batch: VisRenderBatch = BatchScript.new()
	batch.add_every_view(PresetScript.PROPOSAL_DEFAULT, BatchScript.DEFAULT_VIEWS)
	_dock.bind_batch(batch)
	_adopted = EditorInterface.get_edited_scene_root()
	_adopt_open_scene()


## Adopt whatever scene the editor has open, as it changes.
##
## A plugin is enabled *before* the editor opens a scene - `_enter_tree` runs during startup, while
## the docks are being loaded and long before any scene is reopened - so adopting a scene once, at
## enable, is a dock that is empty until it is re-enabled. Watching the edited scene root instead
## means opening a drawing is what points the dock at it, which is what a person expects.
func _process(_delta: float) -> void:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root != _adopted:
		_adopted = root
		_adopt_open_scene()


func _exit_tree() -> void:
	if _sidebar == null:
		return
	remove_dock(_sidebar)
	# The sidebar is ours to free, and the dock is its child, so one free takes away everything this
	# plugin added. A plugin that leaks a panel on disable grows a new panel every time it is toggled
	# off and on again.
	_sidebar.queue_free()
	_sidebar = null
	_dock = null


## Point the dock at the drawing to check, so it has an answer the moment it appears rather than
## waiting to be pointed at a file.
func _adopt_open_scene() -> void:
	if _dock == null:
		return
	var source: Dictionary = _source_for_the_editor()
	_dock.bind_visuals(source["document"], source["layers"], String(source["where"]))
	_dock.check()


## The drawing to check, and what to call it.
##
## The scene the editor has open is asked first, because a drawing somebody is working on is the one
## worth checking. `main.tscn`'s drafting controller holds no document until the game runs, though -
## it is not a `@tool` script, so in the editor its `_ready` never happens - so the fallback is the
## most recent drawing this project has *saved*, which is the drawing the game would open. Failing
## that, the project's own layer set, which is still a real answer: it says whether the two tables
## account for every layer this project defines.
##
## Every path answers. A dock that refused to say anything because a model scene had been opened would
## be a dock whose last report vanished whenever somebody looked at something else.
func _source_for_the_editor() -> Dictionary:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root != null:
		var controller: Node = root.find_child("DraftController", true, false)
		if controller != null:
			var document: Variant = controller.get("document")
			if document != null:
				return {"document": document, "layers": document.get("layers"), "where": ""}
	for path: String in StoreScript.read_recent():
		var read: Dictionary = StoreScript.read(path)
		if not bool(read.get("ok", false)):
			continue
		var opened: Variant = DocumentScript.from_dict(read["data"])
		if opened == null:
			continue
		return {
			"document": opened,
			"layers": opened.get("layers"),
			"where": "the most recent drawing, %s" % StoreScript.display_name(path),
		}
	return {"document": null, "layers": LayerSetScript.default_set(), "where": "no drawing"}


## Render one job through the project's own exporter.
##
## The camera is looked for under the presentation subtree first, because that is the eye a proposal is
## rendered from; any other camera will do, and no camera at all is reported rather than faked so the
## batch records a refusal instead of a blank page.
func _on_render_requested(job: Dictionary) -> void:
	if _dock == null:
		return
	var camera: Camera3D = _presentation_camera()
	if camera == null:
		_dock.record_result("")
		return
	var size: Vector2i = PresetScript.size(job["preset"])
	var path: String = await ExporterScript.new().render_still(
		[camera] as Array[Node], size, String(job["name"]), {}
	)
	_dock.record_result(path)


## The camera a still is rendered from: the presentation eye when the scene has one, and any camera
## otherwise.
func _presentation_camera() -> Camera3D:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	var presentation: Node = root.find_child("Presentation", true, false)
	if presentation != null:
		var eye: Node = presentation.find_child("Camera3D", true, false)
		if eye is Camera3D:
			return eye
	var any: Node = root.find_child("Camera3D", true, false)
	return any as Camera3D