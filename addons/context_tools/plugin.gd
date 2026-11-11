@tool
extends EditorPlugin
## The AI context dock, as an editor plugin.
##
## **This is the only file in the module that knows it is a plugin.** The dock itself
## (`context_dock.gd`) is a plain `Control` holding no editor API, so every one of its decisions is
## driven in a unit test with the dock never added to a tree.

const DockScript := preload("res://addons/context_tools/context_dock.gd")

## The sidebar the editor is showing, and the dock inside it. Both are held so `_exit_tree` can take
## away everything this plugin added.
var _sidebar: EditorDock = null
## The dock is held as a plain `Variant` rather than as its own class, so this file does not depend on
## the class cache having picked up a script in a folder the editor has never scanned. The dock's own
## script is what knows what it can do.
var _dock: Variant = null
## The script the editor had open when it was last adopted, so a change of script is noticed.
var _adopted_script: String = ""


func _enter_tree() -> void:
	_dock = DockScript.new()
	_dock.build()
	_sidebar = EditorDock.new()
	_sidebar.title = "AI Context"
	_sidebar.default_slot = EditorDock.DOCK_SLOT_RIGHT_BL
	_sidebar.available_layouts = EditorDock.DOCK_LAYOUT_VERTICAL | EditorDock.DOCK_LAYOUT_FLOATING
	_sidebar.add_child(_dock)
	add_dock(_sidebar)
	_adopt_open_script()


## Offer the dock whichever script the editor has open, as it changes.
##
## A plugin is enabled *before* a file is open in the script editor - `_enter_tree` runs during
## startup, while the docks load - so adopting once at enable is a source option that stays dead until
## the plugin is re-enabled. Watching the script editor instead means opening a file is what hands the
## dock its source, which is what a person expects.
func _process(_delta: float) -> void:
	var script: Script = EditorInterface.get_script_editor().get_current_script()
	var path: String = "" if script == null else script.resource_path
	if path != _adopted_script:
		_adopted_script = path
		_adopt_open_script()


## Read the open script and hand the dock its path and its text.
##
## The reading happens **here** rather than in the dock, because opening a file is the one thing the
## dock must not do: it is a plain `Control` with no editor API, which is what lets every decision it
## makes be unit-tested with no editor and no project on disk.
func _adopt_open_script() -> void:
	if _dock == null:
		return
	var text: String = ""
	if not _adopted_script.is_empty() and FileAccess.file_exists(_adopted_script):
		var file := FileAccess.open(_adopted_script, FileAccess.READ)
		if file != null:
			text = file.get_as_text()
			file.close()
	_dock.set_source(_adopted_script, text)


func _exit_tree() -> void:
	if _sidebar == null:
		return
	remove_dock(_sidebar)
	# The sidebar is ours to free and the dock is its child, so one free takes away everything this
	# plugin added: a plugin that leaks a panel grows a new one every time it is toggled off and on.
	_sidebar.queue_free()
	_sidebar = null
	_dock = null
