class_name PresenceMember
extends Node
## One person in a shared session: what they are called, which drawing they have open, and where
## they are pointing.
##
## Presence and nothing more - no geometry, no edits. What a team asks for first is knowing who is
## where, and a shared cursor answers that without putting a merge problem on the table: the drawing
## itself is still one person's file, saved and locked, and nothing here writes to it.
##
## Each member owns itself. The authority is derived from the node's own name in `_enter_tree`, so
## every peer works it out identically and there is no networked handoff.

## The node name every peer gives one person's member, so the owner is known without being told.
const MEMBER_PREFIX := "member_"

## The three facts a session carries, in one place so the replication config and the setters cannot
## disagree about what presence is.
const REPLICATED: Array[StringName] = [&"peer_name", &"drawing", &"cursor"]

## The node name a peer's member gets.
static func node_name_for(peer_id: int) -> String:
	return "%s%d" % [MEMBER_PREFIX, peer_id]

## The peer id a member's node name stands for, or 0 when it is not one of ours.
static func peer_of(node_name: String) -> int:
	if not node_name.begins_with(MEMBER_PREFIX):
		return 0
	var digits := node_name.substr(MEMBER_PREFIX.length())
	if digits.is_empty() or not digits.is_valid_int():
		return 0
	return digits.to_int()


@export var peer_name: String = ""
@export var drawing: String = ""
@export var cursor: Vector2 = Vector2.ZERO


func _enter_tree() -> void:
	var id := peer_of(String(name))
	if id > 1:
		set_multiplayer_authority(id)


## Set the three facts. Called by the session on the *local* member only, which is the one node this
## peer has authority over; the synchronizer carries them to everyone else.
func say(who: String, where: String, pointing_at: Vector2) -> void:
	peer_name = who
	drawing = where
	cursor = pointing_at


## One line for a roster: who, and where they are.
func describe() -> String:
	var who := peer_name if peer_name != "" else "someone"
	if drawing == "":
		return who
	return "%s in %s" % [who, drawing]