class_name NoiseEvents
extends RefCounted
## Loud things that happened (gunshots for now). Static, like WorldState, so any
## system can report a noise and any listener can read it without wiring signals
## across scenes. Pure and deterministic: every event gets a serial id, and a
## listener keeps the last id it read, so nothing is heard twice and nothing
## depends on wall-clock time.
##
## Writers: player_weapons.gd (each blaster shot). Readers: Perception (guards).

const MAX_EVENTS := 32

static var _events: Array = []    ## [{ id, pos, radius, kind }] oldest first
static var _next_id := 1


static func reset() -> void:
	_events = []
	_next_id = 1


## Report a noise at `pos` that carries `radius` meters. `kind` is a tag the
## listener can weigh ("shot", "shot_range", later "explosion", "shout").
static func emit(pos: Vector3, radius: float, kind: String = "shot") -> int:
	var id := _next_id
	_next_id += 1
	_events.append({ "id": id, "pos": pos, "radius": radius, "kind": kind })
	while _events.size() > MAX_EVENTS:
		_events.pop_front()
	return id


## Every event newer than `after_id`, oldest first. Issue #540: when there is none
## (nearly every tick, for every guard) the same empty, read-only array comes back.
const _NONE: Array = []


static func after(after_id: int) -> Array:
	if _next_id - 1 <= after_id:
		return _NONE
	var out: Array = []
	for e in _events:
		if int(e.id) > after_id:
			out.append(e)
	return out


static func last_id() -> int:
	return _next_id - 1
