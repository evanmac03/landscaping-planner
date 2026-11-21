extends GDScriptCodeEditTreeSitter

# intended for use with GDScriptParser and SyntaxPlus Highlighter
# use as preloaded class

var _sparse_cache: Dictionary = {}
var _sparse_revision: int = -1

func _init():
	parser = GDScriptTreeParser.new()

func parse() -> Dictionary:
	return parser.parse_script(_script_path)

## Cached sparse_parse(). The C++ call walks the whole tree and allocates a fresh Dictionary every
## time, so repeat calls within one tree revision are pure waste - with several consumers per frame
## that is the bulk of the cost. Reparses first (a free no-op when already current), then serves one
## result per revision.
## The returned Dictionary is SHARED and reused - treat it as read-only, exactly like get_brackets().
func sparse_parse() -> Dictionary:
	parse_text()
	if _edit == null:
		return parser.sparse_parse() # no attached buffer -> no revision to key on, never cache
	if _sparse_revision == _parse_revision:
		return _sparse_cache
	_sparse_cache = parser.sparse_parse()
	_sparse_revision = _parse_revision
	return _sparse_cache

