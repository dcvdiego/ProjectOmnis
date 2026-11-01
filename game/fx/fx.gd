class_name Fx
extends RefCounted
## Lightweight, texture-free shot effects: muzzle flash, tracers, impacts.
##
## Everything here is built from primitive meshes, gradients and particles in
## code, so there are no art assets to license. Effects free themselves.

const TRACER_LIFE := 0.06
const IMPACT_LIFE := 0.6
const MAX_DECALS := 48

static var _tracer_material: StandardMaterial3D
static var _flash_material: StandardMaterial3D
static var _spark_material: StandardMaterial3D
static var _dust_material: StandardMaterial3D
static var _hole_texture: GradientTexture2D
static var _decals: Array[Decal] = []


static func enabled() -> bool:
	return DisplayServer.get_name() != "headless"


## A reusable muzzle flash node (crossed glowing quads + a short light).
static func make_muzzle_flash() -> Node3D:
	var root := Node3D.new()
	root.name = "MuzzleFlash"
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.visible = false
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	quad.material = _flash_mat()
	for i in 3:
		var m := MeshInstance3D.new()
		m.mesh = quad
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.rotation = [Vector3(0, 0, 0), Vector3(0, PI / 2, 0), Vector3(PI / 2, 0, 0)][i]
		root.add_child(m)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.4)
	light.light_energy = 2.5
	light.omni_range = 4.0
	light.shadow_enabled = false
	root.add_child(light)
	return root


## Shows `flash` for one frame-ish, randomly rotated.
static func flash(flash_node: Node3D, scale_factor: float = 1.0) -> void:
	if not enabled() or flash_node == null:
		return
	flash_node.visible = true
	flash_node.scale = Vector3.ONE * scale_factor * randf_range(0.8, 1.2)
	flash_node.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	var light := flash_node.get_child(flash_node.get_child_count() - 1) as OmniLight3D
	light.omni_range = 4.0  # light range shouldn't shrink with the view-model scale
	flash_node.get_tree().create_timer(0.035).timeout.connect(func() -> void:
		if is_instance_valid(flash_node):
			flash_node.visible = false)


static func tracer(parent: Node, from: Vector3, to: Vector3) -> void:
	if not enabled() or parent == null or from.distance_to(to) < 0.5:
		return
	var length := from.distance_to(to)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.012, 0.012, length)
	mesh.material = _tracer_mat()
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(m)
	m.look_at_from_position((from + to) * 0.5, to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	m.get_tree().create_timer(TRACER_LIFE).timeout.connect(m.queue_free)


static func impact(parent: Node, position: Vector3, normal: Vector3, flesh: bool) -> void:
	if not enabled() or parent == null:
		return
	var sparks := CPUParticles3D.new()
	sparks.one_shot = true
	sparks.emitting = false
	sparks.amount = 10 if flesh else 14
	sparks.lifetime = 0.35
	sparks.explosiveness = 1.0
	sparks.direction = Vector3.FORWARD
	sparks.spread = 50.0
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 6.0
	sparks.gravity = Vector3(0, -12, 0)
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.0
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.012, 0.012, 0.06)
	spark_mesh.material = _spark_mat(flesh)
	sparks.mesh = spark_mesh
	sparks.particle_flag_align_y = false
	sparks.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(sparks)
	_orient(sparks, position, normal)
	sparks.emitting = true

	var dust := CPUParticles3D.new()
	dust.one_shot = true
	dust.emitting = false
	dust.amount = 6
	dust.lifetime = 0.6
	dust.explosiveness = 1.0
	dust.direction = Vector3.FORWARD
	dust.spread = 30.0
	dust.initial_velocity_min = 0.4
	dust.initial_velocity_max = 1.2
	dust.gravity = Vector3(0, 0.3, 0)
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1))
	dust.scale_amount_curve = curve
	var puff := SphereMesh.new()
	puff.radius = 0.06
	puff.height = 0.12
	puff.radial_segments = 8
	puff.rings = 4
	puff.material = _dust_mat()
	dust.mesh = puff
	dust.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(dust)
	_orient(dust, position, normal)
	dust.emitting = true

	for p: CPUParticles3D in [sparks, dust]:
		p.get_tree().create_timer(IMPACT_LIFE + 0.1).timeout.connect(p.queue_free)
	if not flesh:
		_bullet_hole(parent, position, normal)


static func _orient(node: Node3D, position: Vector3, normal: Vector3) -> void:
	var up := Vector3.UP if absf(normal.y) < 0.99 else Vector3.RIGHT
	node.look_at_from_position(position + normal * 0.02, position + normal, up)


static func _bullet_hole(parent: Node, position: Vector3, normal: Vector3) -> void:
	var decal := Decal.new()
	decal.size = Vector3(0.07, 0.1, 0.07)
	decal.texture_albedo = _hole_tex()
	decal.cull_mask = 1  # world geometry only
	decal.upper_fade = 0.0
	decal.lower_fade = 0.0
	decal.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(decal)
	# Decals project along their local -Y.
	var up := normal
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.99 else Vector3.RIGHT).normalized()
	decal.global_transform = Transform3D(Basis(side, up, side.cross(up)), position)
	decal.rotate_object_local(Vector3.UP, randf() * TAU)
	_decals.append(decal)
	while _decals.size() > MAX_DECALS:
		var old: Decal = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()


static func _tracer_mat() -> StandardMaterial3D:
	if _tracer_material == null:
		_tracer_material = StandardMaterial3D.new()
		_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_tracer_material.albedo_color = Color(1.0, 0.85, 0.55)
		_tracer_material.emission_enabled = true
		_tracer_material.emission = Color(1.0, 0.75, 0.4)
		_tracer_material.emission_energy_multiplier = 6.0
	return _tracer_material


static func _flash_mat() -> StandardMaterial3D:
	if _flash_material == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1.0, 0.95, 0.8, 1.0))
		gradient.set_color(1, Color(1.0, 0.45, 0.1, 0.0))
		gradient.add_point(0.35, Color(1.0, 0.7, 0.3, 0.8))
		var tex := GradientTexture2D.new()
		tex.gradient = gradient
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 64
		tex.height = 64
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_flash_material.albedo_texture = tex
		_flash_material.albedo_color = Color(4.0, 3.0, 2.0)
	return _flash_material


static func _spark_mat(flesh: bool) -> StandardMaterial3D:
	if flesh:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.45, 0.05, 0.05)
		m.roughness = 0.4
		return m
	if _spark_material == null:
		_spark_material = StandardMaterial3D.new()
		_spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spark_material.albedo_color = Color(1.0, 0.8, 0.45)
		_spark_material.emission_enabled = true
		_spark_material.emission = Color(1.0, 0.6, 0.25)
		_spark_material.emission_energy_multiplier = 8.0
	return _spark_material


static func _dust_mat() -> StandardMaterial3D:
	if _dust_material == null:
		_dust_material = StandardMaterial3D.new()
		_dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dust_material.albedo_color = Color(0.55, 0.52, 0.48, 0.35)
		_dust_material.roughness = 1.0
		_dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	return _dust_material


static func _hole_tex() -> GradientTexture2D:
	if _hole_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0.02, 0.02, 0.02, 1.0))
		gradient.set_color(1, Color(0.1, 0.09, 0.08, 0.0))
		gradient.add_point(0.25, Color(0.04, 0.04, 0.04, 0.95))
		gradient.add_point(0.5, Color(0.12, 0.11, 0.1, 0.4))
		_hole_texture = GradientTexture2D.new()
		_hole_texture.gradient = gradient
		_hole_texture.fill = GradientTexture2D.FILL_RADIAL
		_hole_texture.fill_from = Vector2(0.5, 0.5)
		_hole_texture.fill_to = Vector2(0.5, 0.0)
		_hole_texture.width = 64
		_hole_texture.height = 64
	return _hole_texture
