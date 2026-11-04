extends StaticBody3D
## Issue #401: another LAN player, in this town. The smuggler's own avatar
## (PlayerAvatar) in that player's outfit (kept up as they change it), their name
## floating over it, walking, sprinting, crouching and jumping as they do, the
## weapon in their hand: raised while they aim or fire, lowered while they sprint,
## pointed where their crosshair is, kicking as they shoot; the blade swinging and
## blocking as theirs. The body faces where they look whenever their own would (a
## weapon up, first person).
##
## Friendly fire (lan.json "friendly_fire"): the body is solid, like a guard's, and
## your bolts and blade land on it. It takes no damage itself: the hit goes to
## that player's game (NetLink.hit), which applies it to their own player, so
## being downed works there as it always does. Only your own hits are sent (a
## guard's bolt in your game is not one in theirs). Off: nothing to hit or bump.
## Your hit marker waits for their game's answer (NetLink.hit_back), so it shows
## only when the hit hurt them, and as a kill when it put them down.
##
## NetLink hands it every state packet heard (hear); between packets it closes on
## where the player should be by now (the last spot plus the velocity since),
## smoothed so it does not jitter, and jumps when it is snap_m off (a teleport).
##
## Downed (NetLink.F_DOWNED), the body falls as a ragdoll where it was, pushed away
## from the hit that put them down, as their own does in their game (PlayerKit),
## with nothing to hit or bump. When they wake (the pit, wherever) the body there
## goes and they stand up where they are now. Their sword is their colour and hilt
## (the red saber's red on its black hilt), as heard in each packet.

const UPPER := {
	"pistol_blaster": BodyAnimator.UPPER_AIM,
	"rifle_blaster": BodyAnimator.UPPER_RIFLE,
	"sniper_rifle": BodyAnimator.UPPER_RIFLE,
	"energy_blade": BodyAnimator.UPPER_SWORD,
}
const LEAD_MAX := 0.25            ## seconds a body may run on past its last packet

var peer_id := 0
var player_name := ""
var outfit: Dictionary = {}
var avatar: PlayerAvatar
var tag: Label3D
var tilt := Basis.IDENTITY        ## the ground's frame (PlayerAvatar.animate reads its parent's)
var _mats: LookMaterials
var _s: Dictionary = {}           ## the last state heard
var _placed := false
var ragdoll: Ragdoll              ## while they are downed
var _hidden_weapon: Node3D
## HitFeedback reads this: never fresh, so your own game shows no marker for a hit
## here; it comes when that player's game says the hit landed (NetLink.hit_back).
var damage_usec := -1000000000
var velocity := Vector3.ZERO      ## as last heard (the host's NPCs lead their shots by it)


func setup(id: int, nm: String, fit: Dictionary, mats: LookMaterials = null) -> void:
	peer_id = id
	player_name = nm
	outfit = fit
	_mats = mats


func _ready() -> void:
	name = "Remote_%d" % peer_id
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = NetSession.n("hitbox_radius", 0.35)
	cap.height = NetSession.n("hitbox_height", 1.8)
	cs.shape = cap
	cs.position.y = cap.height * 0.5
	add_child(cs)
	collision_layer = 1 if friendly_fire() else 0
	collision_mask = 0
	avatar = PlayerAvatar.new(_mats, outfit)
	add_child(avatar)
	avatar.build_weapons(UPPER.keys())
	avatar.set_blade_extent(0.0)
	tag = Label3D.new()
	tag.name = "Name"
	tag.text = player_name
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position.y = NetSession.n("name_height", 2.15)
	# The same size on screen however far, and however far you zoom in (_process).
	# Further off the HUD marks them too (ObjectiveHud).
	tag.fixed_size = true
	tag.pixel_size = NetSession.n("name_px", 0.0011)
	tag.font_size = 40
	tag.outline_size = 10
	tag.modulate = Color(1.0, 0.93, 0.78)
	add_child(tag)
	visible = false               # until the first packet places it


## That player changed what they wear.
func wear(fit: Dictionary) -> void:
	outfit = fit
	if avatar != null:
		avatar.set_outfit(fit)


## The latest state packet (NetLink.state's dictionary).
func hear(s: Dictionary) -> void:
	_s = s
	tilt = Basis((s.get("tilt", Quaternion.IDENTITY) as Quaternion).normalized())
	if not _placed:
		global_position = s.pos
		_placed = true
		if avatar != null:
			avatar.facing_yaw = float(s.yaw)
			avatar.reset_render_smoothing()


## Where the player should be by now: the last spot heard, run on at its velocity.
func wanted() -> Vector3:
	if _s.is_empty():
		return global_position
	var since := clampf(Time.get_ticks_msec() / 1000.0 - float(_s.t), 0.0, LEAD_MAX)
	return (_s.pos as Vector3) + (_s.vel as Vector3) * since


## A fixed_size label keeps its size against distance but not against the lens:
## through a 2.5x scope it is 2.5x as big. So its pixel_size shrinks with the fov,
## back to name_px at the view's unzoomed `base_fov`.
static func zoomed_px(px: float, base_fov: float, fov: float) -> float:
	if base_fov <= 0.0 or fov <= 0.0:
		return px
	return px * tan(deg_to_rad(fov) * 0.5) / tan(deg_to_rad(base_fov) * 0.5)


func _process(_dt: float) -> void:
	if tag == null or not visible:
		return
	var cam := get_viewport().get_camera_3d()
	var px := NetSession.n("name_px", 0.0011)
	if cam != null:
		# The on-foot view's CameraRigNode knows its unzoomed lens; any other camera
		# (a ship's, a cutscene's) is taken as unzoomed.
		var base = cam.get_parent().get("base_fov") if cam.get_parent() != null else null
		px = zoomed_px(px, float(base) if base != null else cam.fov, cam.fov)
	tag.pixel_size = px


func _physics_process(dt: float) -> void:
	if _s.is_empty() or avatar == null:
		return
	var flags := int(_s.flags)
	visible = (flags & 8) != 0          # NetLink.F_VISIBLE: not while they sit in a ship
	velocity = _s.vel
	_wear_blade(_s.get("blade", []))
	if _ragdolled(dt, (flags & 512) != 0):   # NetLink.F_DOWNED
		collision_layer = 0
		return
	collision_layer = 1 if visible and friendly_fire() else 0
	var to := wanted()
	if global_position.distance_to(to) > NetSession.n("snap_m", 8.0):
		global_position = to
		avatar.reset_render_smoothing()
	else:
		global_position = global_position.lerp(to, 1.0 - exp(-NetSession.n("smooth_rate", 14.0) * dt))
	var weapon := str(_s.weapon)
	avatar.current = weapon
	avatar.drawn = float(_s.drawn)
	avatar.set_blade_extent(float(_s.drawn) if weapon == "energy_blade" else 0.0)
	# Aiming as they do: the gun comes up while they hold the trigger or aim (always
	# in first person, where the body also faces the look), drops while they
	# sprint, points where their crosshair is; the blade swings as theirs does.
	var fp := (flags & 128) != 0                  # NetLink.F_FIRST_PERSON
	avatar.aim_wanted = (flags & 32) != 0 or fp   # NetLink.F_AIM
	avatar.sprint_lowered = (flags & 64) != 0     # NetLink.F_SPRINT_LOW
	avatar.face_aim = fp
	avatar.aim_target = _s.get("aim_at", Vector3.INF)
	avatar.sword_pose = _s.get("sword", {}) if weapon == "energy_blade" else {}
	avatar.sword_trail_on = weapon == "energy_blade" and (flags & 256) != 0   # NetLink.F_CUTTING
	avatar.reload = float(_s.get("reload", -1.0))
	avatar.animate(dt, {
		"velocity": _s.vel,
		"grounded": (flags & 1) != 0,
		"crouch": (flags & 2) != 0,
		"sprint": (flags & 4) != 0,
		"slide": (flags & 16) != 0,
		"cam_yaw": float(_s.yaw),
		"aim_pitch": float(_s.pitch),
		"upper": UPPER.get(weapon, BodyAnimator.UPPER_FREE),     # as PlayerWeapons.upper_mode: the avatar holsters by `drawn`
	})


## What the host's NPCs read of them (NpcBody.watches_guests), as for the player.
func downed() -> bool:
	return not _s.is_empty() and (int(_s.flags) & 512) != 0    # NetLink.F_DOWNED


func crouched() -> bool:
	return not _s.is_empty() and (int(_s.flags) & 2) != 0


func armed() -> bool:
	return not _s.is_empty() and str(_s.weapon) != ""


# ------------------------------------------------------------------ downed

## Downed: the body goes limp where it is (away from the hit), the weapon in hand
## put away; up again, every joint goes back and the body is where they are now
## (the one on the ground is gone). True while the ragdoll owns the body.
func _ragdolled(dt: float, down: bool) -> bool:
	if not down:
		if ragdoll != null:
			ragdoll.stop()
			ragdoll = null
			if _hidden_weapon != null and is_instance_valid(_hidden_weapon):
				_hidden_weapon.visible = true
			_hidden_weapon = null
			global_position = wanted()
			avatar.reset_render_smoothing()
		return false
	if ragdoll == null:
		if not is_inside_tree():
			return false
		var cfg := Ragdoll.load_config()
		var hit: Array = _s.get("hit", [])
		var from: Vector3 = hit[0] if hit.size() >= 2 and hit[0] is Vector3 else Vector3.INF
		var amount := float(hit[1]) if hit.size() >= 2 else 0.0
		var kick := Ragdoll.kick_for(global_position, from, amount, cfg)
		ragdoll = Ragdoll.new(avatar.joints, cfg)
		ragdoll.start(_s.vel, kick, get_world_3d().direct_space_state, [get_rid()])
		var w := avatar.weapon_node(avatar.current)
		if w != null and w.visible:
			_hidden_weapon = w
			w.visible = false
	var moving := not ragdoll.asleep
	ragdoll.step(dt)
	if moving and avatar.skin != null:
		avatar.skin.sync(avatar.body)
	return true


## Issue #148: their sword's [colour, hilt] (alpha 0 / "": the default blue one).
## A hilt is only ever one of the game's own models.
func _wear_blade(b: Array) -> void:
	if b.size() < 2 or not (b[0] is Color):
		return
	var hilt := str(b[1])
	if hilt != "" and (not hilt.begins_with("res://assets/") or not ResourceLoader.exists(hilt)):
		hilt = ""
	if avatar.blade_color != b[0] or avatar.blade_hilt != hilt:
		avatar.set_blade_color(b[0], hilt)


# ------------------------------------------------------------------ friendly fire

static func friendly_fire() -> bool:
	return bool(NetSession.cfg().get("friendly_fire", true))


## Your game's player, the only shooter whose hits are sent.
func _you() -> Node:
	var scene := get_tree().current_scene if is_inside_tree() else null
	return scene.get("_player") if scene != null else null


## Bolts (and a ship cannon's splash) call this. Issue #402: in the host's game an
## NPC's bolt that lands on a guest's body is a hit on that guest, from the town,
## and so is a Remnant (or locals') droid's.
func apply_damage_from(amount: float, shooter: Node) -> void:
	if shooter != null and is_instance_valid(shooter) and shooter == _you():
		_send_hit(amount)
	elif (shooter is NpcBody or (shooter is DroidController.DroidUnit and shooter.faction != "")) \
			and NetSession.is_host() and amount > 0.0:
		NetSession.link.send_town_hit(peer_id, amount, (shooter as Node3D).global_position)


## Your blade calls this (it is the only one that does).
func apply_blade_hit(amount: float, _dir: Vector3) -> void:
	_send_hit(amount)


## Anything else that hurts without saying who (a fall, a hazard) is not a hit from you.
func apply_damage(_amount: float) -> void:
	pass


func _send_hit(amount: float) -> void:
	var you = _you()
	if friendly_fire() and NetSession.active() and amount > 0.0 and you is Node3D:
		NetSession.link.send_hit(peer_id, amount, (you as Node3D).global_position)
