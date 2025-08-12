extends Node3D

@onready var hinge: HingeJoint3D = $DoorFrame/HingeJoint3D
@onready var door: RigidBody3D = $Door
@onready var close_door: Timer = $CloseDoor

@export var reset_speed : float = 2.0
@export var return_strength = 8.0
var origin_orientation : Vector3


func _physics_process(delta):
	# Calculate torque to return to center (0 degrees)
	var current_angle = door.rotation.y
	var torque = -current_angle * return_strength

	# Apply torque around the Y axis (hinge axis)
	door.apply_torque_impulse(Vector3(0, torque * delta, 0))


func _on_close_door_timeout() -> void:
	door.collision_mask = 2
	await get_tree().create_timer(0.2).timeout
	door.collision_mask = 1


func _on_area_3d_body_entered(_body: Node3D) -> void:
	close_door.start()
