class_name Player
extends CharacterBody3D
## First-person player.
##
## Authority split (see docs/architecture.md):
## - Movement and aim are owned by the controlling peer and replicated by the
##   MultiplayerSynchronizer. That's simple but trusts the client; moving to
##   server-side movement validation / rollback is on the roadmap.
## - Everything that decides outcomes (ammo, fire rate, hit detection, damage,
##   health, respawn) runs only on the server (peer 1).

const WALK_SPEED := 6.0
const SPRINT_SPEED := 9.0
const JUMP_VELOCITY := 4.8
const MOUSE_SENSITIVITY := 0.0025
const MAX_HEALTH := 100
const RESPAWN_DELAY := 2.0
const KILL_PLANE_Y := -30.0
## How far (m) a shot's claimed origin may be from the server's view of the
## player's eyes before the shot is rejected.
const MAX_ORIGIN_ERROR := 1.5
const HIT_MASK := 0b111  # world | players | targets

@export var weapons: Array[WeaponData] = []

var health := MAX_HEALTH
var weapon_index := 0
var ammo := 0
var is_reloading := false

# Server-only state.
var _server_ammo: Array[int] = []
var _next_fire_time := 0.0
var _reload_done_time := 0.0

# Owner-only state.
var _local_next_fire_time := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var hud: CanvasLayer = $HUD
@onready var status_label: Label = $HUD/Status
@onready var hit_marker: Label = $HUD/HitMarker


func _enter_tree() -> void:
	# Players are named after their peer id by the spawner.
	set_multiplayer_authority(peer_id())


func _ready() -> void:
	for weapon in weapons:
		_server_ammo.append(weapon.magazine_size)
	ammo = _server_ammo[weapon_index] if not _server_ammo.is_empty() else 0

	var is_local := is_multiplayer_authority()
	camera.current = is_local
	hud.visible = is_local
	body_mesh.visible = not is_local  # don't render our own capsule over the camera
	if is_local:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		global_position = _world().get_spawn_position(peer_id())
		print("Local player %d spawned" % peer_id())
	_update_hud()


func peer_id() -> int:
	return name.to_int()


func current_weapon() -> WeaponData:
	return weapons[weapon_index]


func is_alive() -> bool:
	return health > 0


# --- Input and movement (owner only) ---------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-motion.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))
	elif event.is_action_pressed("toggle_mouse"):
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("weapon_1"):
		_request_switch_weapon.rpc_id(1, 0)
	elif event.is_action_pressed("weapon_2"):
		_request_switch_weapon.rpc_id(1, 1)
	elif event.is_action_pressed("weapon_next"):
		_request_switch_weapon.rpc_id(1, (weapon_index + 1) % weapons.size())
	elif event.is_action_pressed("reload"):
		_request_reload.rpc_id(1)


func _physics_process(delta: float) -> void:
	if multiplayer.is_server() and is_alive() and global_position.y < KILL_PLANE_Y:
		take_damage(health, 0)

	if not is_multiplayer_authority():
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	var input_dir := Vector2.ZERO
	if is_alive() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
		if Input.is_action_pressed("fire"):
			_try_fire()

	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()


func _try_fire() -> void:
	var now := _now()
	if now < _local_next_fire_time or is_reloading:
		return
	if ammo <= 0:
		_request_reload.rpc_id(1)
		_local_next_fire_time = now + 0.25
		return
	# Client-side throttle only saves bandwidth; the server enforces the real limit.
	_local_next_fire_time = now + current_weapon().seconds_between_shots()
	_request_fire.rpc_id(1, camera.global_position, -camera.global_basis.z)


# --- Server-side rules -------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func _request_fire(origin: Vector3, direction: Vector3) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id():
		return
	if not is_alive() or direction.length_squared() < 0.0001:
		return
	var now := _now()
	if now < _next_fire_time or now < _reload_done_time:
		return
	if _server_ammo[weapon_index] <= 0:
		_server_start_reload()
		return
	if origin.distance_to(camera.global_position) > MAX_ORIGIN_ERROR:
		return  # claimed muzzle position doesn't match where we think the player is

	var weapon := current_weapon()
	_server_ammo[weapon_index] -= 1
	_next_fire_time = now + weapon.seconds_between_shots()

	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction.normalized() * weapon.max_range, HIT_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider.has_method("take_damage"):
		hit.collider.take_damage(weapon.damage, peer_id())
		_confirm_hit.rpc_id(peer_id())
	_server_sync_weapon_state()


@rpc("any_peer", "call_local", "reliable")
func _request_reload() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == peer_id():
		_server_start_reload()


@rpc("any_peer", "call_local", "reliable")
func _request_switch_weapon(index: int) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id():
		return
	if index < 0 or index >= weapons.size() or index == weapon_index:
		return
	weapon_index = index
	_reload_done_time = 0.0
	_next_fire_time = _now() + 0.3  # weapon swap delay
	_server_sync_weapon_state()


func _server_start_reload() -> void:
	var weapon := current_weapon()
	if _server_ammo[weapon_index] >= weapon.magazine_size or _reload_done_time > 0.0:
		return
	_reload_done_time = _now() + weapon.reload_time
	_server_sync_weapon_state(true)
	get_tree().create_timer(weapon.reload_time).timeout.connect(
		_server_finish_reload.bind(weapon_index, _reload_done_time))


func _server_finish_reload(index: int, done_time: float) -> void:
	# A weapon switch or respawn resets _reload_done_time, cancelling this reload.
	if not is_inside_tree() or done_time != _reload_done_time:
		return
	_server_ammo[index] = weapons[index].magazine_size
	_reload_done_time = 0.0
	_server_sync_weapon_state()


func _server_sync_weapon_state(reloading: bool = false) -> void:
	if is_inside_tree():
		_sync_weapon_state.rpc_id(peer_id(), weapon_index, _server_ammo[weapon_index], reloading)


## Called by the server's hit detection. Also used for the kill plane.
func take_damage(amount: int, _attacker_id: int) -> void:
	if not multiplayer.is_server() or not is_alive():
		return
	_set_health.rpc(maxi(health - amount, 0))
	if not is_alive():
		get_tree().create_timer(RESPAWN_DELAY).timeout.connect(_server_respawn)


func _server_respawn() -> void:
	if not is_inside_tree():
		return  # player left while dead
	for i in weapons.size():
		_server_ammo[i] = weapons[i].magazine_size
	_reload_done_time = 0.0
	_set_health.rpc(MAX_HEALTH)
	_respawn_at.rpc_id(peer_id(), _world().get_spawn_position(randi()))
	_server_sync_weapon_state()


# --- Server -> client updates ------------------------------------------------
# These accept calls from the server (peer 1) only.

@rpc("any_peer", "call_local", "reliable")
func _set_health(value: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	health = value
	body_mesh.visible = is_alive() and not is_multiplayer_authority()
	$CollisionShape3D.disabled = not is_alive()
	_update_hud()


@rpc("any_peer", "call_local", "reliable")
func _respawn_at(spawn_position: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	global_position = spawn_position
	velocity = Vector3.ZERO


@rpc("any_peer", "call_local", "reliable")
func _sync_weapon_state(index: int, rounds: int, reloading: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	weapon_index = index
	ammo = rounds
	is_reloading = reloading
	_update_hud()


@rpc("any_peer", "call_local", "unreliable")
func _confirm_hit() -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	hit_marker.visible = true
	get_tree().create_timer(0.1).timeout.connect(func() -> void: hit_marker.visible = false)


# --- Helpers -----------------------------------------------------------------

func _update_hud() -> void:
	if not is_node_ready() or weapons.is_empty():
		return
	var weapon := current_weapon()
	var ammo_text := "Reloading..." if is_reloading else "%d / %d" % [ammo, weapon.magazine_size]
	var state := "HP %d" % health if is_alive() else "Respawning..."
	status_label.text = "%s   %s   %s" % [state, weapon.display_name, ammo_text]


func _world() -> World:
	return get_tree().get_first_node_in_group("world") as World


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
