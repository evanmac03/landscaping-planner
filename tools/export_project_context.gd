# File path: res://tools/export_project_context.gd
# To run: open this in the script editor and press Ctrl+Shift+X (Run).
#
# Editor-GUI twin of tools/export_context_cli.gd. Both write the same report to
# user://gemini_context.md; this one runs from inside the editor, the CLI one from
# `godot --headless -s res://tools/export_context_cli.gd`.
#
# This runner **also copies the report to the clipboard**, because the whole point of the
# snapshot is being pasted into a chat window (Gemini, DeepSeek, anything) and a file you have
# to go and find is the step that gets skipped. One Ctrl+Shift+X gives you a file and a paste.
#
# The CLI twin deliberately does not: `--headless` runs the dummy display server, where
# `DisplayServer.clipboard_set` is a silent no-op. A copy that cannot happen must not be
# reported as one.
#
# The report itself is built by tools/context_report.gd, which the CLI twin also calls, so the
# two exporters cannot drift apart. That builder asks each script for its own property, constant,
# method and signal lists, so the enums, the bit masks, the signatures and the signals all come
# out with the variables.

@tool
extends EditorScript

const ContextReportScript := preload("res://tools/context_report.gd")

## Leave this empty to build and copy the whole snapshot. Set it to a subject name for a **scoped
## pack** instead - `plant-id`, `planting` or `drafting`. The subjects, and anything new, are
## listed by tools/export_context_cli.gd run with `-- subjects`.
const SUBJECT := ""


func _run() -> void:
	# A subject that does not exist writes nothing: a refusal rather than a wrong file.
	if not SUBJECT.is_empty() and not ContextReportScript.has_subject(SUBJECT):
		printerr("No such subject: %s" % SUBJECT)
		printerr("The subjects are: %s" % ", ".join(ContextReportScript.subject_names()))
		return

	var output: String = ContextReportScript.build_for(SUBJECT)
	var path: String = ContextReportScript.output_path(SUBJECT)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("Failed to write context export file: %s" % path)
		return
	file.store_string(output)
	file.close()

	DisplayServer.clipboard_set(output)

	var bytes: int = output.to_utf8_buffer().size()
	print("Context written to %s/%s" % [OS.get_user_data_dir(), path.trim_prefix("user://")])
	print("  %s - %d lines, %d KB - and copied to the clipboard, ready to paste." % [
			"the whole snapshot" if SUBJECT.is_empty() else "the '%s' pack" % SUBJECT,
			output.count("\n") + 1, int(round(bytes / 1024.0)),
	])