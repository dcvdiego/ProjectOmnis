class_name WeaponModel
extends Node3D
## Visual weapon: the imported mesh plus a `Muzzle` marker.
##
## Imported FBX weapons come with placeholder materials, so this assigns the
## project's PBR materials by surface name. Used for both the first-person
## view model and the gun in a third-person character's hand.

@export var body_material: Material
@export var ammo_material: Material
@export var sight_material: Material

@onready var muzzle: Marker3D = $Muzzle
## Where the first-person hands go (see `ArmIK`). Optional.
@onready var grip_right: Marker3D = get_node_or_null("GripR")
@onready var grip_left: Marker3D = get_node_or_null("GripL")
@onready var mag_well: Marker3D = get_node_or_null("MagWell")


func _ready() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for i in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(i)
			var surface_name := source.resource_name if source else ""
			var material := body_material
			if "BULLETS" in surface_name and ammo_material:
				material = ammo_material
			elif "Glow" in surface_name and sight_material:
				material = sight_material
			mesh_instance.set_surface_override_material(i, material)


## Turns shadow casting on or off for every mesh (view models don't cast).
func set_cast_shadows(enabled: bool) -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


## Puts every mesh on the given render layers (used to keep view models out of
## reflections and other cameras).
func set_layers(layers: int) -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).layers = layers
