@tool
extends EditorPlugin
## The cost book dock, as a plugin (spec §1's `addons/biz_tools/`, and §11.2's reason for a plugin of
## our own living in its own directory rather than under `addons/ziva_agent/`: that folder is
## vendored and gitignored, so anything of ours that went in there would be neither version-controlled
## nor safe from a Ziva update).
##
## A dock rather than a toolbar button, because everything here is a form - a path, a percentage, an
## effective date - and a toolbar button would open a dialog that is a worse dock.
##
## **This is the only file in the module that knows it is a plugin.** The dock itself
## (`costbook_dock.gd`) is a plain `Control` holding no editor API, so every one of its decisions is
## driven in a test with the dock never added to a tree; what is left here is twenty lines that could
## only be tested by running the editor.

const DockScript := preload("res://addons/biz_tools/costbook_dock.gd")

## The dock node, held so `_exit_tree` can take it away again.
var _dock: EditorDock = null


func _enter_tree() -> void:
	_dock = EditorDock.new()
	# Right-bottom: a working panel, so it does not displace the inspector or the file system while
	# somebody is designing.
	_dock.title = "Cost book"
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_BL
	_dock.available_layouts = EditorDock.DOCK_LAYOUT_VERTICAL | EditorDock.DOCK_LAYOUT_FLOATING
	var content: Control = DockScript.new()
	content.build()
	_dock.add_child(content)
	add_dock(_dock)


func _exit_tree() -> void:
	if _dock == null:
		return
	remove_dock(_dock)
	# The dock is ours to free: this plugin created it, so this plugin destroys it. A plugin that
	# leaks a panel on disable grows a new panel every time it is toggled off and on again.
	_dock.queue_free()
	_dock = null