extends Node
## Tests for the shared session: the host rule every peer works out identically, the relay address
## built from the project's own settings, and the one member's three facts.

const PresenceScript := preload("res://scripts/presence.gd")
const MemberScript := preload("res://scripts/presence_member.gd")


# --- who is in charge ----------------------------------------------------------------


func test_the_relays_own_slot_is_not_a_peer() -> void:
	assert(not PresenceScript.is_real_peer(1), "id 1 is the relay's phantom server slot")
	assert(not PresenceScript.is_real_peer(0))
	assert(PresenceScript.is_real_peer(2), "the first real peer to arrive is id 2")


func test_the_host_is_the_lowest_real_peer() -> void:
	assert(PresenceScript.host_of([5, 3, 4], 4) == 3, "the lowest id on the roster")
	assert(PresenceScript.host_of([3, 5], 2) == 2, "and I am in the roster too")


func test_a_fresh_connection_does_not_claim_the_host_from_an_empty_roster() -> void:
	# During the connect burst a peer has not yet been told about the lower peers the relay is about
	# to deliver, so it must not treat itself as the host floor.
	assert(PresenceScript.host_of([], 7, false) == 0, "no roster and no self-floor is nobody")
	assert(PresenceScript.host_of([], 7, true) == 7, "but a peer alone in a room is the host")


func test_only_the_peer_that_provably_has_nobody_below_it() -> void:
	# Id 2 is the only id that can be sure, so include_self is only ever true for it.
	assert(PresenceScript.host_of([3, 4], 2, true) == 2, "id 2 is below 3, so id 2 hosts")
	assert(PresenceScript.host_of([1], 2, false) == 0, "id 1 does not count, so there is no host yet")


# --- reaching the relay --------------------------------------------------------------


func test_the_project_knows_where_the_relay_is() -> void:
	assert(PresenceScript.settings_present(), "setup_multiplayer wrote the three settings")


func test_a_room_address_carries_the_account_the_game_and_the_room() -> void:
	var url := PresenceScript.room_url("studio")
	assert(url.begins_with("ws"), "the relay is a websocket")
	assert(url.contains("/r/studio?"), "the room is in the path")
	assert(url.contains("u="), "and the account is in the query")
	assert(url.contains("&g="), "and the game")
	assert(url.ends_with("&v=1"), "and the protocol version")


func test_a_project_without_the_settings_cannot_open_a_session() -> void:
	var presence := PresenceScript.new()
	add_child(presence)
	var saved: Variant = ProjectSettings.get_setting(PresenceScript.RELAY_SETTING, "")
	ProjectSettings.set_setting(PresenceScript.RELAY_SETTING, "")
	var refused: bool = not PresenceScript.settings_present()
	var started: bool = presence.start("studio", "tester")
	var why: String = presence.note()
	# Put the setting back before anything can fail, so one broken assertion cannot poison the rest.
	ProjectSettings.set_setting(PresenceScript.RELAY_SETTING, saved)
	assert(refused, "the settings are missing while we look")
	assert(not started, "a session is refused rather than half-opened")
	assert(why.contains("not set up"), "and the refusal says why")
	assert(PresenceScript.settings_present(), "the setting is put back for the other tests")
	remove_child(presence)
	presence.free()


func test_a_person_is_named_from_the_machine_or_with_a_plain_word() -> void:
	assert(PresenceScript.local_name() != "", "a name is always something")


# --- the session's own state ---------------------------------------------------------


func test_a_new_session_is_off_and_says_so() -> void:
	var presence := PresenceScript.new()
	add_child(presence)
	assert(not presence.is_on(), "opening the planner does not open a room")
	assert(presence.room() == "", "and there is no room")
	assert(presence.roster_text() == "no session")
	assert(presence.describe() == "no session")
	assert(presence.count() == 0, "nobody is in a session that is not open")
	assert(presence.host() == 0, "and there is no host")
	assert(not presence.am_host())
	remove_child(presence)
	presence.free()


func test_leaving_a_session_that_is_not_open_says_so() -> void:
	var presence := PresenceScript.new()
	add_child(presence)
	presence.leave()
	assert(presence.note() == "no session is open")
	assert(not presence.is_on())
	remove_child(presence)
	presence.free()


# --- one person's three facts --------------------------------------------------------


func test_a_member_is_named_for_the_peer_it_belongs_to() -> void:
	assert(MemberScript.node_name_for(7) == "member_7")
	assert(MemberScript.peer_of("member_7") == 7)
	assert(MemberScript.peer_of("member_") == 0, "no id is not an id")
	assert(MemberScript.peer_of("member_x") == 0, "nor is a word")
	assert(MemberScript.peer_of("player_3") == 0, "and a node that is not ours is not ours")


func test_a_member_owns_itself_from_its_own_name() -> void:
	var member := MemberScript.new()
	member.name = MemberScript.node_name_for(5)
	add_child(member)
	assert(member.get_multiplayer_authority() == 5, "the id in the name is the authority")
	remove_child(member)
	member.free()


func test_a_member_carries_a_name_a_drawing_and_a_cursor() -> void:
	var member := MemberScript.new()
	member.say("Bob", "Backyard Design", Vector2(3.0, 4.0))
	assert(member.peer_name == "Bob")
	assert(member.drawing == "Backyard Design")
	assert(member.cursor == Vector2(3.0, 4.0))
	assert(member.describe() == "Bob in Backyard Design", "the roster line reads the way a person says it")
	member.free()


func test_a_member_with_nothing_said_about_it_is_still_somebody() -> void:
	var member := MemberScript.new()
	assert(member.describe() == "someone", "a peer that has not spoken yet is not a blank")
	member.peer_name = "Bob"
	assert(member.describe() == "Bob", "and a name with no drawing is just the name")
	member.free()


func test_the_three_facts_are_the_ones_replicated() -> void:
	assert("|".join(PackedStringArray(MemberScript.REPLICATED)) == "peer_name|drawing|cursor",
		"the replication config and the setters agree on what presence is")