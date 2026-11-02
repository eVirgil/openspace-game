class_name WeaponWheel
extends RefCounted
## The weapon wheel (issue #410): hold Tab, point at a slot with the mouse, WASD
## or the arrows, let go to draw it. Pure: no nodes, no input, no pause.
##
## Eight slots, slot 1 at the top and the rest clockwise, so 1/2/3 sit where the
## number keys read. The ids come from WeaponHolder.slots, padded with "" up to
## eight; an empty slot, or one `can_draw` refuses (story mode, a weapon not yet
## given), is drawn dimmed and can not be picked.
##
## The pointer is a spot inside a unit disc. The mouse moves it by `mouse_pixels`
## per unit; a direction key snaps it to that side and it stays there when the key
## goes up. Inside the dead zone nothing is highlighted: that is the middle, and
## letting go there keeps what you have out.

const SLOTS := 8

var slots: Array = []                      ## ids, padded with "" to SLOTS
var can_draw := func(_id: String) -> bool: return true
var hold_time := 0.2                       ## seconds of Tab before it is a wheel and not a tap
var dead_zone := 0.3                       ## fraction of the radius that is "the middle"
var mouse_pixels := 140.0                  ## mouse travel from the middle to the rim
var is_open := false
var pointer := Vector2.ZERO                ## inside the unit disc; y is down, like the screen
var _held := false
var _held_for := 0.0


func _init(ids: Array = []) -> void:
	set_slots(ids)


func set_slots(ids: Array) -> void:
	slots = ids.duplicate()
	while slots.size() < SLOTS:
		slots.append("")
	slots.resize(SLOTS)


## Which slot (0 is the top, then clockwise) a direction points at, or -1 inside the
## dead zone. `dir` is a pointer position in the unit disc.
static func slot_at(dir: Vector2, dead: float, count: int = SLOTS) -> int:
	if dir.length() < dead:
		return -1
	var step := TAU / count
	var angle := fposmod(atan2(dir.x, -dir.y), TAU)
	return int(roundf(angle / step)) % count


## Where slot i sits, as a unit direction (0 is the top, then clockwise).
static func slot_dir(i: int, count: int = SLOTS) -> Vector2:
	var a := TAU / count * i
	return Vector2(sin(a), -cos(a))


func id_at(i: int) -> String:
	return str(slots[i]) if i >= 0 and i < slots.size() else ""


## A slot you may pick: it holds a weapon and the player may draw it.
func selectable(i: int) -> bool:
	var id := id_at(i)
	return id != "" and bool(can_draw.call(id))


## The slot under the pointer, or -1 (the middle).
func highlighted() -> int:
	return slot_at(pointer, dead_zone)


## The id that letting go now would draw, or "" (middle, empty or refused).
func choice() -> String:
	var i := highlighted()
	return id_at(i) if selectable(i) else ""


# ------------------------------------------------------------------ Tab

func is_held() -> bool:
	return _held


func press() -> void:
	if _held:
		return
	_held = true
	_held_for = 0.0


## Time passing with Tab down. True on the frame the wheel opens.
func tick(dt: float) -> bool:
	if not _held or is_open:
		return false
	_held_for += dt
	if _held_for >= hold_time:
		is_open = true
		pointer = Vector2.ZERO
		return true
	return false


## Tab let go. Returns what to draw ("" = nothing). Whether it was a tap or a wheel
## is `is_open` read before this call.
func release() -> String:
	var picked := choice() if is_open else ""
	cancel()
	return picked


## Close without picking (died, started talking, weapons turned off).
func cancel() -> void:
	_held = false
	_held_for = 0.0
	is_open = false
	pointer = Vector2.ZERO


# ------------------------------------------------------------------ pointing

func move_mouse(relative: Vector2) -> void:
	if not is_open:
		return
	pointer += relative / mouse_pixels
	if pointer.length() > 1.0:
		pointer = pointer.normalized()


## WASD / arrows: a held direction (y down). Zero changes nothing. A key that
## points at a slot you can not pick (empty, or a weapon you may not draw) jumps to
## the nearest one you can, so the keys always land on a weapon. The mouse is
## free to rest on a dimmed slot.
func push_keys(dir: Vector2) -> void:
	if not is_open or dir == Vector2.ZERO:
		return
	pointer = dir.normalized()
	var i := slot_at(pointer, dead_zone)
	if selectable(i):
		return
	var near := nearest_selectable(i)
	if near >= 0:
		pointer = slot_dir(near)


## The slot you can pick that is fewest steps round the wheel from slot i (either
## way); the lower slot wins a tie. -1 when nothing can be picked.
func nearest_selectable(i: int) -> int:
	var best := -1
	var best_d := SLOTS
	for j in SLOTS:
		if not selectable(j):
			continue
		var d := absi(j - i)
		d = mini(d, SLOTS - d)
		if d < best_d:
			best = j
			best_d = d
	return best
