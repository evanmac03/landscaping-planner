class_name Presence
extends Node
## A shared session: who else is here, and where they are.
##
## Presence and nothing more, and started on purpose: opening the planner does not open a room, so
## nothing is billed to the account until somebody shares one. The drawing stays one person's file -
## saved and locked - and what travels is the small, cheap, useful thing a team asks for first:
## who is in the session, which drawing they have open, and where they are pointing.
##
## The relay is a message switch between peers, not a server running this game. One *real* peer acts
## as the authority that owns the spawner, and it is the **lowest real peer id** - chosen identically
## by every peer from the same roster, with no election and no handoff. Peer id 1 is the relay's own
## phantom server slot and never runs anybody's `_process`.

signal changed()

const MemberScript := preload("res://scripts/presence_member.gd")

## The default room. One shared studio: a room per drawing is a finer thing than this step, and
## which drawing a person has open travels *in* the session as a field rather than as its address.
const DEFAULT_ROOM := "studio"

const MEMBERS_NODE := "Members"
const SPAWNER_NODE := "Spawner"

const USER_SETTING := "ziva/multiplayer/user_id"
const GAME_SETTING := "ziva/multiplayer/game_id"
const RELAY_SETTING := "ziva/multiplayer/relay_url"

var _members: Node = null
var _spawner: MultiplayerSpawner = null
var _host: int = 0
var _room: String = ""
var _on: bool = false
var _note: String = ""
var _me_name: String = ""
var _watching: String = ""
var _cursor: Vector2 = Vector2.ZERO


# --- the rule the whole session rests on --------------------------------------------


## A real peer is anyone the relay gave an id above 1. Id 1 is the relay's own phantom server slot,
## which never runs a game, so it is never the host and never has a member.
static func is_real_peer(id: int) -> bool:
	return id > 1


## The host, from the roster and the answer to "am I in it": the lowest real peer id. Every peer
## works this out for itself from the same list, so no message decides it.
##
## `include_self` is false during the one moment a fresh connection has not yet been told about the
## lower peers the relay is about to deliver: claiming self as host then would make this peer reject
## the real host's spawn with an authority error until it caught up.
static func host_of(real_peers: Array, me: int, include_self: bool = true) -> int:
	var candidates: Array = []
	for id in real_peers:
		if is_real_peer(int(id)):
			candidates.append(int(id))
	if include_self and is_real_peer(me):
		candidates.append(me)
	candidates.sort()
	return int(candidates[0]) if not candidates.is_empty() else 0


# --- reaching the relay --------------------------------------------------------------


## Whether this project has been set up for the relay at all. Three public settings, none of them a
## secret: they say which account and which game a connection belongs to.
static func settings_present() -> bool:
	return not String(ProjectSettings.get_setting(USER_SETTING, "")).is_empty() \
		and not String(ProjectSettings.get_setting(GAME_SETTING, "")).is_empty() \
		and not String(ProjectSettings.get_setting(RELAY_SETTING, "")).is_empty()


## The URL one room is opened on, or "" when the project has not been set up. A missing setting is
## refused rather than guessed at: a fallback would connect to the wrong relay, or to nowhere, and
## cost a debug cycle that says nothing.
static func room_url(room_id: String) -> String:
	var user_id := String(ProjectSettings.get_setting(USER_SETTING, ""))
	var game_id := String(ProjectSettings.get_setting(GAME_SETTING, ""))
	var relay := String(ProjectSettings.get_setting(RELAY_SETTING, ""))
	if user_id.is_empty() or game_id.is_empty() or relay.is_empty():
		return ""
	return "%s/r/%s?u=%s&g=%s&v=1" % [relay, room_id, user_id, game_id]


## What to call this person, from the machine they are on. A session name is a courtesy rather than
## an identity, so a machine that will not say falls back to a plain word rather than asking.
static func local_name() -> String:
	for variable in ["USERNAME", "USER", "LOGNAME"]:
		var value: String = OS.get_environment(variable).strip_edges()
		if not value.is_empty():
			return value
	return "designer"


# --- the session ---------------------------------------------------------------------


func _ready() -> void:
	_members = Node.new()
	_members.name = MEMBERS_NODE
	add_child(_members)
	_spawner = MultiplayerSpawner.new()
	_spawner.name = SPAWNER_NODE
	add_child(_spawner)
	_spawner.spawn_path = _spawner.get_path_to(_members)
	_spawner.spawn_function = Callable(self, "_make_member")
	multiplayer.peer_connected.connect(_on_peer_joined)
	multiplayer.peer_disconnected.connect(_on_peer_left)
	multiplayer.connected_to_server.connect(_on_reached_relay)
	multiplayer.connection_failed.connect(_on_relay_refused)
	multiplayer.server_disconnected.connect(_on_relay_gone)
	set_process(false)


## Open a session. Refused in words when the project is not set up or the relay cannot be reached;
## a session that silently did nothing would look exactly like a session nobody joined.
func start(room_id: String = DEFAULT_ROOM, who: String = "") -> bool:
	if _on:
		_note = "a session is already open"
		changed.emit()
		return false
	if not settings_present():
		_note = "this project is not set up for a shared session"
		changed.emit()
		return false
	var wanted := room_id.strip_edges()
	if wanted.is_empty():
		wanted = DEFAULT_ROOM
	_me_name = who if who != "" else local_name()
	_room = wanted
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_client(room_url(wanted))
	if error != OK:
		_room = ""
		_note = "the session relay could not be reached"
		changed.emit()
		return false
	multiplayer.multiplayer_peer = peer
	_on = true
	_note = "opening the session"
	set_process(true)
	changed.emit()
	return true


## Close the session and forget everyone in it.
func leave() -> void:
	if not _on:
		_note = "no session is open"
		changed.emit()
		return
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_clear_members()
	_on = false
	_host = 0
	_room = ""
	set_process(false)
	_note = "left the session"
	changed.emit()


func is_on() -> bool:
	return _on


func room() -> String:
	return _room


func note() -> String:
	return _note


## Which peer is the authority, or 0 while nobody has been decided on.
func host() -> int:
	return _host


func am_host() -> bool:
	return _host > 1 and multiplayer.get_unique_id() == _host


# --- what this person is doing -------------------------------------------------------


## Say which drawing this peer has open and where they are pointing. Pushed by whatever knows
## (the HUD), because a session that reached into the drawing to find out would be a second reader
## of something the drawing already publishes.
func watch(drawing_name: String, pointing_at: Vector2) -> void:
	_watching = drawing_name
	_cursor = pointing_at


func _process(_delta: float) -> void:
	if not _on or _members == null:
		return
	var mine := _members.get_node_or_null(MemberScript.node_name_for(multiplayer.get_unique_id()))
	if mine != null:
		(mine as MemberScript).say(_me_name, _watching, _cursor)


# --- the roster ----------------------------------------------------------------------


func members() -> Array:
	if _members == null:
		return []
	return _members.get_children()


func count() -> int:
	return members().size()


## One line per person, sorted so two peers reading the same room see the same roster.
func roster() -> Array[String]:
	var lines: Array[String] = []
	for member in members():
		lines.append((member as MemberScript).describe())
	lines.sort()
	return lines


func roster_text() -> String:
	if not _on:
		return "no session"
	var lines := roster()
	if lines.is_empty():
		return "in '%s', waiting to hear who else is here" % _room
	return "%d in '%s': %s" % [
		lines.size(), _room, ", ".join(PackedStringArray(lines)),
	]


func describe() -> String:
	if not _on:
		return "no session"
	return "%d in '%s'" % [count(), _room]


# --- the relay's callbacks -----------------------------------------------------------


func _on_reached_relay() -> void:
	var me := multiplayer.get_unique_id()
	# Id 2 is the only peer that provably has no lower peer, so it is the only one that may treat
	# itself as the host the moment it connects. Every other peer waits to be told the roster, and
	# is spawned by the host, so it must not claim the spawner in the meantime.
	_refresh_host(me == 2)
	if me == 2:
		_spawn_everyone()
	changed.emit()


func _on_peer_joined(id: int) -> void:
	if not is_real_peer(id):
		return
	_refresh_host()
	_spawn_everyone()
	changed.emit()


func _on_peer_left(id: int) -> void:
	_remove_member(id)
	# Failover is reactive: the roster is authoritative the moment a peer drops, so the host is
	# recomputed from it. If that makes this peer the lowest, it adopts the roster and re-spawns
	# everyone still present. No timer and no grace window.
	_refresh_host()
	if am_host():
		_spawn_everyone()
	changed.emit()


func _on_relay_refused() -> void:
	_note = "the session relay refused the connection"
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_clear_members()
	_on = false
	_room = ""
	set_process(false)
	changed.emit()


func _on_relay_gone() -> void:
	_note = "the session relay closed the connection"
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_clear_members()
	_on = false
	_host = 0
	_room = ""
	set_process(false)
	changed.emit()


func _refresh_host(include_self: bool = true) -> void:
	var peers: Array = []
	for id in multiplayer.get_peers():
		peers.append(int(id))
	var decided := host_of(peers, multiplayer.get_unique_id(), include_self)
	# Never drop a known host on a transient empty view: authority must not flicker off the real
	# host in the middle of a connect burst.
	if decided > 0:
		_host = decided
		if _spawner != null:
			_spawner.set_multiplayer_authority(_host)


func _spawn_everyone() -> void:
	if not am_host() or _spawner == null:
		return
	_spawn_one(multiplayer.get_unique_id())
	for id in multiplayer.get_peers():
		_spawn_one(int(id))


func _spawn_one(id: int) -> void:
	if not is_real_peer(id) or _members == null:
		return
	if _members.has_node(MemberScript.node_name_for(id)):
		return
	_spawner.spawn(id)


func _remove_member(id: int) -> void:
	if _members == null:
		return
	var node := _members.get_node_or_null(MemberScript.node_name_for(id))
	if node != null:
		node.queue_free()


## Build one member. The name carries the peer id, so the node owns itself on every peer that
## receives it without anybody being told which it is.
func _make_member(data) -> Node:
	var id := int(data)
	var member := MemberScript.new()
	member.name = MemberScript.node_name_for(id)
	member.peer_name = _me_name if id == multiplayer.get_unique_id() else ""
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	# Push every network frame: presence is a cursor and a name, and staler than a frame is staler
	# than the thing it is for.
	sync.replication_interval = 0.0
	var config := SceneReplicationConfig.new()
	for property: StringName in MemberScript.REPLICATED:
		var path := NodePath(".:%s" % String(property))
		config.add_property(path)
		config.property_set_spawn(path, true)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	sync.root_path = NodePath("..")
	member.add_child(sync)
	return member


func _clear_members() -> void:
	if _members == null:
		return
	for member in _members.get_children():
		member.queue_free()