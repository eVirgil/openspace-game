class_name FlightHud
extends CanvasLayer
## The cockpit read-out in the port's sky (M14): speed, throttle, boost, altitude
## above the ground and above sea level, climb rate, a centre reticle, the control
## prompt and a toast. No logic: ShipPilot fills it in. There is no "edge of
## space" read-out: the sky just darkens as you climb, and space is the same sky.
##
## Issue #181: it reads like a shooter now.
##   - The chase view draws the numbers as a flight-sim HUD (FlightSimHud) in place
##     of the old text block in the top left; the cockpit view (V) draws a cockpit
##     with working instruments instead (CockpitView). set_cockpit() picks one.
##   - Your guns' hits pop the hit marker (HitFeedback, as on foot), white for a hit
##     and red for a kill, on ships and on the people and things on the ground.
##   - Being hit flashes the edge of the screen red (DamageFlash).

const INK := Color(0.95, 0.92, 0.85, 0.95)
const DIM := Color(0.95, 0.92, 0.85, 0.55)
const WARN := Color(1.0, 0.45, 0.3, 0.95)

var sim: FlightSimHud            ## issue #181: the chase view's HUD
var cockpit: CockpitView          ## issue #181: the cockpit view's frame and dash
var feedback: HitFeedback         ## issue #181: hit markers and the thud for the ship's guns
var damage_flash: DamageFlash     ## issue #181: red round the edge when you are hit
var cockpit_view := false
var values: Dictionary = {}       ## the last show_values(), for the views and tests
var prompt: Label
var toast_label: Label
var gauge: Control
var boost := 1.0
var vessel_name := ""            ## issue #15: shown on the HUD (issue #181: and the dash)
var target: Dictionary = {}       ## issue #76: an enemy in the air (AtmoFighter.hud_target), or {}
var warn_label: Label             ## the seeker warning's text, over the toast
var seeker_warn := false          ## the seeker warning is sounding (SeekerWarning)
var seeker_lamp := false          ## and its lamp is in the lit half of a flash
var _toast_left := 0.0
var _fade: ColorRect


func _init() -> void:
	name = "FlightHud"
	layer = 5


func _ready() -> void:
	cockpit = CockpitView.new()
	add_child(cockpit)
	sim = FlightSimHud.new()
	add_child(sim)
	prompt = _center_label(-90.0)
	RetroUI.prompt(prompt)
	toast_label = _center_label(-150.0)
	toast_label.add_theme_font_size_override("font_size", RetroUI.size("flight_toast", 26))
	toast_label.size.y = 40
	toast_label.visible = false
	warn_label = _center_label(-210.0)
	warn_label.add_theme_font_size_override("font_size", RetroUI.size("flight_toast", 26) + 6)
	warn_label.add_theme_color_override("font_color", WARN)
	warn_label.text = GameFlow.label("seeker_warning")
	warn_label.size.y = 40
	warn_label.visible = false
	gauge = Control.new()
	gauge.name = "Gauge"
	gauge.set_anchors_preset(Control.PRESET_FULL_RECT)
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.draw.connect(_draw_gauge)
	add_child(gauge)
	feedback = HitFeedback.new()
	add_child(feedback)
	feedback.setup(self)
	damage_flash = DamageFlash.new()
	add_child(damage_flash)
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	visible = false


func _style(l: Label) -> void:
	l.add_theme_color_override("font_color", INK)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _center_label(from_bottom: float) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	l.position = Vector2(-420, from_bottom)
	l.size = Vector2(840, 28)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(l)
	add_child(l)
	return l


## values: speed, throttle (0..1), boost (0..1), agl, altitude, climb, state,
## (issue #55) hull, hull_max, shield, and (issue #181) shield_max, max_speed, the
## attitude (pitch, roll, heading in degrees: attitude()), and the Shift ability
## (ability: its kind, ability_on: running now), and the stick as commanded
## (stick_pitch, stick_yaw, stick_roll, -1..1) for the cockpit's yoke
func show_values(v: Dictionary) -> void:
	if gauge == null:
		return
	values = v
	values["seeker_lamp"] = seeker_lamp
	boost = float(v.get("boost", 0.0))
	for view in [sim, cockpit]:
		view.values = v
		view.vessel_name = vessel_name
		view.queue_redraw()
	gauge.queue_redraw()


## Issue #181: the cockpit view (its dash and instruments) or the chase view (the
## flight-sim HUD). The reticle, target box, marker and flash show in both.
## The cinematic view (V's third) shows neither: its shots are off the ship's
## centre line, so the reticle and the ladder would point at nothing.
func set_cockpit(on: bool, cinematic := false) -> void:
	if cockpit == null:
		return
	cockpit_view = on
	if warn_label != null and on:
		warn_label.visible = false
	cockpit.visible = on
	sim.visible = not on and not cinematic
	gauge.visible = not cinematic
	gauge.queue_redraw()


## Issue #181: your guns hit `target` (bolt.gd's on_hit or on_splash). The marker
## shows only if it really took damage, as on foot.
func on_gun_hit(target: Object) -> void:
	if feedback != null:
		feedback.on_hit(target)


## Issue #181: a hit or kill the space fight's director scored for you.
func confirm_hit(kill: bool) -> void:
	if feedback != null:
		feedback.confirm(kill)


## A seeker of yours hit at `at` (world space): a marker pinned there too.
func mark_hit_at(at: Vector3, kill: bool) -> void:
	if feedback != null:
		feedback.mark_at(at, kill)


## The seeker warning (SeekerWarning): while `on`, the text shows over the view and
## blinks with the lamp; the cockpit view's dash lamp (`values.seeker_lamp`) flashes
## with it.
func set_seeker_warning(on: bool, lamp: bool) -> void:
	seeker_warn = on
	seeker_lamp = on and lamp
	values["seeker_lamp"] = seeker_lamp
	if warn_label != null:
		# The cockpit view has the lamp and the alarm only; the text is for the chase view.
		warn_label.visible = on and not cockpit_view
		warn_label.modulate.a = 1.0 if seeker_lamp else 0.35


## Issue #181: you were hit.
func flash_damage() -> void:
	if damage_flash != null:
		damage_flash.flash()


## Issue #181: pitch, roll and heading in degrees from the ship's basis in the
## ground's own frame (up +Y, north -Z). Pitch + is nose up, roll + is right wing
## down, heading 0..360 clockwise from north (90 = +X).
static func attitude(b: Basis) -> Dictionary:
	var o := b.orthonormalized()
	var fwd := -o.z
	var heading := 0.0
	if Vector2(fwd.x, fwd.z).length() > 0.0001:
		heading = fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)
	else:
		var up_flat := o.y                          # straight up or down: the belly says where
		heading = fposmod(rad_to_deg(atan2(-up_flat.x * signf(fwd.y), up_flat.z * signf(fwd.y))), 360.0)
	return {
		"pitch": rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0))),
		"roll": rad_to_deg(atan2(-o.x.y, o.y.y)),
		"heading": heading,
	}


func set_prompt(text: String) -> void:
	if prompt != null:
		prompt.text = text


func toast(text: String, secs: float = 3.0) -> void:
	if toast_label == null or text == "":
		return
	toast_label.text = text
	toast_label.visible = true
	_toast_left = secs


func set_fade(a: float) -> void:
	if _fade != null:
		_fade.color.a = clampf(a, 0.0, 1.0)


func _process(dt: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= dt
		if _toast_left <= 0.0:
			toast_label.visible = false


func _draw_gauge() -> void:
	var vp := gauge.get_viewport_rect().size
	var c := vp * 0.5
	# Reticle: where the nose points (the chase camera looks along it).
	gauge.draw_arc(c, 12.0, 0.0, TAU, 24, DIM, 1.5)
	gauge.draw_line(c + Vector2(-26, 0), c + Vector2(-16, 0), DIM, 1.5)
	gauge.draw_line(c + Vector2(16, 0), c + Vector2(26, 0), DIM, 1.5)
	_draw_target()


## Issue #76: the space fight's target box and lead pip, for an enemy in the air: a
## box on it (with its hull under it), the dot where to aim, the seekers' lock
## filling a ring round it, and an arrow at the screen's edge pointing to it when it
## is behind or off screen.
func _draw_target() -> void:
	if target.is_empty():
		return
	var cam := gauge.get_viewport().get_camera_3d()
	if cam == null:
		return
	var col := Color(1.0, 0.35, 0.25, 0.95)
	var tp: Vector3 = target.pos
	var vp := gauge.get_viewport_rect().size
	var on_screen := not cam.is_position_behind(tp)
	var sp := cam.unproject_position(tp) if on_screen else Vector2.ZERO
	if on_screen and Rect2(Vector2.ZERO, vp).has_point(sp):
		gauge.draw_rect(Rect2(sp - Vector2(18, 18), Vector2(36, 36)), col, false, 1.5)
		# The seekers' lock building round the box, as in a space fight.
		var lock := clampf(float(target.get("lock", 0.0)), 0.0, 1.0)
		if lock > 0.0:
			gauge.draw_arc(sp, 26.0, -PI * 0.5, -PI * 0.5 + TAU * lock, 32, col, 2.5)
		var hp := clampf(float(target.get("hull", 1.0)), 0.0, 1.0)
		gauge.draw_rect(Rect2(sp + Vector2(-18, 22), Vector2(36, 4)), Color(0, 0, 0, 0.5))
		gauge.draw_rect(Rect2(sp + Vector2(-18, 22), Vector2(36 * hp, 4)), col)
		var font := ThemeDB.fallback_font
		var fs := RetroUI.size("flight_gauge", 17) - 3
		gauge.draw_string(font, sp + Vector2(24, -8), "%d m" % int(target.get("dist", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		if bool(target.get("lead_ok", false)) and not cam.is_position_behind(target.lead):
			gauge.draw_circle(cam.unproject_position(target.lead), 5.0, Color(1.0, 0.85, 0.4, 0.9))
		return
	# Off screen: an arrow on a ring round the reticle, toward it.
	var c := vp * 0.5
	var local := cam.global_transform.basis.inverse() * (tp - cam.global_position)
	var dir := Vector2(local.x, -local.y)
	if dir.length() < 0.001:
		dir = Vector2(0, 1)
	dir = dir.normalized()
	var at := c + dir * minf(vp.x, vp.y) * 0.38
	var side := Vector2(-dir.y, dir.x)
	gauge.draw_colored_polygon(PackedVector2Array([at + dir * 14.0, at - dir * 6.0 + side * 9.0, at - dir * 6.0 - side * 9.0]), col)

