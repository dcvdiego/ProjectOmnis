extends Node
## Owns the multiplayer connection (autoloaded as `Network`).
##
## The server is always peer 1. It spawns players, validates every shot and
## applies all damage. See docs/architecture.md for the full model.

signal status_changed(text: String)

const DEFAULT_PORT := 24680
const MAX_PLAYERS := 16

## True when running as a headless dedicated server (no local player).
var is_dedicated_server := false


## Starts a server. With `dedicated` false, the host also plays.
func host(port: int = DEFAULT_PORT, dedicated: bool = false) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		status_changed.emit("Could not host on port %d: %s" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	is_dedicated_server = dedicated
	status_changed.emit("%s on port %d" % ["Dedicated server running" if dedicated else "Hosting", port])
	return OK


## Connects to a server. Success is reported via `multiplayer.connected_to_server`.
func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		status_changed.emit("Could not connect to %s:%d: %s" % [address, port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	status_changed.emit("Connecting to %s:%d..." % [address, port])
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_dedicated_server = false


## Parses user command-line args (everything after `--`).
##
## Supported: `--server`, `--host`, `--join=ADDRESS`, `--port=N`.
## Returns {"mode": "server"|"host"|"join"|"", "address": String, "port": int}.
static func parse_launch_args(args: PackedStringArray) -> Dictionary:
	var result := {"mode": "", "address": "127.0.0.1", "port": DEFAULT_PORT}
	for arg in args:
		if arg == "--server":
			result.mode = "server"
		elif arg == "--host":
			result.mode = "host"
		elif arg.begins_with("--join"):
			result.mode = "join"
			var value := arg.get_slice("=", 1) if arg.contains("=") else ""
			if not value.is_empty():
				result.address = value
		elif arg.begins_with("--port="):
			var port := arg.get_slice("=", 1)
			if port.is_valid_int() and int(port) > 0 and int(port) < 65536:
				result.port = int(port)
	return result
