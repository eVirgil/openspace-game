extends Node
## LAN play: one set of jobs for everyone. A job taken in any player's game (a
## drop, a bounty, a heist, the supply run, a plain board job) is everyone's: the
## host's game runs it (its town is the town: the bounty's officer stands at the
## outpost there, and the guests see a copy, NetWorld), and every guest's game
## shows it (the job log, the pointer, the drop lying in the sand).
##
## Before this a guest's job lived only in the guest's game: its officer was a body
## the host does not have, so NetWorld threw it away and RemnantOutposts put it
## back, every frame, for ever.
##
## The jobs are book(): which jobs are taken, the drop, the bounty, the heist and
## the supply run. Whoever's book changes sends it: a guest's to the host
## (jobs_up), which takes it as its own and sends it on; the host's to every guest
## (jobs_down). The last one sent wins. Several jobs on at once is fine; where the
## game keeps one of a kind (one drop, one bounty, one heist) the newest is it.
## Credits, gear and pay stay each player's own: whoever finishes a job is paid.
##
## A guest's game that loads a save (its town loading on the way in, WorldState
## .loads) sends nothing until it has heard the host's book again, so its old
## save's jobs never wipe the host's.
##
## Lives at /root/NetLink/Jobs (NetLink makes it).

var _last: Dictionary = {}       ## the book last sent or heard
var _heard_loads := -1           ## guest: WorldState.loads when the host's book was last heard
var _asked_at := -10.0           ## guest: when the host's book was last asked for
var _left := 0.0
var sent := 0                    ## tests
var heard := 0                   ## tests


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _link() -> Node:
	return get_parent()


func _mp() -> MultiplayerAPI:
	return get_tree().get_multiplayer()


func _live() -> bool:
	var l := _link()
	return l != null and l.has_method("_connected") and l._connected() and (_mp().is_server() or bool(l.welcomed_in))


## The jobs everyone shares, as they stand in this game.
static func book() -> Dictionary:
	_mark_taken()
	return {
		"taken": WorldState.jobs_taken.duplicate(true),
		"smuggle": WorldState.smuggle.duplicate(true),
		"bounty": WorldState.bounty.duplicate(true),
		"heist": WorldState.heist.duplicate(true),
		"supply": Territory.supply_out(),
	}


## A drop or a heist's stash picked up here is gone for everyone (the pickup is
## one thing in the world, not one each).
static func _mark_taken() -> void:
	var s := WorldState.smuggle
	if bool(s.get("out", false)) and not bool(s.get("taken", false)) and WorldState.inventory.is_taken("smuggle_%d" % int(s.get("run", 0))):
		s["taken"] = true
	if Heist.stash_taken() and not bool(WorldState.heist.get("taken", false)):
		WorldState.heist["taken"] = true


## Make this game's jobs the book's, with the news a player would have had taking
## them here (the banner: New Job, New Target, Target Killed).
static func adopt(b: Dictionary) -> void:
	var was := book()
	WorldState.jobs_taken = (b.get("taken", {}) as Dictionary).duplicate(true)
	WorldState.smuggle = (b.get("smuggle", {}) as Dictionary).duplicate(true)
	WorldState.bounty = (b.get("bounty", {}) as Dictionary).duplicate(true)
	WorldState.heist = (b.get("heist", {}) as Dictionary).duplicate(true)
	var to := str(b.get("supply", ""))
	if to == "":
		WorldState.control.erase("supply")
	else:
		WorldState.control["supply"] = to
	_news(was, b)


static func _news(was: Dictionary, now: Dictionary) -> void:
	var taken: Dictionary = now.get("taken", {})
	for id in taken:
		if str(taken[id]) == "active" and str(was.taken.get(id, "")) != "active":
			QuestNews.push("job_taken", _title(str(id)))
	var s: Dictionary = now.get("smuggle", {})
	if bool(s.get("out", false)) and int(s.get("run", 0)) != int(was.smuggle.get("run", 0)):
		QuestNews.push("job_taken", _title(str(s.get("job", ""))))
	var h: Dictionary = now.get("heist", {})
	if str(h.get("state", "")) == "out" and int(h.get("run", 0)) != int(was.heist.get("run", 0)):
		QuestNews.push("job_taken", _title(str(h.get("job", ""))))
	var bo: Dictionary = now.get("bounty", {})
	var st := str(bo.get("state", ""))
	var same_run := int(bo.get("run", 0)) == int(was.bounty.get("run", 0))
	if st == "out" and not (same_run and str(was.bounty.get("state", "")) == "out"):
		QuestNews.push("target_new", str(bo.get("name", "")))
	elif st == "dead" and not (same_run and str(was.bounty.get("state", "")) == "dead"):
		QuestNews.push("target_killed", str(bo.get("name", "")))


static func _title(id: String) -> String:
	for j in WorldState.board():
		if str(j.get("id", "")) == id:
			return str(j.get("title", id))
	return id


func _physics_process(dt: float) -> void:
	if not _live():
		_last = {}
		_heard_loads = -1
		return
	_left -= dt
	if _left > 0.0:
		return
	_left = NetSession.n("jobs_every_s", 0.25)
	if _mp().is_server():
		var b := book()
		if b != _last:
			_last = b
			sent += 1
			jobs_down.rpc(b)
		return
	# A guest: the host's book first, after every load; then its own changes go up.
	if _heard_loads != WorldState.loads:
		var now := Time.get_ticks_msec() / 1000.0
		if now - _asked_at > 2.0:
			_asked_at = now
			jobs_ask.rpc_id(1)
		return
	var b := book()
	if b != _last:
		_last = b
		sent += 1
		jobs_up.rpc_id(1, b)


## Guest -> host: send me the jobs.
@rpc("any_peer", "call_remote", "reliable")
func jobs_ask() -> void:
	if not _mp().is_server():
		return
	jobs_down.rpc_id(_mp().get_remote_sender_id(), book())


## Guest -> host: my jobs changed (I took one, finished one, picked up the drop):
## they are the host's now, and everyone's.
@rpc("any_peer", "call_remote", "reliable")
func jobs_up(b: Dictionary) -> void:
	if not _mp().is_server():
		return
	heard += 1
	adopt(b)
	_last = book()
	sent += 1
	jobs_down.rpc(_last)


## Host -> guests: the jobs as they stand.
@rpc("authority", "call_remote", "reliable")
func jobs_down(b: Dictionary) -> void:
	heard += 1
	adopt(b)
	_last = book()
	_heard_loads = WorldState.loads
