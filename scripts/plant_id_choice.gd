class_name PlantIdChoice
extends RefCounted
## Which of the four ways a photograph can be read, and everything the chosen way needs told.
##
## Four answers rather than two, because the honest positions are four and not a switch. **Off** is the
## default and the program this has always been: a photograph is kept, never sent anywhere, and the name
## is the person's to type. **Local** sends it to a vision model on this machine or on the person's own
## network, so nothing leaves the building. **Online** sends it to a service the person names. **Local
## shortlist, then online** is the mixed one: the local model narrows the photograph to a few likely
## plants, and then the photograph and that shortlist go to the online service, which picks the answer.
##
## ## Why the default is Off, and why it is stated rather than absent
##
## A program that began sending photographs to a service the moment somebody picked one would have made
## a decision that is the person's to make, and a plant photograph can be of somebody's garden, their
## address and their neighbour's fence. So nothing is sent until a person chooses a mode, and the four
## modes say in their own sentences exactly what leaves the machine.
##
## ## What this class is and is not
##
## This is the **choice and its settings**: which mode, where the two models are, and what each mode
## still needs before it can be used. It holds no prompt, no HTTP and no picture - `PlantIdLlm` builds
## the request and `PlantIdentifier` runs the pipeline - and it never decides what a name means, which
## is `PlantIDResolver`'s business. `readiness` is the one place that answers "is the chosen way
## actually usable", and it answers with a sentence naming what is missing rather than with a bare no.
##
## ## The settings record is deliberately untyped
##
## `settings()` and `stored()` hand over a plain `Dictionary`, because everything in it makes a round
## trip through JSON - where every number comes back as a float and nothing comes back typed - and a
## record that cannot survive that trip is not a record this program can keep. The **vocabulary** is
## typed (`MODES`), because that is a fact about this program rather than about a file.

## Off: the photograph is kept and never sent, and the name is typed by a person.
const NONE := &"none"
## A model on this machine, or on one on the person's own network.
const LOCAL := &"local"
## A vision service the person names, reached over the internet.
const ONLINE := &"online"
## The local model narrows it, the online model picks from that shortlist.
const HYBRID := &"hybrid"

const MODES: Array[StringName] = [NONE, LOCAL, ONLINE, HYBRID]

## What a program does when nobody has chosen anything: it sends nothing, which is the state this
## program was in before any of this existed.
const DEFAULT: StringName = NONE

const FILE_PATH := "user://plant_id_choice.json"

## The keys of the settings record. Named here so that a page, a file and a test cannot come to call the
## same setting two different things.
const MODE := "mode"
const LOCAL_URL := "local_url"
const LOCAL_MODEL := "local_model"
const ONLINE_URL := "online_url"
const ONLINE_MODEL := "online_model"
const ONLINE_API_KEY := "online_api_key"
const SHORTLIST_SIZE := "shortlist_size"

## The two addresses a person is most likely to have: Ollama's OpenAI-compatible door on this machine,
## and the service most people reach for. Both are *offered* rather than assumed - nothing is sent to
## either until a mode is chosen and a key, where one is needed, is typed.
const DEFAULT_LOCAL_URL := "http://127.0.0.1:11434/v1/chat/completions"
const DEFAULT_LOCAL_MODEL := "llava:7b"
const DEFAULT_ONLINE_URL := "https://api.openai.com/v1/chat/completions"
const DEFAULT_ONLINE_MODEL := "gpt-4o-mini"

## How many plants the local half of a hybrid offers the online half. One is not a shortlist and twenty
## is not narrowing: the point of the first half is that the second has fewer things to choose between.
const DEFAULT_SHORTLIST_SIZE := 5
const SHORTLIST_LEAST := 2
const SHORTLIST_MOST := 10

## What a number that could not be read comes back as, which is not a size anybody could have meant.
const UNREADABLE := -1

## The one line a mode check gives for the off mode. `PlantIdentifier.NOTHING_INSTALLED` is the longer
## sentence a *page* shows somebody, and it stays there and keeps its own words: this is the refusal a
## mode check hands back, and it is short because it sits on a status line rather than in a paragraph.
const NOTHING_SENT := (
	"No model is in use, so nothing is sent anywhere: the name is yours to type and the list checks it."
)


## How a mode is written on a dropdown or a menu, in a person's words rather than in this file's.
static func word(mode: StringName) -> String:
	match mode_for(mode):
		LOCAL:
			return "Local model"
		ONLINE:
			return "Online model"
		HYBRID:
			return "Local shortlist, then online"
	return "Off (type the name yourself)"


## What a mode does with a photograph, in one sentence a person can weigh before choosing it.
##
## Every sentence says what leaves the machine, because that is the question somebody is really asking
## when they pick one of these - and a mixed mode says so twice, since the photograph travels in it too.
static func sentence(mode: StringName) -> String:
	match mode_for(mode):
		LOCAL:
			return (
				"The photograph goes to a vision model on this machine, or on one on your own network, "
				+ "and it does not leave it."
			)
		ONLINE:
			return "The photograph goes to the online service you name, which reads it and answers with a name."
		HYBRID:
			return (
				"A model on this machine narrows the photograph to a few likely plants, and then the "
				+ "photograph and that shortlist go to the online service, which picks the answer."
			)
	return "The photograph is kept and never sent anywhere, and you type the name."


## One of the four, from anything a file, a menu or a dropdown may hand over - and the default for
## anything else.
##
## A JSON round trip gives a value back as a `String` and never as the `StringName` a mode is written
## as, so both are taken. A number or a word nobody offers is not a fifth mode: it is a program nobody
## has chosen anything for, which is the one that sends nothing.
static func mode_for(value: Variant) -> StringName:
	var named: StringName = &""
	if value is StringName:
		named = value
	elif value is String:
		named = StringName(value)
	if MODES.has(named):
		return named
	return DEFAULT


## Which mode a settings record is in. Every question about a record goes through the mode, so this is
## the reading a caller starts with rather than one it does for itself.
static func mode_of(settings: Dictionary) -> StringName:
	return mode_for(settings.get(MODE, DEFAULT))


## A record with every key this program has, and nothing sent anywhere.
##
## Built fresh on every call rather than held in a constant: a caller that changed what it was handed
## would otherwise change the default for everybody after it.
static func default_settings() -> Dictionary:
	return {
		MODE: String(DEFAULT),
		LOCAL_URL: DEFAULT_LOCAL_URL,
		LOCAL_MODEL: DEFAULT_LOCAL_MODEL,
		ONLINE_URL: DEFAULT_ONLINE_URL,
		ONLINE_MODEL: DEFAULT_ONLINE_MODEL,
		ONLINE_API_KEY: "",
		SHORTLIST_SIZE: DEFAULT_SHORTLIST_SIZE,
	}


## The settings the chosen mode needs typed, in the order a page should ask for them: one entry per
## field as `{key, label, secret}`.
##
## A mode asks only for what it uses - somebody using a local model is never shown a field for an API
## key they have no use for - and a secret one says so here rather than in whichever page happens to
## build the field, so no page can decide on its own to show a key in the clear.
static func fields_for(mode: StringName) -> Array[Dictionary]:
	var fields: Array[Dictionary] = []
	match mode_for(mode):
		LOCAL:
			fields = [
				{"key": LOCAL_URL, "label": "where the local model is", "secret": false},
				{"key": LOCAL_MODEL, "label": "which local model to ask", "secret": false},
			]
		ONLINE:
			fields = _online_fields()
		HYBRID:
			fields = [
				{"key": LOCAL_URL, "label": "where the local model is", "secret": false},
				{"key": LOCAL_MODEL, "label": "which local model to ask", "secret": false},
			]
			fields.append_array(_online_fields())
			fields.append({
				"key": SHORTLIST_SIZE,
				"label": "how many plants the local model may offer",
				"secret": false,
			})
	return fields


static func _online_fields() -> Array[Dictionary]:
	return [
		{"key": ONLINE_URL, "label": "where the online service is", "secret": false},
		{"key": ONLINE_MODEL, "label": "which online model to ask", "secret": false},
		{"key": ONLINE_API_KEY, "label": "the key this service is used with", "secret": true},
	]


## Whether a key belongs to a field a page must mask. Asked of the mode's own field list rather than
## answered again, so the des this program writes down and the field a page builds agree.
static func field_is_secret(key: String) -> bool:
	for mode: StringName in MODES:
		for field: Dictionary in fields_for(mode):
			if String(field["key"]) == key:
				return bool(field["secret"])
	return false


## Whether the chosen way can actually be used, and if not, what it is still missing - as
## `{ok, reason}`.
##
## The refusal names the field rather than the feature: "the local model needs an address" is something
## a person can go and fix, and "identification is not configured" is not. The off mode is answered as
## a refusal too, because there genuinely is nothing to send; the caller shows the mode's own sentence
## rather than treating it as a fault.
static func readiness(settings: Dictionary) -> Dictionary:
	match mode_of(settings):
		LOCAL:
			return _half_ready(LOCAL, settings)
		ONLINE:
			return _half_ready(ONLINE, settings)
		HYBRID:
			var local: Dictionary = _half_ready(LOCAL, settings)
			if not bool(local["ok"]):
				return _refuse("the local half of a shortlist-then-online is not ready: %s"
						% String(local["reason"]))
			var online: Dictionary = _half_ready(ONLINE, settings)
			if not bool(online["ok"]):
				return _refuse("the online half of a shortlist-then-online is not ready: %s"
						% String(online["reason"]))
			var size: Dictionary = shortlist_size(settings)
			if not bool(size["ok"]):
				return size
			return _ready()
	return _refuse(NOTHING_SENT)


## How many plants the local half may offer the online half, and whether that number could be read -
## as `{ok, reason, size}`.
##
## A record from a file holds every number as a float, so a whole one is read back as a whole one here
## rather than anywhere the arithmetic happens. A number that is not whole, is not a number, or is
## outside the range is refused by name: a shortlist of one is not a shortlist and a shortlist of a
## hundred is not a narrowing, and quietly answering five would be this class inventing a setting.
static func shortlist_size(settings: Dictionary) -> Dictionary:
	var size: int = _whole(settings.get(SHORTLIST_SIZE, DEFAULT_SHORTLIST_SIZE))
	if size == UNREADABLE:
		return _refuse(
			"how many plants the local model may offer has to be a whole number of plants, between %d and %d"
					% [SHORTLIST_LEAST, SHORTLIST_MOST]
		)
	if size < SHORTLIST_LEAST or size > SHORTLIST_MOST:
		return _refuse(
			"a shortlist of %d plants is not a narrowing: it has to be between %d and %d"
			% [size, SHORTLIST_LEAST, SHORTLIST_MOST]
		)
	return {"ok": true, "reason": "", "size": size}


## What one half of a mode needs, whether it is the local model or the online service.
static func _half_ready(half: StringName, settings: Dictionary) -> Dictionary:
	if half == LOCAL:
		var address: String = String(settings.get(LOCAL_URL, "")).strip_edges()
		if not _is_address(address):
			return _refuse(
				"the local model needs an address beginning http:// or https://, such as %s"
						% DEFAULT_LOCAL_URL
			)
		if String(settings.get(LOCAL_MODEL, "")).strip_edges().is_empty():
			return _refuse(
				"the local model needs a name to ask for - the one it is served under, such as %s"
						% DEFAULT_LOCAL_MODEL
			)
		return _ready()
	var online_address: String = String(settings.get(ONLINE_URL, "")).strip_edges()
	if not _is_address(online_address):
		return _refuse(
			"the online service needs an address beginning http:// or https://, such as %s"
					% DEFAULT_ONLINE_URL
		)
	if String(settings.get(ONLINE_MODEL, "")).strip_edges().is_empty():
		return _refuse("the online service needs the name of the model to ask, such as %s" % DEFAULT_ONLINE_MODEL)
	if String(settings.get(ONLINE_API_KEY, "")).strip_edges().is_empty():
		return _refuse("the online service needs the key it is used with before a photograph can be sent to it")
	return _ready()


## Whether a string is an address this program will send a photograph to. The same rule every other
## service in this program is held to: a name is not an address, and a bare hostname could be anything.
static func _is_address(raw: String) -> bool:
	return raw.begins_with("http://") or raw.begins_with("https://")


## A whole number, or `UNREADABLE` when what was handed over is not one.
static func _whole(raw: Variant) -> int:
	if raw is int:
		return raw
	if raw is float:
		var number: float = raw
		if is_equal_approx(number, roundf(number)):
			return int(roundf(number))
	return UNREADABLE


static func _ready() -> Dictionary:
	return {"ok": true, "reason": "", "size": DEFAULT_SHORTLIST_SIZE}


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "size": 0}


## The record without anything secret in it, for a log, an export or a test to read.
##
## The key a service is used with is replaced rather than dropped, so a reader can see that a key is
## set without seeing the key - a page that says "this service needs a key" is then telling the truth
## about a record that has one.
static func sanitised(settings: Dictionary) -> Dictionary:
	var clean: Dictionary = {}
	for key: Variant in settings.keys():
		clean[String(key)] = settings[key]
	if not String(clean.get(ONLINE_API_KEY, "")).strip_edges().is_empty():
		clean[ONLINE_API_KEY] = "(a key is set)"
	return clean


## The record as it may be **kept**: the settings, with anything a service is used with left out
## altogether rather than written down.
##
## A key is not a setting in the way an address is. `user://` is a folder somebody copies, backs up and
## hands to another person when they ask for help, and a key that travelled with it would be spending
## their account on another machine. So a key is held for the session and typed again the next one.
##
## This is `sanitised`'s opposite number and the difference matters: `sanitised` is what a person may
## read, and it says a key is set without saying what it is; this is what a file may hold, and a file
## says nothing about a key at all. Which keys these are is asked of `field_is_secret`, so the field a
## page masks and the field a file drops cannot come apart.
static func storable(settings: Dictionary) -> Dictionary:
	var kept: Dictionary = {}
	for key: Variant in settings.keys():
		var named: String = String(key)
		if field_is_secret(named):
			continue
		kept[named] = settings[key]
	return kept


## The record as it was last kept, with the default filled in for anything it does not state.
##
## A file that cannot be read is not a failure and is not reported as one: never having chosen anything
## and having chosen the default are the same answer, and a person who has chosen nothing should not be
## told about a fault they did not cause. `FileAccess` and `JSON` are read quietly for the same reason.
static func stored(path: String = FILE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return default_settings()
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return default_settings()
	var record: Variant = json.data
	if not (record is Dictionary):
		return default_settings()
	var held: Dictionary = record
	var merged: Dictionary = default_settings()
	for key: Variant in merged.keys():
		var named: String = String(key)
		if held.has(named):
			merged[named] = held[named]
	# The mode is normalised on the way in rather than trusted: a file naming a mode this program does
	# not offer is a file nobody has chosen anything in, which is the mode that sends nothing.
	merged[MODE] = String(mode_of(merged))
	return merged


## Keep a record, through a temporary file and a rename, so a save that fails never leaves a shorter
## file where the real one was - and so a half-written file is never read back as a choice.
##
## What is kept is `storable` rather than the whole record, so a key typed for a service does not end
## up in the file - and what comes back therefore has no key in it, which is the truth about where the
## key is. A placeholder saying one was set must never be read back as a key, or the next run would
## send a sentence to a service instead of a key and call it configured.
static func remember(settings: Dictionary, path: String = FILE_PATH) -> bool:
	var temp: String = path + ".writing"
	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(storable(settings), "\t"))
	file.close()
	return DirAccess.rename_absolute(temp, path) == OK