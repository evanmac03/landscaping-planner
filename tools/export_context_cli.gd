# res://tools/export_context_cli.gd
# Run headlessly: godot --headless -s res://tools/export_context_cli.gd
# A subject may be named after `--`, for a scoped pack instead of the whole codebase:
#   ... -s res://tools/export_context_cli.gd -- plant-id
#   ... -s res://tools/export_context_cli.gd -- subjects     (lists them)
#
# The headless twin of tools/export_project_context.gd. Same report, written to the same file,
# built by the one builder in tools/context_report.gd so the two cannot drift apart.
#
# It writes the file and nothing else. The editor runner also copies the report to the clipboard;
# this one cannot, because `--headless` runs the dummy display server where
# `DisplayServer.clipboard_set` does nothing at all.
extends SceneTree

const ContextReportScript := preload("res://tools/context_report.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var subject: String = "" if args.is_empty() else String(args[0]).strip_edges()

	if subject == "subjects" or subject == "list":
		print("Subjects: %s" % ", ".join(ContextReportScript.subject_names()))
		quit()
		return

	# A subject we do not have is refused rather than answered with the whole snapshot, which
	# would be a different answer to a different question and would say nothing about it.
	if not subject.is_empty() and not ContextReportScript.has_subject(subject):
		printerr("No such subject: %s" % subject)
		printerr("The subjects are: %s" % ", ".join(ContextReportScript.subject_names()))
		quit(1)
		return

	var output: String = ContextReportScript.build_for(subject)
	var file_path: String = ContextReportScript.output_path(subject)
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		printerr("Failed to write context export file: %s" % file_path)
		quit(1)
		return
	file.store_string(output)
	file.close()

	print("Wrote %s" % file_path)
	print("  %s - %d lines, %d KB" % [
			"the whole snapshot" if subject.is_empty() else "the '%s' pack" % subject,
			output.count("\n") + 1, int(round(output.to_utf8_buffer().size() / 1024.0)),
	])
	quit()