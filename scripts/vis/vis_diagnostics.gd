class_name VisDiagnostics
extends RefCounted
## What the presentation is missing, named by the file that should change.
##
## A report rather than a validator: every finding names the thing to fix, and none of
## them stop a render. A proposal with one unwashed layer is still a proposal
## (REQ-V11.3), which is why nothing here returns a verdict - only findings.
##
## The answers it reports are the ones that were previously found by looking at a
## picture and wondering why it came out grey:
##
##  * a layer that carries geometry and plots but has no wash entry, so it is missing
##    from the painted plan;
##  * a layer that carries geometry and builds no solid, so it is flat in the 3D view -
##    a note rather than a warning, because most layers are flat on purpose and the
##    point is to put that on the record;
##  * a hardscape texture set with a map that is not on disk;
##  * a solid whose material set the texture table does not have.
##
## It asks the *tables themselves* why, rather than repeating their rules: the wash
## table's refusal is `reason_against`, the solid table's is `reason_for`, and the
## textures answer `missing_paths`. A second copy of those rules here would be a second
## thing to keep in step, and the first one has tests.
##
## The drawing is asked which layers it actually uses. A layer nobody has drawn on
## cannot be missing a wash, and reporting it would bury the layers that are.

const WashTableScript := preload("res://scripts/vis/wash_table.gd")
const SolidTableScript := preload("res://scripts/vis/solid_table.gd")
const HardscapeScript := preload("res://scripts/vis/hardscape_material.gd")

## Nothing renders without this one: a solid whose texture is gone is a grey patio.
const ERROR := "error"
## Something is on the drawing and will not appear in one of the pictures.
const WARNING := "warning"
## A decision worth having on the record. Nothing is wrong.
const NOTE := "note"
## Most serious first, which is the order a person wants to read them in.
const SEVERITY_ORDER: Array[String] = [ERROR, WARNING, NOTE]


## Every finding, as `{severity, where, what}`, most serious first.
##
## `document` is asked which layers it has drawn on; `layer_set` is asked what the
## project's layers are. Both are needed and neither is enough: the layer set knows
## what a layer is for, the drawing knows whether it is used.
static func report(document, layer_set) -> Array[Dictionary]:
	var findings: Array[Dictionary] = []
	if layer_set == null:
		return findings
	for layer: Variant in layer_set.layers():
		var layer_name := StringName(layer.name)
		# A construction or tracing layer is not a picture (specification 4.2).
		if not bool(layer.plots):
			continue
		# A layer nobody has drawn on cannot be missing anything.
		if not _is_used(document, layer_name):
			continue
		# Two ways a layer can wash nothing, and they are different problems: the table
		# recorded why it should not (a decision, and nothing to say about it), or the
		# table has never heard of the layer at all (a table to extend). Only the second
		# is worth a finding, and telling them apart is reading the table's own two
		# halves rather than matching on what its prose happens to say.
		#
		# A deliberate non-wash is silent because a plan with twenty annotations on it
		# would otherwise arrive with twenty notes saying so, and a report nobody reads
		# is not a report.
		if not WashTableScript.washes(layer_name):
			if not WashTableScript.NO_WASH.has(layer_name):
				findings.append({
					"severity": WARNING,
					"where": "scripts/vis/wash_table.gd",
					"what": "layer '%s' has geometry and plots but the wash table has no entry for it: add it to WashTable.WASHES or record why it does not wash." % layer_name,
				})
		if not SolidTableScript.has_solid(layer_name):
			if SolidTableScript.NO_SOLID.has(layer_name):
				findings.append({
					"severity": NOTE,
					"where": "scripts/vis/solid_table.gd",
					"what": "layer '%s' builds no solid: %s" % [
						layer_name, SolidTableScript.reason_for(layer_name),
					],
				})
			else:
				findings.append({
					"severity": WARNING,
					"where": "scripts/vis/solid_table.gd",
					"what": "layer '%s' has geometry and plots but the solid table has no entry for it: add it to SolidTable.SOLIDS or record why it stays flat." % layer_name,
				})
	# A solid that names a material set nobody has is a solid that renders grey.
	for set_name: String in SolidTableScript.material_sets():
		if not HardscapeScript.has_set(set_name):
			findings.append({
				"severity": ERROR,
				"where": "scripts/vis/solid_table.gd",
				"what": "a solid asks for texture set '%s', which the texture table does not have" % set_name,
			})
	# The textures themselves, as paths that are not on disk.
	for path: String in HardscapeScript.missing_paths():
		findings.append({
			"severity": ERROR,
			"where": path,
			"what": "the hardscape texture set is missing this map",
		})
	return sorted(findings)


## Whether the drawing has anything drawn on a layer. A drawing that cannot be asked
## (none handed over) counts as used, so a report over a layer set alone is still the
## layer set's answers rather than nothing at all.
static func _is_used(document, layer_name: StringName) -> bool:
	if document == null:
		return true
	if not document.has_method("entities_on_layer"):
		return true
	var entities: Variant = document.entities_on_layer(layer_name)
	if entities == null or not entities is Array:
		return true
	return not (entities as Array).is_empty()


## The findings most serious first, and within a severity by where it is and what it
## says - so the same drawing gives the same report every time and two reports can be
## compared.
static func sorted(findings: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = findings.duplicate(true)
	out.sort_custom(_before)
	return out


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var ar: int = severity_rank(String(a["severity"]))
	var br: int = severity_rank(String(b["severity"]))
	if ar != br:
		return ar < br
	var aw := String(a["where"])
	var bw := String(b["where"])
	if aw != bw:
		return aw < bw
	return String(a["what"]) < String(b["what"])


## Where a severity sits in the order: 0 is the one to fix first. A severity nobody has
## sorts last rather than first, so a typo cannot push something to the top.
static func severity_rank(severity: String) -> int:
	var at: int = SEVERITY_ORDER.find(severity)
	return at if at >= 0 else SEVERITY_ORDER.size()


## How many findings there are of one severity.
static func count_of(findings: Array[Dictionary], severity: String) -> int:
	var out := 0
	for finding: Dictionary in findings:
		if String(finding["severity"]) == severity:
			out += 1
	return out


## The findings that are something to fix - errors and warnings, without the notes.
## A dock lists these first and puts the notes behind a toggle, because "flat as
## authored" is not a problem to act on.
static func problems(findings: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for finding: Dictionary in findings:
		if String(finding["severity"]) != NOTE:
			out.append(finding)
	return out


## The findings as rows a table can show, in the same order.
static func rows(findings: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for finding: Dictionary in findings:
		out.append({
			"severity": String(finding["severity"]),
			"where": String(finding["where"]),
			"what": String(finding["what"]),
			"text": "%s: %s  (%s)" % [
				String(finding["severity"]).to_upper(), String(finding["what"]), String(finding["where"]),
			],
		})
	return out


## The report in one line, for a status bar or a dock's own note.
static func summarise(findings: Array[Dictionary]) -> String:
	if findings.is_empty():
		return "nothing to report: the presentation has everything it asks for."
	var parts: Array[String] = []
	for severity: String in SEVERITY_ORDER:
		var many: int = count_of(findings, severity)
		if many > 0:
			parts.append("%d %s%s" % [many, severity, "" if many == 1 else "s"])
	return " | ".join(parts)


## The report as one line per finding, for a log or a console.
static func report_text(findings: Array[Dictionary]) -> String:
	var lines: Array[String] = [summarise(findings)]
	for row: Dictionary in rows(findings):
		lines.append(String(row["text"]))
	return "\n".join(lines)


## Find the same finding twice, for a test that wants to assert one thing about one
## layer without the whole report being in the way.
static func mentions(findings: Array[Dictionary], needle: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for finding: Dictionary in findings:
		if String(finding["what"]).contains(needle):
			out.append(finding)
	return out


## The questions this report answers, for a dock's own heading.
static func describe() -> String:
	return "washes, solids and texture maps the presentation is missing"