class_name World
extends Node3D
## Base game mode: spawns and removes players on the server.
##
## Maps put spawn points (Marker3D) under `SpawnPoints` and leave player
## spawning to the `PlayerSpawner` (MultiplayerSpawner), which replicates new
## players to every client.

const PLAYER_SCENE := preload("res://game/player/player.tscn")

@onready var players: Node3D = $Players
@onready var spawn_points: Node3D = $SpawnPoints


func _ready() -> void:
	add_to_group("world")


## Server only. `spawn_local_player` is false for dedicated servers.
func start_server(spawn_local_player: bool) -> void:
	assert(multiplayer.is_server())
	multiplayer.peer_connected.connect(_add_player)
	multiplayer.peer_disconnected.connect(_remove_player)
	if spawn_local_player:
		_add_player(multiplayer.get_unique_id())


func _add_player(peer_id: int) -> void:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	players.add_child(player, true)
	print("Player %d joined (%d online)" % [peer_id, players.get_child_count()])


func _remove_player(peer_id: int) -> void:
	var player := players.get_node_or_null(str(peer_id))
	if player:
		player.queue_free()
	print("Player %d left" % peer_id)


## Picks a spawn point. `seed_value` keeps a player's first spawn stable.
func get_spawn_position(seed_value: int) -> Vector3:
	var points := spawn_points.get_children()
	if points.is_empty():
		return Vector3.UP
	return (points[absi(seed_value) % points.size()] as Node3D).global_position
