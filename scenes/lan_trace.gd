extends SceneTree
## Issue #401 trace (headless, loopback): LAN play across real processes. One run
## per player; scripts/test_lan.sh starts a host and two guests in a game capped at
## two players, so:
##   - guest "walker" is let in, walks 10 m (4 m/s along x) and the host's copy of
##     it is within 0.5 m of where it stopped inside 1 s,
##   - guest "late" is turned away: the game is full,
##   - the host's bolt lands on the walker: the walker's game hears the hit and
##     answers (the host's hit marker), and the walker's hit on the host is
##     answered the same way (the guest's hit marker),
##   - the walker changing outfit once it has walked reaches the host,
##   - the walker quitting takes it off the host's roster.
## No town is built: the players' state comes from `local_state`, not a body.
##
## Run: godot --headless --path . -s res://scenes/lan_trace.gd -- host|walker|late <port>

const WALK_SPEED := 4.0
const WALK_M := 10.0

var role := ""
var port := 24991
var session                    ## NetSession (loaded lazily: see reference notes on -s scripts)
var link
var t := 0.0
var walk_t := -1.0             ## the walker: seconds since it was let in
var fails := PackedStringArray()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0] if args.size() > 0 else "host"
	port = int(args[1]) if args.size() > 1 else port
	_run.call_deferred()


func say(s: String) -> void:
	print("LAN_TRACE %s: %s" % [role, s])


func _run() -> void:
	await process_frame
	session = load("res://src/systems/net/net_session.gd")
	session.root = OS.get_user_data_dir() + "/lan_trace_"
	session.max_override = 2
	session._cfg = session.cfg().duplicate(true)
	session._cfg["port"] = port
	session._cfg["connect_timeout"] = 4.0
	var err: int
	if role == "late":
		await _wait(2.0)          # the walker gets the one free place first
	if role == "host":
		err = session.host(self, "Host")
	else:
		err = session.join(self, "127.0.0.1", role)
	if err != OK:
		say("FAIL could not start: %d" % err)
		quit(1)
		return
	link = session.link
	link.with_bodies = false
	link.arrive_on_welcome = false
	link.local_state = _state
	link.local_outfit = func(): return {"hat": "walked"} if walk_t > WALK_M / WALK_SPEED else {}
	if role == "host":
		await _host()
	elif role == "walker":
		await _walker()
	else:
		await _late()


func _state() -> Array:
	var x := 0.0
	if walk_t >= 0.0:
		x = minf(walk_t * WALK_SPEED, WALK_M)
	var moving := walk_t >= 0.0 and x < WALK_M
	return ["port_desert", Vector3(x, 0, 0), 0.0, Vector3(WALK_SPEED if moving else 0.0, 0, 0), 8, "", 0.0, 0.0, Quaternion.IDENTITY]


func _done(ok: bool) -> void:
	for f in fails:
		say("FAIL " + f)
	say("PASS" if ok and fails.is_empty() else "FAILED")
	session.leave()
	await process_frame
	quit(0 if ok and fails.is_empty() else 1)


func _wait(secs: float, until: Callable = Callable()) -> bool:
	var end := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < end:
		await physics_frame
		if until.is_valid() and until.call():
			return true
	return until.is_valid() and until.call()


# ------------------------------------------------------------------ host

func _host() -> void:
	var walker := [0]
	var refused := [0]
	link.player_joined.connect(func(id, nm): if nm == "walker": walker[0] = id)
	link.turned_away.connect(func(_id, why): refused[0] += 1 if why == "refused_full" else 0)
	if not await _wait(15.0, func(): return walker[0] != 0):
		fails.append("the walker never joined")
		await _done(false)
		return
	say("walker joined as %d" % walker[0])
	# The walker starts on its welcome; give it the 2.5 s walk, then 1 s to arrive.
	var arrived := await _wait(8.0, func():
		var s: Dictionary = link.states.get(walker[0], {})
		return not s.is_empty() and absf((s.pos as Vector3).x - WALK_M) <= 0.5 and (s.vel as Vector3).length() < 0.01)
	var seen: Dictionary = link.states.get(walker[0], {})
	say("host's copy of the walker at %s" % str(seen.get("pos", "nothing")))
	if not arrived:
		fails.append("the host's copy never got within 0.5 m of %.1f" % WALK_M)
	link.send_hit(walker[0], 25.0, Vector3.ZERO)       # friendly fire: the host shoots the walker
	if not await _wait(4.0, func(): return link.hits_answered > 0):
		fails.append("the walker's game never answered the host's hit")
	else:
		say("the walker's game answered the hit")
	if not await _wait(10.0, func(): return refused[0] > 0):
		fails.append("the late guest was never refused")
	else:
		say("late guest refused: full")
	if not await _wait(12.0, func(): return not link.roster.has(walker[0])):
		fails.append("the walker quit but is still on the roster")
	else:
		say("walker left; roster %s" % str(link.roster.keys()))
	if link.hits_taken < 1:
		fails.append("the walker's hit never reached the host")
	if link.outfits_heard < 1:
		fails.append("the walker's outfit change never reached the host")
	else:
		say("heard the walker's outfit change")
	await _done(true)


# ------------------------------------------------------------------ guests

func _walker() -> void:
	var start := [-1.0]
	link.welcomed.connect(func(_p): start[0] = Time.get_ticks_msec() / 1000.0)
	if not await _wait(8.0, func(): return start[0] >= 0.0):
		fails.append("never let in")
		await _done(false)
		return
	say("let in; walking")
	var walk_end := WALK_M / WALK_SPEED
	while walk_t < walk_end + 2.0:
		await physics_frame
		walk_t = Time.get_ticks_msec() / 1000.0 - start[0]
	link.send_hit(1, 10.0, Vector3.ZERO)               # and the guest shoots the host
	# Stay a while so the late guest finds the game full (and the host's shot lands), then quit.
	await _wait(4.0)
	if link.hits_answered < 1:
		fails.append("the host's game never answered the walker's hit")
	else:
		say("the host's game answered the hit (guest's hit marker)")
	if link.hits_taken < 1:
		fails.append("the host's hit never reached the walker")
	else:
		say("hit by the host (friendly fire)")
	say("quitting")
	await _done(true)


func _late() -> void:
	var why := [""]
	link.refused.connect(func(w): why[0] = w)
	link.welcomed.connect(func(_p): why[0] = "welcomed")
	await _wait(8.0, func(): return why[0] != "")
	if why[0] != "refused_full":
		fails.append("expected to be turned away as full, got '%s'" % why[0])
	else:
		say("turned away: full")
	await _done(true)
