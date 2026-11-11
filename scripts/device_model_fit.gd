class_name DeviceModelFit
extends RefCounted
## What this machine is, and which vision model it can carry: the two questions the "find a model for
## this device" page asks, kept here as arithmetic rather than left to the page to guess at.
##
## ## One question, not two
##
## Reading the machine and deciding what fits it are one question with two halves, and they live in one
## file because either half alone is useless: a reading with nothing to compare it against is a number,
## and a model with nothing to compare it against is a guess. Everything here is `static` and **every
## reading is an argument**, so a test can ask what the 3.4 GB phone this project was tested on would be
## told without being one - the same door `HeldOrientation` and `TouchInput.force` keep.
##
## ## The number that decides is free memory, not the memory in the box
##
## A model does not get the whole machine. It gets what the operating system and this program are not
## already using, which is why `summary` prints both figures and why `memory_for_a_model` subtracts a
## floor rather than handing over everything. On the Android phone this was measured against, the total
## was 3.37 GB and the free memory 0.75 GB: a machine that reads as "3.4 GB, plenty for a small model"
## and in fact cannot hold one alongside this program.
##
## Measured on this project's own Windows machine, `OS.get_memory_info()["available"]` reported 57.8 GB
## against 31.8 GB of physical memory - it is the commit limit, not the memory - so `available` is
## **never read here** and free memory is clamped to what the box has.
##
## ## A size this program cannot vouch for is not a size
##
## Every model carries the size of the files it takes and a sentence saying where that number came
## from. A model whose figures are not all known - a GGUF whose language weights are published but
## whose projector is not - is **named as not vouched for rather than offered**, because the alternative
## is a person downloading a file on this program's word and finding it half there. The table grows as
## figures are checked; nothing in it is estimated from a model's name.

## A reading that could not be taken. **Not zero**: zero is a real answer - an empty disk - while
## `UNKNOWN` is the absence of an answer, and the two must not be shown as the same thing.
const UNKNOWN := -1

## How much memory a machine has to have spare before a model of a given size is started on it, as a
## proportion of the model's own files, and the runtime around it. This is a stated rule rather than a
## measured constant, which is the point: it is the same arithmetic for every model, so a model added to
## the table tomorrow is sized by the same sentence as the ones here today.
const MODEL_HEADROOM := 1.25
const RUNTIME_BYTES := 250000000

## What the operating system and this program are assumed to keep, so that a model is offered the memory
## left over rather than the whole box. An assumption, written down so it can be argued with.
const PHONE_FLOOR_BYTES := 1800000000
const DESKTOP_FLOOR_BYTES := 2500000000

## What a machine's memory makes of it. The names say what the tier means rather than what sort of
## device is likely to have it: an 11 GB laptop and an 11 GB tablet are the same tier here.
const TIER_UNKNOWN := &"unknown"
const TIER_TIGHT := &"tight"
const TIER_WORKABLE := &"workable"
const TIER_COMFORTABLE := &"comfortable"
const TIER_ROOMY := &"roomy"

## Where a model is best run, given what the machine turned out to be.
const ROUTE_UNMEASURED := &"unmeasured"
const ROUTE_THIS_DEVICE := &"this_device"
const ROUTE_WIFI_COMPUTER := &"wifi_computer"

## The words that mean a model can look at a picture rather than only read text.
##
## This is the **fallback, not the authority**: a service that lists its own models' `capabilities`
## answers this itself and that answer is the one to believe. What is here is for a server that says
## nothing, and it is deliberately narrow - a model this program has never heard of is *not* offered as
## something that can read a photograph, because offering somebody a text model as a plant reader costs
## them an afternoon and teaches them not to trust the next suggestion.
const VISION_MARKERS: PackedStringArray = [
	"llava", "bakllava", "smolvlm", "moondream", "minicpm-v", "pixtral", "internvl", "vision",
	"qwen2-vl", "qwen2vl", "qwen2.5vl", "qwen2.5-vl", "qwen3-vl", "gemma3", "llama4",
]

## The vision models this program can vouch for, smallest first, each with the sentence its size came
## from. Two entries, and deliberately: one is the model that read this project's own test photograph
## correctly, and one is the smallest thing that reads a leaf at all. Everything else a machine has can
## be found by asking it - `LocalModelProbe` reads a server's own list, sizes and capabilities - and a
## list invented here would be a second, worse answer to that.
const MODELS: Array[Dictionary] = [
	{
		"id": "smolvlm-500m",
		"label": "SmolVLM 500M",
		"ollama_tag": "",
		"gguf_repo": "pierretokns/SmolVLM-500M-Instruct-GGUF",
		"needs_mmproj": true,
		"weights_bytes": 289000000,
		"projector_bytes": 190000000,
		"size_whence": (
			"the two file sizes the model's own GGUF repository lists: 289 MB of weights and 190 MB of "
			+ "vision projector"
		),
		"why": (
			"the smallest vision model this program knows of: it names a plant less reliably than the "
			+ "bigger one, but it reads a photograph and it is the only one that fits a small phone"
		),
	},
	{
		"id": "qwen2.5vl-3b",
		"label": "Qwen2.5-VL 3B",
		"ollama_tag": "qwen2.5vl:3b",
		"gguf_repo": "",
		"needs_mmproj": false,
		"weights_bytes": 3200627168,
		"projector_bytes": 0,
		"size_whence": (
			"measured on this project's own machine: the size Ollama reports for qwen2.5vl:3b"
		),
		"why": (
			"the model that read this project's test photograph correctly in under three seconds, and "
			+ "the one the page's own live checks used"
		),
	},
]

## The runners a person gets a model onto a machine with. A runner is not a model: two of these can
## serve the same file, and which one is chosen is about the machine rather than about the plant.
##
## `two_files_needed` is the fact that costs an afternoon when it is left out: a vision model served by
## `llama.cpp` and its phones is **two** files - the language weights and the multimodal projector - and
## a server started with only the first one answers every photograph with a refusal about images.
const RUNNERS: Array[Dictionary] = [
	{
		"id": &"ollama",
		"label": "Ollama",
		"base_url": "http://127.0.0.1:11434",
		"models_url": "http://127.0.0.1:11434/v1/models",
		"download_url": "https://ollama.com/download",
		"pull_command": "ollama pull %s",
		"two_files_needed": false,
		"shared_setting": "OLLAMA_HOST",
	},
	{
		"id": &"llama-server",
		"label": "llama.cpp's llama-server",
		"base_url": "http://127.0.0.1:8080",
		"models_url": "http://127.0.0.1:8080/v1/models",
		"download_url": "https://github.com/ggml-org/llama.cpp/releases",
		"pull_command": "",
		"two_files_needed": true,
		"shared_setting": "",
	},
]


## The one reading this file takes from the world rather than being handed.
##
## `free` and never `available`: on the machine this was written on, `available` reported 57.8 GB against
## 31.8 GB of memory, which is the commit limit and not a fact about the memory. A disk that cannot say
## how much is left answers zero or less, and that becomes `UNKNOWN` rather than "a full disk".
static func scan_this_device() -> Dictionary:
	var memory: Dictionary = OS.get_memory_info()
	var disk: int = UNKNOWN
	var folder: DirAccess = DirAccess.open("user://")
	if folder != null:
		disk = folder.get_space_left()
	return scan(
		OS.get_name(),
		OS.get_model_name(),
		OS.get_processor_name(),
		OS.get_processor_count(),
		int(memory.get("physical", UNKNOWN)),
		int(memory.get("free", UNKNOWN)),
		disk,
		RenderingServer.get_video_adapter_name()
	)


## What a machine is, from readings somebody else took: `{platform, model_name, cpu_name, cores,
## physical_bytes, free_bytes, disk_free_bytes, gpu_name, tier}`.
##
## Every reading is an argument, which is what makes this testable and what makes the phone beside this
## machine askable without being attached. A reading of zero or less is `UNKNOWN`, and free memory is
## clamped to the memory the box has, because more free memory than exists is a machine reporting
## something other than its memory.
static func scan(
	platform: String,
	model_name: String,
	cpu_name: String,
	cores: int,
	physical_bytes: int,
	free_bytes: int,
	disk_free_bytes: int,
	gpu_name: String
) -> Dictionary:
	var physical: int = _said_number(physical_bytes)
	var free_now: int = _said_number(free_bytes)
	if physical > 0 and free_now > physical:
		free_now = physical
	return {
		"platform": platform.strip_edges(),
		"model_name": model_name.strip_edges(),
		"cpu_name": cpu_name.strip_edges(),
		"cores": cores if cores > 0 else UNKNOWN,
		"physical_bytes": physical,
		"free_bytes": free_now,
		"disk_free_bytes": _said_number(disk_free_bytes),
		"gpu_name": gpu_name.strip_edges(),
		"tier": tier_for(physical),
	}


## What a machine's memory makes of it. The thresholds are where a vision model stops being a squeeze
## and starts being comfortable, not where a phone stops being a phone - an 11 GB tablet is `roomy`
## here and so is a 64 GB workstation, because both run the same model the same way.
static func tier_for(physical_bytes: int) -> StringName:
	if physical_bytes == UNKNOWN or physical_bytes <= 0:
		return TIER_UNKNOWN
	if physical_bytes < 4000000000:
		return TIER_TIGHT
	if physical_bytes < 7000000000:
		return TIER_WORKABLE
	if physical_bytes < 12000000000:
		return TIER_COMFORTABLE
	return TIER_ROOMY


## The memory a model may use on this machine: what the box has, less what the operating system and
## this program are assumed to keep. Zero here means the floor is the whole machine, and the fits
## arithmetic simply then fits nothing - an answer, not a missing one.
static func memory_for_a_model(reading: Dictionary) -> int:
	var physical: int = int(reading.get("physical_bytes", UNKNOWN))
	if physical == UNKNOWN or physical <= 0:
		return 0
	var floor_bytes: int = PHONE_FLOOR_BYTES if _is_a_phone(reading) else DESKTOP_FLOOR_BYTES
	if physical <= floor_bytes:
		return 0
	return physical - floor_bytes


## The files a model takes to download, or `UNKNOWN` when this program cannot vouch for the whole of it.
##
## Half a size is not a size: a GGUF whose weights are published and whose projector is not comes back
## `UNKNOWN` rather than as the weights alone, because a person told "1 GB" who then needs a second file
## has been told something false rather than something incomplete.
static func download_bytes(model: Dictionary) -> int:
	var weights: int = int(model.get("weights_bytes", 0))
	if weights <= 0:
		return UNKNOWN
	if bool(model.get("needs_mmproj", false)):
		var projector: int = int(model.get("projector_bytes", 0))
		if projector <= 0:
			return UNKNOWN
		return weights + projector
	return weights


## What a model of this size needs free before it is started: its own files, the room it keeps as it
## works, and the runtime around it - the same arithmetic for every entry, so a model added tomorrow is
## sized by the same sentence as the ones here today.
static func ram_needed_bytes(model: Dictionary) -> int:
	var files: int = download_bytes(model)
	if files == UNKNOWN:
		return UNKNOWN
	return int(float(files) * MODEL_HEADROOM) + RUNTIME_BYTES


## Why this model will not be offered on this machine, in the machine's own numbers, or `""` when
## nothing stops it.
##
## A refusal names the **field to fix** rather than the feature: a model that will not fit the disk is a
## sentence about the disk, and one whose size is not known here is a sentence about this program's
## table rather than about the model.
static func skip_reason(model: Dictionary, reading: Dictionary) -> String:
	var files: int = download_bytes(model)
	if files == UNKNOWN:
		return "this program does not know the whole size of %s, so it will not tell you it fits" % _label(model)
	var needed: int = ram_needed_bytes(model)
	var disk: int = int(reading.get("disk_free_bytes", UNKNOWN))
	if disk == UNKNOWN:
		return "%s needs a disk this machine did not say the size of" % _label(model)
	if files > disk:
		return "%s needs %s of disk and this machine has %s free" % [
			_label(model), bytes_words(files), bytes_words(disk),
		]
	var room: int = memory_for_a_model(reading)
	if room <= 0:
		return (
			"this machine did not say how much memory it has, so nothing can be told it fits %s"
			% _label(model)
		)
	if needed > room:
		return "%s needs about %s of memory and this machine can spare about %s" % [
			_label(model), bytes_words(needed), bytes_words(room),
		]
	return ""


## What to do about a model on this machine: `{ok, tier, route, headline, reason, steps, fits, refused,
## small_experiment, needs_network}`.
##
## The tiers are not a ladder of better and worse - they are three different answers. A roomy machine is
## told the largest model that fits. A machine too tight to carry one at all is told **where to put it
## instead** - a computer on the same Wi-Fi - and is offered the smallest model only as an experiment
## that is expected to be killed, because the useful answer to "can this phone read a leaf" is not a
## smaller download, it is another machine.
static func suggest(reading: Dictionary) -> Dictionary:
	var tier: StringName = StringName(reading.get("tier", TIER_UNKNOWN))
	var fits: Array[Dictionary] = []
	var refused: Array[Dictionary] = []
	for model: Dictionary in MODELS:
		var why: String = skip_reason(model, reading)
		if why.is_empty():
			fits.append({
				"model": model,
				"label": _label(model),
				"ram_needed_bytes": ram_needed_bytes(model),
				"download_bytes": download_bytes(model),
				"runs_from_what_is_free_now": _fits_what_is_free_now(model, reading),
			})
		else:
			refused.append({"model": model, "label": _label(model), "reason": why})
	fits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["ram_needed_bytes"]) > int(b["ram_needed_bytes"]))

	if tier == TIER_UNKNOWN:
		return {
			"ok": false,
			"tier": tier,
			"route": ROUTE_UNMEASURED,
			"headline": "This machine did not say how much memory it has, so no model can be offered for it.",
			"reason": "The reading this page takes came back empty, which is a refusal rather than a small machine.",
			"steps": [] as Array[String],
			"fits": fits,
			"refused": refused,
			"small_experiment": {} as Dictionary,
			"needs_network": false,
		}

	var tag: String = _best_ollama_tag()
	if tier == TIER_TIGHT:
		var experiment: Dictionary = {} as Dictionary
		if not fits.is_empty():
			experiment = fits[0].duplicate()
			experiment["warning"] = (
				"%s is small enough for this machine on paper, but only %s of memory is free at the "
				% [_label(fits[0]["model"]), bytes_words(int(reading.get("free_bytes", UNKNOWN)))]
				+ "moment, so it may be stopped while it runs."
			)
		# Nothing is left in `fits`: on a machine this tight, what fits on paper is offered as an
		# experiment and never as something to run here, so that a page cannot present it as either.
		fits.clear()
		return {
			"ok": true,
			"tier": tier,
			"route": ROUTE_WIFI_COMPUTER,
			"headline": (
				"This machine is too small to carry a vision model, so the photograph is best read by a "
				+ "computer on the same Wi-Fi."
			),
			"reason": (
				"%s of memory is not enough to hold a model that can name a plant and this program at "
				% bytes_words(int(reading.get("physical_bytes", UNKNOWN)))
				+ "the same time - about %s of memory can be spared here."
				% bytes_words(memory_for_a_model(reading))
			),
			"steps": _wifi_steps(tag),
			"fits": fits,
			"refused": refused,
			"small_experiment": experiment,
			"needs_network": true,
		}

	if fits.is_empty():
		return {
			"ok": true,
			"tier": tier,
			"route": ROUTE_WIFI_COMPUTER,
			"headline": (
				"No model this program can vouch for fits this machine, so a computer on the same Wi-Fi "
				+ "is the way to read a photograph."
			),
			"reason": "Every model in this program's own table is too large for %s of memory." % bytes_words(
				int(reading.get("physical_bytes", UNKNOWN))
			),
			"steps": _wifi_steps(tag),
			"fits": fits,
			"refused": refused,
			"small_experiment": {} as Dictionary,
			"needs_network": true,
		}

	var best: Dictionary = fits[0]
	var free_now_note: String = ""
	if not bool(best["runs_from_what_is_free_now"]):
		free_now_note = (
			" Only %s of memory is free at the moment, so start nothing else first."
			% bytes_words(int(reading.get("free_bytes", UNKNOWN)))
		)
	return {
		"ok": true,
		"tier": tier,
		"route": ROUTE_THIS_DEVICE,
		"headline": "%s can run here: %s to download and about %s in memory.%s" % [
			_label(best["model"]),
			bytes_words(int(best["download_bytes"])),
			bytes_words(int(best["ram_needed_bytes"])),
			free_now_note,
		],
		"reason": String(best["model"].get("why", "")),
		"steps": _this_device_steps(best["model"]),
		"fits": fits,
		"refused": refused,
		"small_experiment": {} as Dictionary,
		"needs_network": false,
	}


## The machine in the words a person would use, so that a reading can be checked against the machine in
## front of them rather than read as four numbers.
static func summary(reading: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append(_platform_words(reading))
	var cores: int = int(reading.get("cores", UNKNOWN))
	parts.append(
		"%d processors" % cores if cores != UNKNOWN else "the number of processors was not readable"
	)
	var physical: int = int(reading.get("physical_bytes", UNKNOWN))
	var free_now: int = int(reading.get("free_bytes", UNKNOWN))
	if physical == UNKNOWN:
		parts.append("how much memory it has was not readable")
	elif free_now == UNKNOWN:
		parts.append("%s of memory, and how much is free was not readable" % bytes_words(physical))
	else:
		parts.append("%s of memory, %s of it free" % [bytes_words(physical), bytes_words(free_now)])
	var disk: int = int(reading.get("disk_free_bytes", UNKNOWN))
	parts.append(
		"%s of disk free" % bytes_words(disk) if disk != UNKNOWN else "how much disk is free was not readable"
	)
	var gpu: String = String(reading.get("gpu_name", ""))
	parts.append(
		"graphics %s" % gpu if not gpu.is_empty()
		else "the graphics card was not readable, which is what a program with no screen reports"
	)
	return "%s." % ", ".join(parts)


## A byte count in the words a person would say it in: "3.2 GB", "479 MB", "180 bytes".
##
## `UNKNOWN` gets a sentence rather than a number, which is the whole reason this is not arithmetic in
## the page: a page that printed "0.0 GB" over a reading it never took is showing a small machine where
## there was no answer, and that is the fault this project spends the most effort avoiding.
static func bytes_words(bytes: int) -> String:
	if bytes == UNKNOWN or bytes < 0:
		return "an amount this machine did not say"
	if bytes < 1000:
		return "%d bytes" % bytes
	var units: PackedStringArray = ["kB", "MB", "GB", "TB"]
	var size: float = float(bytes)
	var unit: int = -1
	while size >= 1000.0 and unit < units.size() - 1:
		size /= 1000.0
		unit += 1
	return "%.1f %s" % [size, units[unit]]


## Whether a model's name says it can look at a picture. The fallback for a server that lists no
## capabilities of its own - see `VISION_MARKERS` for why it is narrow on purpose.
static func is_vision_model_id(model_id: String) -> bool:
	var lowered: String = model_id.strip_edges().to_lower()
	if lowered.is_empty():
		return false
	for marker: String in VISION_MARKERS:
		if lowered.contains(marker):
			return true
	return false


## A model's own name for itself, falling back to its id so that a record never says "".
static func _label(model: Dictionary) -> String:
	var label: String = String(model.get("label", "")).strip_edges()
	if not label.is_empty():
		return label
	return String(model.get("id", "a model this program knows nothing about"))


## The biggest model this program can vouch for that a server could be asked for, as the tag a runner
## would be told to fetch.
static func _best_ollama_tag() -> String:
	var best: String = ""
	var biggest: int = 0
	for model: Dictionary in MODELS:
		var files: int = download_bytes(model)
		if files == UNKNOWN:
			continue
		var tag: String = String(model.get("ollama_tag", "")).strip_edges()
		if tag.is_empty():
			continue
		if files > biggest:
			biggest = files
			best = tag
	return best


## Whether what is free *right now* would hold this model, as opposed to what the box has in total. Both
## matter and they disagree often: the phone this was measured on has 3.37 GB of memory and 0.75 GB free.
static func _fits_what_is_free_now(model: Dictionary, reading: Dictionary) -> bool:
	var free_now: int = int(reading.get("free_bytes", UNKNOWN))
	if free_now == UNKNOWN or free_now <= 0:
		return false
	return ram_needed_bytes(model) <= free_now


## How a person gets a model running somewhere else on the Wi-Fi, in the order the steps have to be
## taken: install a runner, fetch the model, let the phone reach it, then type its address here.
static func _wifi_steps(tag: String) -> Array[String]:
	var steps: Array[String] = []
	steps.append("Install Ollama on a computer connected to the same Wi-Fi.")
	steps.append(
		"On that computer, fetch the model: %s" % ("ollama pull %s" % tag if not tag.is_empty() else "ollama pull a vision model")
	)
	steps.append(
		"Start that computer's Ollama so another machine may reach it: the setting is OLLAMA_HOST, and "
		+ "it is the difference between a model only that computer can ask and one the whole house can."
	)
	steps.append(
		"Then put that computer's address in this page, such as http://192.168.1.20:11434, and this "
		+ "phone will send the photograph there to be read."
	)
	return steps


## How a person gets the model onto the machine they are holding, which differs by the runner that can
## carry it: a machine with Ollama is told to pull, and one without is told where the runner comes from.
static func _this_device_steps(model: Dictionary) -> Array[String]:
	var steps: Array[String] = []
	var tag: String = String(model.get("ollama_tag", "")).strip_edges()
	if not tag.is_empty():
		steps.append("Install Ollama if it is not already installed, then fetch the model: ollama pull %s" % tag)
		steps.append("Point the reading at it: http://127.0.0.1:11434 with the model %s." % tag)
		return steps
	var repo: String = String(model.get("gguf_repo", "")).strip_edges()
	if not repo.is_empty():
		steps.append("Get the model's files from %s." % repo)
		steps.append(
			"Give the runner **both** files - the weights and the vision projector - or it will answer "
			+ "every photograph with a refusal about images."
		)
	return steps


## Whether this is a machine whose floor is a phone's. The platform answers it rather than the tier,
## because the tier is not known when the memory was not read.
static func _is_a_phone(reading: Dictionary) -> bool:
	var platform: String = String(reading.get("platform", ""))
	return platform.begins_with("Android") or platform.begins_with("iOS")


## A reading as a number, with zero or less turned into `UNKNOWN`: nothing that could not be read is
## ever allowed through as a value.
static func _said_number(number: int) -> int:
	return number if number > 0 else UNKNOWN


## What sort of machine this is, so that a person reading the summary recognises the machine in front of
## them rather than a list of fields.
static func _platform_words(reading: Dictionary) -> String:
	var platform: String = String(reading.get("platform", "")).strip_edges()
	var model: String = String(reading.get("model_name", "")).strip_edges()
	if platform.is_empty():
		return "a device this program could not identify"
	if model.is_empty():
		return "a %s machine" % platform
	return "a %s machine called %s" % [platform, model]