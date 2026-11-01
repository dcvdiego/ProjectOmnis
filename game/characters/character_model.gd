class_name CharacterModel
extends Node3D
## Third-person body for a player (or a target dummy).
##
## Mesh and animations: Quaternius "Universal Animation Library" (CC0). Its
## mannequin is re-skinned in code with a graphite sim-suit material and an
## accent colour (team colour for players, orange for training dummies).
##
## An AnimationTree blends a locomotion clip (crossfaded when it changes) with
## an upper-body aim pose filtered to the spine and arms, so the character
## keeps aiming while running. Animation is picked from the owning body's
## velocity and `PlayerMotor.State`, so it works the same for local and
## remote players.

## Bones the aim pose overrides.
const UPPER_BODY := [
	"spine_02", "spine_03", "neck_01", "Head",
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
	"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
]
## Clip: native ground speed in m/s, for matching playback rate.
const CLIP_SPEED := {
	"Walk": 1.6, "Jog_Fwd": 3.8, "Sprint": 6.5, "Crouch_Fwd": 1.4,
}
## Render layer for characters (keeps bullet-hole decals off them).
const CHARACTER_LAYER := 1 << 1

## Where the grip sits relative to the right hand, in the aim frame.
const GRIP_OFFSET := Vector3(0.0, -0.03, -0.07)

@export var suit_color := Color(0.13, 0.14, 0.16)
@export var accent_color := Color(0.2, 0.85, 1.0)
## Owner's body, used to read velocity and movement state.
@export var body_path: NodePath = ^".."
## Hide the body (keep its shadow) for the local first-person player.
var first_person := false:
	set(value):
		first_person = value
		_apply_visibility()

var _body: Node3D
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _tree: AnimationTree
var _hand_bone := -1
var _aim_pitch := 0.0
var _weapon_models: Array[WeaponModel] = []
var _weapon_index := 0
var _flash: Node3D
var _slot := 0
var _clip := ["", ""]
var _xfade := 0.0
var _dead := false
var _aim_weight := 1.0
var _reload_left := 0.0
var _facing := 0.0

@onready var visual: Node3D = $Body


func _ready() -> void:
	_body = get_node_or_null(body_path) as Node3D
	_skeleton = visual.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_setup_animation()
	_hand_bone = _skeleton.find_bone("hand_r")
	_flash = Fx.make_muzzle_flash()
	_flash.top_level = true
	_flash.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_flash)
	_apply_materials()
	_apply_visibility()


## Creates the held weapon models (one per weapon, only the current one shown).
func setup(weapons: Array[WeaponData]) -> void:
	if not is_node_ready():
		await ready
	for weapon in weapons:
		var model := weapon.model.instantiate() as WeaponModel
		add_child(model)
		# Placed every rendered frame from the interpolated body, so it opts
		# out of physics interpolation itself.
		model.top_level = true
		model.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		model.set_layers(CHARACTER_LAYER)
		model.visible = false
		_weapon_models.append(model)
	set_weapon(0)


func set_weapon(index: int) -> void:
	if index < 0 or index >= _weapon_models.size():
		return
	_weapon_models[_weapon_index].visible = false
	_weapon_index = index
	_weapon_models[index].visible = true
	_apply_visibility()


func set_dead(dead: bool) -> void:
	if dead == _dead:
		return
	_dead = dead
	if dead:
		_play("Death01", 0.15)


func play_reload() -> void:
	_reload_left = 1.2


## Third-person muzzle flash; returns the muzzle position for tracers.
func fire() -> Vector3:
	if _weapon_models.is_empty():
		return global_position + Vector3.UP * 1.4
	var muzzle := _weapon_models[_weapon_index].muzzle.global_position
	_flash.global_position = muzzle
	Fx.flash(_flash)
	return muzzle


func _process(delta: float) -> void:
	if _tree == null:
		return
	_reload_left = maxf(_reload_left - delta, 0.0)
	_xfade = move_toward(_xfade, float(_slot), delta / 0.18)
	_tree.set("parameters/xfade/blend_amount", _xfade)
	if _dead:
		_aim_weight = move_toward(_aim_weight, 0.0, delta * 4.0)
		_tree.set("parameters/upper/blend_amount", _aim_weight)
		return

	var velocity := Vector3.ZERO
	var state := PlayerMotor.State.GROUND
	var crouched := false
	var pitch := 0.0
	if _body is Player:
		var player := _body as Player
		velocity = player.velocity if player.is_multiplayer_authority() else player.net_velocity
		state = player.net_state as PlayerMotor.State
		crouched = player.net_height < player.movement.stand_height - 0.2
		pitch = player.net_pitch

	var local := _body.global_basis.inverse() * velocity if _body else velocity
	var ground := Vector2(local.x, local.z)
	var speed := ground.length()
	var clip := "Idle"
	var rate := 1.0
	var facing := 0.0  # body turn towards the movement direction

	match state:
		PlayerMotor.State.AIR, PlayerMotor.State.MANTLE:
			clip = "Jump"
		PlayerMotor.State.SLIDE:
			clip = "Crouch_Idle"
		PlayerMotor.State.WALLRUN:
			clip = "Sprint"
		_:
			if crouched:
				clip = "Crouch_Fwd" if speed > 0.4 else "Crouch_Idle"
			elif speed > 6.0:
				clip = "Sprint"
			elif speed > 2.6:
				clip = "Jog_Fwd"
			elif speed > 0.3:
				clip = "Walk"
	if speed > 0.3 and state != PlayerMotor.State.AIR:
		var angle := atan2(-ground.x, -ground.y)  # 0 = forward, + = left
		if absf(angle) > deg_to_rad(110.0):
			rate = -1.0  # backpedal: play the clip in reverse
			angle = wrapf(angle + PI, -PI, PI)
		facing = clampf(angle, deg_to_rad(-55.0), deg_to_rad(55.0))
	if CLIP_SPEED.has(clip):
		rate *= clampf(speed / CLIP_SPEED[clip], 0.6, 1.8)

	_play(clip, 0.18)
	_tree.set("parameters/speed/scale", rate)
	_facing = facing
	var aim_target := 0.0 if state == PlayerMotor.State.WALLRUN or (clip == "Sprint" and _reload_left <= 0.0) else 1.0
	_aim_weight = move_toward(_aim_weight, aim_target, delta * 5.0)
	_tree.set("parameters/upper/blend_amount", _aim_weight)
	_tree.set("parameters/aim/blend_amount", clampf(pitch / deg_to_rad(60.0), -1.0, 1.0))
	_aim_pitch = pitch
	_place_weapon()


## Puts the held weapon in the right hand, pointing where the player aims.
func _place_weapon() -> void:
	if _weapon_models.is_empty() or _hand_bone < 0:
		return
	# Hand position relative to this node, re-applied to the *interpolated*
	# transform so the gun moves exactly with the smoothly drawn body.
	var hand := global_transform.affine_inverse() * (_skeleton.global_transform * _skeleton.get_bone_global_pose(_hand_bone))
	var drawn := get_global_transform_interpolated()
	# Aiming: follow the look pitch. Sprinting / wall-running: carry it angled down.
	var pitch := lerpf(deg_to_rad(-35.0), _aim_pitch, _aim_weight)
	var aim := drawn.basis.orthonormalized() * Basis(Vector3.RIGHT, pitch)
	var model := _weapon_models[_weapon_index]
	model.global_transform = Transform3D(aim, drawn * hand.origin + aim * GRIP_OFFSET)


func _physics_process(delta: float) -> void:
	# Turned per physics tick so physics interpolation keeps it smooth.
	visual.rotation.y = lerp_angle(visual.rotation.y, PI + _facing, 1.0 - exp(-10.0 * delta))


func _play(clip: String, _blend: float) -> void:
	if _tree == null or _clip[_slot] == clip:
		return
	# Put the new clip in the idle slot and crossfade to it.
	_slot = 1 - _slot
	_clip[_slot] = clip
	var node := (_tree.tree_root as AnimationNodeBlendTree).get_node("loco_%d" % _slot) as AnimationNodeAnimation
	node.animation = StringName(clip)
	_tree.set("parameters/loco_%d_seek/seek_request" % _slot, 0.0)


func _apply_materials() -> void:
	var suit := StandardMaterial3D.new()
	suit.albedo_color = suit_color
	suit.metallic = 0.45
	suit.roughness = 0.42
	suit.rim_enabled = true
	suit.rim = 0.25
	suit.rim_tint = 0.6
	var accent := StandardMaterial3D.new()
	accent.albedo_color = accent_color
	accent.roughness = 0.3
	accent.emission_enabled = true
	accent.emission = accent_color
	accent.emission_energy_multiplier = 1.4
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.layers = CHARACTER_LAYER
		for i in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(i)
			var is_joint := source != null and "Joint" in source.resource_name
			mesh.set_surface_override_material(i, accent if is_joint else suit)


func _apply_visibility() -> void:
	if not is_node_ready():
		return
	var mode := (GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if first_person
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	for mesh in find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).cast_shadow = mode


func _setup_animation() -> void:
	_player = visual.get_node("AnimationPlayer") as AnimationPlayer

	var tree_root := AnimationNodeBlendTree.new()
	for i in 2:
		var clip := AnimationNodeAnimation.new()
		clip.animation = &"Idle"
		tree_root.add_node("loco_%d" % i, clip)
		tree_root.add_node("loco_%d_seek" % i, AnimationNodeTimeSeek.new())
		tree_root.connect_node("loco_%d_seek" % i, 0, "loco_%d" % i)
	tree_root.add_node("xfade", AnimationNodeBlend2.new())
	tree_root.connect_node("xfade", 0, "loco_0_seek")
	tree_root.connect_node("xfade", 1, "loco_1_seek")
	tree_root.add_node("speed", AnimationNodeTimeScale.new())
	tree_root.connect_node("speed", 0, "xfade")

	var aim := AnimationNodeBlend3.new()
	tree_root.add_node("aim", aim)
	for pair in [[0, "Pistol_Aim_Down"], [1, "Pistol_Aim_Neutral"], [2, "Pistol_Aim_Up"]]:
		var pose := AnimationNodeAnimation.new()
		pose.animation = StringName(pair[1])
		tree_root.add_node(pair[1], pose)
		tree_root.connect_node("aim", pair[0], pair[1])

	var upper := AnimationNodeBlend2.new()
	upper.filter_enabled = true
	var skeleton_path := visual.get_path_to(_skeleton)
	for bone: String in UPPER_BODY:
		upper.set_filter_path(NodePath("%s:%s" % [skeleton_path, bone]), true)
	tree_root.add_node("upper", upper)
	tree_root.connect_node("upper", 0, "speed")
	tree_root.connect_node("upper", 1, "aim")
	tree_root.connect_node("output", 0, "upper")

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	_tree.tree_root = tree_root
	visual.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_player)
	_tree.root_node = _tree.get_path_to(visual)
	_tree.active = true
	_clip[0] = "Idle"
	_tree.set("parameters/upper/blend_amount", 1.0)
