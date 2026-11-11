extends Control
## A live pass over the **AI context dock** (`addons/context_tools/context_dock.gd`): putting the
## dock on screen, selecting the `plant-id` pack, adding a task prompt, and copying + writing the
## snapshot.

const DockScript := preload("res://addons/context_tools/context_dock.gd")


## The width of the bottom-right dock slot in the editor. A dock that fits here fits the place a
## person actually uses it, which a demo stretched across a whole window can never show.
const DOCK_WIDTH := 470


func _ready() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(row)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(DOCK_WIDTH, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var dock: Control = DockScript.new()
	dock.output_dir = "user://demo_context"
	dock.build()
	dock.said.connect(func(line: String) -> void:
		print("DOCK STATUS: ", line))
	dock.exported.connect(func(subject: String, path: String, chars: int) -> void:
		print("DOCK EXPORTED: subject='%s' path=%s chars=%d" % [subject, path, chars]))
	margin.add_child(dock)

	# What the layout actually did, rather than what it looks like. The dock itself is a plain `Control`
	# and so asks for nothing; the number that matters is the minimum width of its one child, the column
	# everything is stacked in. Wider than the slot means the dock clips its own buttons off the edge.
	await get_tree().process_frame
	await get_tree().process_frame
	var column: Control = dock.find_child("Dock", true, false)
	print("DOCK DEMO (slot %d px): the column is %.0f wide and asks for %.0f" % [
			DOCK_WIDTH, column.size.x, column.get_combined_minimum_size().x])

	var picker: OptionButton = dock.find_child("SubjectPicker", true, false)
	var entries := PackedStringArray()
	for index: int in picker.item_count:
		entries.append(picker.get_item_text(index))
	print("DOCK DEMO (packs): ", picker.item_count, " entries - ", ", ".join(entries))

	dock.select_subject("estimating")
	dock.refresh_preview()
	print("DOCK DEMO (estimating): ", dock.last_words)

	dock.select_subject("plant-id")
	dock.refresh_preview()
	print("DOCK DEMO (plant-id): ", dock.last_words)

	# A real script in hand with every extra ticked, so this is what a full hand-over looks like: the
	# source of the file being edited, a real `git status` run in this project, and the last test run if
	# one has been left behind.
	var sample := "res://scripts/survey_watcher.gd"
	var sample_text := ""
	var sample_file := FileAccess.open(sample, FileAccess.READ)
	if sample_file != null:
		sample_text = sample_file.get_as_text()
		sample_file.close()
	dock.set_source(sample, sample_text)
	(dock.find_child("IncludeSource", true, false) as CheckBox).button_pressed = true
	(dock.find_child("IncludeGit", true, false) as CheckBox).button_pressed = true
	(dock.find_child("IncludeRun", true, false) as CheckBox).button_pressed = true
	dock.select_subject("plant-id")
	var built: String = dock.refresh_preview()
	print("DOCK DEMO (all attached): ", dock.last_words)
	print("DOCK DEMO (sections): source=%s git=%s last run=%s" % [
			built.contains("## Full source of"),
			built.contains("## Uncommitted changes"),
			built.contains("## The last test run")])

	dock.select_subject("")
	dock.refresh_preview()
	print("DOCK DEMO (whole): ", dock.last_words)
