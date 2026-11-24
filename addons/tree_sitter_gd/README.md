# Godot-TreeSitter-Wrapper

A Godot 4 GDExtension that exposes a RefCounted TreeSitter class. Uses:
[tree-sitter](https://tree-sitter.github.io) and the
[tree-sitter-gdscript](https://github.com/PrestonKnopp/tree-sitter-gdscript) grammar.

Simple operation, give it text or a file path, and it parses. Give it an updated text
it will calculate the byte offset and do an incremental parse.

There are a couple other classes here that extend the basic TreeSitter class, they demonstrate
where this can be useful. I use them in the following for faster parsing:
1. [GDScriptParser](https://github.com/brohd11/Godot-Addon-Lib/tree/main/alib_runtime/utils/gdscript/parser) - Type resolution parser
2. [SyntaxPlus](https://github.com/brohd11/Godot-GD-Syntax-Plus) - Scope aware syntax highlighter

For info on [usage](doc/usage.md)

---

## Installation

### gdaddon Install
You can use [gdaddon](https://github.com/brohd11/gdaddon) to manage installation. 
It is a TUI package/repo manager that can install and update addons for you.

`curl -fsSL https://raw.githubusercontent.com/brohd11/gdaddon/main/install.sh | sh`

Then, you can add the addon and install:
```
cd ~/your/project/
gdaddon install brohd11/godot-tree-sitter-gd
```
### Manual Install

Extract release zip into your project root. It contains a single `addons/` tree, so it
merges into place as `addons/_lib/tree_sitter_gd/`:

```
your-project/
└── addons/
    └── _lib/
        └── tree_sitter_gd/
```

Must land at `res://addons/_lib/tree_sitter_gd/` or Godot won't find the libraries.

### macOS: unblocking the binaries

The macOS libraries are not notarized by Apple, so anything downloaded through a browser is
flagged by Gatekeeper (`com.apple.quarantine`) and Godot will refuse to load the extension.
After copying the addon into your project, clear the flag once:

```bash
xattr -dr com.apple.quarantine path/to/project/addons/_lib/tree_sitter_gd
```

Then reopen the project. (Windows and Linux are unaffected.)

---

## License

MIT — see [LICENSE](LICENSE).
*(tree-sitter: MIT, tree-sitter-gdscript: MIT, godot-cpp: MIT)*
