class_name Sound
extends Node
## The sound library and the music (issue #16). Data: content/look/sound.json.
##
## Systems ask for a sound by key and say nothing else:
##   Sound.play("ship_hit", point)      one-shot; 3D at `point`, 2D without one
##   Sound.loop("jet_loop", self)       a looping player on `self`; the caller
##                                      plays, stops and pitches it
##   Sound.battle()                     an NPC just fired at the player
##   Sound.set_space(true)              a fight in orbit started
##   Sound.set_club(id, near, inside)   issue #104: where you are from a cantina
##   Sound.set_club_live(false)         the band is dead: the club goes quiet
##   Sound.club_vibe("hard")            Oda changes the song to one with that mood
##   Sound.radio_next()                 issue #291: J in a ship, the next station
##
## The music is the ambient tracks, played in a shuffled order (a new one each
## game) with cross-fades; a battle track (from 30 s in) while NPCs are shooting
## at you and for `battle_hold` seconds after, and when it runs out with the fight
## still on, `battle_2` blends in and loops for as long as it lasts (a long fight,
## like the climb up the cruiser); the next fight starts on the first again. And a
## space track during a fight in orbit (not for being up there: nothing marks where
## space starts). Space beats battle beats ambient. Credits going up or down make
## a coin sound wherever they changed.
##
## Issue #104: the club mix is a layer of its own (two more decks on the Club
## bus) over the score (the decks above, on the Score bus). Near a cantina it
## fades in muffled through the wall (a low-pass on the Club bus) and the score
## ducks under it; inside the door it is the only music, so gunfire in the club
## does not cut it. Each planet's club has its own playlist, shuffled, and songs
## blend into each other over `club.fade` seconds.
##
## Issue #291: the ship's radio plays a club playlist on that same layer, at full
## volume and unmuffled, wherever the ship is: in space and in a fight too (the
## score stays ducked under it). J steps through `club.radio` and back to off;
## getting out of the seat turns it off.
##
## Static and lazy, like GameFlow and WorldState (no autoload): the first call
## puts one node under the tree root, where it outlives scene changes, so the
## music does not restart when you launch or land. Two buses, Music and SFX
## (default_bus_layout.tres), set in the settings panel and saved per machine.

const DATA := "res://content/look/sound.json"
const SETTINGS_PATH := "user://settings/sound.cfg"
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const SCORE_BUS := "Score"     ## ambient, battle and space (sends to Music)
const CLUB_BUS := "Club"       ## the club mix, with its low-pass (sends to Music)
const SILENT_DB := -60.0

static var _lib: Sound

var cfg: Dictionary
var mode := ""                 ## what the music plays: "", "ambient", "battle", "space"
var in_space := false
var battle_left := 0.0
var battle_part := 0           ## 1 the first battle track, 2 `battle_2` after it (0 not in a fight)
var ambient_track := ""       ## the ambient path playing now
var _ambient_bag: Array = []   ## issue #291: ambient paths still to play, shuffled
var music_on := false
var one_shots := 0
var _streams: Dictionary = {}  ## path -> AudioStream
var _deck: AudioStreamPlayer   ## the track playing now
var _spare: AudioStreamPlayer  ## the last one, fading out
var _tw: Tween
var _credits := -1
var _carried: Dictionary = {}  ## key -> AudioStreamPlayer (carried_loop)
var club := ""                 ## issue #104: the playlist of the club you are near ("" = none)
var club_near := 0.0           ## 0 out of earshot .. 1 at the wall
var club_inside := false
var club_live := true          ## false once a band member is killed
var club_mood := ""            ## what Oda was last asked for ("" = anything)
var club_level := 0.0          ## the club layer now, 0..1, eased toward its target
var club_open := 0.0           ## 0 muffled through the wall .. 1 inside, eased
var club_track := ""           ## the path playing on the club deck
var _club_deck: AudioStreamPlayer
var _club_spare: AudioStreamPlayer
var _club_tw: Tween
var _club_bag: Array = []      ## paths still to play before the playlist reshuffles
var _club_playing := ""        ## the playlist the club deck is playing from
var radio := ""                ## issue #291: the playlist the ship's radio plays ("" = off)


# ------------------------------------------------------------------ the calls

static func lib() -> Sound:
	if is_instance_valid(_lib):
		return _lib
	_lib = Sound.new()
	_lib.name = "Sound"
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		# Deferred: the first call often comes from a scene's _ready, while the
		# root is still busy adding that scene.
		tree.root.add_child.call_deferred(_lib)
	return _lib


## A one-shot. 3D at `at` (falls off with distance), 2D when `at` is INF.
## Returns the player, or null when the key is unknown or too many are playing.
static func play(key: String, at: Vector3 = Vector3.INF) -> Node:
	var s := lib()
	var c: Dictionary = s.cfg.get("sfx", {}).get(key, {})
	var stream := s._pick(c)
	if stream == null or s.one_shots >= int(s.cfg.get("max_one_shots", 24)):
		return null
	var p := s._player(c, at != Vector3.INF)
	p.stream = stream
	p.autoplay = true            # plays once it is in the tree, even if that is next frame
	if at != Vector3.INF:
		(p as AudioStreamPlayer3D).position = at
	s.one_shots += 1
	p.finished.connect(func():
		s.one_shots -= 1
		p.queue_free())
	s.add_child(p)
	return p


## Loads the streams of `keys` now (FxWarmup), so the first play of each is not a disk read.
static func warm(keys: Array) -> void:
	var s := lib()
	for k in keys:
		var st = s.cfg.get("sfx", {}).get(k, {}).get("stream", "")
		for path in (st if st is Array else [st]):
			s._load(str(path))


## A looping player on `parent`: 3D when the parent is a Node3D (unless `spatial`
## is false: the sound of your own ship), 2D otherwise. Not playing yet. Null when
## the key is unknown.
static func loop(key: String, parent: Node, spatial := true) -> Node:
	var s := lib()
	var c: Dictionary = s.cfg.get("sfx", {}).get(key, {})
	var stream := s._pick(c)
	if stream == null:
		return null
	var p := s._player(c, spatial and parent is Node3D)
	p.stream = _looping(stream, 0.0)
	parent.add_child(p)
	return p


## A looping 2D player that lives under Sound, not in a scene, so it plays on
## across a scene change (the ship's drone over a no-fade handoff). One per key;
## the scene starts and stops it. Null when the key is unknown.
static func carried_loop(key: String) -> AudioStreamPlayer:
	var s := lib()
	var p: AudioStreamPlayer = s._carried.get(key)
	if p != null and is_instance_valid(p):
		return p
	p = loop(key, s, false) as AudioStreamPlayer
	if p != null:
		s._carried[key] = p
	return p


## An NPC fired at the player: battle music, and it holds a while after.
static func battle() -> void:
	var s := lib()
	s.battle_left = float(s.cfg.get("music", {}).get("battle_hold", 15.0))


## The fight is over (the general dead at the top of the cruiser): the battle
## music ends now, not `battle_hold` later, and the next shot starts it afresh.
static func end_battle() -> void:
	lib().battle_left = 0.0


static func set_space(on: bool) -> void:
	lib().in_space = on


## Issue #104: the town says where the player is from its cantina each frame:
## `id` the club's playlist ("" when there is no club), `near` 0 out of earshot
## .. 1 at the wall, `inside` past the door.
static func set_club(id: String, near: float, inside: bool) -> void:
	var s := lib()
	s.club = id
	s.club_near = clampf(near, 0.0, 1.0)
	s.club_inside = inside


## A band member was killed (false): the club music stops. A new band (true).
static func set_club_live(on: bool) -> void:
	lib().club_live = on


## Oda puts on a song with this mood tag (any song when none has it). False when
## the club has nothing to play.
static func club_vibe(mood: String) -> bool:
	return lib().vibe(mood)


func vibe(mood: String) -> bool:
	club_mood = mood
	_club_bag.clear()
	return _club_next()


## Issue #291: J in a ship. The radio's next station (`club.radio`: the desert
## cantina mix, the moon rave mix), then off. Returns the playlist now on, "" for off.
static func radio_next() -> String:
	var s := lib()
	var list: Array = s._club_cfg().get("radio", [])
	var i := list.find(s.radio) + 1
	s.set_radio(str(list[i]) if i < list.size() else "")
	return s.radio


## The radio on playlist `id`, or off (""). A new station cuts over in
## `club.radio_fade` seconds, not a song's slow blend.
func set_radio(id: String) -> void:
	if id == radio:
		return
	radio = id
	if id != "" and _club_deck != null and _club_deck.playing:
		_club_next(float(_club_cfg().get("radio_fade", 1.0)))


## Start the music if it is not already going (each playable scene calls this).
static func start_music() -> void:
	lib().music_on = true


## A bus's volume as 0..1 (the settings sliders).
static func volume(bus: String) -> float:
	var i := AudioServer.get_bus_index(bus)
	return db_to_linear(AudioServer.get_bus_volume_db(i)) if i >= 0 else 1.0


static func set_volume(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	linear = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(i, linear <= 0.001)
	DirAccess.make_dir_recursive_absolute(SETTINGS_PATH.get_base_dir())
	var f := ConfigFile.new()
	f.load(SETTINGS_PATH)
	f.set_value("volume", bus, linear)
	f.save(SETTINGS_PATH)


# ------------------------------------------------------------------ the node

func _init() -> void:
	var t := FileAccess.get_file_as_string(DATA)
	var d = JSON.parse_string(t) if t != "" else null
	cfg = d if d is Dictionary else {}
	var f := ConfigFile.new()
	if f.load(SETTINGS_PATH) == OK:
		for bus in [MUSIC_BUS, SFX_BUS]:
			var i := AudioServer.get_bus_index(bus)
			if i >= 0 and f.has_section_key("volume", bus):
				var v := float(f.get_value("volume", bus))
				AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
				AudioServer.set_bus_mute(i, v <= 0.001)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_deck = _music_player()
	_spare = _music_player()
	_club_deck = _music_player(CLUB_BUS)
	_club_spare = _music_player(CLUB_BUS)


func _process(dt: float) -> void:
	battle_left = maxf(0.0, battle_left - dt)
	_watch_credits()
	if not music_on:
		return
	_club_process(dt)
	var want := want_mode()
	if want != mode:
		_switch(want)
	elif _ends_soon():
		_switch(mode)                  # the next ambient track, or battle 1 into battle 2
	elif not _deck.playing:
		_switch(mode)


## Near the end of the track on the deck, with another to blend into: an ambient
## track, or the first battle track when there is a `battle_2`.
func _ends_soon() -> bool:
	if not _deck.playing or _deck.stream == null:
		return false
	var blend := _fade()
	if mode == "battle":
		if battle_part != 1 or not _has_battle_2():
			return false
		blend = float(cfg.get("music", {}).get("battle_blend", 2.0))
	elif mode != "ambient":
		return false
	return _deck.get_playback_position() >= _deck.stream.get_length() - blend


func _has_battle_2() -> bool:
	return str(cfg.get("music", {}).get("battle_2", {}).get("stream", "")) != ""


## What the music should be playing right now.
func want_mode() -> String:
	if in_space:
		return "space"
	if battle_left > 0.0:
		return "battle"
	return "ambient"


func _switch(to: String) -> void:
	var m: Dictionary = cfg.get("music", {})
	var path := ""
	var start := 0.0
	var fade_in := _fade()
	var fade_out := _fade()
	# Issue #80: into a fight the music cuts over at once (a slow cross-fade
	# lagged behind the gunfire). Out of one, back to ambient, the next track
	# fades in like any other; ambient tracks still blend.
	if to == "battle" or (mode == "battle" and to != "ambient"):
		fade_in = float(m.get("battle_cut", 0.25))
		fade_out = float(m.get("battle_cut", 0.25))
	# Already fighting: the first battle track ran out, so the second takes over.
	battle_part = (2 if mode == "battle" and _has_battle_2() else 1) if to == "battle" else 0
	match to:
		"ambient":
			var list: Array = m.get("ambient", [])
			if list.is_empty():
				mode = to
				return
			# Issue #291: a shuffled bag, never the same track twice in a row.
			if _ambient_bag.is_empty():
				_ambient_bag = list.duplicate()
				_ambient_bag.shuffle()
				if _ambient_bag.size() > 1 and str(_ambient_bag.back()) == ambient_track:
					_ambient_bag.push_front(_ambient_bag.pop_back())
			path = str(_ambient_bag.pop_back())
			ambient_track = path
		"battle", "space":
			var c: Dictionary = m.get("battle_2" if battle_part == 2 else to, {})
			path = str(c.get("stream", ""))
			start = float(c.get("start", 0.0))
			if battle_part == 1:
				fade_in = float(m.get("battle_fade_in", 0.05))
			elif battle_part == 2:
				fade_in = float(m.get("battle_blend", 2.0))
				fade_out = fade_in
	mode = to
	var stream := _load(path)
	if stream == null:
		return
	# Every track but an ambient one loops, except a first battle track with a
	# second to follow it.
	if to != "ambient" and not (battle_part == 1 and _has_battle_2()):
		stream = _looping(stream, start)
	# Swap decks: the old track fades out while the new one fades in.
	var old := _deck
	_deck = _spare
	_spare = old
	if _tw != null:
		_tw.kill()
	_deck.stream = stream
	_deck.volume_db = SILENT_DB
	_deck.play(start)
	_tw = create_tween().set_parallel(true)
	_tw.tween_property(_deck, "volume_db", float(m.get("volume_db", -12.0)), fade_in)
	if old.playing:
		_tw.tween_property(old, "volume_db", SILENT_DB, fade_out)
		_tw.chain().tween_callback(old.stop)


# ------------------------------------------------------------------ the club (issue #104)

func _club_cfg() -> Dictionary:
	return cfg.get("club", {})


## The tracks of playlist `id` that exist: the ones tagged `mood` when any are,
## else all of them.
func club_tracks(id: String, mood := "") -> Array:
	var all: Array = []
	var tagged: Array = []
	for t in _club_cfg().get("playlists", {}).get(id, []):
		var path := str(t.get("stream", "")) if t is Dictionary else str(t)
		if path == "" or not ResourceLoader.exists(path):
			continue
		all.append(path)
		if mood != "" and t is Dictionary and (t.get("moods", []) as Array).has(mood):
			tagged.append(path)
	return tagged if not tagged.is_empty() else all


## The playlist the club layer plays: the radio's when it is on, else the club's
## you are near.
func club_playlist() -> String:
	return radio if radio != "" else club


## Whether the club layer has music to play: the radio has no band to kill.
func _club_on() -> bool:
	return radio != "" or club_live


## How loud the club layer should be, 0..1: nothing in space or away from a
## club, up to `outside` at the wall, all of it inside or with the radio on.
func club_target() -> float:
	if radio != "":
		return 1.0
	if club == "" or in_space:
		return 0.0
	if club_inside:
		return 1.0
	return club_near * float(_club_cfg().get("outside", 0.5))


func _club_process(dt: float) -> void:
	var c := _club_cfg()
	var target := club_target()
	var k := clampf(dt * float(c.get("ease", 2.0)), 0.0, 1.0)
	club_level = lerpf(club_level, target, k)
	club_open = lerpf(club_open, 1.0 if club_inside or radio != "" else 0.0, k)
	if target == 0.0 and club_level < 0.002:
		club_level = 0.0
	_club_mix()
	if club_level == 0.0:
		# Out of earshot: stop, so the next walk past starts a new song.
		if _club_deck.playing:
			_club_stop(0.0)
	elif not _club_on():
		# The band is dead: the music stops (the score stays ducked inside).
		if _club_playing != "":
			_club_stop(float(c.get("stop_fade", 1.5)))
	elif _club_playing != club_playlist() or not _club_deck.playing:
		_club_next()
	elif _club_deck.stream != null and _club_deck.get_playback_position() >= _club_deck.stream.get_length() - _club_fade():
		_club_next()


## The bus levels: the club layer up by `club_level`, the score down by it, and
## the wall's muffle opening as you come in.
func _club_mix() -> void:
	var c := _club_cfg()
	var ci := AudioServer.get_bus_index(CLUB_BUS)
	var si := AudioServer.get_bus_index(SCORE_BUS)
	if ci >= 0:
		AudioServer.set_bus_volume_db(ci, linear_to_db(maxf(club_level, 0.0001)))
		var lp := AudioServer.get_bus_effect(ci, 0) as AudioEffectLowPassFilter
		if lp != null:
			var lo := log(float(c.get("muffle_hz", 500.0)))
			var hi := log(float(c.get("open_hz", 20000.0)))
			lp.cutoff_hz = exp(lerpf(lo, hi, club_open))
	if si >= 0:
		AudioServer.set_bus_volume_db(si, linear_to_db(maxf(1.0 - club_level, 0.0001)))


## The next song: from a shuffled bag of the playlist, never the same twice in a
## row, blended in over `fade` seconds (by default the song blend once one is
## going). False when there is nothing to play.
func _club_next(fade := -1.0) -> bool:
	var id := club_playlist()
	if id == "" or not _club_on():
		return false
	if _club_bag.is_empty() or _club_playing != id:
		_club_bag = club_tracks(id, club_mood if radio == "" else "")
		_club_bag.shuffle()
		if _club_bag.size() > 1 and _club_bag.back() == club_track:
			_club_bag.push_front(_club_bag.pop_back())
	if _club_bag.is_empty():
		return false
	var path: String = _club_bag.pop_back()
	var stream := _load(path)
	if stream == null:
		return false
	# A blend when a song is already going; a quick start when walking up
	# (the layer's own level fades it in then).
	if fade < 0.0:
		fade = _club_fade() if _club_deck.playing else 0.5
	_club_playing = id
	club_track = path
	var old := _club_deck
	_club_deck = _club_spare
	_club_spare = old
	if _club_tw != null:
		_club_tw.kill()
	_club_deck.stream = stream
	_club_deck.volume_db = SILENT_DB
	_club_deck.play()
	_club_tw = create_tween().set_parallel(true)
	_club_tw.tween_property(_club_deck, "volume_db", float(_club_cfg().get("volume_db", -10.0)), fade)
	if old.playing:
		_club_tw.tween_property(old, "volume_db", SILENT_DB, fade)
		_club_tw.chain().tween_callback(old.stop)
	return true


func _club_stop(fade: float) -> void:
	_club_playing = ""
	club_track = ""
	_club_bag.clear()
	if _club_tw != null:
		_club_tw.kill()
	for p: AudioStreamPlayer in [_club_deck, _club_spare]:
		if not p.playing:
			continue
		if fade <= 0.0:
			p.stop()
		else:
			_club_tw = create_tween()
			_club_tw.tween_property(p, "volume_db", SILENT_DB, fade)
			_club_tw.tween_callback(p.stop)


func _club_fade() -> float:
	return float(_club_cfg().get("fade", 10.0))


func _watch_credits() -> void:
	var now: int = WorldState.credits
	if _credits >= 0 and now != _credits:
		Sound.play("coin_gain" if now > _credits else "coin_spend")
	_credits = now


func _fade() -> float:
	return float(cfg.get("music", {}).get("fade", 4.0))


func _music_player(bus := SCORE_BUS) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = SILENT_DB
	add_child(p)
	return p


func _player(c: Dictionary, spatial: bool) -> Node:
	var p: Node
	if spatial:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = float(c.get("unit_size", 10.0))
		p3.max_distance = float(c.get("max_distance", 0.0))
		p = p3
	else:
		p = AudioStreamPlayer.new()
	p.bus = SFX_BUS
	p.volume_db = float(c.get("volume_db", 0.0))
	var pr: Array = c.get("pitch", [])
	if pr.size() == 2:
		p.pitch_scale = randf_range(float(pr[0]), float(pr[1]))
	return p


## One of the entry's streams (a list picks at random).
func _pick(c: Dictionary) -> AudioStream:
	var s = c.get("stream", "")
	if s is Array:
		s = s[randi() % s.size()] if not s.is_empty() else ""
	return _load(str(s))


func _load(path: String) -> AudioStream:
	if path == "":
		return null
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	return _streams[path]


## A looping copy of `stream` that comes back round to `from` seconds.
static func _looping(stream: AudioStream, from: float) -> AudioStream:
	var s: AudioStream = stream.duplicate()
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = int(from * s.mix_rate)
		s.loop_end = int(s.get_length() * s.mix_rate)
	elif s is AudioStreamMP3 or s is AudioStreamOggVorbis:
		s.loop = true
		s.loop_offset = from
	return s
