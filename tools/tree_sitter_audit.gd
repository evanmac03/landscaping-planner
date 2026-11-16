extends Node
## A dev tool: read every script under `res://scripts` with the tree_sitter_gd GDExtension and report what
## the grammar found in each - the shape of the tree at a glance, every file it could not read in full, and
## the three faults this project's own doctrine names: a `var` written with neither an explicit type nor a
## `:=` inference, a function that states no return type, and a parameter that states no type.
##
## The first is the interesting one because it has a stated exception - AGENTS.md keeps a dictionary that
## came out of `JSON.parse_string` deliberately untyped, so a value read out of a dictionary is left alone.
## The plain declarations are therefore split in two: the ones that are a Variant by nature (a dictionary
## read, or a loaded resource) which the tool passes over, and the ones a type could actually be written
## for, which it names. That split is a judgement, and the judgement is what a parse tree is for - a word
## tells you nothing, a node does.
##
## Parameters are the third fault, and the one no other check here could see: `(variable_statement ...)` finds
## untyped *variables*, and AGENTS.md says members, **parameters** and return types are all typed. Each
## parameter is named beside the signature it belongs to, because whether one may be typed is a judgement
## about the call it was written for - a helper that takes a dictionary is not the same case as one that
## takes a shape.
##
##     res://tools/tree_sitter_audit.tscn
##
## Read the table at the end. `TREE-SITTER AUDIT: every file read in full, every declaration typed, the
## parameters within the allowance` is the line to look for; anything else names what it found, above it,
## file by file.
##
## It needs the desktop library: the extension ships no phone build, so on a device that has none this says
## so and stops rather than pretending every file parsed.
##
## **It is also a gate.** The workflow runs this scene headless beside the suite and reads the exit code, so
## the doctrine is enforced on every pull request rather than re-measured whenever somebody remembers:
## non-zero for a file the grammar cannot read, a declaration a type could be written for, a function with
## no return type, or an untyped parameter past the allowance - and non-zero for a run that could not happen
## at all, because a check that silently did not run is the very failure this tool goes looking for in the
## code it reads. `faults()` is that rule; `tests/test_tree_sitter_audit.gd` holds it to being able to say no.

## What is read, and what the walk does not descend into - neither the addons nor the editor's cache is
## this project's own script.
const SCRIPTS_ROOT := "res://scripts"
const SKIP_DIRS: Array[String] = ["addons", ".godot"]

## The name each count is reported under, and the query that counts it.
const COUNTS: Dictionary = {
	"classes": "(class_name_statement name: (name) @n)",
	"signals": "(signal_statement name: (name) @n)",
	"constants": "(const_statement name: (name) @n)",
	"variables": "(variable_statement name: (name) @n)",
	"functions": "(function_definition name: (name) @n)",
}

## Where the grammar gave up in a file.
const ERRORS := "(ERROR) @e"

## Declarations with no type field and no `:=` inference: plain `var x = ...`, and bare `var x`.
const PLAIN_VARS := "(variable_statement !type) @v"

## Parameters with no type: a bare `identifier` written straight into a parameter list, and a
## `default_parameter` (`d = 5`), which has a default and still no type. Both are measured, because a default
## is not a type, and a typed parameter parses as a kind of its own (`typed_parameter`,
## `typed_default_parameter`) rather than as an identifier carrying a field.
##
## Anchored to `function_definition` and `lambda` rather than left loose on `parameters`, because a property's
## accessor has a parameter list too: `var mode: ViewMode = ... : set(value):` parses a `parameters` node
## holding `value`, and Godot types that from the property itself - counting it would name a fault nobody
## wrote. The anchor is the whole difference: on one sample, loose reports three parameters and a false one,
## anchored exactly the three.
const UNTYPED_PARAMS := (
	"(function_definition parameters: (parameters (identifier) @p))\n"
	+ "(lambda parameters: (parameters (identifier) @p))\n"
	+ "(function_definition parameters: (parameters (default_parameter) @p))\n"
	+ "(lambda parameters: (parameters (default_parameter) @p))"
)

## Functions that state no return type.
const NO_RETURN := "(function_definition !return_type name: (name) @n)"

## What makes a plain declaration a Variant by nature rather than an omission: a dictionary read (`.get(`
## or an index) or a loaded resource (`load`/`preload`). AGENTS.md keeps the first untyped on purpose. A
## bare dictionary *literal* is not a read, so it is left to the second list.
const VARIANT_READ := "\\.get\\(|[A-Za-z0-9_\\)\\]]\\s*\\["

## The parameters this project keeps untyped **on purpose**, and the gate's allowance for them: a value read
## out of a dictionary, a name accepted as either a `String` or a `StringName`, a spawn function's data, a
## measure that may be null. They are named in the report so the list can be read, and counted here so a
## **new** one cannot slip in behind them - which is the whole difference between a check and a printout.
## Typing one lowers the count and needs nothing changed here; raising it needs a reason written beside it,
## the way this project writes an exception beside the rule it excepts.
const DELIBERATE_PARAMETERS := 24

var _variant_read := RegEx.new()


func _ready() -> void:
	if not ClassDB.class_exists(&"GDScriptTreeSitter"):
		print("TREE-SITTER AUDIT: the tree_sitter_gd extension is not loaded on this device.")
		print("  It ships desktop libraries only (Windows, Linux, macOS); see res://addons/tree_sitter_gd/README.md")
		_finish({ "ran": false })
		return
	_variant_read.compile(VARIANT_READ)

	var files: Array[String] = []
	_collect(SCRIPTS_ROOT, files)
	files.sort()

	print("################ TREE-SITTER AUDIT: %d script(s) under %s ################" % [files.size(), SCRIPTS_ROOT])
	var totals: Dictionary = {}
	for key: String in COUNTS:
		totals[key] = 0
	var clean := 0
	var tripped := 0
	var by_nature: Array[String] = []
	var typable: Array[String] = []
	var no_return: Array[String] = []
	var untyped_params: Array[String] = []
	for path: String in files:
		var row: Dictionary = _read_one(path)
		for key: String in COUNTS:
			totals[key] = int(totals[key]) + int(row[key])
		by_nature.append_array(row["variant"] as Array)
		typable.append_array(row["typable"] as Array)
		no_return.append_array(row["no_return"] as Array)
		untyped_params.append_array(row["params"] as Array)
		if not (row["errors"] as Array).is_empty():
			tripped += 1
			for error: Dictionary in (row["errors"] as Array):
				print("  %s:%d  %s" % [path, int(error["start_line"]) + 1, String(error["text"]).strip_edges().substr(0, 60)])
		else:
			clean += 1

	print("")
	print("=== TREE-SITTER AUDIT RESULTS ===")
	print("  parsed         %d file(s)" % files.size())
	print("  read in full   %d file(s)" % clean)
	print("  tripped        %d file(s)" % tripped)
	for key: String in COUNTS:
		print("  %-14s %d" % [key, int(totals[key])])
	print("  plain `var =`  %d  (of which %d are a Variant by nature)" % [by_nature.size() + typable.size(), by_nature.size()])
	print("  no return type %d function(s)" % no_return.size())
	print("  untyped params %d  (the gate allows %d of these)" % [untyped_params.size(), DELIBERATE_PARAMETERS])

	print("")
	print("--- declarations a type could be written for (%d) ---" % typable.size())
	for line: String in typable:
		print("   ", line)
	print("--- functions with no return type (%d) ---" % no_return.size())
	for line: String in no_return:
		print("   ", line)
	print("--- parameters with no type (%d) ---" % untyped_params.size())
	for line: String in untyped_params:
		print("   ", line)

	_finish(
		{
			"ran": true,
			"tripped": tripped,
			"typable": typable.size(),
			"no_return": no_return.size(),
			"params": untyped_params.size(),
		}
	)


## How many faults a run found: the number the exit code is made from, and the whole of the gate. Zero is
## the pass.
##
## **A run that could not happen is a fault, not a pass.** The extension ships desktop libraries only, so a
## machine without it would otherwise report nothing wrong and be believed - the same failure this tool
## exists to find in the code it reads, one level up.
static func faults(found: Dictionary) -> int:
	if not bool(found.get("ran", false)):
		return 1
	return (
		int(found.get("tripped", 0))
		+ int(found.get("typable", 0))
		+ int(found.get("no_return", 0))
		+ maxi(0, int(found.get("params", 0)) - DELIBERATE_PARAMETERS)
	)


## The last word: the line a person reads, and the exit code CI reads.
func _finish(found: Dictionary) -> void:
	var count := faults(found)
	print("")
	if count == 0:
		print("TREE-SITTER AUDIT: every file read in full, every declaration typed, the parameters within the allowance")
	elif not bool(found.get("ran", false)):
		print("TREE-SITTER AUDIT: the check could not run, so nothing was read and nothing is cleared")
	else:
		print("TREE-SITTER AUDIT: %d fault(s), named above" % count)
		print("  %d file(s) unread" % int(found["tripped"]))
		print("  %d untyped declaration(s)" % int(found["typable"]))
		print("  %d function(s) with no return type" % int(found["no_return"]))
		print("  %d untyped parameter(s), against the %d allowed" % [int(found["params"]), DELIBERATE_PARAMETERS])
	print("################ END TREE-SITTER AUDIT ################")
	get_tree().quit(0 if count == 0 else 1)


## Read one file and return its counts, the grammar's own ERROR nodes, and the two declaration lists.
func _read_one(path: String) -> Dictionary:
	var row: Dictionary = {
		"errors": [] as Array,
		"variant": [] as Array,
		"typable": [] as Array,
		"no_return": [] as Array,
		"params": [] as Array,
	}
	for key: String in COUNTS:
		row[key] = 0
	var source: String = FileAccess.get_file_as_string(path)
	if source.is_empty():
		return row
	# The class is reached through ClassDB, never by name: naming it would stop this script from compiling
	# on a device that has no library, which is the case the guard in _ready exists for.
	var tree_sitter: RefCounted = ClassDB.instantiate(&"GDScriptTreeSitter")
	tree_sitter.call(&"open_text", source)
	for key: String in COUNTS:
		row[key] = _matches(tree_sitter, String(COUNTS[key])).size()
	for m: Dictionary in _matches(tree_sitter, ERRORS):
		row["errors"].append(m["e"])
	for m: Dictionary in _matches(tree_sitter, PLAIN_VARS):
		var where: Dictionary = m["v"]
		var whole := String(where["text"]).strip_edges().replace("\n", " ")
		var spot := "%s:%d  %s" % [path, int(where["start_line"]) + 1, whole.substr(0, 64)]
		if _reads_a_variant(whole):
			row["variant"].append(spot)
		else:
			row["typable"].append(spot)
	for m: Dictionary in _matches(tree_sitter, NO_RETURN):
		var where: Dictionary = m["n"]
		row["no_return"].append("%s:%d  %s()" % [path, int(where["start_line"]) + 1, String(where["text"])])
	var lines := source.split("\n")
	for m: Dictionary in _matches(tree_sitter, UNTYPED_PARAMS):
		var parameter: Dictionary = m["p"]
		var at := int(parameter["start_line"])
		row["params"].append(
			"%s:%d  %s  in  %s" % [path, at + 1, String(parameter["text"]), _signature_above(lines, at)]
		)
	return row


## The matches for a query, or an empty array where the query did not answer with one.
func _matches(tree_sitter: RefCounted, pattern: String) -> Array:
	var found: Variant = tree_sitter.call(&"query", pattern)
	return found as Array if found is Array else [] as Array


## The `func` line a parameter belongs to, found by walking up from the parameter - so an untyped parameter
## is reported with the signature a reader has to look at to judge it, rather than as a name out of context.
func _signature_above(lines: PackedStringArray, at: int) -> String:
	var i := at
	while i >= 0:
		var line := lines[i].strip_edges()
		if line.begins_with("func ") or line.begins_with("static func "):
			return line
		i -= 1
	return "?"


## Whether a plain declaration's value is a Variant by nature - read out of a dictionary, or a loaded
## resource - rather than a type somebody forgot to state.
func _reads_a_variant(statement: String) -> bool:
	var equals := statement.find("=")
	var value := statement.substr(equals + 1).strip_edges() if equals >= 0 else ""
	if value.begins_with("load(") or value.begins_with("preload("):
		return true
	return _variant_read.search(value) != null


## Every `.gd` file under `dir_path`, the folders walked in turn.
func _collect(dir_path: String, out: Array[String]) -> void:
	for file_name: String in DirAccess.get_files_at(dir_path):
		if file_name.ends_with(".gd"):
			out.append(dir_path.path_join(file_name))
	for sub: String in DirAccess.get_directories_at(dir_path):
		if sub in SKIP_DIRS:
			continue
		_collect(dir_path.path_join(sub), out)
