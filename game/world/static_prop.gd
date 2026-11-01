class_name StaticProp
extends StaticBody3D
## Static scenery made from an imported model (e.g. a Poly Haven prop).
##
## Adds a box collider that fits the model's meshes when the map loads, so
## props can be dropped into a map as `StaticProp` + model instance without
## hand-authoring collision. Good enough for crates, barrels and barriers;
## complex shapes should get a hand-made collider instead.

## Shrinks the generated box a little so players don't snag on visual edges.
@export var margin := 0.02


func _ready() -> void:
	var bounds := AABB()
	var first := true
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var local := global_transform.affine_inverse() * mesh_instance.global_transform * mesh_instance.get_aabb()
		bounds = local if first else bounds.merge(local)
		first = false
	if first:
		return
	var shape := BoxShape3D.new()
	shape.size = (bounds.size - Vector3.ONE * margin * 2.0).max(Vector3.ONE * 0.05)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = bounds.get_center()
	add_child(collider)
