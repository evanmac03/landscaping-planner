extends SyntaxHighlighter
## A tree-sitter-driven GDScript highlighter, small enough to read in one sitting - the honest half of a
## scope-aware one. What a name *is* comes from the parse tree the tree_sitter_gd extension builds, so a
## word that merely looks like a function is left alone, and every colour is decided by the grammar rather
## than by rules of thumb.
##
## It reads the project's own extension and, on a device that has none, colours nothing rather than
## guessing - there is no phone build of the library (see res://addons/_lib/tree_sitter_gd/README.md).
##
## Beside tools/tree_sitter_editor_demo.tscn, which puts it on a CodeEdit showing a real project script.

## What each kind of name is coloured, keyed by the kind the rule states. A dark-theme palette, which is
## where a person meets them.
const COLORS := {
	"class": Color("6fd0ff"),
	"signal": Color("e6a6f2"),
	"constant": Color("f2c07a"),
	"function": Color("a8e06a"),
	"string": Color("e0a878"),
	"number": Color("9fc0f2"),
	"comment": Color("6f8f80"),
}

## Each rule is a capture query and the kind it colours. The query names the node, so the tree decides
## what matches; nothing here reads the shape of a word.
const RULES := [
	{ "kind": "class", "query": "(class_name_statement name: (name) @c)" },
	{ "kind": "signal", "query": "(signal_statement name: (name) @c)" },
	{ "kind": "constant", "query": "(const_statement name: (name) @c)" },
	{ "kind": "function", "query": "(function_definition name: (name) @c)" },
	{ "kind": "string", "query": "(string) @c" },
	{ "kind": "number", "query": "(integer) @c" },
	{ "kind": "number", "query": "(float) @c" },
	{ "kind": "comment", "query": "(comment) @c" },
]

## The colour a line falls back to outside a coloured span, taken from the editor's own ink so the spans
## sit on the same paper as the rest of the text.
var _default: Color = Color.WHITE

## line number -> Array of {start, end, color}. Built once per parse, read a line at a time.
var _spans: Dictionary = { }


## Rebuild the spans. Called by the TextEdit when it wants the cache, and by the demo after setting text.
func _update_cache() -> void:
	_rebuild()


func _clear_highlighting_cache() -> void:
	_spans.clear()


func _rebuild() -> void:
	_spans.clear()
	var edit: TextEdit = get_text_edit()
	if edit == null:
		return
	_default = edit.get_theme_color(&"font_color")
	# The class is reached through ClassDB, never by name: naming it would stop this script from
	# compiling on a device that has no library, which is the case this guard exists for.
	if not ClassDB.class_exists(&"GDScriptTreeSitter"):
		return
	var tree_sitter: RefCounted = ClassDB.instantiate(&"GDScriptTreeSitter")
	tree_sitter.call(&"open_text", edit.text)
	for rule: Dictionary in RULES:
		var color: Color = COLORS[rule["kind"]]
		for found: Dictionary in tree_sitter.call(&"query", String(rule["query"])):
			var where: Dictionary = found["c"]
			_add_span(int(where["start_line"]), int(where["start_col"]), int(where["end_col"]), color)


## The colouring for one line: a region starts at each span's first column and runs to where the next
## entry begins, so each span carries a second entry - the editor's own ink - to close it.
func _get_line_syntax_highlighting(line: int) -> Dictionary:
	var spans: Array = _spans.get(line, [])
	if spans.is_empty():
		return { }
	var entries: Array = []
	for span: Dictionary in spans:
		entries.append({ "col": int(span["start"]), "color": span["color"] })
		entries.append({ "col": int(span["end"]), "color": _default })
	entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["col"]) < int(b["col"]),
	)
	var line_data: Dictionary = { }
	for entry: Dictionary in entries:
		if not line_data.has(entry["col"]):
			line_data[entry["col"]] = { "color": entry["color"] }
	return line_data


func _add_span(line: int, start_col: int, end_col: int, color: Color) -> void:
	var spans: Array = _spans.get(line, [])
	spans.append({ "start": start_col, "end": end_col, "color": color })
	_spans[line] = spans
