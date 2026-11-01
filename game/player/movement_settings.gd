class_name MovementSettings
extends Resource
## Movement tuning. Like weapon data, this lives in a text `.tres`
## (`game/player/movement/default.tres`), so a tuning change is a small diff
## that can be playtested on an experimental server before it's merged.
##
## Units are metres and seconds. The defaults aim for a Titanfall / Apex
## feel: momentum you keep by chaining slides, jumps and wall-runs, with
## heavier-than-real gravity so jumps feel snappy instead of floaty.

@export_group("Ground")
@export var walk_speed := 5.0
@export var sprint_speed := 7.6
@export var crouch_speed := 3.0
## How quickly you reach the target speed on the ground (1/s).
@export var ground_accel := 12.0
@export var ground_friction := 7.0
## Below this speed friction acts as if you were going this fast, so you stop
## crisply instead of creeping (the Quake/Source "stop speed").
@export var stop_speed := 2.5

@export_group("Air")
@export var gravity := 20.0
@export var jump_height := 1.25
## Extra jumps in the air (Titanfall pilots have one).
@export_range(0, 3) var air_jumps := 1
@export var air_jump_height := 1.1
## Air acceleration. Combined with `air_speed_cap` this gives Source-style
## air strafing: turning smoothly while holding a strafe key bends (and can
## slightly build) your speed.
@export var air_accel := 60.0
@export var air_speed_cap := 1.0
## Jump pressed this long before landing still counts (seconds).
@export var jump_buffer := 0.12
## Jump still allowed this long after running off a ledge (seconds).
@export var coyote_time := 0.12
## Skip friction for this long after landing, so a buffered jump keeps speed
## (bunny hop / slide hop).
@export var landing_grace := 0.08

@export_group("Slide")
## Minimum speed to start a slide when crouching.
@export var slide_min_speed := 6.0
## Speed added when a slide starts (only if the boost isn't on cooldown).
@export var slide_boost := 2.5
@export var slide_boost_cooldown := 2.0
## Speed lost per second while sliding on flat ground.
@export var slide_decel := 3.6
## Extra acceleration from gravity on slopes while sliding.
@export var slide_slope_gravity := 14.0
## Slide ends below this speed.
@export var slide_exit_speed := 3.2
## Upper speed limit while sliding, so slopes don't launch you forever.
@export var slide_max_speed := 16.0

@export_group("Wall-run")
@export var wallrun_enabled := true
@export var wallrun_min_speed := 4.0
@export var wallrun_speed := 9.0
@export var wallrun_accel := 6.0
## Fraction of gravity applied while wall-running.
@export_range(0.0, 1.0) var wallrun_gravity_scale := 0.15
@export var wallrun_max_time := 1.8
## Speed away from the wall when jumping off it.
@export var walljump_push := 6.0
@export var walljump_height := 1.2
## How far to look for a wall (from the capsule surface).
@export var wall_probe := 0.45

@export_group("Mantle")
@export var mantle_enabled := true
## Ledges between these heights above your feet can be climbed.
@export var mantle_min_height := 0.55
@export var mantle_max_height := 2.0
@export var mantle_time := 0.3

@export_group("Body")
@export var stand_height := 1.8
@export var crouch_height := 1.1
@export var eye_offset := 0.16
@export var max_speed := 25.0


func jump_velocity() -> float:
	return sqrt(2.0 * gravity * jump_height)


func air_jump_velocity() -> float:
	return sqrt(2.0 * gravity * air_jump_height)


func walljump_velocity() -> float:
	return sqrt(2.0 * gravity * walljump_height)
