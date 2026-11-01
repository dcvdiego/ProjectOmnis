class_name Player
extends CharacterBody3D
## First-person player.
##
## Authority split (see docs/architecture.md):
## - Movement and aim are owned by the controlling peer (`PlayerMotor`) and
##   replicated through the `net_*` properties. That trusts the client;
##   server-side movement validation / rollback is on the roadmap.
## - Everything that decides outcomes (ammo, fire rate, hit detection, damage,
##   health, respawn) runs only on the server (peer 1).
##
## Smoothness: physics runs at a fixed tick with physics interpolation on. The
## camera is top-level and placed every rendered frame from the interpolated
## body position plus the latest mouse look, so aiming never waits for a
## physics tick. Remote players are drawn ~100 ms in the past, interpolating
## between received snapshots.

const MAX_HEALTH := 100
const RESPAWN_DELAY := 2.0
const KILL_PLANE_Y := -30.0
## How far (m) a shot's claimed origin may be from the server's view of the
## player's eyes before the shot is rejected (plus a speed-based allowance).
const MAX_ORIGIN_ERROR := 1.5
const HIT_MASK := 0b111  # world | players | targets
## Radians per pixel of mouse motion at sensitivity 1.0.
const BASE_SENSITIVITY := 0.0022
## Radians per second at full stick deflection, at sensitivity 1.0.
const PAD_LOOK_SPEED := 3.2
## How far behind real time remote players are drawn (seconds).
const INTERP_DELAY := 0.1

@export var weapons: Array[WeaponData] = []
@export var movement: MovementSettings

var health := MAX_HEALTH
var weapon_index := 0
var ammo := 0
var is_reloading := false
var motor: PlayerMotor
var yaw := 0.0
var pitch := 0.0

# Replicated by the Synchronizer: written by the owner, read everywhere else.
var net_position := Vector3.ZERO
var net_yaw := 0.0
var net_pitch := 0.0
var net_velocity := Vector3.ZERO
var net_state := 0
var net_height := 1.8

# Server-only state.
var _server_ammo: Array[int] = []
var _next_fire_time := 0.0
var _reload_done_time := 0.0

# Owner-only state.
var _local_next_fire_time := 0.0
var _eye_height_smooth := 1.64
var _land_dip := 0.0
var _land_dip_velocity := 0.0
var _recoil := 0.0
var _tilt := 0.0
var _fov_boost := 0.0

# Remote-client state: [time, position, yaw, pitch] snapshots.
var _snapshots: Array[Array] = []

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Camera3D
@onready var view_model: ViewModel = $Camera3D/ViewModel
@onready var character: CharacterModel = $Character
@onready var hud: Hud = $HUD
@onready var synchronizer: MultiplayerSynchronizer = $Synchronizer


func _enter_tree() -> void:
	# Players are named after their peer id by the spawner.
	set_multiplayer_authority(peer_id())


func _ready() -> void:
	for weapon in weapons:
		_server_ammo.append(weapon.magazine_size)
	ammo = _server_ammo[weapon_index] if not _server_ammo.is_empty() else 0
	motor = PlayerMotor.new(self, collision_shape, movement)
	motor.landed.connect(_on_landed)

	var is_local := is_multiplayer_authority()
	camera.current = is_local
	camera.top_level = true
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	hud.visible = is_local
	view_model.visible = is_local
	character.setup(weapons)
	character.first_person = is_local  # own body only casts a shadow
	synchronizer.synchronized.connect(_on_synchronized)
	if is_local:
		view_model.setup(weapons)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var world := _world()
		if world:
			global_position = world.get_spawn_position(peer_id())
			yaw = world.get_spawn_yaw(peer_id())
		rotation.y = yaw
		_write_net_state()
		reset_physics_interpolation()
		print("Local player %d spawned" % peer_id())
	_update_weapon_visuals()
	_update_hud()


func peer_id() -> int:
	return name.to_int()


func current_weapon() -> WeaponData:
	return weapons[weapon_index]


func is_alive() -> bool:
	return health > 0


## Where shots come from: the server's view of this player's eyes.
func eye_position() -> Vector3:
	var h := motor.eye_height() if is_multiplayer_authority() else net_height - movement.eye_offset
	return global_position + Vector3.UP * h


# --- Input (owner only) ---------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var motion := (event as InputEventMouseMotion).screen_relative
		var sens := BASE_SENSITIVITY * Settings.mouse_sensitivity
		_add_look(Vector2(-motion.x, -motion.y * (-1.0 if Settings.invert_y else 1.0)) * sens)
		view_model.add_sway(motion)
	elif event.is_action_pressed("weapon_1"):
		_request_switch_weapon.rpc_id(1, 0)
	elif event.is_action_pressed("weapon_2"):
		_request_switch_weapon.rpc_id(1, 1)
	elif event.is_action_pressed("weapon_next"):
		_request_switch_weapon.rpc_id(1, (weapon_index + 1) % weapons.size())
	elif event.is_action_pressed("reload"):
		_request_reload.rpc_id(1)


func _add_look(delta: Vector2) -> void:
	yaw = wrapf(yaw + delta.x, -PI, PI)
	pitch = clampf(pitch + delta.y, deg_to_rad(-89.0), deg_to_rad(89.0))


func _read_input(delta: float) -> PlayerMotor.MoveInput:
	var input := PlayerMotor.MoveInput.new()
	if is_alive() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input.wish = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		input.jump_pressed = Input.is_action_just_pressed("jump")
		input.crouch = Input.is_action_pressed("crouch")
		input.sprint = Input.is_action_pressed("sprint") or Settings.auto_sprint
		var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if stick != Vector2.ZERO:
			var speed := PAD_LOOK_SPEED * Settings.stick_sensitivity * delta
			_add_look(Vector2(-stick.x, -stick.y * (-1.0 if Settings.invert_y else 1.0)) * speed * stick.length())
		if Input.is_action_pressed("fire"):
			_try_fire()
	input.yaw = yaw
	return input


# --- Simulation -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if multiplayer.is_server() and is_alive() and global_position.y < KILL_PLANE_Y:
		take_damage(health, 0)

	if is_multiplayer_authority():
		var input := _read_input(delta)
		rotation.y = yaw
		if is_alive():
			motor.step(input, delta)
		_write_net_state()
	else:
		_follow_network(delta)
	head.position.y = net_height - movement.eye_offset
	head.rotation.x = net_pitch


func _write_net_state() -> void:
	net_position = global_position
	net_yaw = yaw
	net_pitch = pitch
	net_velocity = velocity
	net_state = motor.state
	net_height = motor.height


func _follow_network(_delta: float) -> void:
	if multiplayer.is_server():
		# The server uses the newest data for hit detection.
		global_position = net_position
		rotation.y = net_yaw
	elif not _snapshots.is_empty():
		var sample := _sample_snapshots(_now() - INTERP_DELAY)
		global_position = sample[0]
		rotation.y = sample[1]
	_set_capsule_height(net_height)


func _on_synchronized() -> void:
	if is_multiplayer_authority() or multiplayer.is_server():
		return
	var now := _now()
	if not _snapshots.is_empty() and (_snapshots[-1][1] as Vector3).distance_to(net_position) > 6.0:
		_snapshots.clear()  # teleport (respawn): don't interpolate across it
		global_position = net_position
		reset_physics_interpolation()
	_snapshots.append([now, net_position, net_yaw, net_pitch])
	while _snapshots.size() > 2 and (_snapshots[1][0] as float) < now - 1.0:
		_snapshots.pop_front()


## Returns [position, yaw] at `time`, interpolating between snapshots and
## extrapolating briefly past the newest one.
func _sample_snapshots(time: float) -> Array:
	var first: Array = _snapshots[0]
	if time <= first[0]:
		return [first[1], first[2]]
	for i in range(_snapshots.size() - 1):
		var a: Array = _snapshots[i]
		var b: Array = _snapshots[i + 1]
		if time >= a[0] and time <= b[0]:
			var t := inverse_lerp(a[0], b[0], time) if b[0] > a[0] else 1.0
			return [(a[1] as Vector3).lerp(b[1], t), lerp_angle(a[2], b[2], t)]
	var last: Array = _snapshots[-1]
	var ahead := minf(time - (last[0] as float), 0.15)
	return [(last[1] as Vector3) + net_velocity * ahead, last[2]]


func _set_capsule_height(h: float) -> void:
	var capsule := collision_shape.shape as CapsuleShape3D
	if not is_equal_approx(capsule.height, h):
		capsule.height = h
		collision_shape.position.y = h * 0.5


# --- Camera and feel (owner, every rendered frame) ----------------------------------

func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	var speed := motor.horizontal_speed()
	var state := motor.state

	# Eye height eases between standing and crouching; landing adds a dip.
	_eye_height_smooth = lerpf(_eye_height_smooth, motor.eye_height(), 1.0 - exp(-14.0 * delta))
	_land_dip_velocity += (-_land_dip * 120.0 - _land_dip_velocity * 16.0) * delta
	_land_dip += _land_dip_velocity * delta
	_recoil = lerpf(_recoil, 0.0, 1.0 - exp(-10.0 * delta))

	var target_tilt := 0.0
	if state == PlayerMotor.State.WALLRUN:
		target_tilt = deg_to_rad(10.0) * motor.wall_side()
	elif state == PlayerMotor.State.SLIDE:
		target_tilt = deg_to_rad(-3.0)
	_tilt = lerpf(_tilt, target_tilt, 1.0 - exp(-8.0 * delta))

	var fast := clampf((speed - movement.sprint_speed) / 6.0, 0.0, 1.0)
	var target_fov := Settings.fov_boost * (0.6 if state == PlayerMotor.State.SLIDE else 0.0)
	target_fov += Settings.fov_boost * fast
	if Input.is_action_pressed("sprint") and speed > movement.walk_speed:
		target_fov += Settings.fov_boost * 0.3
	_fov_boost = lerpf(_fov_boost, target_fov, 1.0 - exp(-6.0 * delta))
	camera.fov = Settings.fov + _fov_boost

	var origin := get_global_transform_interpolated().origin
	origin.y += _eye_height_smooth + _land_dip
	var look := Basis.from_euler(Vector3(pitch + deg_to_rad(_recoil), yaw, _tilt))
	camera.global_transform = Transform3D(look, origin)

	view_model.update_pose(delta, {
		"speed": speed,
		"grounded": state == PlayerMotor.State.GROUND,
		"sprinting": state == PlayerMotor.State.GROUND and speed > movement.walk_speed + 0.5,
		"sliding": state == PlayerMotor.State.SLIDE,
		"wall_side": motor.wall_side(),
		"vertical_speed": velocity.y,
	})
	hud.set_speed(speed)


func _on_landed(impact_speed: float) -> void:
	if impact_speed > 3.0:
		_land_dip_velocity -= clampf(impact_speed * 0.12, 0.0, 1.6)
		view_model.land(impact_speed)


# --- Shooting ------------------------------------------------------------------------

func _try_fire() -> void:
	var now := _now()
	if now < _local_next_fire_time or is_reloading:
		return
	if ammo <= 0:
		_request_reload.rpc_id(1)
		_local_next_fire_time = now + 0.25
		return
	# Client-side throttle only saves bandwidth; the server enforces the real limit.
	var weapon := current_weapon()
	_local_next_fire_time = now + weapon.seconds_between_shots()
	var origin := eye_position()
	var direction := -camera.global_basis.z
	_request_fire.rpc_id(1, origin, direction)

	# Immediate cosmetic feedback; the server decides what actually got hit.
	_recoil += weapon.recoil_kick
	var muzzle := view_model.fire()
	var end := origin + direction * weapon.max_range
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(origin, end, HIT_MASK, [get_rid()]))
	if not hit.is_empty():
		end = hit.position
		Fx.impact(get_parent(), hit.position, hit.normal, hit.collider.has_method("take_damage"))
	Fx.tracer(get_parent(), muzzle, end)


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
	# Claimed origin must match where we think the player's eyes are. Fast
	# movement gets a little slack for network jitter.
	var allowed := MAX_ORIGIN_ERROR + net_velocity.length() * 0.1
	if origin.distance_to(eye_position()) > allowed:
		return

	var weapon := current_weapon()
	_server_ammo[weapon_index] -= 1
	_next_fire_time = now + weapon.seconds_between_shots()

	var end := origin + direction.normalized() * weapon.max_range
	var query := PhysicsRayQueryParameters3D.create(origin, end, HIT_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var normal := Vector3.ZERO
	var hit_player := false
	if not hit.is_empty():
		end = hit.position
		normal = hit.normal
		hit_player = hit.collider.has_method("take_damage")
		if hit.collider.has_method("take_damage"):
			hit.collider.take_damage(weapon.damage, peer_id())
			_confirm_hit.rpc_id(peer_id())
	_shot_fx.rpc(end, normal, hit_player)
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
		_sync_weapon_state.rpc(weapon_index, _server_ammo[weapon_index], reloading)


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
	var spawn := randi()
	_respawn_at.rpc_id(peer_id(), _world().get_spawn_position(spawn), _world().get_spawn_yaw(spawn))
	_server_sync_weapon_state()


# --- Server -> client updates ----------------------------------------------------
# These accept calls from the server (peer 1) only.

@rpc("any_peer", "call_local", "reliable")
func _set_health(value: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	var was_alive := is_alive()
	health = value
	collision_shape.disabled = not is_alive()
	character.set_dead(not is_alive())
	if is_multiplayer_authority():
		view_model.visible = is_alive()
		if was_alive and not is_alive():
			hud.flash_damage(1.0)
		elif value < MAX_HEALTH:
			hud.flash_damage(0.5)
	_update_hud()


@rpc("any_peer", "call_local", "reliable")
func _respawn_at(spawn_position: Vector3, spawn_yaw: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	global_position = spawn_position
	yaw = spawn_yaw
	pitch = 0.0
	rotation.y = yaw
	motor.reset()
	_write_net_state()
	reset_physics_interpolation()


@rpc("any_peer", "call_local", "reliable")
func _sync_weapon_state(index: int, rounds: int, reloading: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	var started_reload := reloading and not is_reloading
	weapon_index = index
	ammo = rounds
	is_reloading = reloading
	_update_weapon_visuals()  # no-op when unchanged
	if started_reload:
		if is_multiplayer_authority():
			view_model.reload(current_weapon().reload_time)
		character.play_reload()
	_update_hud()


@rpc("any_peer", "call_local", "unreliable")
func _confirm_hit() -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	hud.show_hit_marker()


## Tracer and impact for everyone except the shooter (who already drew them).
@rpc("any_peer", "call_local", "unreliable")
func _shot_fx(end: Vector3, normal: Vector3, hit_player: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1 or is_multiplayer_authority():
		return
	if DisplayServer.get_name() == "headless":
		return
	var muzzle := character.fire()
	if normal != Vector3.ZERO:
		Fx.impact(get_parent(), end, normal, hit_player)
	Fx.tracer(get_parent(), muzzle, end)


# --- Helpers ------------------------------------------------------------------------

func _update_weapon_visuals() -> void:
	if not is_node_ready() or weapons.is_empty():
		return
	character.set_weapon(weapon_index)
	if is_multiplayer_authority():
		view_model.set_weapon(weapon_index)


func _update_hud() -> void:
	if not is_node_ready() or weapons.is_empty():
		return
	hud.set_status(health, MAX_HEALTH, current_weapon().display_name, ammo,
		current_weapon().magazine_size, is_reloading)


func _world() -> World:
	return get_tree().get_first_node_in_group("world") as World


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
