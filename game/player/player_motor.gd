class_name PlayerMotor
extends RefCounted
## Movement simulation for a CharacterBody3D: ground acceleration and friction,
## Source-style air strafing, sprint, crouch, slide (with slide-hop), double
## jump, Titanfall-style wall-running and wall-jumps, and mantling.
##
## It is driven by a `MoveInput` snapshot each physics tick, so the same code
## runs for live input, tests, and (later) server-side replay / prediction.
## Tuning lives in a `MovementSettings` resource.

signal jumped(kind: StringName)  ## &"ground", &"air", &"wall"
signal landed(impact_speed: float)
signal mantled

enum State { GROUND, AIR, SLIDE, WALLRUN, MANTLE }

const WORLD_MASK := 0b1
const WALL_MAX_NORMAL_Y := 0.35

## Snapshot of the controls for one tick.
class MoveInput:
	var wish := Vector2.ZERO  ## x = strafe (right +), y = forward (-) / back (+)
	var yaw := 0.0
	var jump_pressed := false  ## pressed this tick
	var crouch := false
	var sprint := false

var settings: MovementSettings
var state := State.AIR
var crouched := false
## Current capsule height (eases between stand and crouch height).
var height := 1.8
## Wall normal while wall-running (zero otherwise).
var wall_normal := Vector3.ZERO
var air_jumps_left := 0

var _body: CharacterBody3D
var _shape_node: CollisionShape3D
var _capsule: CapsuleShape3D
var _clock := 0.0
var _jump_buffer_left := 0.0
var _coyote_left := 0.0
var _landing_grace_left := 0.0
var _slide_boost_ready_at := 0.0
var _wallrun_time := 0.0
var _last_wall_normal := Vector3.ZERO
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _mantle_t := 0.0
var _jumped_this_airtime := false


func _init(body: CharacterBody3D, shape_node: CollisionShape3D, movement: MovementSettings) -> void:
	_body = body
	_shape_node = shape_node
	_capsule = shape_node.shape as CapsuleShape3D
	settings = movement
	height = settings.stand_height
	air_jumps_left = settings.air_jumps
	_apply_height()
	_body.floor_max_angle = deg_to_rad(50.0)
	_body.floor_snap_length = 0.4
	_body.floor_constant_speed = false


func horizontal_speed() -> float:
	return Vector2(_body.velocity.x, _body.velocity.z).length()


## Camera height above the feet.
func eye_height() -> float:
	return height - settings.eye_offset


## -1 when wall-running with the wall on the left, +1 on the right, 0 otherwise.
func wall_side() -> float:
	if state != State.WALLRUN:
		return 0.0
	var right := _body.global_basis.x
	return -signf(wall_normal.dot(right))


func step(input: MoveInput, delta: float) -> void:
	_clock += delta
	_jump_buffer_left = settings.jump_buffer if input.jump_pressed else _jump_buffer_left - delta
	_landing_grace_left -= delta

	if state == State.MANTLE:
		_step_mantle(delta)
		return

	var wish := Basis(Vector3.UP, input.yaw) * Vector3(input.wish.x, 0.0, input.wish.y)
	var wish_amount := minf(wish.length(), 1.0)
	var wish_dir := wish.normalized() if wish_amount > 0.01 else Vector3.ZERO
	var forward := Basis(Vector3.UP, input.yaw) * Vector3.FORWARD

	_update_ground_state(input, delta)
	_update_height(input.crouch, delta)

	match state:
		State.GROUND:
			_step_ground(input, wish_dir, wish_amount, delta)
		State.SLIDE:
			_step_slide(input, wish_dir, delta)
		State.WALLRUN:
			_step_wallrun(input, wish_dir, delta)
		State.AIR:
			_step_air(input, wish_dir, wish_amount, forward, delta)

	if state == State.MANTLE:
		return
	_body.velocity = _body.velocity.limit_length(settings.max_speed)
	_body.move_and_slide()


## Puts the motor back in a neutral state (e.g. after a respawn teleport).
func reset() -> void:
	_body.velocity = Vector3.ZERO
	state = State.AIR
	crouched = false
	height = settings.stand_height
	_apply_height()
	wall_normal = Vector3.ZERO
	_last_wall_normal = Vector3.ZERO
	air_jumps_left = settings.air_jumps


# --- States -------------------------------------------------------------------

func _update_ground_state(input: MoveInput, delta: float) -> void:
	if _body.is_on_floor():
		_coyote_left = settings.coyote_time
		air_jumps_left = settings.air_jumps
		_last_wall_normal = Vector3.ZERO
		_jumped_this_airtime = false
		if state == State.AIR or state == State.WALLRUN:
			landed.emit(maxf(-_body.get_real_velocity().y, 0.0))
			_landing_grace_left = settings.landing_grace
			wall_normal = Vector3.ZERO
			state = State.GROUND
			if input.crouch and horizontal_speed() >= settings.slide_min_speed:
				_start_slide()
	else:
		_coyote_left -= delta
		if state == State.GROUND or state == State.SLIDE:
			state = State.AIR


func _step_ground(input: MoveInput, wish_dir: Vector3, wish_amount: float, delta: float) -> void:
	if input.crouch and not crouched and horizontal_speed() >= settings.slide_min_speed:
		_start_slide()
		_step_slide(input, wish_dir, delta)
		return
	crouched = input.crouch or not _can_stand()
	var forward_ish := input.wish.y < -0.3
	var target := settings.walk_speed
	if crouched:
		target = settings.crouch_speed
	elif input.sprint and forward_ish:
		target = settings.sprint_speed

	if _landing_grace_left <= 0.0:
		_apply_friction(settings.ground_friction, delta)
	_accelerate(wish_dir, target * wish_amount, settings.ground_accel, delta)

	if _jump_buffer_left > 0.0:
		_jump(settings.jump_velocity(), &"ground")


func _start_slide() -> void:
	state = State.SLIDE
	crouched = true
	var h := Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	if _clock >= _slide_boost_ready_at and h.length() > 0.1:
		h += h.normalized() * settings.slide_boost
		_slide_boost_ready_at = _clock + settings.slide_boost_cooldown
	h = h.limit_length(settings.slide_max_speed)
	_body.velocity.x = h.x
	_body.velocity.z = h.z


func _step_slide(input: MoveInput, wish_dir: Vector3, delta: float) -> void:
	var h := Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	var speed := h.length()
	# Linear deceleration instead of Source friction keeps long slides readable.
	if speed > 0.0:
		h = h.normalized() * maxf(speed - settings.slide_decel * delta, 0.0)
	# Slopes speed you up going down and slow you going up.
	var n := _body.get_floor_normal()
	var downhill := Vector3.DOWN - n * Vector3.DOWN.dot(n)
	h += Vector3(downhill.x, 0.0, downhill.z) * settings.slide_slope_gravity * delta
	# A little steering, without adding speed.
	if wish_dir != Vector3.ZERO and h.length() > 0.1:
		var steered := h.normalized().slerp(wish_dir, minf(1.5 * delta, 1.0))
		h = steered * h.length()
	h = h.limit_length(settings.slide_max_speed)
	_body.velocity.x = h.x
	_body.velocity.z = h.z

	if _jump_buffer_left > 0.0:
		_jump(settings.jump_velocity(), &"ground")  # slide-hop keeps momentum
		return
	if not input.crouch:
		state = State.GROUND
		crouched = not _can_stand()
	elif h.length() < settings.slide_exit_speed:
		state = State.GROUND
		crouched = true


func _step_air(input: MoveInput, wish_dir: Vector3, wish_amount: float, forward: Vector3, delta: float) -> void:
	_body.velocity.y -= settings.gravity * delta
	crouched = input.crouch or not _can_stand()

	# Source-style air acceleration: only the speed *along* the wish direction
	# is capped, so turning while strafing redirects (and can build) speed.
	if wish_dir != Vector3.ZERO:
		var current := _body.velocity.dot(wish_dir)
		var add := settings.air_speed_cap * wish_amount - current
		if add > 0.0:
			_body.velocity += wish_dir * minf(settings.air_accel * wish_amount * delta, add)
		# Gentle air control when slow, so a standing jump isn't a commitment.
		if horizontal_speed() < settings.walk_speed:
			_accelerate(wish_dir, settings.walk_speed * wish_amount, 2.5, delta)

	if _jump_buffer_left > 0.0:
		if _coyote_left > 0.0 and not _jumped_this_airtime:
			_jump(settings.jump_velocity(), &"ground")
			return
		var wall := _find_wall(_body.velocity)
		if not wall.is_empty() and settings.wallrun_enabled:
			wall_normal = wall.normal
			_wall_jump(wish_dir)
			return
		if air_jumps_left > 0:
			air_jumps_left -= 1
			# A double jump can change direction, like a Titanfall pilot's.
			if wish_dir != Vector3.ZERO:
				var h := Vector3(_body.velocity.x, 0.0, _body.velocity.z)
				var redirected := wish_dir * maxf(h.length(), settings.walk_speed * 0.8)
				h = h.lerp(redirected, 0.6)
				_body.velocity.x = h.x
				_body.velocity.z = h.z
			_jump(settings.air_jump_velocity(), &"air")
			return

	if settings.mantle_enabled and input.wish.y < -0.3 and _body.velocity.y < 3.0 and _try_mantle(forward):
		return

	if settings.wallrun_enabled and horizontal_speed() >= settings.wallrun_min_speed and not input.crouch:
		var hit := _find_wall(_body.velocity)
		# Only start once the wall is beside us (not just ahead on a diagonal).
		if not hit.is_empty() and _can_run_on(hit.normal) and not _probe_wall(-hit.normal).is_empty():
			_start_wallrun(hit.normal)


func _start_wallrun(normal: Vector3) -> void:
	state = State.WALLRUN
	wall_normal = normal
	_wallrun_time = 0.0
	air_jumps_left = settings.air_jumps
	_jumped_this_airtime = false
	# Titanfall gives a small lift when you catch a wall.
	_body.velocity.y = clampf(_body.velocity.y * 0.4 + 1.5, 0.0, 4.0)


func _step_wallrun(input: MoveInput, wish_dir: Vector3, delta: float) -> void:
	_wallrun_time += delta
	var probe := _probe_wall(-wall_normal)
	if probe.is_empty() or _wallrun_time > settings.wallrun_max_time or input.crouch:
		_leave_wall()
		_body.velocity.y -= settings.gravity * delta
		return
	wall_normal = probe.normal

	var h := Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	var along := h - wall_normal * h.dot(wall_normal)
	if along.length() < 0.5:
		_leave_wall()
		return
	var dir := along.normalized()
	# Pulling away from the wall (stick or keys) drops you off it.
	if wish_dir.dot(wall_normal) > 0.7:
		_leave_wall()
		return
	var speed := along.length()
	speed = move_toward(speed, maxf(speed - 0.5 * delta, settings.wallrun_speed), settings.wallrun_accel * delta)
	h = dir * speed - wall_normal * 1.0  # keep contact with the wall
	_body.velocity.x = h.x
	_body.velocity.z = h.z
	# Gravity ramps up towards the end of the run.
	var fade := clampf(_wallrun_time / settings.wallrun_max_time, 0.0, 1.0)
	var g := settings.gravity * lerpf(settings.wallrun_gravity_scale, 0.6, fade * fade)
	_body.velocity.y = maxf(_body.velocity.y - g * delta, -3.0)

	if _jump_buffer_left > 0.0:
		_wall_jump(wish_dir)


func _wall_jump(wish_dir: Vector3) -> void:
	var h := Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	var along := h - wall_normal * h.dot(wall_normal)
	var push := wall_normal * settings.walljump_push
	if wish_dir != Vector3.ZERO:
		push += wish_dir * 1.5
	h = along + push
	_body.velocity = Vector3(h.x, settings.walljump_velocity(), h.z)
	_last_wall_normal = wall_normal
	wall_normal = Vector3.ZERO
	air_jumps_left = settings.air_jumps
	_jump_buffer_left = 0.0
	_jumped_this_airtime = true
	state = State.AIR
	jumped.emit(&"wall")


func _leave_wall() -> void:
	_last_wall_normal = wall_normal
	wall_normal = Vector3.ZERO
	state = State.AIR


func _jump(velocity_y: float, kind: StringName) -> void:
	_body.velocity.y = velocity_y
	_jump_buffer_left = 0.0
	_coyote_left = 0.0
	_jumped_this_airtime = true
	state = State.AIR
	jumped.emit(kind)


# --- Mantle ---------------------------------------------------------------------

func _try_mantle(forward: Vector3) -> bool:
	var space := _body.get_world_3d().direct_space_state
	var feet := _body.global_position
	var reach := _capsule.radius + 0.45
	# 1. Something solid in front of us at waist height...
	var waist := feet + Vector3.UP * (settings.mantle_min_height + 0.1)
	var front := _ray(space, waist, waist + forward * reach)
	if front.is_empty() or absf(front.normal.y) > WALL_MAX_NORMAL_Y:
		return false
	# 2. ...with a walkable top within reach...
	var front_position: Vector3 = front.position
	var front_normal: Vector3 = front.normal
	var over := front_position - front_normal * 0.3
	var top_start := Vector3(over.x, feet.y + settings.mantle_max_height + 0.05, over.z)
	var top := _ray(space, top_start, Vector3(over.x, feet.y + settings.mantle_min_height, over.z))
	if top.is_empty() or top.normal.y < 0.7:
		return false
	# 3. ...and room to stand on it.
	var target: Vector3 = top.position + Vector3.UP * 0.02
	if _ray(space, feet + Vector3.UP * (height - 0.1), target + Vector3.UP * (height - 0.1)).size() > 0:
		return false
	if not _capsule_fits(target, settings.stand_height):
		return false
	state = State.MANTLE
	_mantle_from = feet
	_mantle_to = target
	_mantle_t = 0.0
	_body.velocity = Vector3.ZERO
	mantled.emit()
	return true


func _step_mantle(delta: float) -> void:
	_mantle_t = minf(_mantle_t + delta / settings.mantle_time, 1.0)
	# Rise first, then roll forward over the edge.
	var up := ease(_mantle_t, 0.5)
	var across := ease(_mantle_t, 2.0)
	_body.global_position = Vector3(
		lerpf(_mantle_from.x, _mantle_to.x, across),
		lerpf(_mantle_from.y, _mantle_to.y, up),
		lerpf(_mantle_from.z, _mantle_to.z, across))
	if _mantle_t >= 1.0:
		var dir := (_mantle_to - _mantle_from) * Vector3(1, 0, 1)
		_body.velocity = dir.normalized() * settings.walk_speed * 0.6 if dir.length() > 0.01 else Vector3.ZERO
		state = State.GROUND
		_body.apply_floor_snap()


# --- Helpers ------------------------------------------------------------------

func _accelerate(wish_dir: Vector3, wish_speed: float, accel: float, delta: float) -> void:
	var current := _body.velocity.dot(wish_dir) if wish_dir != Vector3.ZERO else 0.0
	var add := wish_speed - current
	if add <= 0.0 or wish_dir == Vector3.ZERO:
		return
	_body.velocity += wish_dir * minf(accel * wish_speed * delta, add)


func _apply_friction(friction: float, delta: float) -> void:
	var h := Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	var speed := h.length()
	if speed < 0.01:
		_body.velocity.x = 0.0
		_body.velocity.z = 0.0
		return
	var drop := maxf(speed, settings.stop_speed) * friction * delta
	h *= maxf(speed - drop, 0.0) / speed
	_body.velocity.x = h.x
	_body.velocity.z = h.z


func _update_height(want_crouch: bool, delta: float) -> void:
	var target := settings.crouch_height if (crouched or want_crouch or state == State.SLIDE) else settings.stand_height
	if target > height and not _can_stand():
		target = height
	var next := move_toward(height, target, 6.0 * delta)
	if not is_equal_approx(next, height):
		height = next
		_apply_height()


func _apply_height() -> void:
	_capsule.height = height
	_shape_node.position.y = height * 0.5


func _can_stand() -> bool:
	if height >= settings.stand_height - 0.01:
		return true
	return _capsule_fits(_body.global_position, settings.stand_height)


func _capsule_fits(feet: Vector3, h: float) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = _capsule.radius - 0.02
	shape.height = h - 0.04
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (h * 0.5 + 0.02))
	query.collision_mask = WORLD_MASK
	query.exclude = [_body.get_rid()]
	return _body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## Looks for a runnable wall to the sides of (and slightly ahead along) `motion`.
func _find_wall(motion: Vector3) -> Dictionary:
	var h := Vector3(motion.x, 0.0, motion.z)
	if h.length() < 0.1:
		h = _body.global_basis * Vector3.FORWARD
	var dir := h.normalized()
	var right := dir.cross(Vector3.UP)
	var best := {}
	for probe_dir: Vector3 in [right, -right, (right + dir).normalized(), (-right + dir).normalized()]:
		var hit := _probe_wall(probe_dir)
		if hit.is_empty():
			continue
		if best.is_empty() or hit.distance < best.distance:
			best = hit
	return best


func _probe_wall(direction: Vector3) -> Dictionary:
	var space := _body.get_world_3d().direct_space_state
	var from := _body.global_position + Vector3.UP * (height * 0.5)
	var hit := _ray(space, from, from + direction * (_capsule.radius + settings.wall_probe))
	if hit.is_empty() or absf(hit.normal.y) > WALL_MAX_NORMAL_Y:
		return {}
	hit.distance = from.distance_to(hit.position)
	return hit


func _can_run_on(normal: Vector3) -> bool:
	if _last_wall_normal != Vector3.ZERO and normal.dot(_last_wall_normal) > 0.9:
		return false  # same wall we just left: no re-attaching
	# Need to be travelling along the wall, not straight into it.
	var h := Vector3(_body.velocity.x, 0.0, _body.velocity.z).normalized()
	return absf(h.dot(normal)) < 0.8


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK, [_body.get_rid()])
	return space.intersect_ray(q)
