class_name Hud
extends CanvasLayer
## In-game HUD: crosshair, hit marker, health / ammo, speed readout and a
## damage vignette. Drawn in code so there are no image assets to license.

const ACCENT := Color(0.95, 0.97, 1.0, 0.92)
const HIT := Color(1.0, 0.35, 0.3, 1.0)

var _health := 100
var _max_health := 100
var _hit_marker_left := 0.0
var _damage_flash := 0.0

@onready var overlay: Control = $Overlay
@onready var status_label: Label = $Overlay/Status
@onready var ammo_label: Label = $Overlay/Ammo
@onready var speed_label: Label = $Overlay/Speed


func _ready() -> void:
	overlay.draw.connect(_draw_overlay)


func _process(delta: float) -> void:
	if _hit_marker_left > 0.0 or _damage_flash > 0.0:
		_hit_marker_left = maxf(_hit_marker_left - delta, 0.0)
		_damage_flash = maxf(_damage_flash - delta * 1.5, 0.0)
		overlay.queue_redraw()


func set_status(health: int, max_health: int, weapon_name: String, ammo: int, magazine: int, reloading: bool) -> void:
	_health = health
	_max_health = max_health
	status_label.text = ("HP %d" % health) if health > 0 else "Respawning..."
	ammo_label.text = "%s   %s" % [weapon_name.to_upper(), "RELOADING" if reloading else "%d / %d" % [ammo, magazine]]
	overlay.queue_redraw()


func set_speed(metres_per_second: float) -> void:
	speed_label.text = "%.1f m/s" % metres_per_second


func show_hit_marker() -> void:
	_hit_marker_left = 0.12
	overlay.queue_redraw()


func flash_damage(strength: float) -> void:
	_damage_flash = maxf(_damage_flash, strength)
	overlay.queue_redraw()


func _draw_overlay() -> void:
	var size := overlay.size
	var c := size * 0.5
	# Crosshair: four short lines with a gap.
	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		overlay.draw_line(c + dir * 5.0, c + dir * 13.0, Color(0, 0, 0, 0.5), 3.0, true)
		overlay.draw_line(c + dir * 5.0, c + dir * 13.0, ACCENT, 1.5, true)
	overlay.draw_circle(c, 1.2, ACCENT)
	if _hit_marker_left > 0.0:
		for dir: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var d := dir.normalized()
			overlay.draw_line(c + d * 7.0, c + d * 15.0, HIT, 2.5, true)
	# Health bar, bottom left.
	var bar := Rect2(Vector2(28, size.y - 40), Vector2(260, 10))
	overlay.draw_rect(bar.grow(2.0), Color(0, 0, 0, 0.45))
	var fill := bar
	fill.size.x *= clampf(float(_health) / float(_max_health), 0.0, 1.0)
	overlay.draw_rect(fill, Color(0.35, 0.95, 0.65, 0.9) if _health > 35 else HIT)
	# Damage vignette.
	if _damage_flash > 0.0:
		var a := _damage_flash * 0.35
		var edge := 90.0
		overlay.draw_rect(Rect2(0, 0, size.x, edge), Color(0.8, 0.05, 0.05, a))
		overlay.draw_rect(Rect2(0, size.y - edge, size.x, edge), Color(0.8, 0.05, 0.05, a))
		overlay.draw_rect(Rect2(0, 0, edge, size.y), Color(0.8, 0.05, 0.05, a))
		overlay.draw_rect(Rect2(size.x - edge, 0, edge, size.y), Color(0.8, 0.05, 0.05, a))
