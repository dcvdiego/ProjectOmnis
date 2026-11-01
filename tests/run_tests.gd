extends SceneTree
## Headless test runner. Exits non-zero on failure.
##
##   godot --headless --path . -s tests/run_tests.gd
##
## Kept dependency-free on purpose; switch to GUT or gdUnit4 once the suite grows.

const NetworkScript := preload("res://game/autoload/network.gd")
const WEAPON_DIR := "res://game/weapons/data/"

var _checks := 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_weapon_data()
	_test_launch_args()
	await _test_scenes_instantiate()
	await _test_server_combat_rules()

	print("\n%d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures:
		printerr("  FAIL: " + failure)
	quit(1 if _failures.size() > 0 else 0)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)


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
	_check(player.weapons.size() == 2, "player has rifle and pistol")
	player.free()


## Runs offline, where this process is peer 1 (the server).
func _test_server_combat_rules() -> void:
	var world := (load("res://game/world/training_garage.tscn") as PackedScene).instantiate() as World
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
	var origin := player.camera.global_position
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
