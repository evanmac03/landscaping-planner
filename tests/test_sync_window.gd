extends Node
## The sync page: what is waiting, what wants a person, where it does not agree, and what the last run
## said - shown from `BizSync`'s own words and deciding nothing itself.
##
## The page is built by hand rather than popped up, because `popup_centered` needs a window server and a
## test process has not got one. Every test makes its own page and frees it, and the engine is
## reference-counted, so nothing is left for the runner to report.

const WindowScript := preload("res://scripts/sync_window.gd")
const SyncScript := preload("res://scripts/biz/sync.gd")
const HttpScript := preload("res://scripts/biz/http_transport.gd")


func _page(engine: SyncScript) -> WindowScript:
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(engine)
	return page


func test_the_page_has_the_controls_a_page_about_sync_has() -> void:
	var page := _page(SyncScript.new())
	assert(page.get_node_or_null(^"Scroll/Column/Summary") != null)
	assert(page.get_node_or_null(^"Scroll/Column/Queue") != null)
	assert(page.get_node_or_null(^"Scroll/Column/Conflicts") != null)
	assert(page.get_node_or_null(^"Scroll/Column/SyncButton") == null, "the buttons live in their rows")
	assert(page.get_node_or_null(^"Scroll/Column/RunRow/SyncButton") != null)
	assert(page.get_node_or_null(^"Scroll/Column/RunRow/SaveButton") != null)
	assert(page.get_node_or_null(^"Scroll/Column/RunRow/Close") != null)
	assert(page.get_node_or_null(^"Scroll/Column/Status") != null)
	page.free()


func test_a_page_with_no_engine_says_so_instead_of_failing() -> void:
	var page := _page(null)
	assert(page.summary_text().contains("no sync"), page.summary_text())
	assert(page.service_text().contains("nowhere to sync to"), page.service_text())
	assert(page.queue_rows().is_empty())
	page.free()


func test_the_queue_shows_the_engines_own_rows() -> void:
	var sync := SyncScript.new()
	sync.pending.append({"kind": "time_entry", "id": "T1", "why": "delivered at the gate"})
	sync.pending.append({"kind": "change_order", "id": "CO-2"})
	var page := _page(sync)
	assert(page.queue_rows() == sync.pending_row_texts(), str(page.queue_rows()))
	assert(page.queue_rows().size() == 2)
	page.free()


func test_the_conflicts_shown_are_the_engines_own() -> void:
	var sync := SyncScript.new()
	sync.conflicts.append({
		"kind": "time_entry", "id": "T1", "field": "rate", "class": "money",
		"ours": 100, "theirs": 200,
	})
	var page := _page(sync)
	assert(page.conflict_rows() == sync.conflict_texts(), str(page.conflict_rows()))
	assert(page.conflict_rows().size() == 1)
	page.free()


func test_nothing_given_up_on_that_is_a_clean_sentence() -> void:
	var sync := SyncScript.new()
	var page := _page(sync)
	assert(page.stranded_text().contains("nothing has been given up on"), page.stranded_text())
	# Five tries is a person's problem, so a change that has had them is named rather than hidden.
	sync.pending.append({"kind": "time_entry", "id": "T9", "tries": int(SyncScript.MAX_TRIES), "last": "503"})
	page.refresh()
	assert(page.stranded_text().contains("T9"), page.stranded_text())
	page.free()


func test_the_service_words_are_the_transports_own() -> void:
	var page := _page(SyncScript.new(null, HttpScript.new("https://office.example", "tok")))
	assert(page.service_text().contains("office.example"), page.service_text())
	# And a service with no address yet says so in the transport's own words.
	var bare := _page(SyncScript.new(null, HttpScript.new()))
	assert(bare.service_text().contains("no address yet"), bare.service_text())
	bare.free()
	page.free()


func test_the_settings_fields_are_the_transports_own_and_the_token_is_masked() -> void:
	var page := _page(SyncScript.new(null, HttpScript.new()))
	var address := page.setting_field(HttpScript.BASE_URL)
	var token := page.setting_field(HttpScript.TOKEN)
	assert(address != null and token != null, "one field per setting the transport declares")
	assert(not address.secret, "the address is not a secret")
	assert(token.secret, "the token is masked")
	page.free()


func test_saving_the_settings_reaches_the_transport() -> void:
	var http: HttpScript = HttpScript.new()
	var page := _page(SyncScript.new(null, http))
	page.setting_field(HttpScript.BASE_URL).text = "https://office.example"
	page.setting_field(HttpScript.TOKEN).text = "secret-token"
	assert(not http.is_ready(), "nowhere until the page saves it")
	var out: Dictionary = page.save_settings()
	assert(bool(out["ok"]), str(out))
	assert(http.is_ready(), "the transport is configured the way the fields say")
	page.free()


func test_syncing_with_nowhere_to_talk_says_so_rather_than_doing_nothing() -> void:
	var sync := SyncScript.new()
	var page := _page(sync)
	var announced: Array[int] = []
	page.sync_changed.connect(func() -> void: announced.append(1))
	var out: Dictionary = page.run_now()
	assert(not bool(out["ok"]))
	assert(page.status_text().contains("no sync service"), page.status_text())
	assert(announced.size() == 1, "the run is announced even when it did not go")
	page.free()


func test_settling_nothing_does_nothing() -> void:
	var sync := SyncScript.new(null, HttpScript.new("https://x", "t"))
	var page := _page(sync)
	assert(page.selected_conflict() == -1)
	assert(not page.settle(SyncScript.OUR_COPY))
	page.free()


func test_only_the_settings_fields_are_built_with_a_keyboard_of_their_own() -> void:
	var page := _page(SyncScript.new(null, HttpScript.new("https://x", "t")))
	assert(page.get_node(^"Scroll/Column/Queue").focus_mode == Control.FOCUS_NONE)
	assert(page.get_node(^"Scroll/Column/Conflicts").focus_mode == Control.FOCUS_NONE)
	for button: Node in [
		page.get_node(^"Scroll/Column/RunRow/SyncButton"),
		page.get_node(^"Scroll/Column/RunRow/SaveButton"),
		page.get_node(^"Scroll/Column/RunRow/Close"),
		page.get_node(^"Scroll/Column/SettleRow/OurCopyButton"),
		page.get_node(^"Scroll/Column/SettleRow/TheirCopyButton"),
	]:
		assert((button as Control).focus_mode == Control.FOCUS_NONE, "%s takes no keyboard" % button.name)
	# The settings fields are the one kind of control that may hold it.
	var field := page.setting_field(HttpScript.BASE_URL)
	assert(field != null and not field.secret, "the address field is a typed field")
	page.free()