## The four ways a photograph can be read, and what each of them still needs before it can be used.
##
## The rules held here are the ones a mode model gets wrong: that a mode nobody has chosen sends
## nothing, that a refusal names the field to go and fix rather than the feature, that a number out of
## a file is still a number, and that the key a service is used with never reaches a record that is
## written down. No node, no scene and no file of its own but the one it makes in `user://`.
extends Node

const ChoiceScript := preload("res://scripts/plant_id_choice.gd")

const TEMP := "user://plant_id_choice_test.json"


func _forget() -> void:
	if FileAccess.file_exists(TEMP):
		DirAccess.remove_absolute(TEMP)


func _write(text: String) -> void:
	var file: FileAccess = FileAccess.open(TEMP, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## The default record, in a mode, which is what a page hands over after somebody picks one.
func _settings(mode: StringName) -> Dictionary:
	var made: Dictionary = ChoiceScript.default_settings()
	made[ChoiceScript.MODE] = String(mode)
	return made


func _reason_of(settings: Dictionary) -> String:
	return String(ChoiceScript.readiness(settings)["reason"])


func test_the_default_is_no_model_so_nothing_is_sent_until_a_person_asks() -> void:
	_forget()
	assert(
		ChoiceScript.DEFAULT == ChoiceScript.NONE,
		"a program nobody has chosen anything for is the one that sends nothing: %s"
				% String(ChoiceScript.DEFAULT)
	)
	var answer: Dictionary = ChoiceScript.readiness(ChoiceScript.default_settings())
	assert(not bool(answer["ok"]), "so there is nothing to be ready for")
	assert(
		String(answer["reason"]).contains("name is yours to type"),
		"and the refusal says what happens instead: %s" % String(answer["reason"])
	)
	assert(
		ChoiceScript.mode_of(ChoiceScript.stored(TEMP)) == ChoiceScript.NONE,
		"a file that is not there is a program nobody has chosen anything for"
	)


func test_every_mode_has_its_own_word_and_its_own_sentence() -> void:
	var words: Array[String] = []
	var sentences: Array[String] = []
	for mode: StringName in ChoiceScript.MODES:
		var said: String = ChoiceScript.word(mode)
		var meant: String = ChoiceScript.sentence(mode)
		assert(said != "", "every mode has a word: %s" % String(mode))
		assert(meant != "", "and a sentence: %s" % String(mode))
		assert(not words.has(said), "no two modes read the same: %s" % said)
		assert(not sentences.has(meant), "no two modes mean the same: %s" % meant)
		words.append(said)
		sentences.append(meant)
	# A person choosing a mixed mode is choosing for the photograph to travel, and the sentence has to
	# say so: it names the shortlist and the service the photograph then goes to.
	var hybrid: String = ChoiceScript.sentence(ChoiceScript.HYBRID)
	assert(hybrid.contains("shortlist"), "the mixed mode says it narrows first: %s" % hybrid)
	assert(hybrid.contains("online"), "and says the photograph goes on to the service: %s" % hybrid)
	assert(
		ChoiceScript.sentence(ChoiceScript.LOCAL).contains("does not leave"),
		"the local mode says the photograph stays where it is"
	)


func test_local_mode_refuses_when_the_address_or_the_model_name_is_missing() -> void:
	var ready: Dictionary = _settings(ChoiceScript.LOCAL)
	assert(bool(ChoiceScript.readiness(ready)["ok"]), "the default local settings are usable")

	var no_address: Dictionary = _settings(ChoiceScript.LOCAL)
	no_address[ChoiceScript.LOCAL_URL] = ""
	assert(not bool(ChoiceScript.readiness(no_address)["ok"]), "no address is no local model")
	assert(
		_reason_of(no_address).contains("address"),
		"and the refusal names the address: %s" % _reason_of(no_address)
	)

	var a_name_not_an_address: Dictionary = _settings(ChoiceScript.LOCAL)
	a_name_not_an_address[ChoiceScript.LOCAL_URL] = "127.0.0.1:11434"
	assert(
		not bool(ChoiceScript.readiness(a_name_not_an_address)["ok"]),
		"a bare host and port is not an address this program will send a photograph to"
	)

	var no_model: Dictionary = _settings(ChoiceScript.LOCAL)
	no_model[ChoiceScript.LOCAL_MODEL] = "   "
	assert(not bool(ChoiceScript.readiness(no_model)["ok"]), "a model with no name cannot be asked")
	assert(
		_reason_of(no_model).contains("name"),
		"and the refusal names the model: %s" % _reason_of(no_model)
	)


func test_online_mode_refuses_until_an_address_a_model_and_a_key_are_all_stated() -> void:
	var ready: Dictionary = _settings(ChoiceScript.ONLINE)
	ready[ChoiceScript.ONLINE_API_KEY] = "sk-a-key"
	assert(bool(ChoiceScript.readiness(ready)["ok"]), "an address, a model and a key are enough")

	var no_key: Dictionary = _settings(ChoiceScript.ONLINE)
	assert(not bool(ChoiceScript.readiness(no_key)["ok"]), "the default has no key, so nothing is sent")
	assert(
		_reason_of(no_key).contains("key"),
		"and the refusal names the key: %s" % _reason_of(no_key)
	)

	var no_model: Dictionary = _settings(ChoiceScript.ONLINE)
	no_model[ChoiceScript.ONLINE_API_KEY] = "sk-a-key"
	no_model[ChoiceScript.ONLINE_MODEL] = ""
	assert(not bool(ChoiceScript.readiness(no_model)["ok"]), "no model name is nothing to ask")
	assert(
		_reason_of(no_model).contains("model"),
		"and the refusal names the model: %s" % _reason_of(no_model)
	)


func test_hybrid_mode_needs_both_the_local_and_the_online_halves_ready() -> void:
	var ready: Dictionary = _settings(ChoiceScript.HYBRID)
	ready[ChoiceScript.ONLINE_API_KEY] = "sk-a-key"
	assert(bool(ChoiceScript.readiness(ready)["ok"]), "both halves ready is a usable mixed mode")

	var no_local: Dictionary = _settings(ChoiceScript.HYBRID)
	no_local[ChoiceScript.ONLINE_API_KEY] = "sk-a-key"
	no_local[ChoiceScript.LOCAL_URL] = ""
	assert(not bool(ChoiceScript.readiness(no_local)["ok"]), "the local half cannot be missing")
	assert(
		_reason_of(no_local).contains("local half"),
		"and the refusal says which half: %s" % _reason_of(no_local)
	)

	var no_online: Dictionary = _settings(ChoiceScript.HYBRID)
	assert(not bool(ChoiceScript.readiness(no_online)["ok"]), "and neither can the online half")
	assert(
		_reason_of(no_online).contains("online half"),
		"and that refusal says which half: %s" % _reason_of(no_online)
	)


func test_a_shortlist_nobody_could_read_is_refused_naming_what_it_has_to_be() -> void:
	var unreadable: Dictionary = _settings(ChoiceScript.HYBRID)
	unreadable[ChoiceScript.SHORTLIST_SIZE] = "five"
	assert(not bool(ChoiceScript.shortlist_size(unreadable)["ok"]), "a word is not a number of plants")
	assert(
		String(ChoiceScript.shortlist_size(unreadable)["reason"]).contains("whole number"),
		"and the refusal says what it has to be: %s" % String(ChoiceScript.shortlist_size(unreadable)["reason"])
	)

	for refused: Variant in [5.5, 1, 11, 0, -3]:
		var odd: Dictionary = _settings(ChoiceScript.HYBRID)
		odd[ChoiceScript.SHORTLIST_SIZE] = refused
		assert(
			not bool(ChoiceScript.shortlist_size(odd)["ok"]),
			"a shortlist of %s is not a narrowing" % str(refused)
		)

	# The one that would go unnoticed: every number out of a file arrives as a float, and a whole one
	# has to read back as a whole one or a perfectly good setting is refused for being 5.0.
	var from_a_file: Dictionary = _settings(ChoiceScript.HYBRID)
	from_a_file[ChoiceScript.SHORTLIST_SIZE] = 5.0
	var read: Dictionary = ChoiceScript.shortlist_size(from_a_file)
	assert(bool(read["ok"]), "a whole number out of a file is a whole number: %s" % String(read["reason"]))
	assert(int(read["size"]) == 5, "and it reads back as itself: %s" % str(read["size"]))


func test_the_key_is_kept_out_of_a_record_that_is_written_down_or_exported() -> void:
	_forget()
	var settings: Dictionary = _settings(ChoiceScript.ONLINE)
	settings[ChoiceScript.ONLINE_API_KEY] = "sk-never-written-down"

	var clean: Dictionary = ChoiceScript.sanitised(settings)
	assert(
		String(clean[ChoiceScript.ONLINE_API_KEY]) != "sk-never-written-down",
		"a record written down or shown does not carry the key"
	)
	assert(
		not String(clean[ChoiceScript.ONLINE_API_KEY]).is_empty(),
		"but it still says a key is set, so a page is not told a key is missing: %s"
				% String(clean[ChoiceScript.ONLINE_API_KEY])
	)
	assert(
		String(clean[ChoiceScript.ONLINE_MODEL]) == String(settings[ChoiceScript.ONLINE_MODEL]),
		"and everything that is not the key is left exactly as it was"
	)

	assert(
		not ChoiceScript.storable(settings).has(ChoiceScript.ONLINE_API_KEY),
		"and the record a file may hold does not carry the key at all"
	)
	assert(
		String(ChoiceScript.storable(settings)[ChoiceScript.ONLINE_MODEL])
				== String(settings[ChoiceScript.ONLINE_MODEL]),
		"while keeping everything that is not a secret"
	)

	# The file itself does not carry it either. `user://` is a folder somebody copies and hands on, and
	# a key that travelled with it would be spending their account on another machine.
	assert(ChoiceScript.remember(settings, TEMP), "the record is kept")
	assert(
		not FileAccess.get_file_as_string(TEMP).contains("sk-never-written-down"),
		"and the key is not in the file it was kept in"
	)
	var back: Dictionary = ChoiceScript.stored(TEMP)
	assert(
		String(back[ChoiceScript.ONLINE_API_KEY]).is_empty(),
		"so what comes back has no key in it at all, rather than a note claiming one was set: %s"
				% String(back[ChoiceScript.ONLINE_API_KEY])
	)
	assert(ChoiceScript.mode_of(back) == ChoiceScript.ONLINE, "while the choice itself survives")
	_forget()


func test_settings_survive_the_file_and_a_corrupt_file_falls_back_without_an_error() -> void:
	_forget()
	var settings: Dictionary = _settings(ChoiceScript.HYBRID)
	settings[ChoiceScript.LOCAL_MODEL] = "qwen2.5-vl:7b"
	settings[ChoiceScript.ONLINE_URL] = "https://example.test/v1/chat/completions"
	settings[ChoiceScript.ONLINE_API_KEY] = "sk-a-key"
	settings[ChoiceScript.SHORTLIST_SIZE] = 7
	assert(ChoiceScript.remember(settings, TEMP), "the record is kept")

	var back: Dictionary = ChoiceScript.stored(TEMP)
	assert(ChoiceScript.mode_of(back) == ChoiceScript.HYBRID, "the mode survives the file")
	assert(
		String(back[ChoiceScript.LOCAL_MODEL]) == "qwen2.5-vl:7b",
		"as does which local model: %s" % String(back[ChoiceScript.LOCAL_MODEL])
	)
	assert(
		String(back[ChoiceScript.ONLINE_URL]) == "https://example.test/v1/chat/completions",
		"and the service it was pointed at"
	)
	# Read through the door the arithmetic uses rather than off the record, because every number comes
	# back out of a file as a float and only one reading of it is the right one.
	assert(int(ChoiceScript.shortlist_size(back)["size"]) == 7, "and how big the shortlist was set to")

	# The key is deliberately not in the file, so a mixed mode comes back not-ready and says which half
	# it is waiting on. That is the price of not writing a key down, and it has to be the *stated* price
	# rather than a mode that looks ready and then sends a request nobody can authorise.
	assert(
		not bool(ChoiceScript.readiness(back)["ok"]),
		"a record with no key in it cannot send a photograph anywhere"
	)
	assert(
		_reason_of(back).contains("key"),
		"and it says the key is what it is waiting for: %s" % _reason_of(back)
	)
	# Everything the file *did* keep is coherent, which the local half of the same record shows: the
	# addresses, the model names and the shortlist size all came back usable.
	var local_half: Dictionary = back.duplicate()
	local_half[ChoiceScript.MODE] = String(ChoiceScript.LOCAL)
	assert(
		bool(ChoiceScript.readiness(local_half)["ok"]),
		"while everything the file did keep is usable: %s" % _reason_of(local_half)
	)

	# A parser that talked to the log would fail a whole test run over a file nobody was asked about,
	# which is why this is read with a reader rather than with `JSON.parse_string`.
	_write("this is not a record at all")
	assert(
		ChoiceScript.mode_of(ChoiceScript.stored(TEMP)) == ChoiceScript.NONE,
		"a file that is not a record leaves the program sending nothing"
	)

	_write("[1, 2, 3]")
	assert(
		ChoiceScript.mode_of(ChoiceScript.stored(TEMP)) == ChoiceScript.NONE,
		"and so does a file that holds a list rather than a record"
	)

	_write("{\"%s\": \"telepathy\"}" % ChoiceScript.MODE)
	assert(
		ChoiceScript.mode_of(ChoiceScript.stored(TEMP)) == ChoiceScript.NONE,
		"and a file naming a mode this program does not offer"
	)

	_write("{\"%s\": \"online\", \"%s\": \"https://example.test/v1/chat/completions\"}"
			% [ChoiceScript.MODE, ChoiceScript.ONLINE_URL])
	var partial: Dictionary = ChoiceScript.stored(TEMP)
	assert(ChoiceScript.mode_of(partial) == ChoiceScript.ONLINE, "a record that states a little keeps it")
	assert(
		String(partial[ChoiceScript.ONLINE_MODEL]) == ChoiceScript.DEFAULT_ONLINE_MODEL,
		"and is given the default for everything it does not state: %s"
				% String(partial[ChoiceScript.ONLINE_MODEL])
	)
	assert(
		String(partial[ChoiceScript.ONLINE_API_KEY]).is_empty(),
		"including no key, which is the one thing a default must never invent"
	)
	_forget()


func test_a_mode_asks_only_for_the_settings_it_uses() -> void:
	assert(ChoiceScript.fields_for(ChoiceScript.NONE).is_empty(), "the off mode has nothing to ask")
	assert(ChoiceScript.fields_for(ChoiceScript.LOCAL).size() == 2, "the local mode asks where and which")
	assert(ChoiceScript.fields_for(ChoiceScript.ONLINE).size() == 3, "the online mode asks for its key too")
	assert(
		ChoiceScript.fields_for(ChoiceScript.HYBRID).size() == 6,
		"and the mixed mode asks for both halves and how big the shortlist may be"
	)
	for mode: StringName in [ChoiceScript.LOCAL, ChoiceScript.ONLINE, ChoiceScript.HYBRID]:
		var keys: Array[String] = []
		for field: Dictionary in ChoiceScript.fields_for(mode):
			keys.append(String(field["key"]))
		assert(not keys.has(ChoiceScript.MODE), "no mode asks a person to type which mode they are in")
	assert(ChoiceScript.field_is_secret(ChoiceScript.ONLINE_API_KEY), "the key is a secret")
	assert(not ChoiceScript.field_is_secret(ChoiceScript.LOCAL_MODEL), "and a model's name is not")