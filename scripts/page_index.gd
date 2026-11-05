class_name PageIndex
extends RefCounted
## Which of this project's scripts are pages.
##
## A page is a `Window`: a thing a menu opens, with a title bar, holes to fill in and a way to close it -
## as opposed to a model, which is a `RefCounted` that does the arithmetic and never draws. Thirty of
## them live under `res://scripts`, and the list is built by **reading that folder** rather than by being
## written down, for the reason this project writes nothing down twice: a page added tomorrow is a page
## considered tomorrow, without anybody remembering to come back here.
##
## Two things ask this question and they must never disagree about the answer - the page layout check,
## which measures every page, and the manual's page table, which holds every page to a subject. A second
## walk of the folder would be a second opinion on what a page is, so there is one, and it is this.

## Where the pages live.
const PAGES_DIR := "res://scripts"


## Every script under the pages folder whose instance is a `Window`, in a stable order.
static func scripts() -> Array[String]:
	var out: Array[String] = []
	_collect(PAGES_DIR, out)
	out.sort()
	return out


## The name a page is known by: its script's file name without the extension. That is the name
## `PageLayout.page_name` reports a page by and the name the manual's page table is keyed on, so a page
## is one row in both places.
static func page_name(path: String) -> String:
	return path.get_file().get_basename()


## Whether an instance of this script is a `Window`. Asking the script what it inherits, rather than
## looking for the word "Window" in its text, is what a `class_name` page and a plain one answer alike.
static func is_page(path: String) -> bool:
	var script: Script = load(path) as Script
	return script != null and script.get_instance_base_type() == &"Window"


static func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file: String in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var path: String = dir_path.path_join(file)
		if is_page(path):
			out.append(path)
	for folder: String in dir.get_directories():
		if folder.begins_with("."):
			continue
		_collect(dir_path.path_join(folder), out)