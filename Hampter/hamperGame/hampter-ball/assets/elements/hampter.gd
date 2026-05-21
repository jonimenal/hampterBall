extends CharacterBody2D

# tinkering variables
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
#TODO tune hamper onAir speed to make more of an arch sorta jump

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
# coyote time stuff
var noCoyoteTime = false

# fastfall
@export var fastfall_power : float

# landing
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
@onready var roll_cooldown: Timer = $rollCooldown
@onready var ball_bail_timer: Timer = $ballBailTimer

# gravity logic variables
@onready var jump_velocity : float = ((2.0 * jump_height) / jump_peak_time) * -1.0 # use this to calculate a velocity that respects set height
@onready var jump_gravity : float = ((gravityJ * jump_height) / (jump_peak_time * jump_peak_time)) * -1.0
@onready var fall_gravity : float = ((gravityF * jump_height) / (jump_drop_time * jump_drop_time)) * -1.0
@onready var real_fall_gravity : float = ((-18 * jump_height) / (jump_drop_time * jump_drop_time)) * -1.0 # same formula as fall gravity
@onready var fastfall_gravity : float = ((-80 * jump_height) / (jump_drop_time * jump_drop_time)) * -1.0 # same formula as fall gravity
@onready var dash_gravity: float = ((-14 * 20) / (0.4 * 0.4)) * -1.0 # same formula as jump_gravity
@onready var dash_fall_gravity : float = ((-17 * 20) / (0.9 * 0.9)) * -1.0 # same formula as fall_gravity

# dashing
var dashDelayOver = false
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
var exitTimerOver = false
var bailCount = 0
var ballBailTime = 0
var bailTiming = false
var bail = false
var ballPastDist = ballLink.length()
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
		velocity.y = jump_velocity/1.25
func roll():
		var rollSSpeed = direction * SPEED * 3
		pushForce = 5
		if rollFrames <= 1: # instant boost
			velocity.x = rollSSpeed
			currentSpeed =+ velocity.x
		else: # progressive slowdown
			velocity.x = move_toward(currentSpeed, direction * SPEED * grounded_max_speed, 10)
			currentSpeed = velocity.x
func dash(): # dashing logic
	# handle dash logic
	xyDirection = Input.get_vector("left","right", "up", "down")
	velocity = xyDirection.normalized() * dash_speed
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
	# check double ball click for person to exit tp loop
	if not bail: # block tp is bailing is true
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
	for gormiti in range(90):
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
		rolling = false
		rollFrames = 0
		if turnedDuringLand:
			hampterSprite.play("quickTurn")
			spriteBusy = true
			turnedDuringLand = false
	)
func _input(_InputEvent) -> void: # runs anytime an input from the player is pressed
	# get player current direction
	xyDirection = Input.get_vector("left","right", "up", "down")
	
	# Handle ball bail
	if Input.is_action_just_pressed("ball") and insideBall and shouldBeInBall and bailCount == 0:
		ball_bail_timer.start()
		bailCount += 1
	elif Input.is_action_just_pressed("ball") and insideBall and shouldBeInBall:
		bailCount += 1
	# the bail verify is down at the signal func of ball_bail_timer
	
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
	if Input.is_action_just_pressed("dash") and not dashing and not wasDashing and not dashDelaying:
		#print("start time")  TODO timer triggering at inconcistent times
		if not is_on_floor():
			currentPosition = global_position
			dash_delay_timer.start() # prepare delay
		else:
			dashDelayOver = true
			pass
	# HANDLE BALL INPUTS
	# Handle ball jump (INPUT)
	if shouldBeInBall:
		if Input.is_action_pressed("jump") and insideBall and ballJumping == false:
			xyDirection = Input.get_vector("left","right", "up", "down") # get current direction
			pushForce = 0
			ballJumping = true
			# apply jump velocity on ball
			ball.linear_velocity = Vector2((xyDirection.x * -0.5) * jump_velocity * 2.5,  jump_velocity * 2.6)
		if Input.is_action_just_released("jump") and insideBall:
			pushForce = push
	# TODO make dash doable while inside ball
	# Handle ball dash (INPUT)
	if shouldBeInBall:
		if Input.is_action_just_pressed("dash") and insideBall:
			ball.apply_central_impulse(Vector2(xyDirection.normalized().x * 250, xyDirection.normalized().y * 350))
func _process(_delta: float) -> void: # runs on a loop (framerate depends on hardware)
	if !dash_delay_timer.is_stopped():
		#print("dash delaying")
		dashDelaying = true
func _physics_process(delta: float) -> void: # runs on a loop at a fixed framerate
	#print(currentSpeed)
	var pastState = state
	xyDirection = Input.get_vector("left","right", "up", "down") # update to player current direction
	var just_landed = is_on_floor() and wasOnAir # this var needs to be here, idk why but it does.
	# back here 
	if not teleporting:
		ballPastDist = ballLink.length()
	ballLink = ball.global_position - global_position # update ball link
	# Anti clippling inside the ball
	if shouldBeInBall:
		hampter.safe_margin = 0.00001 # making safe margin bigger
	else:
		hampter.safe_margin = 1
	if insideBall:
		#var ballDistPerFrame = ball.linear_velocity.length() * (1.0/60.0) # define the distance per frame (physics runs at 60fps constant)
		#var ballThreshold = ball_collision_shape.shape.radius - hampterCollision.shape.radius
		#print("distance per frame: ", ballDistPerFrame)
		#print("threshold: ", ballThreshold)

		# reactive anti clip prevention
		#if (ballLink.x < -12 or ballLink.x > 12): #:
			#print("away from link X")
			##print(ball.linear_velocity.length_squ5ared())
			#tp_to_ball()
		#elif  (ballLink.y < -15.2 or ballLink.y > 13):
			#print("away from link Y")
			#tp_to_ball()
		#if ball.linear_velocity.length_squared() > 100000:
			#print("pretty fast ball")
			#print(ball.linear_velocity.length_squared())
			#tp_to_ball()
		#else:
			#teleporting = false
		#print(ballLink)
		
		# predictive anti clip prevention
		
		#var ballNextPos = ball.global_position + (ball.linear_velocity * delta) # predict by calculating speed with current position
		#if (ballNextPos - global_position).length() > 16 and shouldBeInBall: # check if the next position compared to hampter rn, is bigger than ball's radius
		var teleport = false
		if (ballPastDist < ballLink.length()) and (ballLink.length() - ballPastDist) > 1.8 and shouldBeInBall: # ball's speed is growing
			teleporting = true
			teleport = true
		elif (ballPastDist >= ballLink.length()) and shouldBeInBall:
			teleporting = false
			teleport = false
			
		if teleport:
			print("predictive prevention")
			tp_to_ball()
		
		#ball.global_position
	#if shouldBeInBall and not insideBall and not teleporting:
		#print("should be in ball, teleporting")
		## back here
		#print(ball.linear_velocity.length_squared())
		#tp_to_ball()
	#else:
		#teleporting = false 
		

	# Handle gravity (y axis / y logic)
	if not dashDelaying and not teleporting:
		#print("gravity on")
		if wasDashing or groundedDash:
			velocity.y += (get_jump_gravity()/2.5) * delta # on dash make gravity lighter
			#print("dash gravity")
		elif not ballMagnet:
			if not dashing:
				velocity.y += get_jump_gravity() * delta # normal gravity
				#print("normal gravity")
		else:
			#print("no gravity")
			if jump_buffer:
				jump()
				jump_buffer = false
				#print("jump buffer")
				# TODO jump buffer sometimes bugs and give out a double jump comboing with coyote jump, its a feature combo bug dude 
	#else:
		#print("no gravity applied")
	# Handle movement (x axis/x logic)
	direction = Input.get_axis("left", "right") # update axis
	if not dashing and not dashDelaying and not (rolling and not shouldBeInBall): # block movement logic if player is dashing or rolling
		#print("movement on")
		if wasDashing and not is_on_floor():
			 # apply smoother ease if player was dashing
			var target = direction * SPEED * 2.5
			if abs(velocity.x) > abs(target) and sign(velocity.x) == sign(direction):
				velocity.x = move_toward(velocity.x * 0.7, target, ACCELERATION * onAir_acceleration * 0.8)
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
	#else: # DEBUG
		#print("movement logic disabled")

	# Handle dash physics logic (needs to be in physics instead of input)
	if dashDelaying: # stop hampter if preparing for dash
		#print("stopping hampter")
		global_position = currentPosition
	if dashDelayOver: # apply dashing logic
		dash_timer.start()
		dashing = true
		wasDashing = true
		dashDelayOver = false
		# dash logic:
		if is_on_floor(): # grounded dashes
			groundedDash = true
			velocity = xyDirection.normalized() * dash_speed # diagonal dashes
			if xyDirection.x == 0: # neutral x grounded
				print("neutral grounded")
				velocity.y = -dash_speed / 2
			elif xyDirection.y == 0:  # neutral y grounded
				velocity.y = -dash_speed / 2.4
				print("velocity before ", velocity.x)
				if state == "walking":
					print("dash boost")
					velocity.x *= (dash_speed * 0.0015)
				print("velocity after ", velocity.x)
				print("straight grounded dash ", xyDirection.normalized())
			else:
				print("diagonal grounded")
		elif xyDirection == Vector2.ZERO: # neutral air dash
			velocity.y = -dash_speed / 2
		else: # normal air dash
				dash()
	else:
		if not insideBall: # bandaid for error where pushForce was reset while jumping inside ball
			pushForce = push # reset push force
	# reset dash permission
	if is_on_floor():
		wasDashing = false
	if dashing == false and is_on_floor():
		groundedDash = false
	
	# Handle jump key while holding
	if Input.is_action_pressed("jump") and jump_timer.time_left != 0 and velocity.y < 0 and not dashing:
		#print("jump hold")
		velocity.y += move_toward(velocity.y, jump_velocity * 20 * delta, 500000)

	# Handle jump bail
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

	# ball jump physics logic
	if ballJumping == true and insideBall:
		tp_to_ball()
	if ballJumping: # logic to reset ball jump
		if ball.linear_velocity.y > 5: # check if ball was moving down
			#print("ball is going down")
			ballWasGoingDown = true # state it was going down a frame before
			ballDownFrames += 1 # counter number of frames it was going down
		else: # if it isnt moving down, verify validy
			if ballWasGoingDown and ballDownFrames > 2:
				print("ball landed!")
				ballDownFrames = 0
				ballWasGoingDown = false #it for sure no longer was
				ballJumping = false # re enable ballJump option
				velocity.y += get_jump_gravity() * delta # force gravity to come back
			else:
				ballDownFrames = 0

	# Handle ball movement physics
	if insideBall and shouldBeInBall and not bail: # check if player is inside ball (and is supposed to)
		ball.physics_material_override.friction = 0.3
		if rolling: # Handle ball roll
			ball.apply_central_impulse(xyDirection * 20)
		else: # walking speed boost
			pushForce = 5
			currentSpeed += xyDirection.normalized().x * 1.7

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
# handle softer magnet
#if ballLink.y <= 18 and not ballLink.y < 0:
	#velocity += Vector2.ZERO.move_toward(ballLink.normalized() * 20000 * delta, 2000) # define magnet strength
	#print("close to the ball on Y")
	#if ballLink.x <= 5 and ballLink.x >= -5:
		#print("VERY close to ball X")
		#velocity += Vector2.ZERO.move_toward(ballLink.normalized() * 2000 * delta, 2000) # define magnet strength
	#elif ballLink.x <= 11 and ballLink.x >= -11:
		#print("close to ball on X too!")
		# TODO fix ball jittering... u gotta aplly the force at the top of the ball, not the center. thats the cleanest fix
		velocity += Vector2.ZERO.move_toward(ballLink.normalized() * 15000 * delta, 2000) # define magnet strength
		
		# ease ball jitter
		if ball.linear_velocity.y < 50:
			ball.linear_velocity.y = 0
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
			#print("momentum stopped: ", SPEED) # DEBUG
	else: 
		# reset scan shape
		scan_area.shape.radius = 10
		scan_area.shape.height = 32
		scan_area.position.y = -8
	
	# Handle pull ball (handle ball pull)| needs to be here instead of input, because it interacts with physics real-time
	if Input.is_action_pressed("ball") and not insideBall and exit_ball_timer.time_left == 0 and ball_switch_cooldown.time_left == 0:
		state = "idle"
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
	
	# Handle roll grounded (needs to be in physics bcos of is_in_floor() better responsiveness
	if rolling:
		roll()
	if hampterSprite.animation == "roll":
		rollFrames += 1
		#print("roll frame: ", rollFrames)
	if pastFlip != hampterSprite.flip_h: # cancel roll
		rolling = false
	
	# Update variables 
	if direction != 0:
		pastDirection = sign(direction)
	pastFlip = hampterSprite.flip_h
	wasOnAir = not is_on_floor()
	wasOnFloor = is_on_floor()
	
	if bail:
		if not insideBall and not shouldBeInBall:
			bail = false
	
	if teleporting or ballJumping:
		velocity = Vector2.ZERO
	## DEBUG
	#print("Y distance: ", ballLink.y)
	
	#if pastState != state:
		#print(state)
	
	if not dashDelaying: #lock move and slide if dashDelaying
		if insideBall and Input.is_action_pressed("ball") and bail:
			move_and_slide()
			print("ball tp lock prevention")
		elif not teleporting: # also lock if teleporting
			move_and_slide() # trigger movement
		#else:
			#print("no move and slide")
	# check coyote time
	# TODO coyote causes double jump if key is spammed
	if wasOnFloor and not is_on_floor():
		coyote_timer.start()
		
	# push ball
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
	ball.mass = 1.35
	ball.physics_material_override.bounce = 0.2
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
	ball.mass = 2
	ball.physics_material_override.bounce = 0.75
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
func _on_roll_cooldown_timeout() -> void:
	pass # Replace with function body.
	#TODO add timeout functionality to prevent roll spamming
	# make it work while the roll is rolling, not after, cuz its easier ig

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
