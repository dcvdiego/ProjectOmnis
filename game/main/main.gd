extends Node
## Entry point: main menu plus command-line launch modes.
##
##   godot --path . -- --host
##   godot --path . -- --join=127.0.0.1 --port=24680
##   godot --headless --path . -- --server        # dedicated server

@onready var world: World = $World
@onready var menu: CanvasLayer = $Menu
@onready var menu_camera: Camera3D = $MenuCamera
@onready var address_input: LineEdit = %Address
@onready var status_label: Label = %Status


func _ready() -> void:
	Network.status_changed.connect(_set_status)
	%HostButton.pressed.connect(_on_host_pressed)
	%JoinButton.pressed.connect(_on_join_pressed)
	%QuitButton.pressed.connect(get_tree().quit)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	var launch := Network.parse_launch_args(OS.get_cmdline_user_args())
	match launch.mode:
		"server":
			_start_server(launch.port, true)
		"host":
			_start_server(launch.port, false)
		"join":
			address_input.text = launch.address
			Network.join(launch.address, launch.port)


func _on_host_pressed() -> void:
	_start_server(Network.DEFAULT_PORT, false)


func _on_join_pressed() -> void:
	var address := address_input.text.strip_edges()
	Network.join(address if not address.is_empty() else "127.0.0.1")


func _start_server(port: int, dedicated: bool) -> void:
	if Network.host(port, dedicated) != OK:
		return
	world.start_server(not dedicated)
	if not dedicated:
		menu.hide()


func _on_connected() -> void:
	menu.hide()


func _on_connection_failed() -> void:
	Network.leave()
	_set_status("Connection failed.")


func _on_server_disconnected() -> void:
	Network.leave()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


func _set_status(text: String) -> void:
	status_label.text = text
	print(text)
