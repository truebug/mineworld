## Visual puppet for a MuJoCo-authoritative dynamic_prop (T4.6 push box).
## Follows base_pose from gateway state; no local physics.
class_name MWPropPuppet
extends Node3D

@export var entity_id: String = "prop_crate"
@export var box_size: Vector3 = Vector3(0.06, 0.06, 0.06)

var _mesh: MeshInstance3D


func _ready() -> void:
	_ensure_mesh()


func _ensure_mesh() -> void:
	"""Build a simple box mesh if missing."""
	if _mesh != null:
		return
	_mesh = MeshInstance3D.new()
	_mesh.name = "Box"
	var box := BoxMesh.new()
	box.size = box_size
	_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.48, 0.22)
	mat.roughness = 0.7
	_mesh.material_override = mat
	add_child(_mesh)


func apply_state(entity: Dictionary, _t_sim: float) -> void:
	"""Snap to authority pose (MW Z-up → Godot Y-up)."""
	_ensure_mesh()
	var pose: Dictionary = entity.get("base_pose", {})
	var x := float(pose.get("x", 0.0))
	var y := float(pose.get("y", 0.0))
	var z := float(pose.get("z", 0.25))
	position = Vector3(x, z, -y)
	rotation.y = float(pose.get("yaw", 0.0))
