class_name ViewModel
extends Node3D
## First-person weapon presentation: sway, bob, sprint pose, slide and
## wall-run lean, recoil, landing dip, and procedural reload / swap motions.
##
## Models are drawn at `VIEW_SCALE` and moved proportionally closer to the
## camera. That looks identical but keeps the gun inside the player's capsule,
## so it never clips into walls, without needing a second camera.

const VIEW_SCALE := 0.3
## Render layer for view models, so other cameras / reflection probes skip them.
const VIEW_LAYER := 1 << 19

var _models: Array[WeaponModel] = []
var _offsets: Array[Vector3] = []
var _current := -1
var _sway := Vector2.ZERO
var _sway_target := Vector2.ZERO
var _bob_phase := 0.0
var _bob_amount := 0.0
var _kick := 0.0
var _kick_velocity := 0.0
var _land := 0.0
var _land_velocity := 0.0
var _sprint_blend := 0.0
var _lean := 0.0
var _swap := 0.0  # 1 = fully lowered
var _reload_left := 0.0
var _reload_total := 1.0
var _flash: Node3D


func setup(weapons: Array[WeaponData]) -> void:
	for weapon in weapons:
		var model := weapon.model.instantiate() as WeaponModel
		add_child(model)
		model.scale = Vector3.ONE * VIEW_SCALE
		model.set_cast_shadows(false)
		model.set_layers(VIEW_LAYER)
		model.visible = false
		_models.append(model)
		_offsets.append(weapon.view_offset)
	_flash = Fx.make_muzzle_flash()
	add_child(_flash)
	set_weapon(0)


func set_weapon(index: int) -> void:
	if index == _current or index < 0 or index >= _models.size():
		return
	if _current >= 0:
		_models[_current].visible = false
	_current = index
	_models[_current].visible = true
	_swap = 1.0  # raise the new weapon from below
	_reload_left = 0.0


func add_sway(mouse_motion: Vector2) -> void:
	_sway_target += mouse_motion * 0.0009


## Plays the shot motion; returns the muzzle position for tracers.
func fire() -> Vector3:
	_kick_velocity += 9.0
	var muzzle := muzzle_position()
	if _flash:
		_flash.global_position = muzzle
		Fx.flash(_flash, VIEW_SCALE)
	return muzzle


func muzzle_position() -> Vector3:
	if _current < 0:
		return global_position
	return _models[_current].muzzle.global_position


func land(impact_speed: float) -> void:
	_land_velocity -= clampf(impact_speed * 0.25, 0.0, 4.0)


func reload(duration: float) -> void:
	_reload_total = maxf(duration, 0.1)
	_reload_left = _reload_total


## `ctx`: speed, grounded, sprinting, sliding, wall_side, vertical_speed.
func update_pose(delta: float, ctx: Dictionary) -> void:
	if _current < 0:
		return
	var speed: float = ctx.speed
	var grounded: bool = ctx.grounded

	# Sway lags behind the mouse, then settles.
	_sway_target = _sway_target.lerp(Vector2.ZERO, 1.0 - exp(-10.0 * delta)).limit_length(1.0)
	_sway = _sway.lerp(_sway_target, 1.0 - exp(-14.0 * delta))

	# Bob follows ground speed.
	var bob_target := clampf(speed / 7.5, 0.0, 1.3) if grounded else 0.0
	_bob_amount = lerpf(_bob_amount, bob_target, 1.0 - exp(-8.0 * delta))
	_bob_phase += delta * lerpf(6.0, 13.0, clampf(speed / 9.0, 0.0, 1.0))

	# Springs for recoil and landing.
	_kick_velocity += (-_kick * 260.0 - _kick_velocity * 22.0) * delta
	_kick += _kick_velocity * delta
	_land_velocity += (-_land * 140.0 - _land_velocity * 14.0) * delta
	_land += _land_velocity * delta

	_sprint_blend = lerpf(_sprint_blend, 1.0 if ctx.sprinting and _reload_left <= 0.0 else 0.0, 1.0 - exp(-10.0 * delta))
	var lean_target := 0.0
	if ctx.sliding:
		lean_target = 1.0
	elif ctx.wall_side != 0.0:
		lean_target = -0.6 * float(ctx.wall_side)
	_lean = lerpf(_lean, lean_target, 1.0 - exp(-8.0 * delta))
	_swap = move_toward(_swap, 0.0, delta * 3.5)

	var reload_curve := 0.0
	if _reload_left > 0.0:
		_reload_left = maxf(_reload_left - delta, 0.0)
		var t := 1.0 - _reload_left / _reload_total
		reload_curve = sin(t * PI)  # down and back up over the reload

	var offset := _offsets[_current]
	var pos := offset
	var rot := Vector3.ZERO
	pos += Vector3(sin(_bob_phase) * 0.012, -absf(cos(_bob_phase)) * 0.014, 0.0) * _bob_amount
	pos += Vector3(-_sway.x * 0.02, _sway.y * 0.02, 0.0)
	rot += Vector3(_sway.y * 0.05, -_sway.x * 0.08, -_sway.x * 0.06)
	pos.z += _kick * 0.035
	rot.x += _kick * 0.05
	pos.y += _land * 0.03
	rot.x += deg_to_rad(ctx.vertical_speed) * 0.08 if not grounded else 0.0
	# Sprint: lower and angle the weapon.
	pos += Vector3(-0.04, -0.05, 0.03) * _sprint_blend
	rot += Vector3(deg_to_rad(-12.0), deg_to_rad(28.0), deg_to_rad(8.0)) * _sprint_blend
	# Slide / wall-run lean.
	rot.z += deg_to_rad(12.0) * _lean
	pos.x -= 0.02 * _lean
	# Reload: drop and roll the weapon.
	pos.y -= 0.09 * reload_curve
	rot += Vector3(deg_to_rad(-25.0), 0.0, deg_to_rad(35.0)) * reload_curve
	# Swap: raise from below.
	pos.y -= 0.25 * _swap * _swap
	rot.x -= deg_to_rad(40.0) * _swap * _swap

	var model := _models[_current]
	model.position = pos * VIEW_SCALE
	model.rotation = rot
