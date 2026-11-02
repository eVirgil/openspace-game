extends RefCounted
## Seeker warning. Pure: while an enemy holds a lock on the player's ship, or has a
## seeker in flight at it, the cockpit sounds an alarm and flashes a lamp for
## `alarm_secs`. Then it falls silent and cannot go off again for `rest_secs`; if a
## lock or a seeker is still on her after that, it goes off again. Losing the threat
## cuts it off early (and the same rest applies), so it never wails about nothing.
##
## ShipPilot feeds it Dogfight.seekers_on_player() every frame and drives the alarm
## sound, the HUD text and the dash lamp from `sounding` and `lamp_on()`.
## Tuning is data (content/core/flow/launch_pads.json: seeker_alarm_*).

var alarm_secs := 5.0
var rest_secs := 1.0
var flash_hz := 2.0         ## lamp cycles a second (on for the first half of each)
var sounding := false
var sounds := 0              ## times the alarm has gone off (traces, tests)
var _left := 0.0             ## seconds the alarm has left
var _rest := 0.0             ## seconds before it may go off again
var _clock := 0.0            ## seconds since it went off, for the lamp


func configure(alarm: float, rest: float, hz: float) -> void:
	alarm_secs = alarm
	rest_secs = rest
	flash_hz = hz


func reset() -> void:
	sounding = false
	_left = 0.0
	_rest = 0.0
	_clock = 0.0


## Advance by dt. `threat`: a lock or a seeker is on the player this frame.
func update(dt: float, threat: bool) -> void:
	if sounding:
		_left -= dt
		_clock += dt
		if not threat or _left <= 0.0:
			sounding = false
			_rest = rest_secs
	elif _rest > 0.0:
		_rest = maxf(0.0, _rest - dt)
	if threat and not sounding and _rest <= 0.0:
		sounding = true
		sounds += 1
		_left = alarm_secs
		_clock = 0.0


## The lamp, lit for the first half of each flash while the alarm sounds.
func lamp_on() -> bool:
	return sounding and fposmod(_clock * flash_hz, 1.0) < 0.5
