extends RefCounted
## Energy blade (M3). Pure, headless-testable melee state machine with a stamina
## budget. The core skill is DEFLECTION: pressing block and holding it through an
## incoming bolt within a tight timing window deflects the bolt instead of taking
## its damage. Stamina gates light/heavy attacks and sustained blocking.
##
## This is the melee combat layer of M3. The duelist enemy that also blocks,
## parries, and pressures is a separate brain; it consumes the same blade logic so
## it can deflect the player's bolts too.

enum State {
	IDLE,
	LIGHT,
	HEAVY,
	BLOCK,
	BLOCKED_OUT,
}

enum BoltResult {
	PIERCED,    ## not blocking -> the bolt lands as damage
	BLOCKED,    ## blocking late -> damage absorbed, stamina drained
	DEFLECTED,  ## blocked early enough -> bolt is reflected, stamina refunded
}

var config: Dictionary
var stamina: float
var max_stamina: float
var state := State.IDLE
var _state_time := 0.0        ## time in the current action state
var _block_elapsed := 0.0     ## time since the block was pressed
var _recovering := false            ## cooldown before the next attack is allowed
var _recover_time := 0.0
var _since_exert := 999.0           ## issue #133: seconds since the sprint last spent stamina

# Tunable timing windows.
var light_duration := 0.25
var heavy_duration := 0.5
var light_cost := 8.0
var heavy_cost := 16.0
var block_drain_per_sec := 5.0   ## stamina lost per second while blocking
var deflect_window := 0.18       ## block must have started within this window to deflect
var deflect_refund := 6.0


func _init(cfg: Dictionary) -> void:
	config = cfg
	# Defaults so the blade is usable even with a bare config; override later.
	max_stamina = float(cfg.get("max_stamina", 100.0))
	stamina = max_stamina
	block_drain_per_sec = float(cfg.get("block_cost_stamina", 5.0))
	deflect_window = float(cfg.get("deflect_window", 0.18))
	deflect_refund = float(cfg.get("deflect_refund_stamina", 6.0))


func reset() -> void:
	state = State.IDLE
	stamina = max_stamina
	_state_time = 0.0
	_block_elapsed = 0.0
	_recovering = false
	_recover_time = 0.0


func can_act() -> bool:
	return state == State.IDLE and not _recovering


func light_attack() -> bool:
	## Begin a light attack. Returns true only if there is stamina and we are free.
	if not can_act() or stamina < light_cost:
		return false
	stamina -= light_cost
	state = State.LIGHT
	_state_time = 0.0
	return true


func heavy_attack() -> bool:
	if not can_act() or stamina < heavy_cost:
		return false
	stamina -= heavy_cost
	state = State.HEAVY
	_state_time = 0.0
	return true


## A follow-up in a chain (SwordCombo): the swing before flows straight into it, so
## it skips the recovery. It still needs the stamina.
func chain_attack(heavy: bool) -> bool:
	if state == State.BLOCK or state == State.BLOCKED_OUT:
		return false
	var cost := heavy_cost if heavy else light_cost
	if stamina < cost:
		return false
	stamina -= cost
	state = State.HEAVY if heavy else State.LIGHT
	_state_time = 0.0
	_recovering = false
	_recover_time = 0.0
	return true


func start_block() -> void:
	## Start (or continue) blocking. The deflect window opens from this moment.
	if state == State.BLOCK:
		return
	if _recovering:
		return
	state = State.BLOCK
	_block_elapsed = 0.0
	_state_time = 0.0


func end_block() -> void:
	if state != State.BLOCK:
		return
	state = State.IDLE
	_block_elapsed = 0.0


func is_blocking() -> bool:
	return state == State.BLOCK


func light_damage() -> int:
	return int(config.get("light_damage", 16))


func heavy_damage() -> int:
	return int(config.get("heavy_damage", 30))


## The active attack's damage this frame, if we are in an attack that deals damage
## on its first frame. Callers can poll this when they want to know "hit now?".
func incoming_damage_this_frame() -> int:
	match state:
		State.LIGHT:
			return light_damage()
		State.HEAVY:
			return heavy_damage()
	return 0


## Issue #133: the player's sprint spends this same stamina. Regen waits until
## half a second after the last spend.
func exert(cost: float) -> void:
	stamina = maxf(0.0, stamina - cost)
	_since_exert = 0.0


## Advance the blade one frame. Regens stamina when standing down; drains it while
## blocking. Returns the blade's current State so tests can observe the result.
func update(dt: float) -> int:
	_state_time += dt
	_since_exert += dt

	# (1) Advance any in-progress recovery FIRST, so a BLOCKED_OUT entered by this
	# frame's drain is not advanced through its own cooldown in the same frame.
	if _recovering:
		_recover_time -= dt
		if _recover_time <= 0.0:
			_recovering = false
			if state == State.BLOCKED_OUT:
				state = State.IDLE

	if state == State.LIGHT or state == State.HEAVY:
		var dur: float = heavy_duration if state == State.HEAVY else light_duration
		if _state_time >= dur:
			state = State.IDLE
			_start_recovery(0.15)

	if state == State.BLOCK:
		_block_elapsed += dt
		# Blocking drains stamina; when it bottoms out we are forced into a cooldown.
		stamina = maxf(0.0, stamina - block_drain_per_sec * dt)
		if stamina <= 0.0:
			state = State.BLOCKED_OUT
			_start_recovery(0.4)

	if state == State.BLOCKED_OUT and not _recovering:
		# Defensive: enter a recovery if we somehow bottom out without one running.
		_start_recovery(0.4)

	# Recover stamina when standing down -- but not on the frame an action just
	# ended (the cost must stay visible for a moment), and not while recovering.
	if state == State.IDLE and not _recovering and _state_time > 0.5 and _since_exert > 0.5:
		stamina = minf(max_stamina, stamina + 18.0 * dt)

	return state


## Resolve an incoming bolt against the blade's current block.
## Returns a BoltResult: DEFLECTED reflects the bolt (and refunds stamina),
## BLOCKED absorbs it at a stamina cost, PIERCED means the bolt lands as damage
## (we are not blocking). Timed deflection: a block started within `deflect_window`
## of the bolt reflects it; a block held longer merely absorbs it.
func intercept_bolt() -> int:
	if state != State.BLOCK:
		return BoltResult.PIERCED
	# A freshly pressed block within the deflect window reflects the bolt.
	if _block_elapsed <= deflect_window:
		stamina = minf(max_stamina, stamina + deflect_refund)
		return BoltResult.DEFLECTED
	# Otherwise absorb the bolt, paying stamina.
	stamina = maxf(0.0, stamina - block_drain_per_sec * 0.5)
	if stamina <= 0.0:
		state = State.BLOCKED_OUT
		_start_recovery(0.15)
	return BoltResult.BLOCKED


func _start_recovery(seconds: float) -> void:
	_recovering = true
	_recover_time = seconds
