class_name WeaponData
extends Resource
## Balance data for one weapon.
##
## Weapons live in `game/weapons/data/*.tres`, which are plain text, so a
## balance proposal is a small, reviewable diff. See docs/contributing.md.

@export var display_name := "Weapon"
## Damage per hit.
@export_range(1, 500) var damage := 20
@export_range(1.0, 2000.0) var rounds_per_minute := 600.0
## Hitscan range in metres.
@export_range(1.0, 1000.0) var max_range := 100.0
@export_range(1, 200) var magazine_size := 30
## Seconds.
@export_range(0.1, 10.0) var reload_time := 2.0

@export_group("Presentation")
## Visual model (a `WeaponModel` scene). Has no effect on balance.
@export var model: PackedScene
## Where the view model sits relative to the camera, in metres.
@export var view_offset := Vector3(0.16, -0.17, -0.32)
## Visual kick per shot, in degrees (camera and view model).
@export var recoil_kick := 0.8
## Third-person hold offset relative to the right hand.
@export var hand_offset := Transform3D.IDENTITY


func seconds_between_shots() -> float:
	return 60.0 / rounds_per_minute


func shots_to_kill(target_health: int) -> int:
	return ceili(float(target_health) / float(damage))


## Time from first to last shot needed to kill, assuming every shot hits.
func time_to_kill(target_health: int) -> float:
	return (shots_to_kill(target_health) - 1) * seconds_between_shots()
