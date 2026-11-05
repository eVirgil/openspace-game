class_name WeaponHolder
extends RefCounted
## Which hand weapon the player has out, and the swap between them (M11). Pure.
##
## A swap is HOLSTER (put the current one away) then DRAW (bring the next one
## up). Pressing again mid-swap retargets cleanly: during HOLSTER it just changes
## where we are going; during DRAW it reverses into a HOLSTER from the same point,
## so spamming the keys never desyncs the hands from the weapon.
##
## `drawn()` (0..1) is how far the current weapon is from its holster; the avatar
## blends holster -> ready with it. `update()` returns events for sound and the
## blade's ignite/retract: "holstered:<id>", "drawing:<id>", "drawn:<id>".

enum Phase { IDLE, HOLSTERING, DRAWING }

var holster_time := 0.18
var draw_time := 0.17
var slots: Array = []          ## weapon ids in slot order (1, 2, 3 ...); "" = an empty slot
var current := ""              ## "" = hands free
var pending := ""              ## where a swap is headed
var previous := ""             ## for "last weapon" (Q)
var can_draw := func(_id: String) -> bool: return true   ## issue #200: false = that weapon stays holstered
var phase := Phase.IDLE
var _t := 0.0                  ## seconds into the phase


func _init(slot_ids: Array = []) -> void:
	slots = slot_ids


func is_ready() -> bool:
	return phase == Phase.IDLE and current != ""


func is_swapping() -> bool:
	return phase != Phase.IDLE


## 0 = in the holster, 1 = up and ready.
func drawn() -> float:
	match phase:
		Phase.IDLE:
			return 1.0 if current != "" else 0.0
		Phase.HOLSTERING:
			return 1.0 - clampf(_t / holster_time, 0.0, 1.0)
		Phase.DRAWING:
			return clampf(_t / draw_time, 0.0, 1.0)
	return 0.0


## Ask for a weapon. "" holsters. Asking for the weapon already out holsters it.
## One the player may not draw (can_draw) is ignored.
func request(id: String) -> void:
	if id != "" and not can_draw.call(id):
		return
	if phase == Phase.IDLE and id == current:
		id = ""
	if phase == Phase.IDLE:
		if id == current:
			return
		pending = id
		if current == "":
			_start_draw(id)
		else:
			phase = Phase.HOLSTERING
			_t = 0.0
		return
	if phase == Phase.HOLSTERING:
		pending = id
		return
	# DRAWING: same target -> keep going; anything else -> reverse from here.
	if id == current:
		return
	pending = id
	var frac := clampf(_t / draw_time, 0.0, 1.0)
	phase = Phase.HOLSTERING
	_t = (1.0 - frac) * holster_time


## The weapons in the slots, in order, without the empty ones.
func weapon_ids() -> Array:
	return slots.filter(func(id): return str(id) != "")


## Number key n. An empty slot does nothing (it does not holster).
func request_slot(n: int) -> void:
	if n >= 1 and n <= slots.size() and str(slots[n - 1]) != "":
		request(str(slots[n - 1]))


func request_last() -> void:
	request(previous)


func cycle(step: int) -> void:
	if slots.is_empty():
		return
	var target := pending if is_swapping() else current
	var i := slots.find(target) if target != "" else -1     # hands free: not an empty slot
	for _n in slots.size():
		i = (i + step + slots.size()) % slots.size() if i >= 0 else (0 if step > 0 else slots.size() - 1)
		if str(slots[i]) == "":
			continue        # an empty slot
		if str(slots[i]) == target:
			return          # the only one it may draw is already out
		if can_draw.call(str(slots[i])):
			request(str(slots[i]))
			return


## Tab: forward through the weapons it may draw, then hands free after the last
## one, then round to the first again.
func cycle_to_empty() -> void:
	var target := pending if is_swapping() else current
	var from := slots.find(target) + 1 if target != "" else 0
	for i in range(from, slots.size()):
		if str(slots[i]) != "" and can_draw.call(str(slots[i])):
			request(str(slots[i]))
			return
	if target != "":
		request("")


func update(dt: float) -> Array:
	var events: Array = []
	_t += dt
	match phase:
		Phase.HOLSTERING:
			if _t >= holster_time:
				events.append("holstered:" + current)
				if current != "":
					previous = current
				current = ""
				if pending != "":
					_start_draw(pending)
					events.append("drawing:" + current)
				else:
					phase = Phase.IDLE
					_t = 0.0
		Phase.DRAWING:
			if _t >= draw_time:
				phase = Phase.IDLE
				_t = 0.0
				events.append("drawn:" + current)
	return events


func _start_draw(id: String) -> void:
	current = id
	pending = id
	phase = Phase.DRAWING
	_t = 0.0
