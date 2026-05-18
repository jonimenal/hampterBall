extends CharacterBody2D

# tinkering variables
	#movemnet
const trueSPEED = 60
var SPEED = trueSPEED
const ACCELERATION = 10.0
@export var grounded_max_speed := 1.1
@export var grounded_acceleration := 2.0
@export var onAir_max_speed := 1.5
@export var onAir_acceleration := 1.0
@export var onBall_max_speed := 2.5
@export var onBall_acceleration := 0.5
	#jumping
@export var jump_height = 60
#@export var jump_velocity : float
@export var jump_peak_time : float
@export var jump_drop_time : float
@export var gravityJ : float
@export var gravityF : float
		# jump buffer stuff
@export var jump_buffer_time : float
var jump_buffer : bool = false
		# coyote time stuff
var noCoyoteTime = false

# fastfall
@export var fastfall_power : float

# landing
var landingSpeed = 0

# pull ball force
@export var pull_force : float
# timers
@export var exit_ball_timer: Timer
@onready var ball_switch_cooldown: Timer = $ball_switch_cooldown
@onready var jump_timer: Timer = $JumpTimer # include jumpTimer node
@onready var coyote_timer: Timer = $coyoteTimer
@onready var dash_delay_timer: Timer = $dashDelayTimer


@onready var jump_velocity : float = ((2.0 * jump_height) / jump_peak_time) * -1.0 # use this to calculate a velocity that respects height
@onready var jump_gravity : float = ((gravityJ * jump_height) / (jump_peak_time * jump_peak_time)) * -1.0
@onready var fall_gravity : float = ((gravityF * jump_height) / (jump_drop_time * jump_drop_time)) * -1.0

# dashing
var dashDelayOver = false
@export var dash_speed := 50.0
@onready var dash_timer: Timer = $dashTimer
var dashing = false
# player direction
var xyDirection = Input.get_vector("left","right", "up", "down")
var direction = Input.get_axis("left", "right")
# collisions
const push = 10
var pushForce = push
# ball
var donut_cols = []
var ballLink = Vector2.ZERO
var shouldBeInBall = false

# include nodes
@onready var hampter: CharacterBody2D = $"."
@onready var hampterSprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hampterCollision: CollisionShape2D = $CollisionShape2D
@onready var ball: RigidBody2D = $"../ball"
@onready var scan_area: CollisionShape2D = $"../ball/TopScan2/scanArea" # collision of top ball scanner
@onready var ball_scanner: Area2D = $"../ball/TopScan2" # top ball scanner itself
@onready var ball_collision_shape: CollisionShape2D = $"../ball/ballCollisionShape2D" # ball smooth collision
@onready var ball_collision_polygon: CollisionPolygon2D = $"../ball/CollisionPolygon2D" # ball blocky collision

# variables
	# ball relationship
var insideBall = false
var ballMagnet = false
var magnetForce = 0
var teleporting = false
	# speed
var currentSpeed = 0
	# pastFrame checks
var pastDirection = 0
var pastFlip = false
var wasOnFloor = false
var wasOnAir = false
var wasDashing = false
var dashDelaying = false
var currentPosition = null 

# for animation
var state = "idle"
var spriteBusy = false
var turnedDuringLand = false

# MY FUNCTIONS
# jump gravity function (define what type of gravity is applied) i think it only affects up n down
func get_jump_gravity() -> float:
	return jump_gravity if velocity.y < 0.0 else fall_gravity
func jump():
	#print("player pressed jump")
	velocity.y = jump_velocity
func dash(): # dashing logic
	xyDirection = Input.get_vector("left","right", "up", "down")
	velocity = xyDirection.normalized() * dash_speed
	# add a slight x boost
	velocity.x = xyDirection.x * dash_speed * 1.4
	# add a sligh y boost too
	velocity.y = xyDirection.y * dash_speed * 1.25
	if dashing: # lower dash speed progressivelly (dash counter speed)
		velocity = velocity.move_toward(Vector2.ZERO, dash_speed/4)
		pushForce = 400
func pull_ball(delta):
		ball.apply_central_impulse((-1 * ballLink).normalized() * Vector2(1, 1.5) * pull_force)
		ball.mass = 1
		scan_area.shape.radius = 70
		scan_area.shape.height = 50
		scan_area.position.y = 0
		velocity += ballLink.normalized() * 400 * delta
		magnetForce = 0
		set_collision_mask_value(2, false)
func tp_to_ball(intentional : bool = false):
	#print("TP TO BALL")
	teleporting = true
	if intentional == true:
		#print("start switch cooldown")
		ball_switch_cooldown.start()
	if shouldBeInBall == false:
		shouldBeInBall = true
	if !ball_collision_shape.disabled:
		ball_collision_shape.set_deferred("disabled", true)
		for donut in donut_cols:
			donut.set_deferred("disabled", false)
	global_position = ball.global_position
	#ball.apply_central_impulse(Vector2.ZERO) # reset ball momentum
	velocity = Vector2.ZERO # reset hampter momentum
	#ball.physics_material_override.bounce = 0

# GODOT GAME ENV FUNCTIONS

func _ready(): # runs on game startup, when everything is ready ig
	#Engine.time_scale = 0.2
	# create donut collision for ball
	for gormiti in range(360):
		var angle = gormiti*2*PI/90
		var shape = CircleShape2D.new()
		shape.radius = 1
		var donut = CollisionShape2D.new()
		donut.shape = shape
		donut.position = Vector2(16*cos(angle), sin(angle)*16)
		donut.disabled = true
		donut_cols.append(donut)
		ball.add_child(donut)
	hampterSprite.animation_finished.connect(func():
		#print("animation finished")
		spriteBusy = false
		if turnedDuringLand:
			hampterSprite.play("quickTurn")
			spriteBusy = true
			turnedDuringLand = false
	)
func _input(_InputEvent) -> void: # runs anytime an input from the player is pressed
	# get player current direction
	xyDirection = Input.get_vector("left","right", "up", "down")
	
	# Handle jump
	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			jump()
			noCoyoteTime = true
		elif !is_on_floor() and noCoyoteTime == false:
			print("coyote")
			jump()
			noCoyoteTime = true
		else:
			jump_buffer = true
			get_tree().create_timer(jump_buffer_time).timeout.connect(on_jump_buffer_timeout)
		jump_timer.start()
	
	# Handle dash input
	if Input.is_action_just_pressed("dash") and not dashing and !wasDashing:
		print("start time")
		currentPosition = global_position
		dash_delay_timer.start() # prepare delay
	
	# Handle ball exit
	if Input.is_action_just_pressed("ball") and insideBall and ball_switch_cooldown.time_left == 0:
		print("cooldown over")
		exit_ball_timer.start()
		print("trigger ball exit")
		shouldBeInBall = false
		set_collision_mask_value(2, false)
	# Handle ball jump
	if Input.is_action_just_pressed("jump") and insideBall:
		pushForce = 200
		velocity = velocity * 2
	if Input.is_action_just_released("jump") and insideBall:
		pushForce = push
func _process(_delta: float) -> void: # runs on a loop (framerate depends on hardware)
	if !dash_delay_timer.is_stopped():
		#print("dash delaying")
		dashDelaying = true
func _physics_process(delta: float) -> void: # runs on a loop at a fixed framerate
	
	xyDirection = Input.get_vector("left","right", "up", "down") # update to player current direction
	var just_landed = is_on_floor() and wasOnAir # this var needs to be here, idk why but it does.
	ballLink = ball.global_position - global_position # update ball link
	# Anti clippling inside the ball
	if shouldBeInBall:
		hampter.safe_margin = 0.00001 # making safe margin bigger
	else:
		hampter.safe_margin = 1
	if insideBall:
		if ball.linear_velocity.length_squared() > 40000:
			#print("pretty fast ball")
			#print(ball.linear_velocity.length_squared())
			tp_to_ball()
		else:
			teleporting = false
	if shouldBeInBall and insideBall == false:
		print("should be in ball, teleporting")
		tp_to_ball()
	else:
		teleporting = false
	# Handle dashing (needs to be in physics instead of input)
	if dashDelaying: # stop hampter if preparing for dash
		global_position = currentPosition
	if dashDelayOver: # apply dashing logic
		print("dealy time over")
		dash_timer.start() # TODO fix dash timer jankyness, gravity pulls while delay is active
		# It's missing a position pinning, like making hampter freeze on the air while the delay is playing.
		dashing = true
		wasDashing = true
		dashDelayOver = false
		# dash logic:
		if is_on_floor(): # grounded dashes
			velocity = xyDirection.normalized() * dash_speed
			if velocity.y >= 0:
				velocity.y = -dash_speed / 2
						#if Input.is_action_pressed("up"):
							#dash()
						#elif Input.is_action_pressed("left") and not Input.is_action_pressed("up"):
						#elif Input.is_action_pressed("right") and not Input.is_action_pressed("up"):
							## dash up right
							#velocity.x = 247.4874
							#velocity.y = -247.4874
						#else:
							#velocity.y = -350
							#state = "idle"
		# air dashes:
		elif xyDirection == Vector2.ZERO:
			velocity.y = -dash_speed / 1.1
		else:
				dash()
	else:
		if not insideBall: # bandaid for error where pushForce was reset while jumping inside ball
			pushForce = push # reset push force
	# reset dash permission
	if is_on_floor():
		wasDashing = false
	# Handle gravity (y axis / y logic)
	if not dashDelaying and teleporting == false:
		
			if wasDashing:
				velocity.y += (get_jump_gravity()/2) * delta
			elif not is_on_floor() and not ballMagnet:
				if not dashing:
					velocity.y += get_jump_gravity() * delta
				#else:
					#print("dashing on air")
			else:
				if jump_buffer:
					jump()
					jump_buffer = false
					print("jump buffer")
	
	# Handle movement (x axis/x logic)
	direction = Input.get_axis("left", "right") # update axis
	if not dashing and not dashDelaying: # block movement logic if player is dashing
		if wasDashing and not is_on_floor(): # apply smoother ease if player was dashing
			var target = direction * SPEED * onAir_max_speed
			if abs(velocity.x) > abs(target) and sign(velocity.x) == sign(direction):
				velocity.x = move_toward(velocity.x * 0.7, target, ACCELERATION * onAir_acceleration * 0.3)
			else:
				velocity.x = move_toward(velocity.x, target, ACCELERATION * onAir_acceleration)
			currentSpeed = velocity.x
		else:
			if direction:
				if ballMagnet: # change movement logic if player is on ball
					velocity.x = move_toward(currentSpeed, -1 * (direction * SPEED * onBall_max_speed), ACCELERATION * onBall_acceleration)
					currentSpeed = velocity.x
				elif not is_on_floor(): # change speed while on air
					velocity.x = move_toward(currentSpeed, direction * SPEED * onAir_max_speed, ACCELERATION * onAir_acceleration )
					currentSpeed = velocity.x
				else: # normal logic
					velocity.x = move_toward(currentSpeed, direction * SPEED * grounded_max_speed, ACCELERATION * grounded_acceleration )
					currentSpeed = velocity.x
			else:
				velocity.x = move_toward(currentSpeed, 0, ACCELERATION * 2.5 )
			currentSpeed = velocity.x
		
	# Handle jump key while holding
	if Input.is_action_pressed("jump") and jump_timer.time_left != 0 and velocity.y < 0:
		velocity.y += move_toward(velocity.y, jump_velocity * 20 * delta, 2000)
	
	# Handle Fastfall
	if Input.is_action_just_released("jump") and not is_on_floor():
		velocity.y += ( get_gravity().y * delta ) * fastfall_power

	# Handle landing
	var landingAnim = false
	if just_landed:
		print(currentSpeed)
		landingSpeed = currentSpeed
		print(currentSpeed)
		noCoyoteTime = false
		coyote_timer.stop()
		hampterSprite.rotation = 0
		hampterSprite.stop()
		hampterSprite.play("land")
		spriteBusy = true
		landingAnim = true
		state = "land"
		if Input.is_action_pressed("left") or Input.is_action_pressed("right"):
			turnedDuringLand = true
	if state == "land":
		print("landingSpeed: ", landingSpeed)
		velocity.x = move_toward(landingSpeed / 35, landingSpeed, abs(currentSpeed) * 0.6)
		currentSpeed = velocity.x
		print("LANDING ANIMATION: ")
		print(velocity.x)
		print(currentSpeed)
	# BALL INTERACTION MECHANICS
	# Handle magnet
	if ballMagnet == true and not Input.is_action_pressed("jump") and not insideBall:
		velocity += ballLink.normalized() * 35000 * delta # define magnet strength
		# ease ball jitter
		if ball.linear_velocity.y < 10:
			ball.linear_velocity.y = 0
		# change scanner shape to an orbit
		scan_area.shape.radius = move_toward(scan_area.shape.radius, 28, 0.5)
		scan_area.shape.height = move_toward(scan_area.shape.height, 0.2, 0.5)
		scan_area.position.y = move_toward(scan_area.position.y, 0, 0.05)
		
		# prevent side orbiting bug when momentum was interrupted
		# ERROR?? can't go fast on the ball due to momentum
		# ig on top of the ball could be more of a slow, with more control OVER the ball mechanic yk?
		
		#if state == "turning": # lower while turning
			## drastically lower player velocity
			#velocity.x = move_toward(velocity.x, 0, 4000)
			#velocity.y = move_toward(velocity.y, 0, 2000)
			## drastically lower ball velocity
			#ball.linear_velocity.x = move_toward(ball.linear_velocity.x,0, 4000)
			#ball.linear_velocity.y = move_toward(ball.linear_velocity.y,0, 4000)
			#ball.physics_material_override.friction = 500 # increase ball friction
			##print("momentum stopped: ", SPEED) # DEBUG
			#pass
			
		# ^^ this whole if block is removed, the sideways movement is controlled on the movement Handling
		
		# PREVENT SLIPPING OFF THE BALL WHEN STOPPING
		if xyDirection == Vector2.ZERO: # lower while stopped
			velocity.x = move_toward(velocity.x, 0, 10)
			velocity.y = move_toward(velocity.y, 0, 10)
			ball.linear_velocity.x = move_toward(ball.linear_velocity.x,0, 10)
			ball.linear_velocity.y = move_toward(ball.linear_velocity.y,0, 10)
			#print("momentum stopped: ", SPEED) # DEBUG
	else: 
		# reset scan shape
		scan_area.shape.radius = 10
		scan_area.shape.height = 32
		scan_area.position.y = -8
	
	# Handle pull ball button | needs to be here instead of input, because it interacts with physics real-time
	if Input.is_action_pressed("ball") and not insideBall and exit_ball_timer.time_left == 0 and ball_switch_cooldown.time_left == 0:
		pull_ball(delta)
		if ballMagnet == true and insideBall == false: # teleport (tp inside ball)
			tp_to_ball(true)
	if Input.is_action_pressed("ball") and shouldBeInBall:
		set_collision_mask_value(2, true)
	# reset scanner shape (from orbit back to small)
	if Input.is_action_just_released("ball"):
		scan_area.shape.radius = 10
		scan_area.shape.height = 32
		scan_area.position.y = -8
		#and collision mask
		set_collision_mask_value(2, true)
		
	# STYLING AND ANIMATIONS OF SPRITE
	# Flip sprite depending on direction (needs to be before state machine)
	if direction < 0:
		hampterSprite.flip_h = true
	elif direction > 0:
		hampterSprite.flip_h = false
	else:
		hampterSprite.rotation = 0
	# Handle state machine
	if not landingAnim:
		if dashDelaying:
			hampterSprite.play("dashDelay")
			state = "dashDelay"
		elif dashDelayOver or dashing:
			hampterSprite.play("dash")
			spriteBusy = true
			state = "dash"
		elif Input.is_action_just_pressed("jump") and is_on_floor():
			hampterSprite.stop()
			hampterSprite.play("jump")
			state = "jump"
			spriteBusy = true
		elif pastFlip != hampterSprite.flip_h and is_on_floor():
			state = "turning"
			spriteBusy = true
			print("turning")
			hampterSprite.stop()
			hampterSprite.play("turn")
		elif is_on_floor() and currentSpeed != 0 and direction != pastDirection:
			state = "stop"
		elif not spriteBusy:
			if !is_on_floor():
				state = "onAir"
			elif direction != 0:
				state = "walking"
			else:
				state = "idle" 
	# Animate
	if state == "stop":
		hampterSprite.play("stop")
		#print("stop")
		spriteBusy = false
	elif not spriteBusy:
		if state == "onAir":
			#print("onAir")
			hampterSprite.play("onAir")
		elif state == "walking":
			#print("walking")
			hampterSprite.play("walk")
		else:
			#print("idle")
			state = "idle"
			hampterSprite.play("idle")
	# Add onAir pizazz (needs to be on its own to trigger constantly)
	if not is_on_floor(): # do it only while airbone
		if hampterSprite.animation == "dash" or dashDelaying:
			if velocity.x > 0:
				hampterSprite.rotation = 45+(atan2(velocity.y, velocity.x))#*solveFlip
			else:
				hampterSprite.rotation = 90+(atan2(velocity.y, velocity.x))
		elif dashDelaying:
			if xyDirection != Vector2.ZERO:
				if xyDirection.x > 0:
					hampterSprite.rotation = (atan2(velocity.y, velocity.x))#*solveFlip
				else:
					hampterSprite.rotation = (atan2(velocity.y, velocity.x))

	# Update past variables
	if direction != 0:
		pastDirection = sign(direction)
	pastFlip = hampterSprite.flip_h
	wasOnAir = not is_on_floor()
	wasOnFloor = is_on_floor()
	
	if teleporting:
		velocity = Vector2.ZERO
	
	if not dashDelaying: #lock move and slide if dashDelaying
		if not teleporting: # also lock if teleporting
			move_and_slide() # trigger movement

	# check coyote time
	# TODO coyote causes double jump if key is spammed
	if wasOnFloor and not is_on_floor():
		coyote_timer.start()
	
	# push ball
	# TODO: fix collision issues, clipping outside when inside the ball
	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		# print(c.get_collider()) DEBUG, the collision sometimes triggers on the TileMapLayer while inside the ball
		if c.get_collider() is RigidBody2D:
			if sign(c.get_normal().x) == sign(direction):
				velocity.x *= 0.01
			c.get_collider().apply_central_impulse(-c.get_normal() * pushForce)

# SIGNAL CHECKS
func _on_top_scan_2_body_entered(_body: Node2D) -> void: # check if hampte ON top of ball
	ballMagnet = true
	#print("body entered")
func _on_top_scan_2_body_exited(_body: Node2D) -> void: # check if shambper OFF top of ball
	ballMagnet = false
	#print("body exit")
	SPEED = trueSPEED
	#print("speed is: ", SPEED)
func _on_inside_ball_body_entered(_body: Node2D) -> void: # check if gampter INSIDE ball
	print("hampter inside ball")
	insideBall = true
	teleporting = false
	# swtich collisions
	ball_collision_shape.set_deferred("disabled", true) 
	for donut in donut_cols:
		donut.set_deferred("disabled", false)
	# disable magnet scanner
	ball_scanner.monitoring = false
	# Tinker IN BALL ball physics
	ball.mass = 1.8
	ball.physics_material_override.bounce = 0.2
func _on_inside_ball_body_exited(_body: Node2D) -> void: # check if gfasmper OUTSIDE ball
	print("hampter free")
	insideBall = false
	#switch collisions back
	ball_collision_shape.set_deferred("disabled", false)
	for donut in donut_cols:
		donut.set_deferred("disabled", true)
	# enable magnet scanner
	ball_scanner.monitoring = true
	# Tinker OUT BALL ball physics
	ball.mass = 2
	ball.physics_material_override.bounce = 0.6
	ball.gravity_scale = 1.0
func _on_exit_ball_timer_timeout() -> void: # check if exit ball timer is over
	## switch collisions back to OUTSIDE ball
	#ball_collision_shape.set_deferred("disabled", false)
	#for donut in donut_cols: # disable inner ball collision
		#donut.set_deferred("disabled", true)
	ball_scanner.monitoring = true
func on_jump_buffer_timeout()->void: # check if jump buffer is valid (timer ended)
	jump_buffer = false
func _on_coyote_timer_timeout() -> void: # check if coyote timer ended
	noCoyoteTime = true
func _on_dash_delay_timer_timeout() -> void: # check if dash delay ended
	dashDelayOver = true
	dashDelaying = false
func _on_dash_timer_timeout() -> void: # check if dash ended
	dashing = false
func _on_ball_switch_cooldown_timeout() -> void: # check if tp cooldown over
	# *fix for constant tp in/out while holding pull button inside ball right after teleporting in
	pass
