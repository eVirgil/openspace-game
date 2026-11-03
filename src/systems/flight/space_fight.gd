class_name SpaceFight
extends Node3D
## A space encounter in the port's own sky (issue #46). Flying out of the
## atmosphere used to hand off to the dogfight scene, which unloaded the town and
## loaded it again on the way down: a pause and a restart. Now the town scene
## stays, and this node runs the same pure director (dogfight.gd) right where the
## ship is, so space is just the sky above the port.
##
## The encounter is authored around the origin, facing -Z; begin() moves it onto
## the ship (allies keep their place beside you, waves arrive ahead of you). The
## player's ship in the director takes over the town ship's position, heading and
## speed, and ShipPilot copies it back every frame, so the parked model the town
## built is still the ship on screen. A DogfightView draws everyone else.
##
## No input here: ShipPilot passes the player's command to step(). The combat
## read-out (shield, hull, guns, target box, lead marker) is drawn here; toasts go
## through the pilot's FlightHud.
##
## LAN: in a host's game, its fight is everyone's: NetFight sends its ships and
## lands the guests' hits on them. A guest who climbs out while it is on flies a
## copy of it (`net_copy`, set before begin()): only their own ship, everyone else
## the host's, put where the host's are.

const Dogfight := preload("res://src/systems/flight/dogfight.gd")

var df
var view: DogfightView
var encounter_id := ""
var hud: Control
var hud_label: Label
var sheltered := false   ## the fight goes on without the player (Dogfight.player_sheltered)
var net_copy := false    ## LAN: a guest's copy of the host's fight (NetFight)
var net_ids := {}        ## LAN, net_copy: the host's ship id -> the copy's here
var net_sent := 0        ## LAN: the last projectile uid NetFight has looked at


## Start `enc_id` around a ship flying with transform `at` at `speed` m/s.
## Returns false (and starts nothing) for an unknown encounter. Pass the scene's
## ShipKit: a new one builds its own materials, a 60 ms hitch mid-flight.
## `player_ship` (issue #43) flies the encounter as that ship instead of its own
## player ship: whichever ship you took up.
func begin(content, enc_id: String, at: Transform3D, speed: float, rng_seed: int = 1, kit: ShipKit = null,
		player_ship: String = "") -> bool:
	encounter_id = enc_id
	name = "SpaceFight"
	df = Dogfight.new(content, enc_id, rng_seed)
	if df.encounter.is_empty():
		return false
	var fwd := -at.basis.z
	var yaw := atan2(-fwd.x, -fwd.z) if Vector2(fwd.x, fwd.z).length() > 0.01 else 0.0
	df.encounter = placed(df.encounter, at.origin, yaw)
	if player_ship != "" and df.encounter.has("player"):
		df.encounter.player.ship = player_ship
	if net_copy:
		df.net_copy = true
		df.encounter["allies"] = []      # the host's wingmen come as copies
	df.wave_yaw = yaw
	# Issue #15: everyone who spawns gets a name; each sortie brings new pilots.
	df.names = WorldState.names
	df.name_scope = "pilot:%s/%d" % [enc_id, WorldState.bump("sorties_" + enc_id)]
	df.start()
	var me: Dictionary = df.get_ship(df.player_id)
	if not me.is_empty():
		# Zero throttle stops her here too, as it does in normal flight (a VTOL
		# fighter hovers): the throttle means the same speed on both sides of the
		# switch, so leaving the cruiser's bay at zero is not a jump to the fight's
		# floor. The fight's own ships keep theirs and never stall.
		me.flight.cfg = me.flight.cfg.duplicate()
		me.flight.cfg["min_speed"] = 0.0
		me.flight.basis = at.basis.orthonormalized()
		me.flight.position = at.origin
		me.flight.speed = minf(speed, me.flight.max_speed())
	view = DogfightView.new(kit)
	view.skip_id = df.player_id
	add_child(view)
	view.sync(df)
	_build_hud()
	return true


## The encounter moved onto the ship: its player spawn on `origin`, everything else
## turned by `yaw` about it. Pure (a copy), so tests can check the placement.
static func placed(enc: Dictionary, origin: Vector3, yaw: float) -> Dictionary:
	var out := enc.duplicate(true)
	var pl: Dictionary = out.get("player", {})
	var pivot := Dogfight._vec(pl.get("spawn", [0, 0, 0]))
	var move := func(a) -> Array:
		var v: Vector3 = (Dogfight._vec(a) - pivot).rotated(Vector3.UP, yaw) + origin
		return [v.x, v.y, v.z]
	var turn := func(a) -> Array:
		var v: Vector3 = Dogfight._vec(a).rotated(Vector3.UP, yaw)
		return [v.x, v.y, v.z]
	if not pl.is_empty():
		pl["spawn"] = move.call(pl.get("spawn", [0, 0, 0]))
		pl["facing"] = turn.call(pl.get("facing", [0, 0, -1]))
	for a in out.get("allies", []):
		a["spawn"] = move.call(a.get("spawn", [0, 0, 0]))
		a["facing"] = turn.call(a.get("facing", [0, 0, -1]))
	var arena: Dictionary = out.get("arena", {})
	arena["center"] = move.call(arena.get("center", [0, 0, 0]))
	out["arena"] = arena
	return out


func running() -> bool:
	return df != null and df.state == Dogfight.State.RUNNING


func won() -> bool:
	return df != null and df.state == Dogfight.State.COMPLETE


func payout() -> int:
	return int(df.encounter.get("payout", 0)) if df != null else 0


## The player's flight model in the director (position, basis, speed).
func player_flight():
	var me: Dictionary = df.get_ship(df.player_id) if df != null else {}
	return me.flight if not me.is_empty() else null


## Out of the fight for now (or back in): nobody targets her, and the combat
## read-out is put away until she is.
func set_sheltered(on: bool) -> void:
	sheltered = on
	if df != null:
		df.player_sheltered = on
	if hud != null:
		hud.get_parent().visible = not on


func next_target() -> void:
	if df != null:
		df.cycle_player_target()


## Advance the fight. `cmd`: { pitch, yaw, roll, throttle, boost, fire, missile }.
## Returns the director's events for this step.
func step(dt: float, cmd: Dictionary) -> Array:
	if df == null:
		return []
	var net = _net()
	var news: Array = net.before_step(self, dt) if net != null else []
	if net_copy and net == null:
		news = [{ "type": "net_over" }]     # out of the LAN game: the host's fight is gone
	df.set_player_command(float(cmd.get("pitch", 0.0)), float(cmd.get("yaw", 0.0)),
		float(cmd.get("roll", 0.0)), float(cmd.get("throttle", 0.6)), bool(cmd.get("boost", false)),
		bool(cmd.get("fire", false)), bool(cmd.get("missile", false)))
	var ev: Array = df.step(dt)
	if net != null:
		net.after_step(self, ev)
	ev.append_array(news)
	for e in ev:
		view.on_event(e)
	view.sync(df)
	view.tick(dt)
	_update_hud()
	return ev


## The fight is over for this game (ShipPilot.end_fight): a host's ends for the
## guests flying copies of it too.
func finish(outcome: String) -> void:
	var net = _net()
	if net != null and not net_copy:
		net.host_over(self, outcome)


## LAN's fight node (/root/NetLink/Fight), or null out of a LAN game.
func _net():
	return NetSession.link.get_node_or_null("Fight") if NetSession.active() else null


# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "FightHud"
	layer.layer = 5
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	hud.draw.connect(_draw_hud)
	hud_label = Label.new()
	hud_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hud_label.position = Vector2(-430, 54)
	hud_label.size = Vector2(400, 170)
	hud_label.add_theme_font_size_override("font_size", RetroUI.size("space_fight", 22))   # issue #71
	hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud_label.add_theme_color_override("font_color", Color(0.5, 0.95, 1.0, 0.95))
	hud_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	hud_label.add_theme_constant_override("outline_size", 4)
	hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hud_label)


func _update_hud() -> void:
	var me: Dictionary = df.get_ship(df.player_id)
	if me.is_empty() or hud_label == null:
		return
	var d = me.defense
	var tgt: Dictionary = df.get_ship(df.player_target_id)
	var tline := "no target"
	if not tgt.is_empty() and tgt.alive:
		var who := Dogfight.who(tgt)
		tline = "%s  %d m" % [who if who != "" else str(tgt.cfg.get("label", tgt.ship_id)),
			int((tgt.flight.position - me.flight.position).length())]
	hud_label.text = "SHIELD %3d  HULL %3d\nGUNS %d%s  SEEKERS %d%s  LOCK %3d%%\nTARGET %s\nWAVE %d/%d  HOSTILES %d" % [
		int(d.shield), d.hull_hp(),
		me.loadout.group_ammo("primary"), " (cooling)" if me.loadout.group_reloading("primary") else "",
		me.loadout.group_ammo("secondary"), " (reloading)" if me.loadout.group_reloading("secondary") else "",
		int(me.lock.fraction() * 100.0), tline,
		df.stats.waves, df.waves_total(), df.alive_on(Dogfight.TEAM_HOSTILE).size()]
	hud.queue_redraw()


func _draw_hud() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null or df == null:
		return
	var tgt: Dictionary = df.get_ship(df.player_target_id)
	if tgt.is_empty() or not tgt.alive:
		return
	var tp: Vector3 = tgt.flight.position
	var lock_col := Color(1.0, 0.45, 0.3, 0.9)
	if not camera.is_position_behind(tp):
		var sp := camera.unproject_position(tp)
		hud.draw_rect(Rect2(sp - Vector2(18, 18), Vector2(36, 36)), lock_col, false, 1.5)
		var me: Dictionary = df.get_ship(df.player_id)
		if not me.is_empty() and me.lock.fraction() > 0.0:
			hud.draw_arc(sp, 26.0, -PI * 0.5, -PI * 0.5 + TAU * me.lock.fraction(), 32, lock_col, 2.5)
	var lead: Dictionary = df.player_lead()
	if lead.get("valid", false) and not camera.is_position_behind(lead.point):
		hud.draw_circle(camera.unproject_position(lead.point), 5.0, Color(1.0, 0.85, 0.4, 0.9))
