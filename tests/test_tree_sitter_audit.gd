extends Node
## The tree-sitter audit's gate, held down.
##
## `tools/tree_sitter_audit.gd` is a dev tool, so there is little here about what it prints. What there is
## is the one thing it cannot check about itself: **that its gate can say no.** The workflow runs it
## headless beside the suite and reads the exit code, so a rule that answered zero for everything would be
## theatre - green on every commit, including the one that added a fresh untyped declaration.
##
## The rule is `faults()`, and it is static for exactly this reason.

const Audit := preload("res://tools/tree_sitter_audit.gd")


## A project with nothing wrong in it - every file read, nothing left to type - is the pass, and it is the
## only thing that is.
func test_a_clean_run_is_no_faults() -> void:
	var clean := { "ran": true, "tripped": 0, "typable": 0, "no_return": 0, "params": Audit.DELIBERATE_PARAMETERS }
	assert(Audit.faults(clean) == 0, "a project with nothing wrong in it passes")


## A run that could not happen at all is a fault and not a pass. The extension ships desktop libraries
## only, so a machine without it must not be read as having found nothing wrong - which is the same failure
## this tool goes looking for in the code it reads, one level up.
func test_a_run_that_could_not_happen_is_a_fault() -> void:
	assert(Audit.faults({ "ran": false }) > 0, "a check that never ran is not a check that passed")


## Each of the three faults fails the gate on its own, so no one of them can hide behind the others.
func test_each_fault_fails_the_gate_alone() -> void:
	for key: String in ["tripped", "typable", "no_return"]:
		var broken := { "ran": true, "tripped": 0, "typable": 0, "no_return": 0, "params": Audit.DELIBERATE_PARAMETERS }
		broken[key] = 1
		assert(Audit.faults(broken) > 0, "one " + key + " is a fault")


## The deliberate parameters are allowed up to the number stated and no further, which is what makes a 25th
## one fail rather than join them quietly.
func test_one_parameter_past_the_allowance_is_a_fault() -> void:
	var at_the_line := {
		"ran": true,
		"tripped": 0,
		"typable": 0,
		"no_return": 0,
		"params": Audit.DELIBERATE_PARAMETERS,
	}
	assert(Audit.faults(at_the_line) == 0, "the allowance itself is allowed")
	at_the_line["params"] = Audit.DELIBERATE_PARAMETERS + 1
	assert(Audit.faults(at_the_line) > 0, "one past it is a fault")


## Typing some of the deliberate ones is progress and must leave the gate open: the number may fall freely,
## and a project that typed one of them is not in trouble for it.
func test_fewer_than_the_allowance_is_still_a_pass() -> void:
	var fewer := {
		"ran": true,
		"tripped": 0,
		"typable": 0,
		"no_return": 0,
		"params": maxi(Audit.DELIBERATE_PARAMETERS - 1, 0),
	}
	assert(Audit.faults(fewer) == 0, "typing one of them is progress, not a fault")


## The scene runs the script, so the command the workflow runs is the check it says it is.
func test_the_audit_scene_runs_the_audit_script() -> void:
	var packed := ResourceLoader.load("res://tools/tree_sitter_audit.tscn", "PackedScene") as PackedScene
	assert(packed != null, "the audit scene loads")
	var root: Node = packed.instantiate()
	var script: Script = root.get_script()
	var path: String = script.resource_path if script != null else ""
	root.free()
	assert(path == "res://tools/tree_sitter_audit.gd", path)
