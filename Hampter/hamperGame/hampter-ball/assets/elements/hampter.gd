extends CharacterBody2D

# movemnet
const trueSPEED = 60
var SPEED = trueSPEED
const ACCELERATION = 10.0
@export var grounded_max_speed := 1.1
@export var grounded_acceleration := 2.0
@export var onAir_max_speed := 1.5
@export var onAir_acceleration := 1.0
@export var onBall_max_speed := 2.5
@export var onBall_acceleration := 0.5

# jump vars
@export var jump_height = 60
#@export var jump_velocity : float
@export var jump_peak_time : float
@export var jump_drop_time : float
@export var gravityJ : float
@export var gravityF : float
var wasJumping = false
var cancelJump = false
# jump buffer stuff
@export var jump_buffer_time : float
var jump_buffer : bool = false
# coyote time vars
var noCoyoteTime = false
# fastfall vars
@export var fastfall_power : float
# landing vars
var landingSpeed = 0
# roll vars
var rolling = false
var canRoll = true
var rollFrames = 0
var holdingRoll = false
# pull ball force
@export var pull_force : float
# timers
@export var exit_ball_timer: Timer
@onready var ball_switch_cooldown: Timer = $ball_switch_cooldown
@onready var jump_timer: Timer = $JumpTimer # include jumpTimer node
@onready var coyote_timer: Timer = $coyoteTimer
@onready var dash_delay_timer: Timer = $dashDelayTimer
@onready var ball_bail_timer: Timer = $ballBailTimer
# gravity logic variables
@onready var jump_velocity : float = ((2.0 * jump_height) / jump_peak_time) * -1.0 # use this to calculate a velocity that respects set height
@onready var jump_gravity : float = ((gravityJ * jump_height) / (jump_peak_time * jump_peak_time)) * -1.0
@onready var fall_gravity : float = ((gravityF * jump_height) / (jump_drop_time * jump_drop_time)) * -1.0
@onready var real_fall_gravity : float = ((-18 * jump_height) / (jump_drop_time * jump_drop_time)) * -1.0 # same formula as fall gravity
@onready var fastfall_gravity : float = ((-80 * jump_height) / (jump_drop_time * jump_drop_time)) * -1.0 # same formula as fall gravity
@onready var dash_gravity: float = ((-14 * 20) / (0.4 * 0.4)) * -1.0 # same formula as jump_gravity
@onready var dash_fall_gravity : float = ((-17 * 20) / (0.9 * 0.9)) * -1.0 # same formula as fall_gravity
# dash vars (dashing vars)
var dashDelayOver = false
var dashLock = false
@export var dash_speed := 50.0
@onready var dash_timer: Timer = $dashTimer
var dashing = false
var groundedDash = false

# player direction
var xyDirection = Input.get_vector("left","right", "up", "down")
var direction = Input.get_axis("left", "right")

# collisions
const push = 10
var pushForce = push

# ball vars
var donut_cols = []
var ballLink = Vector2.ZERO
var shouldBeInBall = false
var ballJumping = false
var ballJumpLock = false
var ballDownFrames = 0
var ballWasGoingDown = false
var ballGoingUp = false
var exitTimerOver = false
var bailCount = 0
var ballBailTime = 0
var bailTiming = false
var bail = false
var ballDashDelay = false
var ballDelayFrames = 0
var ballDash = false
var ballInitPosition : Vector2

# include nodes (hampter vars)
@onready var hampter: CharacterBody2D = $"."
@onready var hampterSprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hampterCollision: CollisionShape2D = $CollisionShape2D
@onready var ball: RigidBody2D = $"../ball"
@onready var scan_area: CollisionShape2D = $"../ball/TopScan2/scanArea" # collision of top ball scanner
@onready var ball_scanner: Area2D = $"../ball/TopScan2" # top ball scanner itself
@onready var ball_collision_shape: CollisionShape2D = $"../ball/ballCollisionShape2D" # ball smooth collision
# ball donut colision is called on ready... i think? idk just Find: gormiti

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
	if not wasDashing: # do jump gravity
		if velocity.y < 0.0:
			return jump_gravity
			#print("jump gravity")
		elif wasJumping and cancelJump == false:
			#print("jumping gravity")
			return fall_gravity
		else:
			#print("normal fall gravity")
			return real_fall_gravity
	else: # do dash gravity
		if velocity.y < 0.0:
			return dash_gravity
		else: 
			return dash_fall_gravity
func jump():
	wasJumping = true
	if not state == "land":
		velocity.y = jump_velocity
	else:
		velocity.y = jump_velocity/1.3
func tp_to_ball(intentional : bool = false):
	# check double ball click for person to exit tp loop
	if not bail: # block tp is bailing is true
		#print("TP TO BALL")
		teleporting = true
		if intentional == true:
			ball_switch_cooldown.start()
		if shouldBeInBall == false: # make sure this bool is true
			shouldBeInBall = true
		if !ball_collision_shape.disabled: # switch collisions
			ball_collision_shape.set_deferred("disabled", true)
			for donut in donut_cols:
				donut.set_deferred("disabled", false)
		global_position = ball.global_position - Vector2(0, 6) # teleport

# GODOT GAME ENV FUNCTIONS

func _ready(): # runs on game startup, when everything is ready ig
	#Engine.time_scale = 0.2
	for gormiti in range(90): # create donut collision for ball
		var angle = gormiti*2*PI/90
		var shape = CircleShape2D.new()
		shape.radius = 1.5
		var donut = CollisionShape2D.new()
		donut.shape = shape
		donut.position = Vector2(15*cos(angle), sin(angle)*15)
		donut.disabled = true
		donut_cols.append(donut)
		ball.add_child(donut)
	hampterSprite.animation_finished.connect(func():
		#print("animation finished")
		spriteBusy = false
		rolling = false
		rollFrames = 0
		if turnedDuringLand:
			hampterSprite.play("quickTurn")
			spriteBusy = true
			turnedDuringLand = false
	)
func _input(_InputEvent) -> void: # runs anytime an input from the player is pressed
	# HANDLE HAMPTER INPUTS
	# Handle ball bail
	if Input.is_action_just_pressed("ball") and insideBall and shouldBeInBall and bailCount == 0:
		ball_bail_timer.start()
		bailCount += 1
	elif Input.is_action_just_pressed("ball") and insideBall and shouldBeInBall:
		bailCount += 1
	# NOTE: the bail verify is down at the signal func of ball_bail_timer
	# Handle jump
	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			jump()
			noCoyoteTime = true
		elif !is_on_floor() and noCoyoteTime == false: # smth smelly going on over here...
			print("coyote")
			jump()
			noCoyoteTime = true
		else: # and here too...
			jump_buffer = true
			get_tree().create_timer(jump_buffer_time).timeout.connect(on_jump_buffer_timeout)
		jump_timer.start()
	# Handle dash input
	if Input.is_action_just_pressed("dash") and not dashing and not wasDashing and not dashDelaying:
		#print("start time")  TODO timer triggering at inconcistent times
		if not is_on_floor():
			currentPosition = global_position
			dash_delay_timer.start() # prepare delay
		else:
			dashDelayOver = true
			pass
	# HANDLE BALL INPUTS
	if shouldBeInBall:
		# Handle ball jump input
		if Input.is_action_pressed("jump") and insideBall and ballJumping == false:
			xyDirection = Input.get_vector("left","right", "up", "down") # get current direction
			pushForce = 0 # TODO: disable collisions while jumping
			ballJumping = true
			# make the ball jump:
			ball.linear_velocity = Vector2((xyDirection.x * -0.5) * jump_velocity * 1.5,  jump_velocity * 2.45)
		if Input.is_action_just_released("jump") and insideBall:
			pushForce = push # reset push force
		
		 # Handle ball dash (INPUT) 	# TODO make dash doable while inside ball
		if Input.is_action_just_pressed("dash") and insideBall:
			ballDashDelay = true
			ballInitPosition = ball.global_position
		
		#if ballDelayFrames == 10:
			## reset vars
			#ballDelayFrames = 0
			#ballDashDelay = false
			#ballDash = true # trigger ball dash
		#elif ballDashDelay == true:
			#ball.global_position = ballInitPosition # freeze the ball 
			#ballDelayFrames += 1 # count frames
			#print("frame count: ", ballDelayFrames)
		if ballDash == true: # somethin stinky goin on here...
			ballDash = false
			ball.apply_central_impulse(Vector2(xyDirection.normalized().x * 250, xyDirection.normalized().y * 450))
			
func _process(_delta: float) -> void: # runs on a loop (framerate depends on hardware)
	if !dash_delay_timer.is_stopped():
		#print("dash delaying")
		dashDelaying = true
func _physics_process(delta: float) -> void: # runs on a loop at a fixed framerate
	var pastState = state 
	xyDirection = Input.get_vector("left","right", "up", "down") # update to player current direction
	var just_landed = is_on_floor() and wasOnAir # this var needs to be here, idk why but it does.
	ballLink = ball.global_position - global_position # update ball link
	
	 # force hampter to be inside ball (when supposed to obv)
	if shouldBeInBall and not insideBall:
		print("should be in ball, teleporting")
		tp_to_ball()
	else:
		teleporting = false 

	# MOVEMENT X and Y logic
	# Handle gravity (y axis / y logic)
	if not dashDelaying and not teleporting:
		if wasDashing or groundedDash:
			velocity.y += (get_jump_gravity()/2.5) * delta # on dash make gravity lighter
			#print("dash gravity")
		elif not ballMagnet:
			if not dashing:
				velocity.y += get_jump_gravity() * delta # normal gravity
				#print("normal gravity")
		else:
			print("no gravity")
			if jump_buffer: # TODO jump buffer sometimes bugs and gives out a double jump comboing with coyote jump
				jump()
				jump_buffer = false
				#print("jump buffer")
	# Handle movement (x axis/x logic)
	direction = Input.get_axis("left", "right") # update axis
	if not dashDelaying and not rolling: #(rolling and not shouldBeInBall): # block movement logic if player is dashing or rolling
		if wasDashing and not is_on_floor(): # apply smoother x movement while dashing
			var target = direction * SPEED * 2.5
			if abs(velocity.x) > abs(target) and sign(velocity.x) == sign(direction):
				velocity.x = move_toward(velocity.x * 0.7, target, ACCELERATION * onAir_acceleration * 0.8)
			else:
				velocity.x = move_toward(velocity.x, target, ACCELERATION * onAir_acceleration)
			currentSpeed = velocity.x
		else:
			if direction:
				if ballMagnet: # change movement logic if player is on top of ball
					velocity.x = move_toward(currentSpeed, -1 * (direction * SPEED * onBall_max_speed), ACCELERATION * onBall_acceleration)
					currentSpeed = velocity.x
				elif not is_on_floor(): # change speed while on air
					velocity.x = move_toward(currentSpeed, direction * SPEED * onAir_max_speed, ACCELERATION * onAir_acceleration )
					currentSpeed = velocity.x
				else: # normal x logic
					velocity.x = move_toward(currentSpeed, direction * SPEED * grounded_max_speed, ACCELERATION * grounded_acceleration )
					currentSpeed = velocity.x
			else: # stop logic
				velocity.x = move_toward(currentSpeed, 0, ACCELERATION * 2 )
			currentSpeed = velocity.x
			
	# Handle dash physics logic #
	if dashDelaying: # stop hampter if preparing for dash
		global_position = currentPosition
		if insideBall and shouldBeInBall:
			ball.global_position = currentPosition
	if dashDelayOver: # these need to happen regardless
		dash_timer.start()
		dashing = true # is this the culprit? make dashing depend on sprite state, maybe
		wasDashing = true
		dashDelayOver = false
	if dashDelayOver and not shouldBeInBall:
		# dash logic:
		# GROUNDED DASHES
		if is_on_floor():
			groundedDash = true
			state = "dash"
			velocity = xyDirection.normalized() * dash_speed / 1.5 # diagonal dashes
			if xyDirection.x == 0: # neutral x grounded
				print("neutral grounded")
				velocity.y = -dash_speed / 2
			elif xyDirection.y == 0:  # neutral y grounded
				velocity.y = -dash_speed / 2.4
				print("velocity before ", velocity.x)
				velocity.x += ( xyDirection.normalized().x * dash_speed ) / 5
				currentSpeed = velocity.x
				print("straight grounded dash ", xyDirection.normalized())
			else:
				print("diagonal grounded")
		# AIRBONE DASHES
		elif xyDirection == Vector2.ZERO: # neutral air dash
			velocity.y = -dash_speed / 1.4
		else: # normal air dash
			# handle dash logic
			xyDirection = Input.get_vector("left","right", "up", "down")
			velocity = xyDirection.normalized() * dash_speed
			if dashing: # lower dash speed progressivelly (dash counter speed)
				velocity = velocity.move_toward(Vector2.ZERO, dash_speed/4)
				pushForce = 400
	elif dashDelayOver and shouldBeInBall:
		pass # do the 
	else:
		if not insideBall: # bandaid for error where pushForce was reset while jumping inside ball
			pushForce = push # reset push force
	# reset dash permission
	if is_on_floor():
		wasDashing = false
	if dashing == false and is_on_floor():
		groundedDash = false
	# Handle jump physics logic
	# Handle holding jump (jump hold)
	
	if Input.is_action_pressed("jump") and jump_timer.time_left != 0 and velocity.y < 0 and not dashing and not dashLock: 
		print("jump hold")
		velocity.y += move_toward(velocity.y, jump_velocity * 20 * delta, 500000)
	# Handle jump cancel
	if Input.is_action_just_released("jump") and not is_on_floor():
		#print("jump cancel trigger")
		cancelJump = true
	# Handle fastfall
	if Input.is_action_pressed("down") and not is_on_floor() and not shouldBeInBall:
		print("fastfall trigger")
		velocity.y += ( get_gravity().y * delta ) * fastfall_power

	# Handle landing
	var landingAnim = false
	if just_landed:
		wasJumping = false
		cancelJump = false
		landingSpeed = currentSpeed
		noCoyoteTime = true
		coyote_timer.stop()
		hampterSprite.rotation = 0
		hampterSprite.stop()
		hampterSprite.play("land")
		spriteBusy = true
		landingAnim = true
		state = "land"
		if Input.is_action_pressed("left") or Input.is_action_pressed("right"):
			turnedDuringLand = true
	if state == "land": # slowdown landing
		landingSpeed = currentSpeed
		velocity.x = move_toward(landingSpeed / 35, landingSpeed, abs(currentSpeed) * 0.6)
		currentSpeed = velocity.x
		
	# Handle roll input
	if ((Input.is_action_pressed("down") and Input.is_action_pressed("left")) or (Input.is_action_pressed("right") and Input.is_action_pressed("down"))) and (is_on_floor() or just_landed):
		rolling = true
		canRoll = false

	# HANDLE BALL PHYSICS LOGIC N INTERACTIONS

	# Handle ball movement physics
	if shouldBeInBall: # lock player inside the ball, absolute clipping prevention
		global_position = ball.global_position - ballLink.normalized() * min(ballLink.length(), ball_collision_shape.shape.radius - 3) # set hampter position condition
	if shouldBeInBall:
		velocity += ball.linear_velocity / 4
		if ballGoingUp or ballWasGoingDown: # apply y direction
			ball.apply_central_force(Vector2(0, xyDirection.y * 200))
			#print("Y FORCE")
		if xyDirection.x: # apply x direction
			if not ballGoingUp and not ballWasGoingDown: # check if its on ground
				ball.apply_central_force(Vector2(xyDirection.x * 350, 0))
				pass
			else:
				ball.apply_central_force(Vector2(xyDirection.x * 450, 0))
				pass
	
	# handle ball jump reset
	if ballJumping: # logic to reset ball jump
		if ball.linear_velocity.y < 0: # check if was moving up
			ballGoingUp = true
		if ball.linear_velocity.y > 5: # check if ball was moving down
			ballWasGoingDown = true # state it was going down a frame before
			ballDownFrames += 1 # count number of frames it was going down
		else: # if it isnt moving neither up nor down...
			if ballWasGoingDown and ballDownFrames >= 2: # verify validy
				ballDownFrames = 0
				ballGoingUp = false
				ballWasGoingDown = false
				ballJumping = false # re enable ballJump option
				velocity.y += get_jump_gravity() * delta # force gravity to come back
			else:
				ballDownFrames = 0
				
	# handle ball roll
	if rolling and shouldBeInBall and not ballJumping:
		print("rolling")
		velocity = Vector2.ZERO
		global_position.move_toward(ball.global_position - Vector2(0, -12), 100)
		ball.apply_central_impulse(Vector2(direction * 15, 0))
	
	# Handle ball exit 
	if Input.is_action_just_pressed("ball") and insideBall:
		#print("cooldown over")
		exit_ball_timer.start()
		#print("trigger ball exit")
		shouldBeInBall = false
		velocity.y += get_jump_gravity() * delta # force gravity
		set_collision_mask_value(2, false)
	if shouldBeInBall == false and insideBall:
		set_collision_mask_value(2, false)
	elif shouldBeInBall == false and insideBall == false:
		set_collision_mask_value(2, true)
	
	# Handle magnet (handle ball magnet)
	if ballMagnet == true and not Input.is_action_pressed("jump") and not dashing and not rolling and not insideBall:
		# TODO fix ball jittering... u gotta aplly the force at the top of the ball, not the center. thats the cleanest fix
		velocity += Vector2.ZERO.move_toward(ballLink.normalized() * 15000 * delta, 2000) # define magnet strength
		# change scanner shape to an orbit
		scan_area.shape.radius = move_toward(scan_area.shape.radius, 28, 0.5)
		scan_area.shape.height = move_toward(scan_area.shape.height, 0.2, 0.5)
		scan_area.position.y = move_toward(scan_area.position.y, 0, 0.05)
		# *the sideways movement, on top of ball, is controlled on the movement Handling
		# PREVENT SLIPPING OFF THE BALL WHEN STOPPING
		if xyDirection == Vector2.ZERO: # lower while stopped
			velocity.x = move_toward(velocity.x, 0, 10)
			velocity.y = move_toward(velocity.y, 0, 10)
			ball.linear_velocity.x = move_toward(ball.linear_velocity.x,0, 10)
			ball.linear_velocity.y = move_toward(ball.linear_velocity.y,0, 10)
	# handle softer magnet
	#if ballLink.y <= 18 and not ballLink.y < 0:
		#velocity += Vector2.ZERO.move_toward(ballLink.normalized() * 20000 * delta, 2000) # define magnet strength
		#print("close to the ball on Y")
		#if ballLink.x <= 5 and ballLink.x >= -5:
			#print("VERY close to ball X")
			#velocity += Vector2.ZERO.move_toward(ballLink.normalized() * 2000 * delta, 2000) # define magnet strength
		#elif ballLink.x <= 11 and ballLink.x >= -11:
			#print("close to ball on X too!")
	else: 
		# reset scan shape
		scan_area.shape.radius = 10
		scan_area.shape.height = 32
		scan_area.position.y = -8
	
	# Handle pull ball physics (handle ball pull)
	if Input.is_action_pressed("ball") and not insideBall and exit_ball_timer.time_left == 0:
		state = "idle"
		ball.apply_central_impulse((-1 * ballLink).normalized() * Vector2(1, 2) * pull_force) # apply the pull force
		ball.mass = 1
		# change scanner behaviour
		scan_area.shape.radius = 70
		scan_area.shape.height = 50
		scan_area.position.y = 0
		magnetForce = 0
		#set_collision_mask_value(2, true)
		if ballMagnet == true and insideBall == false: # teleport (tp inside ball)
			tp_to_ball(true)
	# reset scanner shape (from orbit back to small)
	if Input.is_action_just_released("ball"):
		scan_area.shape.radius = 10
		scan_area.shape.height = 32
		scan_area.position.y = -8
		
	# STYLING AND ANIMATIONS OF SPRITE
	# Flip sprite depending on direction (needs to be before stst mchnie)
	if direction < 0:
		hampterSprite.flip_h = true
	elif direction > 0:
		hampterSprite.flip_h = false
	else:
		hampterSprite.rotation = 0
	# Handle state machine
	if rolling:
		state = "roll"
	elif not landingAnim:
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
		elif pastFlip != hampterSprite.flip_h and is_on_floor() and not just_landed and not state == "land":
			state = "turning"
			spriteBusy = true
			#print("turning")
			hampterSprite.stop()
			hampterSprite.play("turn")
		elif is_on_floor() and currentSpeed != 0 and direction != pastDirection and not just_landed and state != "land":
			state = "stop"
		elif not spriteBusy:
			if !is_on_floor():
				state = "onAir"
			elif direction != 0 and state != "land":
				state = "walking"
			else:
				state = "idle" 
	# Animate
	if state == "stop":
		hampterSprite.play("stop")
		#print("stop")
		spriteBusy = false
	elif state == "roll" and pastState != "roll":
		hampterSprite.play("roll")
		spriteBusy = true
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
			elif velocity.x == 0:
				hampterSprite.rotation = atan2(0, (velocity.y) * -1)
			else:
				hampterSprite.rotation = 90+(atan2(velocity.y, velocity.x))
		elif dashDelaying:
			if xyDirection != Vector2.ZERO:
				if xyDirection.x > 0:
					hampterSprite.rotation = (atan2(velocity.y, velocity.x))#*solveFlip
				else:
					hampterSprite.rotation = (atan2(velocity.y, velocity.x))
					
	# needs to be after animations and before updates
	
	 # Handle roll #
	if rolling:
		var rollSSpeed = direction * SPEED * 3
		if not shouldBeInBall:
			pushForce = 400
		else: # handle ball roll
			# TODO: smth
			pushForce = 0
		if rollFrames <= 1: # instant boost
			velocity.x = rollSSpeed
			currentSpeed =+ velocity.x
		else: # progressive slowdown
			velocity.x = move_toward(currentSpeed, direction * SPEED * grounded_max_speed, 300 * delta)
			currentSpeed = velocity.x
	if hampterSprite.animation == "roll":
		rollFrames += 1
	else: 
		rollFrames = 0
		pushForce = push
	if pastFlip != hampterSprite.flip_h: # cancel roll
		rolling = false
	# handle dash lock
	if state == "dash":
		dashLock = true
	else:
		dashLock = false
	# keep hampter still while dashing inside ball
	if shouldBeInBall and (state == "dash" or dashing):
		global_position = ball.global_position
		velocity = Vector2.ZERO
	if not ballWasGoingDown and not ballGoingUp and state == "dash":
		state = "land"
	# check if ball landed and set hampter to landing state if so
	# Update variables 
	if direction != 0:
		pastDirection = sign(direction)
	pastFlip = hampterSprite.flip_h
	wasOnAir = not is_on_floor()
	wasOnFloor = is_on_floor()
	if bail:
		if not insideBall and not shouldBeInBall:
			bail = false
	
	if not dashDelaying: # lock move and slide
		if insideBall and Input.is_action_pressed("ball") and bail:
			move_and_slide()
			shouldBeInBall = false # idk just to make sure
			print("ball tp lock prevention")
		elif not teleporting: # also lock if teleporting
			move_and_slide() # trigger movement
			
	# check coyote time
	# TODO coyote causes double jump if key is spammed
	if wasOnFloor and not is_on_floor():
		coyote_timer.start()
		
	# handle ball physics
	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		if c.get_collider() is RigidBody2D:
			if sign(c.get_normal().x) == sign(direction):
				velocity.x *= 0.01
			if not shouldBeInBall:
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
	#print("hampter inside ball")
	insideBall = true
	teleporting = false
	# swtich collisions
	ball_collision_shape.set_deferred("disabled", true) 
	for donut in donut_cols:
		donut.set_deferred("disabled", false)
	# disable magnet scanner
	ball_scanner.monitoring = false
	# Tinker IN BALL ball physics
	if shouldBeInBall:
		ball.mass = 1.35
		ball.physics_material_override.bounce = 0.0
		ball.gravity_scale = 0.6
func _on_inside_ball_body_exited(_body: Node2D) -> void: # check if gfasmper OUTSIDE ball
	# BALL STATE OUTSIDE
	#print("hampter free")
	insideBall = false
	#switch collisions back
	ball_collision_shape.set_deferred("disabled", false)
	for donut in donut_cols:
		donut.set_deferred("disabled", true)
	# enable magnet scanner
	ball_scanner.monitoring = true
	# Tinker OUT BALL ball physics
	if not shouldBeInBall:
		ball.mass = 2
		ball.physics_material_override.bounce = 0.2
		ball.gravity_scale = 0.55
func _on_exit_ball_timer_timeout() -> void: # check if exit ball timer is over
	## switch collisions back to OUTSIDE ball
	exitTimerOver = true
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
func _on_ball_bail_timer_timeout() -> void:
	if bailCount >= 2:
		bail = true
		shouldBeInBall = false
		print("ball bail activated!")
		print("pressed ball: ", bailCount, "times")
	else:
		bail = false
		
	bailTiming = false
	ballBailTime = 0
	bailCount = 0
	pass # Replace with function body.
