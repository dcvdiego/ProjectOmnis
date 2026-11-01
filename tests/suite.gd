extends RefCounted
## Test cases. Loaded at runtime by `run_tests.gd`, after autoloads exist, so
## it can reference game classes that use them.

const NetworkScript := preload("res://game/autoload/network.gd")
const WEAPON_DIR := "res://game/weapons/data/"

var root: Window
var tree: SceneTree
var checks := 0
var failures: PackedStringArray = []
var physics_frame: Signal
var process_frame: Signal


func _init(scene_tree: SceneTree) -> void:
	tree = scene_tree
	root = scene_tree.root
	physics_frame = scene_tree.physics_frame
	process_frame = scene_tree.process_frame


func run() -> void:
	_test_weapon_data()
	_test_launch_args()
	await _test_scenes_instantiate()
	await _test_server_combat_rules()
	await _test_movement()
	_test_snapshot_interpolation()


func create_timer(seconds: float) -> SceneTreeTimer:
	return tree.create_timer(seconds)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


# --- Tests -------------------------------------------------------------------

func _test_weapon_data() -> void:
	var files := Array(DirAccess.get_files_at(WEAPON_DIR)).filter(
		func(f: String) -> bool: return f.ends_with(".tres"))
	_check(files.size() >= 2, "at least two weapons defined")
	for file: String in files:
		var weapon := load(WEAPON_DIR + file) as WeaponData
		_check(weapon != null, "%s loads as WeaponData" % file)
		if weapon == null:
			continue
		_check(not weapon.display_name.is_empty(), "%s has a name" % file)
		_check(weapon.damage > 0 and weapon.damage <= 100, "%s damage in 1..100" % file)
		_check(weapon.magazine_size > 0, "%s magazine > 0" % file)
		# Balance guardrail: nothing should kill a full-health player instantly.
		_check(weapon.shots_to_kill(Player.MAX_HEALTH) >= 2, "%s needs 2+ shots to kill" % file)

	var w := WeaponData.new()
	w.damage = 25
	w.rounds_per_minute = 600.0
	_check(is_equal_approx(w.seconds_between_shots(), 0.1), "600 rpm = 0.1 s between shots")
	_check(w.shots_to_kill(100) == 4, "25 dmg vs 100 hp = 4 shots")
	_check(is_equal_approx(w.time_to_kill(100), 0.3), "4 shots at 0.1 s = 0.3 s TTK")
	w.damage = 30
	_check(w.shots_to_kill(100) == 4, "30 dmg vs 100 hp rounds up to 4 shots")


func _test_launch_args() -> void:
	var none := NetworkScript.parse_launch_args(PackedStringArray())
	_check(none.mode == "" and none.port == NetworkScript.DEFAULT_PORT, "no args = menu, default port")

	var server := NetworkScript.parse_launch_args(PackedStringArray(["--server", "--port=3000"]))
	_check(server.mode == "server" and server.port == 3000, "--server --port=3000")

	var join := NetworkScript.parse_launch_args(PackedStringArray(["--join=10.0.0.5"]))
	_check(join.mode == "join" and join.address == "10.0.0.5", "--join=ADDRESS")

	var bare_join := NetworkScript.parse_launch_args(PackedStringArray(["--join"]))
	_check(bare_join.address == "127.0.0.1", "--join defaults to localhost")

	var bad_port := NetworkScript.parse_launch_args(PackedStringArray(["--host", "--port=99999"]))
	_check(bad_port.port == NetworkScript.DEFAULT_PORT, "invalid port ignored")


func _test_scenes_instantiate() -> void:
	for path in ["res://game/main/main.tscn", "res://game/world/training_garage.tscn",
			"res://game/player/player.tscn", "res://game/world/target_dummy.tscn"]:
		var scene := load(path) as PackedScene
		_check(scene != null, "%s loads" % path)
		if scene == null:
			continue
		var node := scene.instantiate()
		_check(node != null, "%s instantiates" % path)
		root.add_child(node)
		await process_frame
		node.queue_free()
		await process_frame

	var player := (load("res://game/player/player.tscn") as PackedScene).instantiate() as Player
	_check(player != null, "player.tscn instantiates as Player")
	if player:
		_check(player.weapons.size() == 2, "player has rifle and pistol")
		_check(player.movement != null, "player has movement settings")
		for weapon in player.weapons:
			_check(weapon.model != null, "%s has a model" % weapon.display_name)
		player.free()


## Runs offline, where this process is peer 1 (the server).
func _test_server_combat_rules() -> void:
	var world := (load("res://game/world/training_garage.tscn") as PackedScene).instantiate() as World
	_check(world != null, "training garage instantiates as World")
	if world == null:
		return
	root.add_child(world)
	var dummy := (load("res://game/world/target_dummy.tscn") as PackedScene).instantiate() as TargetDummy
	dummy.position = Vector3(20, 0, 20)  # open lane, no cover in between
	world.add_child(dummy)
	var player := (load("res://game/player/player.tscn") as PackedScene).instantiate() as Player
	player.name = "1"
	world.players.add_child(player)
	player.global_position = Vector3(20, 0, 30)
	for i in 3:
		await physics_frame

	var rifle := player.current_weapon()
	var origin := player.eye_position()
	var aim := (dummy.global_position + Vector3(0, 1.2, 0) - origin).normalized()

	player._request_fire.rpc_id(1, origin, aim)
	_check(dummy.health == TargetDummy.MAX_HEALTH - rifle.damage, "server hitscan damages target")
	_check(player.ammo == rifle.magazine_size - 1, "shot consumes ammo and syncs to owner")

	player._request_fire.rpc_id(1, origin, aim)
	_check(dummy.health == TargetDummy.MAX_HEALTH - rifle.damage, "fire rate limit enforced on server")

	player._next_fire_time = 0.0
	player._request_fire.rpc_id(1, origin + Vector3(0, 0, 5), aim)
	_check(dummy.health == TargetDummy.MAX_HEALTH - rifle.damage, "shot from implausible origin rejected")

	player._request_fire(origin, aim)
	_check(dummy.health == TargetDummy.MAX_HEALTH - rifle.damage, "direct (non-RPC) call rejected")

	player._request_switch_weapon.rpc_id(1, 1)
	_check(player.weapon_index == 1, "weapon switch applied")
	player._request_switch_weapon.rpc_id(1, 7)
	_check(player.weapon_index == 1, "out-of-range weapon index rejected")

	player._server_ammo[1] = 0
	player._next_fire_time = 0.0
	player._request_fire.rpc_id(1, origin, aim)
	_check(player.is_reloading, "empty magazine triggers reload")
	_check(player._server_ammo[1] == 0, "magazine not refilled before reload finishes")
	await create_timer(player.current_weapon().reload_time + 0.1).timeout
	_check(player._server_ammo[1] == player.current_weapon().magazine_size, "reload refills magazine")
	_check(not player.is_reloading, "reload state cleared")

	player.take_damage(Player.MAX_HEALTH, 0)
	_check(not player.is_alive(), "lethal damage kills player")
	await create_timer(Player.RESPAWN_DELAY + 0.1).timeout
	_check(player.health == Player.MAX_HEALTH, "player respawns at full health")

	world.queue_free()
	await process_frame


# --- Movement ----------------------------------------------------------------

## A tiny arena built in code so map changes can't break these tests:
## floor, a long wall along x = 3, a 1.5 m ledge and a low ceiling.
func _movement_arena() -> Node3D:
	var arena := Node3D.new()
	arena.name = "Arena"
	_add_box(arena, Vector3(0, -0.5, 0), Vector3(200, 1, 200))  # floor
	_add_box(arena, Vector3(3.25, 3, -20), Vector3(0.5, 6, 60))  # wall, face at x = 3
	_add_box(arena, Vector3(-10, 0.75, -6), Vector3(4, 1.5, 2))  # ledge, front face at z = -5
	_add_box(arena, Vector3(-20, 1.6, 0), Vector3(4, 0.4, 4))  # ceiling 1.4 m high
	return arena


func _add_box(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = size
	body.add_child(shape)
	body.position = center
	parent.add_child(body)


func _spawn_mover(arena: Node3D, at: Vector3) -> Player:
	var player := (load("res://game/player/player.tscn") as PackedScene).instantiate() as Player
	player.name = "1"
	arena.add_child(player)
	player.set_physics_process(false)  # the test drives the motor directly
	player.global_position = at
	player.motor.reset()
	return player


func _input(wish: Vector2 = Vector2.ZERO, sprint: bool = false, crouch: bool = false) -> PlayerMotor.MoveInput:
	var input := PlayerMotor.MoveInput.new()
	input.wish = wish
	input.sprint = sprint
	input.crouch = crouch
	return input


## Steps the motor for `seconds`; `jump_at` lists tick indices that press jump.
func _simulate(player: Player, input: PlayerMotor.MoveInput, seconds: float, jump_at: Array = []) -> Dictionary:
	var dt := 1.0 / Engine.physics_ticks_per_second
	var ticks := roundi(seconds / dt)
	var stats := {"max_y": player.global_position.y, "states": {}, "max_speed": 0.0}
	for i in ticks:
		await physics_frame
		input.jump_pressed = i in jump_at
		player.motor.step(input, dt)
		stats.max_y = maxf(stats.max_y, player.global_position.y)
		stats.max_speed = maxf(stats.max_speed, player.motor.horizontal_speed())
		stats.states[player.motor.state] = true
	return stats


func _test_movement() -> void:
	var arena := _movement_arena()
	root.add_child(arena)
	for i in 2:
		await physics_frame
	var settings: MovementSettings = load("res://game/player/movement/default.tres")
	var forward := Vector2(0, -1)

	# Ground speed caps.
	var p := _spawn_mover(arena, Vector3(-40, 0.05, 40))
	await _simulate(p, _input(forward), 1.5)
	_check(absf(p.motor.horizontal_speed() - settings.walk_speed) < 0.3, "walk reaches walk speed")
	await _simulate(p, _input(forward, true), 1.5)
	_check(absf(p.motor.horizontal_speed() - settings.sprint_speed) < 0.3, "sprint reaches sprint speed")
	await _simulate(p, _input(Vector2.ZERO), 1.0)
	_check(p.motor.horizontal_speed() < 0.05, "friction stops the player")

	# Jump height and double jump.
	var start_y := p.global_position.y
	var stats := await _simulate(p, _input(), 1.2, [0])
	_check(absf(stats.max_y - start_y - settings.jump_height) < 0.15, "jump reaches jump_height")
	stats = await _simulate(p, _input(), 1.6, [0, 20, 40])
	var expected := settings.jump_height + settings.air_jump_height
	_check(stats.max_y - start_y > expected - 0.4, "double jump adds height")
	_check(stats.max_y - start_y < expected + 0.6, "only one air jump")
	_check(p.motor.state == PlayerMotor.State.GROUND, "lands after jumping")

	# Air strafing can't be used to accelerate straight ahead.
	await _simulate(p, _input(forward, true), 1.5)
	stats = await _simulate(p, _input(forward, true), 0.5, [0])
	_check(stats.max_speed < settings.sprint_speed + settings.air_speed_cap + 0.2, "no forward air acceleration exploit")
	await _simulate(p, _input(), 1.0)

	# Slide: crouching at sprint speed boosts, then slows down to a crouch.
	await _simulate(p, _input(forward, true), 1.5)
	var before := p.motor.horizontal_speed()
	stats = await _simulate(p, _input(forward, true, true), 0.1)
	_check(p.motor.state == PlayerMotor.State.SLIDE, "crouch while sprinting starts a slide")
	_check(stats.max_speed > before + settings.slide_boost * 0.8, "slide start gives a speed boost")
	_check(p.motor.height < settings.stand_height - 0.3, "sliding lowers the capsule")
	await _simulate(p, _input(forward, true, true), 3.0)
	_check(p.motor.state == PlayerMotor.State.GROUND and p.motor.crouched, "slide decays into a crouch")
	await _simulate(p, _input(forward), 0.5)
	_check(not p.motor.crouched, "releasing crouch stands up")
	p.queue_free()

	# Wall-run along the wall at x = 3, then jump off it.
	p = _spawn_mover(arena, Vector3(2.4, 0.05, 20))
	await _simulate(p, _input(forward, true), 1.2)
	stats = await _simulate(p, _input(forward, true), 1.0, [0])
	_check(PlayerMotor.State.WALLRUN in stats.states, "jumping along a wall starts a wall-run")
	_check(p.global_position.y > 0.8, "wall-run holds the player up")
	_check(p.motor.wall_side() > 0.0, "wall reported on the right")
	stats = await _simulate(p, _input(forward, true), 0.3, [0])
	_check(p.global_position.x < 2.0, "wall-jump pushes away from the wall")
	p.queue_free()

	# Mantle onto the 1.5 m ledge at z = -5.
	p = _spawn_mover(arena, Vector3(-10, 0.05, 0))
	await _simulate(p, _input(forward), 0.5)
	stats = await _simulate(p, _input(forward), 1.2, [0])
	_check(PlayerMotor.State.MANTLE in stats.states, "jumping at a ledge mantles")
	_check(p.global_position.y > 1.4, "mantle ends on top of the ledge")
	p.queue_free()

	# Can't stand up under a low ceiling.
	p = _spawn_mover(arena, Vector3(-20, 0.05, 6))
	await _simulate(p, _input(forward, false, true), 2.5)
	await _simulate(p, _input(), 0.5)
	_check(p.motor.crouched and p.motor.height < settings.stand_height - 0.3, "stays crouched under a low ceiling")
	p.queue_free()

	arena.queue_free()
	await process_frame


## Remote players are drawn between received snapshots.
func _test_snapshot_interpolation() -> void:
	var p := (load("res://game/player/player.tscn") as PackedScene).instantiate() as Player
	p._snapshots = [[1.0, Vector3(0, 0, 0), 0.0, 0.0], [1.1, Vector3(1, 0, 0), 0.2, 0.0]]
	var mid: Array = p._sample_snapshots(1.05)
	_check((mid[0] as Vector3).is_equal_approx(Vector3(0.5, 0, 0)), "snapshot position interpolates")
	_check(is_equal_approx(mid[1], 0.1), "snapshot yaw interpolates")
	var before: Array = p._sample_snapshots(0.5)
	_check((before[0] as Vector3).is_equal_approx(Vector3.ZERO), "before first snapshot holds the first")
	p.net_velocity = Vector3(10, 0, 0)
	var ahead: Array = p._sample_snapshots(2.0)
	_check((ahead[0] as Vector3).is_equal_approx(Vector3(2.5, 0, 0)), "extrapolation is capped at 0.15 s")
	p.free()
