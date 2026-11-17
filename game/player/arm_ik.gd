class_name ArmIK
extends SkeletonModifier3D
## Puts the first-person arms' hands on the weapon: analytic two-bone IK per
## arm (shoulder → elbow → wrist), the hand rotated to match a grip marker,
## and fingers curled around the grip. It also collapses the head and legs,
## which are never meant to be seen in first person.
##
## Grip markers live on the weapon scenes (`GripR`, `GripL`). Their position is
## the wrist; their -Z is the direction from wrist to knuckles; +Y is the back
## of the hand. Pole nodes pull the elbows (down and out).

const FINGERS := ["index", "middle", "ring", "pinky"]

## Targets (wrist position + hand orientation) and elbow poles, per side.
var right_target: Node3D
var left_target: Node3D
var right_pole: Node3D
var left_pole: Node3D
## 0..1 blend of each hand onto its target (e.g. the left hand leaves the gun
## while reloading).
var left_weight := 1.0
## Finger curl in radians for proximal / middle / distal joints.
var curl := Vector3(1.15, 1.25, 0.8)
var left_curl := Vector3(1.0, 1.1, 0.7)

var _arms := {}  # side -> {upper, lower, hand, fingers, thumb, finger_dir, back_dir}


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for side: String in ["r", "l"]:
		var hand := skeleton.find_bone("hand_" + side)
		var rest_hand := skeleton.get_bone_global_rest(hand)
		var middle := skeleton.get_bone_global_rest(skeleton.find_bone("middle_01_" + side)).origin
		var thumb := skeleton.get_bone_global_rest(skeleton.find_bone("thumb_01_" + side)).origin
		var finger_dir := (middle - rest_hand.origin).normalized()
		# T-pose palms face down, so the back of the hand is +Y. Use the thumb
		# side to make the frame exact for this rig.
		var side_dir := (thumb - rest_hand.origin).normalized()
		var back := finger_dir.cross(side_dir).normalized()
		if back.y < 0.0:
			back = -back
		var fingers: Array[int] = []
		for f: String in FINGERS:
			for j in 3:
				fingers.append(skeleton.find_bone("%s_%02d_%s" % [f, j + 1, side]))
		var thumbs: Array[int] = []
		for j in 3:
			thumbs.append(skeleton.find_bone("thumb_%02d_%s" % [j + 1, side]))
		_arms[side] = {
			"upper": skeleton.find_bone("upperarm_" + side),
			"lower": skeleton.find_bone("lowerarm_" + side),
			"hand": hand,
			"fingers": fingers,
			"thumbs": thumbs,
			"rest_hand_basis": rest_hand.basis.orthonormalized(),
			"rest_frame": _frame(finger_dir, back),
		}


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or _arms.is_empty():
		return
	_hide(skeleton, "neck_01")
	_hide(skeleton, "thigh_l")
	_hide(skeleton, "thigh_r")
	_solve(skeleton, _arms.r, right_target, right_pole, 1.0, curl)
	_solve(skeleton, _arms.l, left_target, left_pole, left_weight, left_curl)


func _hide(skeleton: Skeleton3D, bone_name: String) -> void:
	var bone := skeleton.find_bone(bone_name)
	if bone >= 0:
		skeleton.set_bone_pose_scale(bone, Vector3.ONE * 0.001)


func _solve(skeleton: Skeleton3D, arm: Dictionary, target: Node3D, pole: Node3D, weight: float,
		finger_curl: Vector3) -> void:
	if target == null or pole == null or weight <= 0.0:
		return
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var goal := to_skeleton * target.global_transform
	var pole_position := to_skeleton * pole.global_position
	var upper: int = arm.upper
	var lower: int = arm.lower
	var hand: int = arm.hand

	# Curl the fingers (local rotations on top of the rest pose).
	for i: int in arm.fingers.size():
		var bone: int = arm.fingers[i]
		var angle: float = [finger_curl.x, finger_curl.y, finger_curl.z][i % 3] * weight
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
			* Quaternion(Vector3.RIGHT, angle))
	for j: int in arm.thumbs.size():
		var bone: int = arm.thumbs[j]
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
			* Quaternion(Vector3.RIGHT, 0.35 * weight))

	var a := skeleton.get_bone_global_pose(upper).origin
	var b := skeleton.get_bone_global_pose(lower).origin
	var c := skeleton.get_bone_global_pose(hand).origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var wrist := c.lerp(goal.origin, weight)
	var to_goal := wrist - a
	var d := clampf(to_goal.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir := to_goal.normalized()
	# Elbow sits in the plane of shoulder, wrist and pole.
	var bend := pole_position - a
	bend = (bend - dir * bend.dot(dir)).normalized()
	if bend == Vector3.ZERO:
		bend = Vector3.DOWN
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var elbow := a + dir * (l1 * cos_a) + bend * (l1 * sqrt(1.0 - cos_a * cos_a))
	var reach := a + dir * d

	_aim_bone(skeleton, upper, b, elbow)
	_aim_bone(skeleton, lower, skeleton.get_bone_global_pose(hand).origin, reach)

	# Hand orientation: map the rest frame (fingers, back of hand) onto the
	# target's (-Z, +Y).
	var goal_frame := _frame(-goal.basis.z.normalized(), goal.basis.y.normalized())
	var rotation := goal_frame * (arm.rest_frame as Basis).transposed()
	var hand_pose := skeleton.get_bone_global_pose(hand)
	var current := hand_pose.basis.orthonormalized()
	var wanted := (rotation * (arm.rest_hand_basis as Basis)).orthonormalized()
	var blended := current.get_rotation_quaternion().slerp(wanted.get_rotation_quaternion(), weight)
	skeleton.set_bone_global_pose(hand, Transform3D(Basis(blended), hand_pose.origin))


## Rotates `bone` so its child (currently at `child_position`) points at `goal`.
func _aim_bone(skeleton: Skeleton3D, bone: int, child_position: Vector3, goal: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var from := (child_position - pose.origin).normalized()
	var to := (goal - pose.origin).normalized()
	if from.is_equal_approx(to) or from == Vector3.ZERO or to == Vector3.ZERO:
		return
	var turn := Quaternion(from, to)
	skeleton.set_bone_global_pose(bone, Transform3D(Basis(turn) * pose.basis, pose.origin))


static func _frame(forward: Vector3, up: Vector3) -> Basis:
	var x := forward.normalized()
	var y := (up - x * up.dot(x)).normalized()
	return Basis(x, y, x.cross(y))
