extends CharacterBody3D

## Youtube links
# https://www.youtube.com/watch?v=NJJNWGD25rg&t=607s
# https://www.youtube.com/watch?v=A3HLeyaBCq4
# https://www.youtube.com/watch?v=qo-NuxA99-c&ab_channel=CrookedSmileStudios

# Nodes 
@onready var head: Node3D = $Head
@onready var eyes: Node3D = $Head/Eyes
@onready var cam3d: Camera3D = %Camera3D

@onready var hand: Node3D = $Hand
@onready var flashlight: SpotLight3D = %SpotLight3D

@onready var standing_collshape: CollisionShape3D = $StandingColShape
@onready var crouching_collshape: CollisionShape3D = $CrouchingColShape
@onready var stand_up_check: RayCast3D = $StandUpCheck

@onready var interaction_raycast: RayCast3D = %InteractionRaycast


# Movement Settings 
@export_group("Movement")
@export_range(1.0, 8.0, 0.5) var WALK_SPEED : float = 3.0
@export_range(5.0, 15.0, 0.5) var SPRINT_SPEED : float = 6.0
@export_range(0.5, 3.0, 0.1) var CROUCH_SPEED : float = 1.0
@export_range(1.0, 10.0, 0.5) var CURR_SPEED : float = 0.0

@export_range(0.0, 20.0, 0.5) var JUMP_VELOCITY : float = 0.0
@export_range(-50.0, -5.0, 1.0) var GRAVITY : float = -20.0
@export_range(1.0, 20.0, 0.5) var LERP_SPEED : float = 10.0

@export_range(0.0, 5.0, 0.1) var HEAD_HEIGHT : float = 2.5
const CROUCH_DEPTH : float = -0.9

var moving : bool = false
var input_dir : Vector2 = Vector2.ZERO
var direction : Vector3 = Vector3.ZERO

# State Machines
enum PlayerState{
	IDLE_STAND,
	IDLE_CROUCH,
	CROUCHING,
	WALKING,
	SPRINTING,
	AIR
}
var player_state : PlayerState = PlayerState.IDLE_STAND

## Player Changeable Settings
@export_category("Player Customizable Settings")

# Camera Settings 
@export_group("Camera Settings")
@export_range(0.0, 10.0, 0.1) var MOUSE_SENSITIVITY : float = 0.2
@export_range(0.0, 180.0, 5.0) var CAM_X_CLAMP = 80.0  # degrees
@export_range(0.0, 180.0, 5.0) var BASE_FOV : float = 90.0

# Headbob Settings 
@export_group("Headbob Settings")
@export_range(0.0, 50.0, 0.5) var CROUCH_BOBSPEED : float = 10.0
@export_range(0.0, 50.0, 0.5) var WALK_BOBSPEED : float = 14.0
@export_range(0.0, 50.0, 0.5) var SPRINT_BOBSPEED : float = 25.0

@export var BOB_AMP = 0.08

@export var CROUCH_INTENSITY = 0.05
@export var WALK_INTENSITY = 0.1
@export var SPRINT_INTENSITY = 0.25

var CURR_INTENSITY : float = 0.0
var CURR_BOBVECTOR : Vector2 = Vector2.ZERO # xy representation of headbob
var CURR_BOBINDEX : float = 0.0 # how far along the sine function we are in the head bob

# Flashlight Settings
@export_group("Flashlight Settings") 
@export_range(1.0, 25.0, 0.5) var FLASHLIGHT_SPEED = 15.0
var delay_rotation : Basis
var light_on : bool = false

var door_is_closed : bool = false
var collider

# Variables
var t_bob = 0.0
var _initial_camera_pos: Vector3
var noise = FastNoiseLite.new()

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_initial_camera_pos = cam3d.transform.origin
	
	crouching_collshape.disabled = true
	
	noise.seed = randi()
	flashlight.visible = light_on

func _input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
	
	if Input.is_action_just_pressed("toggle_light"):
		light_on = not light_on
		flashlight.visible = light_on

	if event is InputEventMouseMotion:
		# Mouse movement rotates whole Player body on y-axis (left and right)
		rotate_y(deg_to_rad(-event.relative.x * MOUSE_SENSITIVITY))
		
		# and rotates Camera on x-axis (up and down)
		head.rotate_x(deg_to_rad(-event.relative.y * MOUSE_SENSITIVITY))
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))


func updatePlayerState() -> void:
	# If input direction is not zero, player is trying to move, set moving boolean true, 
	# or false if opposite is true
	moving = (input_dir != Vector2.ZERO)
	
	if not is_on_floor(): # Mid-air
		player_state = PlayerState.AIR
	
	else: # Grounded
		if Input.is_action_pressed("crouch"): # Crouching - holding crouch button
			if not moving: # while Idle
				player_state = PlayerState.IDLE_CROUCH
			else: # while Moving
				player_state = PlayerState.CROUCHING
		
		elif !stand_up_check.is_colliding(): # If NO object above player
			if not moving: # Standing idle
				player_state = PlayerState.IDLE_STAND
			elif Input.is_action_pressed("sprint"): # Running
				player_state = PlayerState.SPRINTING
			else: # Walking
				player_state = PlayerState.WALKING
	
	updatePlayerCollShape(player_state)
	updatePlayerSpeed(player_state)


func updatePlayerCollShape(curr_state : PlayerState) -> void:
	if curr_state == PlayerState.CROUCHING or curr_state == PlayerState.IDLE_CROUCH:
		standing_collshape.disabled = true
		crouching_collshape.disabled = false
	else:
		standing_collshape.disabled = false
		crouching_collshape.disabled = true


func updatePlayerSpeed(curr_state : PlayerState) -> void:
	if curr_state == PlayerState.CROUCHING or curr_state == PlayerState.IDLE_CROUCH:
		CURR_SPEED = CROUCH_SPEED
	elif curr_state == PlayerState.WALKING:
		CURR_SPEED = WALK_SPEED
	elif curr_state == PlayerState.SPRINTING:
		CURR_SPEED = SPRINT_SPEED


func updateCamera(delta : float)-> void:
	## Player is mid-air
	if player_state == PlayerState.AIR:
		pass
	
	## Crouching
	elif player_state == PlayerState.CROUCHING or player_state == PlayerState.IDLE_CROUCH:
		# Drop down camera to crouching depth
		head.position.y = lerp(head.position.y, HEAD_HEIGHT + CROUCH_DEPTH, delta * LERP_SPEED)
		cam3d.fov = lerp(cam3d.fov, BASE_FOV * 0.95, delta * LERP_SPEED) # lerp camera fov to be 0.95 smaller than base fov
		CURR_INTENSITY = CROUCH_INTENSITY
		CURR_BOBINDEX += CROUCH_BOBSPEED * delta
	
	## Idle
	elif player_state == PlayerState.IDLE_STAND:
		head.position.y = lerp(head.position.y, HEAD_HEIGHT, delta * LERP_SPEED)
		cam3d.fov = lerp(cam3d.fov, BASE_FOV, delta * LERP_SPEED)
		CURR_INTENSITY = WALK_INTENSITY
		CURR_BOBINDEX += WALK_BOBSPEED * delta
	
	## Walking
	elif player_state == PlayerState.WALKING:
		head.position.y = lerp(head.position.y, HEAD_HEIGHT, delta * LERP_SPEED)
		cam3d.fov = lerp(cam3d.fov, BASE_FOV * 1.05, delta * LERP_SPEED)
		CURR_INTENSITY = WALK_INTENSITY
		CURR_BOBINDEX += WALK_BOBSPEED * delta
	
	## Sprinting
	elif player_state == PlayerState.SPRINTING:
		head.position.y = lerp(head.position.y, HEAD_HEIGHT, delta * LERP_SPEED)
		cam3d.fov = lerp(cam3d.fov, BASE_FOV * 1.25, delta * LERP_SPEED)
		CURR_INTENSITY = SPRINT_INTENSITY
		CURR_BOBINDEX += SPRINT_BOBSPEED * delta
	
	## Camera bobbing
	CURR_BOBVECTOR.y = sin(CURR_BOBINDEX)
	CURR_BOBVECTOR.x = (sin(CURR_BOBINDEX)/2 + 0.5)
	
	if moving:
		eyes.position.y = lerp(eyes.position.y, CURR_BOBVECTOR.y * (CURR_INTENSITY/2.0), delta * LERP_SPEED)
		eyes.position.x = lerp(eyes.position.x, CURR_BOBVECTOR.x * (CURR_INTENSITY/2.0), delta * LERP_SPEED)
	else:
		eyes.position.y = lerp(eyes.position.y, 0.0, delta * LERP_SPEED)
		eyes.position.x = lerp(eyes.position.x, 0.0, delta * LERP_SPEED)


func updateFlashlight(delta : float) -> void:
	if light_on:
		delay_rotation = delay_rotation.slerp(cam3d.global_transform.basis, delta * FLASHLIGHT_SPEED)
		flashlight.global_transform = Transform3D(
			delay_rotation,
			flashlight.global_transform.origin.slerp(cam3d.global_transform.origin, delta * FLASHLIGHT_SPEED)
		)


# delta -> time between frames
func _physics_process(delta):
	updatePlayerState()
	
	## Falling
	if not is_on_floor():
		if velocity.y >= 0:
			velocity.y += GRAVITY * delta
		else: # Falling down
			velocity.y += GRAVITY * delta + 0.2
	
	else: # On ground -> Jump
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
	
	updateCamera(delta)
	updateFlashlight(delta)
	
	## Movement 
	# input_dir.x -> forward backward movement
	# input_dir.y -> left right movement
	input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	direction = lerp(direction, (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), delta * 10.0)
	
	if direction: # Player is moving
		velocity.x = direction.x * CURR_SPEED
		velocity.z = direction.z * CURR_SPEED
	else: # Player stops moving - slow down instead of stop immediately
		velocity.x = move_toward(velocity.x, 0, CURR_SPEED)
		velocity.z = move_toward(velocity.z, 0, CURR_SPEED)
	
	move_and_slide()

#func _process(delta: float) -> void:
	#if raycast.is_colliding():
		#door_label.show()
		#collider = raycast.get_collider()
		#if collider.name == "Door" and Input.is_key_pressed(KEY_E):
			#print("opening door")
	#else:
		#door_label.hide()
