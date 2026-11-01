class_name TargetDummy
extends StaticBody3D
## Training Garage target. Shows damage taken and resets after a pause.

const MAX_HEALTH := 100
const RESET_DELAY := 3.0

var health := MAX_HEALTH
var _hits_since_reset := 0

@onready var label: Label3D = $Label3D
@onready var character: CharacterModel = $Character


func _ready() -> void:
	_refresh_label(0)


## Server only (called by player hit detection).
func take_damage(amount: int, _attacker_id: int) -> void:
	if not multiplayer.is_server():
		return
	health = maxi(health - amount, 0)
	_hits_since_reset += 1
	_show_hit.rpc(amount, health, _hits_since_reset)
	var hits := _hits_since_reset
	get_tree().create_timer(RESET_DELAY).timeout.connect(func() -> void:
		if hits == _hits_since_reset:  # no newer hits: reset
			health = MAX_HEALTH
			_hits_since_reset = 0
			_show_hit.rpc(0, health, 0))


@rpc("authority", "call_local", "reliable")
func _show_hit(amount: int, new_health: int, hits: int) -> void:
	health = new_health
	_hits_since_reset = hits
	_refresh_label(amount)
	character.set_dead(new_health == 0)


func _refresh_label(last_damage: int) -> void:
	var lines := ["HP %d / %d" % [health, MAX_HEALTH]]
	if last_damage > 0:
		lines.append("-%d  (hits: %d)" % [last_damage, _hits_since_reset])
	if health == 0:
		lines.append("ELIMINATED")
	label.text = "\n".join(lines)
