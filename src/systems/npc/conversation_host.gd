class_name ConversationHost
extends Node
## Talking to the town's AI characters (M12; one host for all of them since #42).
## Owns what every conversation shares: the LLM service, the chat box, the debug
## (F3) and model settings (F10) panels, the "[E] Talk to ..." prompt and the save
## that holds what each character remembers. Each character is a TalkSpot (brain,
## body, where you stand): the Cantina Owner behind her counter, built here, and
## any others the town adds with add_spot() (Skrugs at his stall).
##
## Walk up to a spot: "[E] Talk to Oda Vell". Talking locks movement and weapons,
## frees the mouse, and moves the camera to a two-shot. Esc (or them ending it)
## walks you back out, unless the spot holds you (hold_line: the general's pit
## meeting ends only when he says so).
##
## Issue #328: AI characters are off unless the player turns them on (F10, or the
## first launch's question). Off, every character talks from a topic menu and
## their canned lines. On, the local models load in the background and a small
## status says "AI model loading" until a first word arrives, then "AI model
## ready" and fades; a turn that gets no model is canned, says why once per
## conversation, and the next turn tries again.
##
## town_demo.gd keeps this as `bar`; `brain`, `npc` and `bar_front` are still the
## Cantina Owner's, so code written for the one-character bar keeps working.

const TALK_RADIUS := 1.9
const TWO_SHOT_FOV := 34.0
const GROUP := "conversation_host"      ## issue #303: the end card waits while any host is talking

var demo                              ## town_demo.gd
var llm: LLMService
var panel: DialoguePanel
var overlay: LLMDebugOverlay
var settings: LLMSettingsPanel
var save := SaveSystem.new()
var save_path := ""                   ## "" = the save being played (SaveSlots), fixed at setup
var autosave := true
var fresh := false                ## issue #200: no save was found (a first launch): NewGameMenu asks the mode
var spots: Array = []                 ## TalkSpot, the Cantina Owner first
var active: TalkSpot                  ## who the player is talking to (null when not)
var owner_spot: TalkSpot              ## the Cantina Owner's
var talking := false
var warmed := false
var _warmed: Dictionary = {}          ## issue #328: provider id -> its warm-up turn id
var _offline_told := false            ## issue #328: said why this conversation is canned
var _topics_used: Array = []          ## topic ids picked in this talk: off the menu until the next one
var _ai_state := ""                   ## "" | "loading" | "ready" (the status line)
var _status_tween: Tween
var reminders := 0                    ## issue #29: times the AI reminder was repeated (tests)

## The Cantina Owner's, for the code (and tests) written before #42.
var brain: NpcBrain:
	get: return owner_spot.brain if owner_spot != null else null
var npc: CantinaOwnerNPC:
	get: return owner_spot.body as CantinaOwnerNPC if owner_spot != null else null
var bar_front: Vector3:
	get: return owner_spot.stand if owner_spot != null else Vector3.ZERO

static var _loaded_once := false      ## this run's WorldState is the save's (SaveSlots sets it on a switch)

var _prompt: Label
var _status_dot: Label
var _hud: CanvasLayer
var _scripted = null
var _loaded := false

const SaveSystem := preload("res://src/systems/save/save_system.gd")


## Build everything. `scripted` = CI provider (no network, no sidecar).
func setup(town_demo, scripted = null) -> void:
	demo = town_demo
	_scripted = scripted
	if save_path == "":
		save_path = SaveSlots.current_path()
	add_to_group(GROUP)
	# Issue #303: a checkpoint (the general's death, the dark master's answer) saves now.
	WorldState.checkpoint_hooks.append(_on_checkpoint)
	# The model service every character shares.
	llm = LLMService.new()
	add_child(llm)
	var cfg := LLMConfig.new().load_all()
	llm.configure(cfg, scripted)
	if scripted == null:
		llm.start_sidecar()
	llm.status_changed.connect(_on_llm_status)
	llm.finished.connect(_on_llm_finished)
	if is_inside_tree():
		get_tree().create_timer(3.0).timeout.connect(_on_llm_status)
	_load_save()
	# UI.
	panel = DialoguePanel.new()
	add_child(panel)
	panel.submitted.connect(_on_submit)
	panel.leave_requested.connect(end_talk)
	panel.job_answered.connect(_on_job_answer)
	panel.topic_picked.connect(_on_topic)
	overlay = LLMDebugOverlay.new()
	overlay.llm = llm
	add_child(overlay)
	settings = LLMSettingsPanel.new()
	settings.llm = llm
	add_child(settings)
	_hud = CanvasLayer.new()
	_hud.layer = 5
	add_child(_hud)
	_prompt = _label(Control.PRESET_CENTER_BOTTOM, Vector2(-260, -140), 22, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.visible = false
	RetroUI.prompt(_prompt)
	_status_dot = _label(Control.PRESET_TOP_RIGHT, Vector2(-760, 52), 14, HORIZONTAL_ALIGNMENT_RIGHT)
	_status_dot.offset_right = -16
	_status_dot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_dot.visible = false
	_build_cantina_owner()
	overlay.brain = owner_spot.brain


## The Cantina Owner: her body just behind the counter, facing the customers, and
## the bar front where you stand.
func _build_cantina_owner() -> void:
	var town = demo.town
	var front: Vector3 = town.marker_pos("bar_front")
	var counter: Dictionary = town.get_box("bar_counter")
	var marker: Vector3 = town.marker_pos("cantina_owner")
	var mats: LookMaterials = demo._flat_mats() if demo.has_method("_flat_mats") else LookMaterials.new()
	# Issue #45: the marker says who runs this cantina (their card) and how they
	# look; the port's is Oda. The bar itself takes the planet's town style.
	var om: Dictionary = town.get_marker("cantina_owner")
	var body := CantinaOwnerNPC.new(mats, str(om.get("look", "cantina_owner")))
	demo.add_child(body)
	var stand_x := float(counter.min[0]) - 0.55 if not counter.is_empty() else marker.x
	body.global_position = Vector3(stand_x, marker.y, marker.z)
	body.rotation.y = atan2(front.x - stand_x, 0.0)
	body.look_at_target = demo._player
	if demo.use_look:
		var dressing := CantinaDressing.new()
		demo.add_child(dressing)
		dressing.dress(town, demo.decor.mats if "decor" in demo and demo.decor != null else mats)
		body.dressing = dressing
	var card := str(om.get("card", ""))
	var brain: NpcBrain
	if card == "" and str(om.get("planet", "")) != "" and "planet" in demo:
		# Issue #75: this planet's own Oda (a new card, a new brain, nothing shared).
		brain = NpcBrain.new(null, PlanetOwner.card(demo.planet))
	elif card == "":
		brain = NpcBrain.new()
	else:
		brain = NpcBrain.new(null, "res://content/core/" + card)
	var s := TalkSpot.new(brain, body, front)
	s.radius = TALK_RADIUS
	add_spot(s)
	owner_spot = s


## Another character the player can talk to. Their brain shares this host's model
## service, and what they remember is loaded from (and saved to) the same save.
func add_spot(s: TalkSpot) -> void:
	spots.append(s)
	var b := s.brain
	if b.llm == null:
		b.attach(llm)
	b.thinking.connect(func(bark): _on_thinking(s, bark))
	b.line_delta.connect(func(text): _on_delta(s, text))
	b.line_done.connect(func(turn): _on_done(s, turn))
	b.job_offered.connect(func(j): _on_job(s, j))
	b.drink_poured.connect(func(d): _on_drink(s, d))
	b.ended.connect(func(reason): _end_soon(reason))
	var r := save.get_relationship(s.id())
	if not r.is_empty():
		b.rel.from_save(r)


func spot(id: String) -> TalkSpot:
	for s in spots:
		if s.id() == id:
			return s
	return null


func _label(preset: int, off: Vector2, size: int, align: int) -> Label:
	var l := Label.new()
	l.set_anchors_preset(preset)
	l.offset_left = off.x
	l.offset_top = off.y
	l.offset_right = off.x + 520 if align == HORIZONTAL_ALIGNMENT_CENTER else off.x + 288
	l.offset_bottom = off.y + 32
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	_hud.add_child(l)
	return l


func is_talking() -> bool:
	return talking


## The spot the player is standing at (the nearest, if two overlap), or null.
func spot_in_range() -> TalkSpot:
	var p: Node3D = demo._player
	var best: TalkSpot = null
	for s in spots:
		if not s.manual and s.in_range(p) and (best == null or s.distance_to(p) < best.distance_to(p)):
			best = s
	return best


## At the bar front (the Cantina Owner's spot).
func player_in_range() -> bool:
	return owner_spot != null and owner_spot.in_range(demo._player)


func _process(_dt: float) -> void:
	if owner_spot == null:
		return
	for s in spots:
		s.brain.tick()
	if overlay.visible:
		overlay.refresh()
	if not talking:
		var s := spot_in_range()
		_prompt.visible = s != null
		if s != null and not s.brain.serving():
			_prompt.text = "%s won't talk to you. Come back later." % s.display_name()
		elif s != null:
			_prompt.text = "[E]  Talk to " + s.display_name()
		if s != null and s.brain.serving() and InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
			start_talk(s)
	_warm_models()
	_update_ai_status()


## Issue #328: once AI characters are on, load each local model as soon as its
## server answers (Ollama loads a model on its first request, which can take a while).
func _warm_models() -> void:
	if _scripted != null or not llm.ai_on() or llm.config == null:
		return
	for pid in ["local", "ollama"]:
		if _warmed.has(pid) or not llm.config.chain().has(pid) or not llm.config.usable(pid):
			continue
		if bool(llm.health.get(pid, {}).get("up", false)):
			warmed = true
			_warmed[pid] = owner_spot.brain.warm_up(pid)


## Load this character's prompt into the local server while the player reads the
## greeting. Cold, a full persona takes the local model longer than its first-word
## limit; the abandoned request is dropped by the server, so every turn came back
## "no answer in time". Player turns skip local until this finishes.
func _warm_for_talk(s: TalkSpot) -> void:
	if _scripted != null or not llm.ai_on() or llm.config == null or not llm.active_chain().has("local"):
		return
	s.brain.warm_up("local")


## Issue #328: "AI model loading" while a model loads with nothing else to answer,
## or a reply has no first word yet. Nothing with AI characters off.
func _update_ai_status() -> void:
	if not llm.ai_on():
		if _ai_state != "":
			_ai_state = ""
			_show_status("")
		return
	var waiting := talking and active != null and active.brain.busy and not active.brain.has_words()
	var loading := waiting or (llm.loading() and llm.active_chain().is_empty())
	if loading and _ai_state != "loading":
		_ai_state = "loading"
		_show_status(_status_line("loading"), Color(1.0, 0.75, 0.35))
	elif not loading and _ai_state == "loading":
		_ai_state = ""
		_show_status("")


## The first word arrived with no error: "AI model ready", then it fades.
func _ai_ready() -> void:
	_ai_state = "ready"
	_show_status(_status_line("ready"), Color(0.55, 0.9, 0.55))
	if is_inside_tree():
		_status_tween = create_tween()
		_status_tween.tween_interval(1.2)
		_status_tween.tween_property(_status_dot, "modulate:a", 0.0, 0.8)
		_status_tween.tween_callback(func():
			if _ai_state == "ready":
				_ai_state = ""
				_status_dot.visible = false)


func _show_status(text: String, color: Color = Color.WHITE) -> void:
	if _status_tween != null:
		_status_tween.kill()
		_status_tween = null
	_status_dot.modulate.a = 1.0
	_status_dot.text = text
	_status_dot.add_theme_color_override("font_color", color)
	_status_dot.visible = text != ""


## The status line's text ("" if it is not showing).
func ai_status() -> String:
	return _status_dot.text if _status_dot.visible else ""


static func _status_line(key: String) -> String:
	var fallback := { "loading": "AI model loading...", "ready": "AI model ready" }
	return str(Disclaimers.data().get("status", {}).get(key, fallback[key]))


## Issue #328: a warm-up answered, so its model is loaded.
func _on_llm_finished(turn_id: int, r: Dictionary) -> void:
	if _warmed.values().has(turn_id) and bool(r.get("ok", false)) and not (talking and active != null and active.brain.busy):
		_ai_ready()


## Issue #328: AI characters on or off, and (save_now) written to the player's settings.
func set_ai_enabled(on: bool, save_now: bool = true) -> void:
	llm.set_ai_enabled(on)
	if save_now:
		llm.config.save_user()
	if talking and active != null:
		_refresh_menu(active)


## Issue #328: the first launch's answer: on or off, and the question is never asked again.
func answer_first_run(on: bool) -> void:
	llm.config.set_first_run_asked()
	set_ai_enabled(on)


## The topic menu: with AI characters off, or once a turn in this talk was canned.
## A topic picked in this talk is off it until the next talk.
func _refresh_menu(s: TalkSpot) -> void:
	var menu: Array = s.brain.topics().filter(func(t): return not _topics_used.has(str(t.id)))
	panel.set_topics(menu if not llm.ai_on() or _offline_told else [])
	panel.set_notice(Disclaimers.talk_text(s.display_name()) if llm.ai_on() else "")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F3:
		overlay.toggle()
	elif event.keycode == KEY_F10 and event.shift_pressed:
		var m := llm.cycle_mode()
		_toast("AI brain: " + m)
	elif event.keycode == KEY_F10:
		settings.toggle()


# ------------------------------------------------------------------ talking

## Start talking to `s` (the Cantina Owner when null).
func start_talk(s: TalkSpot = null) -> void:
	if talking:
		return
	if s == null:
		s = owner_spot
	NpcVoice.stop(s.body)
	active = s
	talking = true
	_offline_told = false
	_topics_used.clear()
	overlay.brain = s.brain
	_prompt.visible = false
	var p: CharacterBody3D = demo._player
	p.locked = true
	if demo.player_kit != null:
		demo.player_kit.weapons.holder.request("")
		demo.player_kit.weapons.set_enabled(false)
	var rig = demo._rig
	if rig != null:
		rig.input_enabled = false
		rig.set_override(s.two_shot(p), TWO_SHOT_FOV)
		# Face them.
		rig.rig.yaw = atan2(s.body.global_position.x - p.global_position.x, s.body.global_position.z - p.global_position.z)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_warm_for_talk(s)
	var greeting := s.brain.begin_visit()
	# Issue #64: the story speaks first when it has something to say.
	var beat := Story.beat(s.id())
	if not beat.is_empty():
		greeting = str(beat.say)
		s.brain.replace_greeting(greeting)
	var opening: Dictionary = s.opener.call() if beat.is_empty() and s.opener.is_valid() else {}
	if str(opening.get("say", "")) != "":
		greeting = str(opening.say)
		s.brain.replace_greeting(greeting)
	panel.open(s.display_name(), greeting)
	_refresh_menu(s)    # issue #29: the AI notice (only with AI on); issue #328: the topic menu
	panel.set_mood(s.brain.rel.mood)
	panel.set_money(WorldState.credits, s.brain.rel.tab)
	if str(beat.get("job", "")) != "":
		var j := WorldState.job(str(beat.job))
		if not j.is_empty():
			panel.show_job(j)
	elif opening.has("sale"):
		panel.show_sale(opening.sale, WorldState.credits)
	var story_line := _story_mood(s)
	_speak(s, story_line if story_line != "" else greeting)
	s.speak_pulse()
	# Issue #185: back after time away, she opens with what happened (the model's
	# turn, in her own voice) unless the story or an opener spoke first.
	if beat.is_empty() and opening.is_empty() and s.brain.recap_wanted:
		s.brain.recap_turn()
	else:
		s.brain.recap_wanted = false


func end_talk() -> void:
	if not talking:
		return
	if settings.visible:
		settings.visible = false
		return
	if active != null and active.hold_line != "":
		panel.post_notice(active.hold_line)
		return
	var s := active
	talking = false
	active = null
	NpcVoice.stop(s.body)
	s.brain.end_visit()
	panel.close()
	var p: CharacterBody3D = demo._player
	p.locked = false
	if demo.player_kit != null:
		demo.player_kit.weapons.set_enabled(true)
	var rig = demo._rig
	if rig != null:
		rig.input_enabled = true
		rig.clear_override()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	s.act("idle")
	_save_memory()


## The Cantina Owner's two-shot (kept for the review tools).
func two_shot() -> Transform3D:
	return owner_spot.two_shot(demo._player)


## Bots and tests talk through here (same path as the text field).
func player_says(text: String) -> bool:
	if not talking:
		return false
	return _on_submit(text)


## Issue #328: bots and tests pick a topic through here (same path as the button).
func player_picks(topic: String) -> bool:
	if not talking:
		return false
	return _on_topic(topic)


func _on_topic(topic: String) -> bool:
	var s := active
	if s == null or s.brain.busy:
		return false
	for t in s.brain.topics():
		if str(t.id) == topic:
			_before_turn(s, str(t.say))
			var ok := s.brain.say_topic(topic)
			if ok:
				_topics_used.append(topic)
				_refresh_menu(s)
			return ok
	return false


func _on_submit(text: String) -> bool:
	var s := active
	if s == null or s.brain.busy:
		return false
	_before_turn(s, text)
	return s.brain.say(text)


## The player's line into the history, and the box waits for the answer.
func _before_turn(s: TalkSpot, text: String) -> void:
	NpcVoice.stop(s.body)
	panel.commit_line()
	panel.add_player_line(text)
	if Disclaimers.triggered(text):
		# Issue #29: the reminder again, before their reply. The message still goes.
		panel.post_notice(Disclaimers.repeat_text(s.display_name()))
		reminders += 1
	panel.set_line("")
	panel.set_input_enabled(false)
	s.act("thinking")


func _on_thinking(s: TalkSpot, bark: String) -> void:
	if s != active:
		return
	panel.set_line(bark, true)
	s.act("thinking")


func _on_delta(s: TalkSpot, text: String) -> void:
	if s != active:
		return
	if _ai_state == "loading":
		_ai_ready()
	panel.set_line(text)
	s.speak_pulse()


func _on_done(s: TalkSpot, turn: Dictionary) -> void:
	if s != active:
		return
	panel.set_line(str(turn.say))
	var story_line := _story_mood(s)
	panel.set_mood(s.brain.rel.mood)
	if str(turn.source) == "canned" and llm.ai_on():
		_offline(s, turn)
	panel.set_money(WorldState.credits, s.brain.rel.tab)
	panel.set_input_enabled(true)
	_speak(s, story_line if story_line != "" else str(turn.say))
	s.speak_pulse()


## Issue #328: the AI is on but no model answered: say why, once per conversation,
## and put the topic menu up. The next turn tries the model again.
func _offline(s: TalkSpot, turn: Dictionary) -> void:
	if _ai_state == "loading":
		_ai_state = ""
		_show_status("")
	if _offline_told:
		return
	_offline_told = true
	if llm.loading() and (turn.get("fell_back_from", []) as Array).is_empty():
		# Nothing failed: the model is still loading. Written lines until it is up.
		panel.post_notice(str(Disclaimers.data().get("still_loading", "The AI model is still loading: written lines for now.")))
	else:
		var why := llm.explain({ "fell_back_from": turn.get("fell_back_from", []), "error": turn.get("error", "") })
		panel.post_notice(str(Disclaimers.data().get("offline", "AI offline: %s. Canned lines for now; F10 to fix.")) % why)
	_refresh_menu(s)


func _on_drink(s: TalkSpot, d: Dictionary) -> void:
	s.act("pouring", 1.4)
	if s.body != null and s.body.has_method("serve"):
		s.body.serve(d)
	if s == active:
		panel.set_money(int(d.credits), int(d.tab))


func _on_job(s: TalkSpot, j: Dictionary) -> void:
	if s == active:
		panel.show_job(j)


func _on_job_answer(id: String, accepted: bool) -> void:
	if active != null:
		NpcVoice.stop(active.body)
	if accepted and active != null and active.brain.accept_job(id):
		_toast("Job taken: " + str(WorldState.job(id).get("title", id)))
		var story_line := _story_mood(active)
		if story_line != "":
			_speak(active, story_line)


## Issue #64: in the first smuggling run, Oda amused or warm lends the player her
## jetpack. She says so, and it goes on their back if the slot is free.
func _story_mood(s: TalkSpot) -> String:
	if s == null or s.id() != "cantina_owner":
		return ""
	var said := Story.on_owner_mood(s.brain.rel.mood)
	if said == "":
		return ""
	panel.set_line(said)
	s.speak_pulse()
	var gear = demo.gear if demo != null and "gear" in demo else null
	if gear != null:
		var item: Dictionary = gear.content.get_item(Story.JETPACK)
		if WorldState.inventory.in_slot(str(item.get("slot", ""))) == "":
			WorldState.inventory.attach(Story.JETPACK, item)
		gear.sync_gear()
		if gear.hud != null:
			gear.hud.toast(Story.line("jetpack_toast"), 4.0)
	return said


func _speak(s: TalkSpot, text: String) -> void:
	if s == null or text.strip_edges() == "":
		return
	var voice_profile := NpcVoice.profile_for_npc(s.id(), s.brain.card)
	NpcVoice.speak(text, voice_profile, s.brain.rel.mood, s.body, false, true)


func _end_soon(_reason: String) -> void:
	var t := get_tree().create_timer(2.0) if is_inside_tree() else null
	if t != null:
		t.timeout.connect(end_talk)
	else:
		end_talk()


func _on_llm_status() -> void:
	if not llm.ai_on():
		_warmed.clear()                 # issue #328: turned on again, they load again
	if overlay != null:
		overlay.refresh()
	# Say why in the Godot output too, so a canned character is never a mystery.
	var rep := llm.brain_report()
	var text := "AI brain: %s\n  %s" % [rep.summary, "\n  ".join(PackedStringArray(rep.lines))]
	if text != _last_report:
		_last_report = text
		print(text)


var _last_report := ""


func _toast(text: String) -> void:
	if demo.pads.size() > 0:
		demo.pads[0].toast(text, 2.5)


# ------------------------------------------------------------------ memory

## Read the save once: the world, and each character's relationship (applied as
## they are added).
func _load_save() -> void:
	if not autosave or _loaded:
		return
	_loaded = true
	if save.load_from(save_path):
		if not _loaded_once and not save.get_world().is_empty():
			var arrival := WorldState.to_save()     # keep what this session already did
			WorldState.from_save(save.get_world())
			for k in arrival.flags:
				WorldState.flags[k] = true
	else:
		save.new_game()
		fresh = true
	_loaded_once = true


func _save_memory() -> void:
	if not autosave:
		return
	if save.data.is_empty():
		save.new_game()
	for s in spots:
		save.set_relationship(s.id(), s.brain.rel.to_save())
	save.set_world(WorldState.to_save())
	save.data["credits"] = WorldState.credits
	_save_where()
	save.save_to(save_path)


## Issue #113: the planet you are on, and your spot on it when you are standing
## on your own feet (not flying, riding, falling or down). Otherwise the last
## good spot on this planet is kept; a different planet's spot is dropped.
func _save_where() -> void:
	var id := GameFlow.current_planet_id()
	var p = demo._player if demo != null else null
	var standing: bool = p != null and is_instance_valid(p) and p.is_inside_tree() and not bool(p.get("piloting")) \
		and not bool(p.get("is_downed")) and not GameFlow.in_flight and p.is_on_floor()
	if standing:
		save.set_where(id, (p as Node3D).global_position, true)
		return
	var old := save.get_where()
	if str(old.get("planet", "")) == id and old.has("pos"):
		return
	save.set_where(id, Vector3.ZERO, false)


func _on_checkpoint(_why: String) -> void:
	if _loaded:
		_save_memory()


func _exit_tree() -> void:
	WorldState.checkpoint_hooks.erase(_on_checkpoint)
	if not spots.is_empty():
		_save_memory()
