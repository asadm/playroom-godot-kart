
## for interfacing with playroom.
## encapsulates playroom interface functions for cleaner calling/typing.
## also handles creating playroom joysticks - 
## (easier here since this is loaded across all players)


class_name PlayroomInstance
extends Node



# ----- FIELDS -----



# signals allow other nodes to listen for playroom callbacks

## emitted when the playroom host launches the game
signal coin_inserted(args)

## emitted when a new player joins
signal player_joined(args)

## start playroom in stream mode?
@export var stream_mode = false

# TODO dynamic joystick assignments? state "joystick_type" = 0, 1, etc.?

## joystick config
@export var joystick_config : PlayroomJoystickConfig

## should host get a joystick?
@export var host_joystick = false

# we do this as an export instead of explicitly defining a path
# so it doesn't break if the scene gets moved
@export_category("Preloads")
@export var playroom_player_template : PackedScene


## reference to the playroom JS interface.
## prefer using encapsulated functions here over calls to the interface
@onready var playroom = JavaScriptBridge.get_interface("Playroom") :
	get: return playroom
	set(value): pass


## playroom players: stored as a dict of player state -> player node.
## can be referenced by state, but contains additional information
var players = {} :
	get : return players
	set(value) : pass


# We will create js callables to send to playroom to trigger async behavior -
# ie. when a player loads into the game.
# An extra reference to these callables is kept just in case, to prevent the callable 
# from being refcount deleted (garbage collected)


# Our array of JS callables - to save from being deleted
var _js_callbacks : Array[JavaScriptObject]



# ----- CALLBACKS -----



# -- JS Callbacks 


# called by playroom when the host has pressed launch and loaded the game
func _on_insert_coin(args):
	
	# register player join/leave callbacks.
	# call these AFTER insert coin for proper behavior. 
	# (playerjoin will retroactively find joined players)
	playroom.onPlayerJoin(_create_callback(_on_new_player_join))
	playroom.onDisconnect(_create_callback(_on_disconnect))
	
	print("COIN INSERTED")
	coin_inserted.emit(args)


# called by playroom when a new player joins (including the host)
func _on_new_player_join(args):
	
	# new player node
	var player : PlayroomPlayer = playroom_player_template.instantiate()
	
	# get state
	var state = args[0]
	print("I AM: ", playroom_my_player().id,  " PLAYER HAS JOINED: ", state.id)
	player.player_state = state
	
	# add state and player to dict
	players[state] = player
	
	# populate state data (synced data)
	
	if playroom_is_host():
		print("SETTING SELF AS HOST")
		state.setState("host_player", playroom_my_player())
		print(state.getState("host_player"))
		# TODO for some reason can't get/set state from host player
		
		# if never set, should return false?
		state.setState("is_host", true)
	
	
	# log callback to listen for player quitting
	state.onQuit(_create_callback(_on_player_quit))
	
	# add joystick
	player.joystick = _setup_joysticks(state)


# called by playroom when a player quits
func _on_player_quit(player_state):
	players.erase(player_state)


# called by playroom when this player disconnects
func _on_disconnect(error):
	pass


# -- Godot Callbacks


func _ready():
	pass


func _process(delta):
	pass



# ----- PUBLIC -----



## launches playroom!
func start_playroom():
	_start_playroom()


# -- Playroom interface functions


## returns if the current context is the playroom host
func playroom_is_host() -> bool:
	return playroom.isHost()


## returns this context's player state object
func playroom_my_player():
	return playroom.myPlayer()


## returns if current context is the stream screen
func playroom_is_stream_screen():
	return playroom.isStreamScreen()


## COROUTINE - returns control when given state is set truthy (see api)
func playroom_await_player_state(player_state, state_key : String):
	await playroom.waitForPlayerState(player_state, state_key)



# ----- PRIVATE -----



# Our method for creating JS callbacks: 
# wraps a godot callable as a JS callable and logs it in our callback array
func _create_callback(callable : Callable):
	
	var callback = JavaScriptBridge.create_callback(callable)
	_js_callbacks.push_back(callback)
	
	return callback


# regsiters callbacks and initializes the playroom lobby
func _start_playroom():
	
	# populate initialization options
	var init_options = JavaScriptBridge.create_object("Object")
	
	# launch in stream mode
	if stream_mode: init_options.streamMode = true
	
	# insert coin!
	# registers our callback for when the game launches
	playroom.insertCoin(init_options, _create_callback(_on_insert_coin))


# adds joystick to this state
func _setup_joysticks(player_state) -> JavaScriptObject:
	if joystick_config == null: return
	
	# is host joining?
	if !host_joystick and player_state.getState("is_host"): return
	
	var joy_options = joystick_config.create_joy_options()
	return JavaScriptBridge.create_object("Joystick", player_state, joy_options)
	
