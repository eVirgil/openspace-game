class_name PlayerWeapons
extends Node
## The player's hand weapons in the port (M11): blaster pistol, energy sword and
## rifle, the swap between them, firing, the sword's swings and block, and turning
## enemy bolts around. Owns the HUD bits for weapons (crosshair, ammo); stamina
## shows in the RetroHud footer.
##
## Controls (project.godot actions):
##   1 / 2 / 3     blaster / energy sword / rifle   (same key again holsters)
##   Q             last weapon        mouse wheel   cycle        H   holster
##   Tab           next weapon, and hands free after the last one
##   LMB (fire)    shoot / swing: a click swipes left, the next right, and so on;
##                 a double click is the combo, left-right-centre
##   RMB (alt)     right-click TOGGLES: blaster aim/zoom in-out, sword block on-off
##                 (re-click to undo; with the sword, block just before a bolt lands
##                 to deflect it back)
##   R             reload
##
## The pure parts are proven headless: WeaponHolder (swap), SwordCombo (chain,
## active frames), Weapon (ammo/reload) and EnergyBlade (stamina, deflect window).

const Weapon := preload("res://src/systems/combat/weapon.gd")
const SwordCombo := preload("res://src/systems/combat/sword_combo.gd")
const WeaponHolder := preload("res://src/systems/combat/weapon_holder.gd")
const BodyAnimator := preload("res://src/systems/anim/body_animator.gd")
const Ads := preload("res://src/systems/look/ads.gd")
const BoltScene := preload("res://scenes/entities/bolt.tscn")
const LOOK_PATH := "res://content/look/hand_weapons.json"

signal fired(weapon_id: String)
signal swung(name: String)
signal deflected(bolt: Node)
signal hit_something(target: Node, damage: float)

var player: CharacterBody3D
var avatar: PlayerAvatar
var rig_node: Node3D                ## camera_rig_node.gd
var bolt_parent: Node3D
var holder := WeaponHolder.new(["pistol_blaster", "energy_blade", "rifle_blaster"])
var guns: Dictionary = {}           ## id -> Weapon (ammo + timing)
var combo: SwordCombo
var look: Dictionary = {}
var cfg: Dictionary = {}            ## core weapon data by id
var enabled := true                 ## false while talking at the bar
var in_range_zone: Callable = Callable()   ## (pos) -> bool: on the sanctioned range?
var off_record_zone: Callable = Callable() ## (pos) -> bool: nobody counts shots here (at the party barge)

var blade_extent := 0.0
var aiming := false
var shots := 0
var deflections := 0
var blocks := 0
var sword_hits := 0

var _fire_held := false
var _alt_on := false
var _hitstop := 0.0
var _tip_was := Vector3.INF         ## the blade tip last frame of a swing (INF = not swinging)
var _sfx: Dictionary = {}
var _sfx_pitch: Dictionary = {}     ## key -> base pitch (the rifle is the pistol's shot, slowed and deeper)
var _hum: AudioStreamPlayer
var _hud: CanvasLayer
var _cross: Control
var _ammo: Label
var _name: Label
var _name_left := 0.0
var feedback: HitFeedback           ## hit markers + thud (issue #65)

## Issue #133: the Shift sprint. While it is on the gun is down, nothing fires or
## swings, and it spends the blade's stamina (one STA bar for both). Run dry and
## you drop to the run until stamina is back up to sprint_resume.
var sprint_drain := 20.0            ## stamina per second (100 lasts 5 s)
var sprint_resume := 25.0
var sprinting := false
var winded := false


func setup(p: CharacterBody3D, a: PlayerAvatar, rig: Node3D, bolts_into: Node3D) -> void:
	player = p
	avatar = a
	rig_node = rig
	bolt_parent = bolts_into
	look = CharacterKit._read_json(LOOK_PATH)
	for id in holder.slots:
		cfg[id] = GearUpgrades.apply(CharacterKit._read_json("res://content/core/weapons/%s.json" % id), id)
		if id != "energy_blade":
			guns[id] = Weapon.new(cfg[id])
	combo = SwordCombo.new(cfg.get("energy_blade", {}))
	holder.can_draw = func(id): return WorldState.weapon_allowed(id)      # issue #200: a story save starts with the pistol only
	avatar.build_weapons(holder.slots)
	avatar.set_blade_extent(0.0)


## Issue #208: the fence fitted an upgrade: each gun takes its data again with
## every upgrade on (the magazine keeps its rounds).
func refit() -> void:
	for id in guns:
		cfg[id] = GearUpgrades.apply(CharacterKit._read_json("res://content/core/weapons/%s.json" % id), id)
		(guns[id] as Weapon).config = cfg[id]


func _ready() -> void:
	name = "Weapons"
	_build_sfx()
	_build_hud()


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			holder.cycle(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			holder.cycle(1)
	for n in 3:
		if event.is_action_pressed("weapon_%d" % (n + 1)):
			holder.request_slot(n + 1)
	if event.is_action_pressed("weapon_last"):
		holder.request_last()
	if event.is_action_pressed("weapon_cycle"):
		holder.cycle_to_empty()
	if event.is_action_pressed("holster"):
		holder.request("")
	if event.is_action_pressed("reload") and guns.has(holder.current):
		(guns[holder.current] as Weapon).start_reloading()
	if event.is_action_pressed("fire"):
		_fire_held = true
		if holder.current == "energy_blade" and holder.is_ready() and not sprinting:
			if combo.attack():
				_on_swing_started()
	elif event.is_action_released("fire"):
		_fire_held = false
	if event.is_action_pressed("alt_fire"):
		toggle_alt()


## Bot / test seam: drive the same paths without input events.
func press_fire() -> void:
	_fire_held = true
	if holder.current == "energy_blade" and holder.is_ready() and not sprinting and combo.attack():
		_on_swing_started()


func release_fire() -> void:
	_fire_held = false


func set_alt(on: bool) -> void:
	_alt_on = on


## Right-click: flip aim (blaster zoom) with the sword's block. Re-click undoes it.
func toggle_alt() -> void:
	_alt_on = not _alt_on


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		_fire_held = false
		_alt_on = false
		combo.set_block(false)
		aiming = false
		if rig_node != null:
			rig_node.set_zoom(1.0)
	_hud.visible = on


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	if player == null:
		return
	for ev in holder.update(dt):
		_on_holder_event(str(ev))
	var cur := holder.current
	# Blade extent follows the swap: ignite while drawing, retract while holstering.
	var want := 0.0
	if cur == "energy_blade":
		want = 1.0 if holder.phase != WeaponHolder.Phase.HOLSTERING else 0.0
	blade_extent = move_toward(blade_extent, want, dt / 0.15)
	avatar.set_blade_extent(blade_extent)
	if _hum != null:
		var on := cur == "energy_blade" and blade_extent > 0.5
		if on and not _hum.playing:
			_hum.play()
		elif not on and _hum.playing:
			_hum.stop()

	_tick_sprint(dt)

	# Guns tick every frame (cooldowns, reloads) whether or not the trigger is down.
	# Issue #87: in third person a resting gun comes up first, then fires.
	avatar.aim_wanted = enabled and not sprinting and (_fire_held or _alt_on)
	# Third person: the gun points where the crosshair does, not straight out of the chest.
	avatar.aim_target = aim_point() if not avatar.first_person and guns.has(cur) else Vector3.INF
	for id in guns:
		var g: Weapon = guns[id]
		var trigger: bool = enabled and id == cur and holder.is_ready() and _fire_held and avatar.gun_up() \
			and not sprinting
		var r: int = g.start_firing(dt, trigger)
		if r == Weapon.Result.SHOT:
			_shoot(id)
	aiming = enabled and guns.has(cur) and holder.is_ready() and _alt_on and not sprinting
	if rig_node != null:
		# Each gun has its own magnification (issue #65): fov = base / mag.
		rig_node.set_zoom(Ads.zoom(look, cur) if aiming else 1.0)
		avatar.ads_camera = rig_node.camera()
	avatar.ads_on = aiming

	# Sword.
	var sdt := dt * (0.08 if _hitstop > 0.0 else 1.0)
	_hitstop = maxf(0.0, _hitstop - dt)
	combo.set_block(enabled and cur == "energy_blade" and holder.is_ready() and _alt_on and not sprinting)
	for ev in combo.update(sdt):
		if str(ev).begins_with("swing:"):
			_on_swing_started()
		elif str(ev) == "block_broken":
			# Out of stamina: let go of the toggle, or the guard goes straight back
			# up the moment the cooldown ends and stamina never gets to recover.
			_alt_on = false
	if cur == "energy_blade" and combo.is_active():
		_sword_hits()
	else:
		_tip_was = Vector3.INF
	if cur == "energy_blade" and blade_extent > 0.5:
		_intercept_bolts()
	avatar.sword_pose = combo.pose(avatar.first_person) if cur == "energy_blade" else {}
	avatar.sword_trail_on = cur == "energy_blade" and combo.cutting()
	avatar.current = cur
	avatar.drawn = holder.drawn()
	avatar.reload = (guns[cur] as Weapon).reload_progress() if guns.has(cur) else -1.0
	_update_hud(dt)


func upper_mode() -> String:
	match holder.current:
		"pistol_blaster":
			return BodyAnimator.UPPER_AIM
		"rifle_blaster":
			return BodyAnimator.UPPER_RIFLE
		"energy_blade":
			return BodyAnimator.UPPER_SWORD
	return BodyAnimator.UPPER_FREE


## Issue #133: read the sprint off the movement controller, spend stamina on it and
## tell the controller whether it may keep sprinting.
func _tick_sprint(dt: float) -> void:
	var ctl = player.get("controller")
	if ctl == null or not ctl.has_method("is_dashing"):
		sprinting = false
		return
	sprinting = ctl.is_dashing()
	var b = combo.blade
	if sprinting:
		b.exert(sprint_drain * dt)
	if b.stamina <= 0.0:
		winded = true
	elif winded and b.stamina >= sprint_resume:
		winded = false
	ctl.dash_allowed = not winded
	avatar.sprint_lowered = sprinting


func _on_holder_event(ev: String) -> void:
	var parts := ev.split(":")
	match parts[0]:
		"drawing":
			if parts[1] == "energy_blade":
				_alt_on = false     # an aim toggled on with a gun is not a block
			_play("blade_on" if parts[1] == "energy_blade" else "swap")
			_show_name(str(cfg.get(parts[1], {}).get("label", parts[1])))
		"holstered":
			if parts[1] == "energy_blade":
				_play("blade_off")
				combo.reset()
			if holder.pending == "":
				_show_name("Holstered")


# ------------------------------------------------------------------ blasters

## Where the crosshair points: the first thing under the screen center. In the
## cinematic view (no crosshair) it is the third person view's center.
func aim_point() -> Vector3:
	var cam: Camera3D = rig_node.camera() if rig_node != null else null
	if cam == null or not cam.is_inside_tree():
		return avatar.global_position + avatar.global_basis.z * 50.0
	var view: Transform3D = rig_node.aim_transform() if rig_node.has_method("aim_transform") else cam.global_transform
	var from := view.origin
	var dir := -view.basis.z
	var to := from + dir * 250.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [player.get_rid()]
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else to


func _shoot(id: String) -> void:
	var c: Dictionary = cfg[id]
	var origin := avatar.muzzle_position()
	var target := aim_point()
	var dir := (target - origin).normalized()
	# A touch of spread, less when aiming.
	var spread := deg_to_rad(float(c.get("spread_deg", 1.2)) * (0.35 if aiming else 1.0))
	dir = dir.rotated(dir.cross(Vector3.UP).normalized(), randf_range(-spread, spread)).rotated(Vector3.UP, randf_range(-spread, spread))
	var b = BoltScene.instantiate()
	b.direction = dir
	b.speed = float(c.get("bolt_speed", 40.0))
	b.damage = float(c.get("damage", 10.0))
	b.range_m = float(c.get("range", 80.0))
	b.shooter = player
	b.stylize = true
	b.sweep = true
	b.color = Color.html(str(c.get("bolt_color", "#ff6a2a")))
	b.streak_length = float(look.get("bolt", {}).get("length", 0.9))
	b.on_hit.connect(func(t): hit_something.emit(t, b.damage))
	if bolt_parent != null:
		bolt_parent.add_child(b)
		b.global_position = origin
	shots += 1
	if rig_node != null:
		rig_node.kick(float(c.get("recoil", 2.0)) * (0.5 if aiming else 1.0))
		rig_node.shake(0.15)
	_play("shot_" + id)
	_muzzle_flash(origin, dir, b.color)
	avatar.fire_kick()
	var in_range: bool = in_range_zone.is_valid() and bool(in_range_zone.call(player.global_position))
	if not (off_record_zone.is_valid() and bool(off_record_zone.call(player.global_position))):
		WorldState.on_player_fired(in_range)
	# Guards hear it (NoiseEvents). On the range it is "shot_range", which a brain can shrug off.
	NoiseEvents.emit(avatar.global_position, float(c.get("noise_radius", 45.0)), "shot_range" if in_range else "shot")
	fired.emit(id)


## A short orange light at the muzzle. At the muzzle itself it was ~0.35 m from
## the grip hand and turned the whole glove and sleeve flat orange (issue #229).
func _muzzle_flash(at: Vector3, dir: Vector3, col: Color) -> void:
	if not is_inside_tree():
		return
	var ml: Dictionary = look.get("muzzle_light", {})
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = float(ml.get("energy", 6.0))
	l.omni_range = float(ml.get("range", 4.5))
	l.shadow_enabled = false
	var host: Node = bolt_parent if bolt_parent != null else self
	host.add_child(l)
	l.global_position = at + dir * float(ml.get("ahead", 0.0))
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.08)
	tw.tween_callback(l.queue_free)


# ------------------------------------------------------------------ sword

func _on_swing_started() -> void:
	_play("blade_swing")
	swung.emit(str(combo.swing_def().name))


func _sword_hits() -> void:
	var space := player.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.2
	var pts := avatar.blade_points([0.35, 0.7, 1.0])
	# Which way the blade is sweeping: a sword kill flings the body that way.
	var sweep := Vector3.ZERO
	if not pts.is_empty():
		if _tip_was != Vector3.INF:
			sweep = pts[-1] - _tip_was
		_tip_was = pts[-1]
	for p in pts:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.transform = Transform3D(Basis(), p)
		q.exclude = [player.get_rid()]
		q.collide_with_areas = false
		for r in space.intersect_shape(q, 8):
			var col: Object = r.collider
			var target := _damage_receiver(col)
			if target == null:
				continue
			var key := target.get_instance_id()
			if combo.hits_this_swing.has(key):
				continue
			combo.hits_this_swing[key] = true
			var dmg := float(combo.damage())
			if target.has_method("apply_blade_hit"):
				target.apply_blade_hit(dmg, _fling_dir(sweep, target))
			else:
				target.apply_damage(dmg)
			sword_hits += 1
			ExplosionFx.bolt(player.get_parent(), p)      # sparks where the blade bit
			var heavy: bool = combo.swing_def().heavy
			_hitstop = 0.09 if heavy else 0.06          # the combo's centre chop lands harder
			_play("blade_clash")
			if rig_node != null:
				rig_node.shake(0.6 if heavy else 0.35)
			hit_something.emit(target, dmg)


## Mostly along the blade's sweep, a little away from the player so nobody is
## flung back into you; straight away when the blade was not moving sideways.
func _fling_dir(sweep: Vector3, target: Object) -> Vector3:
	var away := Vector3.ZERO
	if target is Node3D:
		away = (target as Node3D).global_position - player.global_position
	away = Vector3(away.x, 0.0, away.z).normalized()
	var side := Vector3(sweep.x, 0.0, sweep.z)
	if side.length() < 0.001:
		return away
	return (side.normalized() + away * 0.35).normalized()


static func _damage_receiver(o: Object) -> Object:
	if o == null:
		return null
	if o.has_method("apply_damage"):
		return o
	if o is Node and (o as Node).get_parent() != null and (o as Node).get_parent().has_method("apply_damage"):
		return (o as Node).get_parent()
	return null


## Enemy bolts that reach the blade: deflect (timed block or a live swing), block
## (late), or let through.
func _intercept_bolts() -> void:
	var chest: Vector3 = avatar.global_position + Vector3(0, 1.25, 0)
	for b in get_tree().get_nodes_in_group("bolts"):
		if not is_instance_valid(b) or b.shooter == player or b.get_meta("intercepted", false):
			continue
		var to_me: Vector3 = chest - b.global_position
		if to_me.length() > 1.5 or b.direction.dot(to_me) <= 0.0:
			continue
		var res := intercept(b)
		if res == "pierced":
			continue
		b.set_meta("intercepted", true)


## Resolve one incoming bolt. Returns "deflected", "blocked" or "pierced".
func intercept(b: Node) -> String:
	var res: int
	if combo.mode == SwordCombo.Mode.SWING and combo.is_active():
		res = combo.blade.BoltResult.DEFLECTED
	else:
		res = combo.blade.intercept_bolt()
	match res:
		combo.blade.BoltResult.DEFLECTED:
			var back: Vector3
			if b.shooter is Node3D and is_instance_valid(b.shooter):
				back = ((b.shooter as Node3D).global_position + Vector3(0, 0.3, 0) - b.global_position).normalized()
			else:
				back = (aim_point() - b.global_position).normalized()
			b.reflect(back, player)
			if b.reflected == 1:    # a bolt you sent back that lands counts as your hit
				b.on_hit.connect(func(t): hit_something.emit(t, b.damage))
			deflections += 1
			WorldState.on_deflection()
			_play("blade_deflect")
			deflected.emit(b)
			return "deflected"
		combo.blade.BoltResult.BLOCKED:
			b.apply_to(null)
			blocks += 1
			_play("blade_clash")
			if rig_node != null:
				rig_node.shake(0.2)
			return "blocked"
	return "pierced"


## Issue #303: your blade met the dark master's (a parry either way): the clash
## sound, a short hitstop and a jolt of the camera.
func on_clash() -> void:
	_hitstop = 0.08
	_play("blade_clash")
	if rig_node != null:
		rig_node.shake(0.5)


# ------------------------------------------------------------------ audio + hud

func _build_sfx() -> void:
	var sounds: Dictionary = CharacterKit._read_json(LOOK_PATH).get("sounds", {})
	var map := {
		"swap": sounds.get("swap", ""), "blade_on": sounds.get("blade_on", ""),
		"blade_off": sounds.get("blade_off", ""), "blade_swing": sounds.get("blade_swing", ""),
		"blade_clash": sounds.get("blade_clash", ""), "blade_deflect": sounds.get("blade_deflect", ""),
	}
	var lk: Dictionary = CharacterKit._read_json(LOOK_PATH)
	var blade_vol: Dictionary = lk.get("blade_volume", {})
	for id in ["pistol_blaster", "rifle_blaster"]:
		map["shot_" + id] = lk.get(id, {}).get("sound", "")
		_sfx_pitch["shot_" + id] = float(lk.get(id, {}).get("sound_pitch", 1.0))
	for k in map:
		var path := str(map[k])
		if path == "" or not ResourceLoader.exists(path):
			continue
		var p := AudioStreamPlayer.new()
		p.stream = load(path)
		# Issue #16: the blade sat on top of everything; its sounds are a step down.
		p.volume_db = float(blade_vol.get("db", -13.0)) if k.begins_with("blade") else -6.0
		p.max_polyphony = 4
		p.bus = Sound.SFX_BUS
		add_child(p)
		_sfx[k] = p
	var hum_path := str(sounds.get("blade_hum", ""))
	if hum_path != "" and ResourceLoader.exists(hum_path):
		var s = load(hum_path)
		if s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(s.get_length() * s.mix_rate)
		_hum = AudioStreamPlayer.new()
		_hum.stream = s
		_hum.volume_db = float(blade_vol.get("hum_db", -24.0))
		_hum.bus = Sound.SFX_BUS
		add_child(_hum)


func _play(key: String) -> void:
	if _sfx.has(key) and is_inside_tree():
		var p: AudioStreamPlayer = _sfx[key]
		p.pitch_scale = float(_sfx_pitch.get(key, 1.0)) * randf_range(0.94, 1.06)
		p.play()


## The crosshair shows with a gun ready, unless a cinematic (the bar's two-shot, or
## V's cinematic view) owns the camera or the sights are up in first person (then
## the sight is the crosshair).
static func crosshair_shown(has_gun: bool, ready: bool, overridden: bool, first_person: bool, ads_blend: float) -> bool:
	return has_gun and ready and not overridden and not (first_person and ads_blend >= 0.95)


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "WeaponHUD"
	_hud.layer = 4
	add_child(_hud)
	_cross = Control.new()
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_cross)
	feedback = HitFeedback.new()
	add_child(feedback)
	feedback.setup(_hud)
	hit_something.connect(feedback.on_hit)
	for r in [Rect2(-12, -1, 7, 2), Rect2(5, -1, 7, 2), Rect2(-1, -12, 2, 7), Rect2(-1, 5, 2, 7), Rect2(-1, -1, 2, 2)]:
		var c := ColorRect.new()
		c.position = r.position
		c.size = r.size
		c.color = Color(1, 0.92, 0.8, 0.85)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cross.add_child(c)
	_ammo = _label(Control.PRESET_BOTTOM_RIGHT, Vector2(-220, -114), 26)
	_name = _label(Control.PRESET_BOTTOM_RIGHT, Vector2(-220, -148), 18)


func _label(preset: int, offset: Vector2, size: int) -> Label:
	var l := Label.new()
	l.set_anchors_preset(preset)
	l.offset_left = offset.x
	l.offset_top = offset.y
	l.offset_right = offset.x + 190
	l.offset_bottom = offset.y + 32
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(l)
	return l


func _show_name(text: String) -> void:
	if _name != null:
		_name.text = text
		_name_left = 1.6


func _update_hud(dt: float) -> void:
	if _hud == null:
		return
	var cur := holder.current
	_cross.visible = crosshair_shown(guns.has(cur), holder.is_ready(),
		rig_node != null and (rig_node.is_overridden() or rig_node.has_method("is_cinematic") and rig_node.is_cinematic()),
		avatar.first_person, avatar.ads_blend)
	if guns.has(cur):
		var g: Weapon = guns[cur]
		_ammo.text = "RELOADING" if g.is_reloading() else "%d / %d" % [g.ammo, int(g.config.get("mag", 0))]
		_ammo.visible = true
	else:
		_ammo.visible = false
	_name_left = maxf(0.0, _name_left - dt)
	_name.visible = _name_left > 0.0
