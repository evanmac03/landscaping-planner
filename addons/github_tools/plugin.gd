@tool
extends EditorPlugin

const Content := preload("res://addons/github_tools/workflow_dock.gd")
var _dock: EditorDock
var _content: Control


func _enter_tree() -> void:
	_dock = EditorDock.new()
	_dock.title = "Godot Dev Workflow"
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_BL
	_content = Content.new()
	_dock.add_child(_content)
	add_dock(_dock)


func _exit_tree() -> void:
	if _content != null:
		_content.finish()
	if _dock != null:
		remove_dock(_dock)
		_dock.queue_free()
