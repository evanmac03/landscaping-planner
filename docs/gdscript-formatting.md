# GDScript formatting: the house style, the sweep, and the one construct that breaks it

`AGENTS.md` asks that a change match the local style. The local style here is **the GDScript formatter's**
output at a **120-character** budget: collection literals exploded one entry per line with a trailing comma,
`{}` written `{ }`, tabs, and a file ending in a newline. This is the record of what that means, of the sweep
that settles a tree which has drifted, and of the one construct that stops the tool working at all.

## 1. What the formatter is, and where it lives

`addons/GDQuest_GDScript_formatter/` is the editor plugin, gitignored and off limits like every other addon.
**It ships no binary**: the plugin fetches `gdscript-formatter-<version>-windows-x86_64.exe.zip` from
GDQuest's releases into Godot's own cache (`%APPDATA%\Godot\cache\gdquest\`), and with no binary there it
can only offer to install one. So the formatter is **not in this repository** - which is why the check in CI
fetches it (section 4), and why a local run starts from the recipe below rather than from a command here.

## 2. The sweep, and the two ways it goes wrong

One file at a time, to standard output, and the result read before it is written:

    gdscript-formatter --stdout --max-line-length 120 --verify-structure tests/example.gd > build/formatted.gd
    diff -u tests/example.gd build/formatted.gd     # read it, and be sure the print is not empty
    cp build/formatted.gd tests/example.gd          # write only what was read

**Never let it write in place with a length flag.** Measured on a 738-line test file: the in-place run with
`--max-line-length 120` rewrote 185 lines - the answer for its *own default* of 100 - while the same
transformation to standard output differs by ten. An in-place run is a mass reformat of a file that believed
it was being formatted at 120.

**Never mass-rewrite while Godot is open.** The binary needs nothing from the engine, so the safest run has
the editor closed; with it open, rewrite in small batches, leave the file the script editor is holding until
last, and read the editor's own log between batches.

To see the state of the whole tree in one pass - `scripts`, `tests` and `tools`, never `addons/`:

    gdscript-formatter --check --max-line-length 120 --verify-structure scripts tests tools

It answers *All 637 file(s) are formatted* and exits 0, or exits 1 and names what it would change.

## 3. The one construct that breaks it

**An expression longer than 120 characters that is not inside brackets.** To wrap one, the formatter can only
fall back on backslash continuations, and it splits at whatever boundary it finds - so `node.a.b` is broken
after `node`, and two of the three lines it produces end in a backslash. **Its own `--verify-structure`
refuses that transformation**, and without the flag the unverified output disagrees with itself on the next
pass, which reads like a file that never settles. Two files here sat unformatted for a week for exactly this
reason, and the way out was in our code rather than the tool's: bracket the condition, or split the
expression into statements.

    # refused: 130 characters with nothing to wrap inside
    if not width_known or not height_known or not depth_known:

    # formatted: the wrap has somewhere to happen
    if (
        not width_known
        or not height_known
        or not depth_known
    ):

A file's formatted output must parse as the input did, so rewriting an expression is safe - and both ways out
read better than the line they replace.

## 4. The check in CI

`.github/workflows/workflow-checks.yml` carries a **formatting** job. It fetches the verified 0.28.0 release,
checks the archive against the hash measured from it, and runs the whole-tree `--check` above. A file that is
not formatted, **or one whose formatting the structure check refuses**, fails the job - which is the point:
the refusal is the fault in section 3 arriving, and a gate that accepted the unchecked output would let it
through.

When the gate fails, run the sweep and commit the result as a commit of its own. A formatting change and a
behaviour change in one commit make the second one unreadable.

## 5. What it does not do

It is a formatter with a parser, not a linter: it has no opinion about a name, a comment or a rule. It cannot
rewrite a string literal that is over the budget, so a long string stays long - which is why a passing
`--check` does not mean no line here exceeds 120 characters, only that every line the tool *can* wrap has
been wrapped. The typed-declaration audit in `tools/tree_sitter_audit.gd` is the other half of that question.

## 6. Reported upstream

The construct in section 3 is a fault in the tool: it refuses a transformation it produced itself, and its
diagnostic asks for a report with a copy of the input. The reproducer is three lines -

    extends Node

    func f() -> bool:
        if not one_long_condition_here or not another_long_condition or not a_third_long_condition:
            return false
        return true

- where the `if` line is over 120 characters and nothing about it is bracketed: `--stdout
--verify-structure` fails with *The formatted output is structurally different from the input.* Bracketing the
condition, or shortening the line, is the workaround.
