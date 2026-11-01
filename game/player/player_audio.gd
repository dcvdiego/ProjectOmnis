class_name PlayerAudio
extends Node
## Everything a player sounds like: gunshots, reloads, footsteps (surface
## aware), jumps, jets, landings, slides and wind.
##
## It reads the replicated `net_*` state, which the owner writes every tick,
## so the same logic produces sound for the local player (non-positional) and
## for remote players (3D, positioned where they're drawn). Other players'
## footsteps matter for gameplay: you can hear someone coming.

const STRIDE_WALK := 1.15
const STRIDE_SPRINT := 1.9
## Gunshots carry: louder and further than everything else.
const SHOT_UNIT_SIZE := 14.0
const SHOT_MAX_DISTANCE := 400.0
## Beyond this, remote shots use the mid-distance recordings.
const FAR_SHOT_DISTANCE := 25.0

var _player: Player
var _local := false
var _step_distance := 0.0
var _last_state := PlayerMotor.State.GROUND
var _last_vertical := 0.0
var _wind: Node
var _slide: Node


func setup(player: Player) -> void:
	_player = player
	_local = player.is_multiplayer_authority()
	if not Sfx.enabled():
		set_process(false)
		return
	_slide = Sfx.make_loop(player, Sfx.SLIDE_LOOP, not _local)
	if _local:
		_wind = Sfx.make_loop(player, Sfx.WIND_LOOP, false)
		player.motor.jumped.connect(_on_jumped)
		player.motor.landed.connect(_on_landed)
		player.motor.mantled.connect(func() -> void: _play(Sfx.pick(Sfx.GEAR), -6.0, 3.0))


# --- Events called by the player -----------------------------------------------

func shot(weapon: WeaponData, muzzle: Vector3) -> void:
	if _local:
		Sfx.play_2d(_player, Sfx.pick(weapon.fire_sounds), -5.0, 0.03)
		return
	var listener := _listener_position()
	var far := listener.distance_to(muzzle) > FAR_SHOT_DISTANCE and not weapon.fire_sounds_far.is_empty()
	var stream := Sfx.pick(weapon.fire_sounds_far if far else weapon.fire_sounds)
	Sfx.play_3d(_world(), stream, muzzle, 0.0, SHOT_UNIT_SIZE, SHOT_MAX_DISTANCE, 0.03)


func reload(weapon: WeaponData) -> void:
	_play(weapon.reload_sound, -6.0, 3.0)


func weapon_switched() -> void:
	_play(Sfx.WEAPON_SWITCH, -8.0, 2.0)


func dry_fire() -> void:
	_play(Sfx.DRY_FIRE, -6.0, 2.0)


func hit_confirmed(killed: bool) -> void:
	Sfx.play_2d(_player, Sfx.KILL_CONFIRM if killed else Sfx.HIT_MARKER, -6.0 if killed else -9.0, 0.02, &"Master")


func hurt() -> void:
	_play(Sfx.pick(Sfx.IMPACTS[&"flesh"]), -4.0, 4.0)


func died() -> void:
	_play(Sfx.BODY_FALL, -2.0, 5.0)


# --- Continuous sounds ------------------------------------------------------------

func _process(delta: float) -> void:
	if _player == null:
		return
	var state := _player.net_state as PlayerMotor.State
	var velocity := _player.velocity if _local else _player.net_velocity
	var speed := Vector2(velocity.x, velocity.z).length()
	var alive := _player.is_alive()

	_update_footsteps(state, speed, alive, delta)
	if not _local:
		_detect_remote_events(state, velocity)
	_last_state = state
	_last_vertical = velocity.y

	# Slide scrape, louder the faster you go.
	var sliding := alive and state == PlayerMotor.State.SLIDE
	_set_loop(_slide, sliding, linear_to_db(clampf(speed / 12.0, 0.15, 1.0)) - 4.0, delta)
	if _slide is AudioStreamPlayer3D:
		(_slide as AudioStreamPlayer3D).global_position = _player.get_global_transform_interpolated().origin
	# Wind rush at speed and in the air (local only).
	if _wind:
		var rush := clampf((speed - _player.movement.sprint_speed) / 8.0, 0.0, 1.0)
		if state == PlayerMotor.State.AIR or state == PlayerMotor.State.WALLRUN:
			rush = maxf(rush, clampf((speed - 4.0) / 10.0, 0.0, 0.6))
		_set_loop(_wind, alive and rush > 0.02, linear_to_db(maxf(rush, 0.001)) - 8.0, delta)


func _update_footsteps(state: PlayerMotor.State, speed: float, alive: bool, delta: float) -> void:
	var grounded := state == PlayerMotor.State.GROUND
	var running_wall := state == PlayerMotor.State.WALLRUN
	if not alive or not (grounded or running_wall) or speed < 1.2:
		_step_distance = STRIDE_WALK * 0.7  # first step comes quickly
		return
	var crouched := _player.net_height < _player.movement.stand_height - 0.2
	var stride := lerpf(STRIDE_WALK, STRIDE_SPRINT, clampf((speed - 3.0) / 6.0, 0.0, 1.0))
	if running_wall:
		stride *= 0.8
	_step_distance += speed * delta
	if _step_distance < stride:
		return
	_step_distance = 0.0
	var volume := -9.0 if _local else -2.0
	if crouched:
		volume -= 8.0
	var surface := _surface_underfoot(running_wall)
	_play(Sfx.pick(Sfx.FOOTSTEPS.get(Sfx.SURFACE_NAMES[surface], Sfx.FOOTSTEPS[&"concrete"])), volume, 4.0)
	if speed > _player.movement.walk_speed + 1.0 and randf() < 0.35:
		_play(Sfx.pick(Sfx.GEAR), volume - 6.0, 3.0)


func _surface_underfoot(on_wall: bool) -> Sfx.Surface:
	var space := _player.get_world_3d().direct_space_state
	var origin := _player.global_position + Vector3.UP * 0.3
	var exclude: Array[RID] = [_player.get_rid()]
	var surface: Sfx.Surface
	if on_wall and _local and _player.motor.wall_normal != Vector3.ZERO:
		var mid := _player.global_position + Vector3.UP * 0.9
		surface = Sfx.surface_at(space, mid, mid - _player.motor.wall_normal * 1.0, exclude)
	elif on_wall:
		surface = Sfx.Surface.METAL  # wall-run panels are metal
	else:
		surface = Sfx.surface_at(space, origin, origin + Vector3.DOWN * 0.8, exclude)
	return surface if surface != Sfx.Surface.FLESH and surface != Sfx.Surface.NONE else Sfx.Surface.CONCRETE


## Remote players don't send jump / land events; infer them from state.
func _detect_remote_events(state: PlayerMotor.State, velocity: Vector3) -> void:
	var airborne_before := _last_state == PlayerMotor.State.AIR or _last_state == PlayerMotor.State.WALLRUN
	if velocity.y - _last_vertical > 3.5 and velocity.y > 2.0:
		_on_jumped(&"air" if airborne_before else &"ground")
	if airborne_before and (state == PlayerMotor.State.GROUND or state == PlayerMotor.State.SLIDE):
		_on_landed(maxf(-_last_vertical, 0.0))


func _on_jumped(kind: StringName) -> void:
	if kind == &"ground":
		_play(Sfx.pick(Sfx.GEAR), -6.0, 3.0)
		_play(Sfx.pick(Sfx.FOOTSTEPS[Sfx.SURFACE_NAMES[_surface_underfoot(false)]]), -8.0 if _local else -2.0, 4.0)
	else:
		_play(Sfx.JUMP_JET, -7.0 if _local else -1.0, 6.0)


func _on_landed(impact_speed: float) -> void:
	if impact_speed < 3.0:
		return
	var heavy := clampf((impact_speed - 3.0) / 10.0, 0.0, 1.0)
	_play(Sfx.pick(Sfx.FOOTSTEPS[Sfx.SURFACE_NAMES[_surface_underfoot(false)]]), lerpf(-10.0, -2.0, heavy), 4.0)
	if heavy > 0.25:
		_play(Sfx.LAND_THUMP, lerpf(-14.0, -3.0, heavy), 4.0)
	_step_distance = 0.0


# --- Helpers --------------------------------------------------------------------

func _play(stream: AudioStream, volume_db: float, unit_size: float) -> void:
	if _local:
		Sfx.play_2d(_player, stream, volume_db)
	else:
		Sfx.play_3d(_world(), stream, _player.get_global_transform_interpolated().origin + Vector3.UP * 0.2,
			volume_db, unit_size, 60.0)


func _set_loop(player: Node, on: bool, target_db: float, delta: float) -> void:
	if player == null:
		return
	var current: float = player.get("volume_db")
	var goal := target_db if on else -60.0
	player.set("volume_db", lerpf(current, goal, 1.0 - exp(-10.0 * delta)))
	var playing: bool = player.get("playing")
	if on and not playing:
		player.call("play")
	elif not on and playing and current < -55.0:
		player.call("stop")


func _world() -> Node:
	return _player.get_parent()


func _listener_position() -> Vector3:
	var camera := _player.get_viewport().get_camera_3d()
	return camera.global_position if camera else Vector3.ZERO
