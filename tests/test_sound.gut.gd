extends GutTest
## Issue #16: the sound library and the music. Every sound and track the library
## names must exist and load; the music picks space over battle over ambient,
## battle starts 30 s in and loops back there, and credits make coin noises.

const DATA := "res://content/look/sound.json"
const TownLayout := preload("res://src/systems/world/town_layout.gd")
var cfg: Dictionary


func before_all() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string(DATA))


func _paths() -> Array:
	var out: Array = []
	for k in cfg.sfx:
		var s = cfg.sfx[k].stream
		out.append_array(s if s is Array else [s])
	out.append_array(cfg.music.ambient)
	out.append(cfg.music.battle.stream)
	out.append(cfg.music.space.stream)
	for id in cfg.club.playlists:
		for t in cfg.club.playlists[id]:
			out.append(t.stream)
	return out


func test_every_sound_and_track_loads() -> void:
	for p in _paths():
		assert_true(ResourceLoader.exists(str(p)), "exists: " + str(p))
		assert_true(load(str(p)) is AudioStream, "loads: " + str(p))


func test_the_issue_asks_for_these_sounds() -> void:
	for k in ["coin_gain", "coin_spend", "jet_loop", "ship_engine", "ship_laser", "droid_beep", "droid_hum"]:
		assert_true(cfg.sfx.has(k), "sfx key: " + k)
	assert_gt(cfg.music.ambient.size(), 1, "more than one ambient track to cycle")
	assert_eq(float(cfg.music.battle.start), 30.0, "battle starts 30 s in")


## Ships and speeders share one explosion: a few CC0 booms, picked at random.
func test_vehicles_share_an_explosion() -> void:
	assert_true(cfg.sfx.has("vehicle_boom"), "sfx key: vehicle_boom")
	assert_gt(cfg.sfx.vehicle_boom.stream.size(), 1, "more than one boom to pick from")
	assert_false(cfg.sfx.has("ship_boom"), "ships use the shared key")
	for f in ["res://src/systems/vehicles/speeder_node.gd", "res://src/systems/flight/ship_pilot.gd"]:
		assert_true(FileAccess.get_file_as_string(f).contains("Sound.play(\"vehicle_boom\""), f + " plays the shared boom")


func test_buses_exist() -> void:
	assert_gt(AudioServer.get_bus_index(Sound.MUSIC_BUS), 0, "Music bus")
	assert_gt(AudioServer.get_bus_index(Sound.SFX_BUS), 0, "SFX bus")
	# Issue #104: the score and the club mix both go through the Music slider.
	for b in [Sound.SCORE_BUS, Sound.CLUB_BUS]:
		var i := AudioServer.get_bus_index(b)
		assert_gt(i, 0, b + " bus")
		assert_eq(str(AudioServer.get_bus_send(i)), Sound.MUSIC_BUS, b + " sends to Music")
	assert_true(AudioServer.get_bus_effect(AudioServer.get_bus_index(Sound.CLUB_BUS), 0) is AudioEffectLowPassFilter,
		"the club is muffled through the wall")


func test_music_priority() -> void:
	var s: Sound = autofree(Sound.new())
	assert_eq(s.want_mode(), "ambient")
	s.battle_left = 5.0
	assert_eq(s.want_mode(), "battle", "NPCs shooting")
	s.in_space = true
	assert_eq(s.want_mode(), "space", "space wins")
	s.in_space = false
	s.battle_left = 0.0
	assert_eq(s.want_mode(), "ambient", "back to ambient")


func test_battle_holds_then_lets_go() -> void:
	var s: Sound = add_child_autofree(Sound.new())
	s.battle_left = float(cfg.music.battle_hold)
	s._process(float(cfg.music.battle_hold) - 1.0)
	assert_eq(s.want_mode(), "battle", "still holding")
	s._process(2.0)
	assert_eq(s.want_mode(), "ambient", "quiet long enough")


## Issue #80: the fight music cuts in at once; after the fight the next
## ambient track fades in over `fade` seconds, not the battle cut.
func test_battle_cuts_in_and_ambient_fades_back() -> void:
	var s: Sound = add_child_autofree(Sound.new())
	var full := float(cfg.music.volume_db)
	s._switch("ambient")
	s._switch("battle")
	s._tw.custom_step(0.5)
	assert_almost_eq(s._deck.volume_db, full, 0.1, "battle is in at once")
	s._switch("ambient")
	s._tw.custom_step(0.5)
	assert_lt(s._deck.volume_db, full - 6.0, "ambient is still fading in")
	s._tw.custom_step(float(cfg.music.fade))
	assert_almost_eq(s._deck.volume_db, full, 0.1, "ambient faded in")


func test_battle_plays_from_30s_and_loops_there() -> void:
	var s: Sound = add_child_autofree(Sound.new())
	s._switch("battle")
	assert_eq(s.mode, "battle")
	var st = s._deck.stream
	assert_true(st is AudioStreamMP3, "battle track")
	assert_true(st.loop, "loops")
	assert_eq(st.loop_offset, 30.0, "loops back to 30 s")
	assert_true(s._deck.playing, "playing")


func test_ambient_cycles() -> void:
	var s: Sound = add_child_autofree(Sound.new())
	var seen := {}
	for i in cfg.music.ambient.size():
		s._switch("ambient")
		seen[s._deck.stream.resource_path] = true
	assert_eq(seen.size(), cfg.music.ambient.size(), "each ambient track in turn")


## Issue #291: the ambient order is shuffled, so a new game does not always open
## on the same track, and a reshuffle never plays the last track again at once.
func test_ambient_shuffles() -> void:
	var firsts := {}
	for i in 30:
		var s: Sound = add_child_autofree(Sound.new())
		s._switch("ambient")
		firsts[s.ambient_track] = true
	assert_gt(firsts.size(), 1, "games open on different tracks")
	var s: Sound = add_child_autofree(Sound.new())
	var last := ""
	for i in cfg.music.ambient.size() * 6:
		s._switch("ambient")
		assert_ne(s.ambient_track, last, "not the same track twice in a row")
		last = s.ambient_track


func test_credits_make_coin_noises() -> void:
	var s := Sound.lib()
	var before := s.one_shots
	var had := WorldState.credits
	s._credits = had
	WorldState.credits = had + 25
	s._watch_credits()
	assert_eq(s.one_shots, before + 1, "a coin sound for credits in")
	WorldState.credits = had
	s._watch_credits()
	assert_eq(s.one_shots, before + 2, "and one for credits out")


func test_blade_is_quieter() -> void:
	var look: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/look/hand_weapons.json"))
	assert_lt(float(look.blade_volume.db), -6.0, "blade one-shots under the old -6 dB")
	assert_lt(float(look.blade_volume.hum_db), -16.0, "hum under the old -16 dB")


# ------------------------------------------------------------------ issue #104: the club

## A Sound with a test playlist made of the ambient tracks (the real playlists
## wait for the approved tracks), two tagged "hard".
func _club_sound() -> Sound:
	var s: Sound = add_child_autofree(Sound.new())
	var amb: Array = cfg.music.ambient
	s.cfg.club = cfg.club.duplicate(true)
	s.cfg.club.playlists = { "test": [
		{ "stream": amb[0], "moods": ["chill"] },
		{ "stream": amb[1], "moods": ["hard"] },
		{ "stream": amb[2], "moods": ["hard", "dark"] },
	] }
	s.music_on = true
	return s


func test_club_config() -> void:
	assert_eq(float(cfg.club.fade), 10.0, "songs blend over 10 s")
	assert_eq(float(cfg.club.hear), 40.0, "heard from 40 m out")
	for id in ["dust_lounge", "salvage_rave"]:
		assert_true(cfg.club.playlists.has(id), "playlist " + id)
		for t in cfg.club.playlists[id]:
			assert_false((t.get("moods", []) as Array).is_empty(), "mood tags on " + str(t.stream))
	for f in ["port_desert", "grit_station"]:
		var p: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/core/planets/%s.json" % f))
		assert_true(cfg.club.playlists.has(str(p.get("club", ""))), f + " names a playlist")


func test_club_distance() -> void:
	var r := Rect2(-90, -16, 40, 32)
	assert_eq(ClubMusic.distance(r, -70, 0), 0.0, "inside")
	assert_almost_eq(ClubMusic.distance(r, -30, 0), 20.0, 0.001, "20 m out the door side")
	assert_almost_eq(ClubMusic.near(20.0, 40.0), 0.5, 0.001)
	assert_eq(ClubMusic.near(50.0, 40.0), 0.0, "out of earshot")
	assert_eq(ClubMusic.near(0.0, 40.0), 1.0, "at the wall")


func test_club_level_by_where_you_are() -> void:
	var s := _club_sound()
	assert_eq(s.club_target(), 0.0, "no club")
	s.club = "test"
	s.club_near = 1.0
	assert_almost_eq(s.club_target(), float(cfg.club.outside), 0.001, "at the wall: part of it, muffled")
	s.club_inside = true
	assert_eq(s.club_target(), 1.0, "inside: all of it")
	s.in_space = true
	assert_eq(s.club_target(), 0.0, "not in space")


func test_club_plays_and_ducks_the_score() -> void:
	var s := _club_sound()
	s.club = "test"
	s.club_inside = true
	for i in 30:
		s._process(0.1)
	assert_true(s._club_deck.playing, "a song is on")
	assert_true(s.club_tracks("test").has(s.club_track), "from the playlist")
	assert_gt(s.club_level, 0.9, "faded in")
	var si := AudioServer.get_bus_index(Sound.SCORE_BUS)
	assert_lt(AudioServer.get_bus_volume_db(si), -20.0, "the score ducks under it")
	s.battle_left = 10.0
	s._process(0.1)
	assert_true(s._club_deck.playing, "gunfire does not cut the club")
	s.club = ""
	for i in 60:
		s._process(0.1)
	assert_eq(s.club_level, 0.0, "walked away")
	assert_false(s._club_deck.playing, "stopped, so the next visit starts a new song")
	assert_gt(AudioServer.get_bus_volume_db(si), -0.1, "the score is back")


func test_club_shuffles_without_repeats() -> void:
	var s := _club_sound()
	s.club = "test"
	var last := ""
	for i in 9:
		assert_true(s._club_next(), "next song")
		assert_ne(s.club_track, last, "not the same twice in a row")
		last = s.club_track


func test_oda_changes_the_vibe() -> void:
	var s := _club_sound()
	s.club = "test"
	for i in 5:
		assert_true(s.vibe("hard"))
		assert_true(str(s.club_track) in [cfg.music.ambient[1], cfg.music.ambient[2]], "a hard song")
	assert_true(s.vibe("polka"), "no such mood: any song")


func test_dead_band_stops_the_music() -> void:
	var s := _club_sound()
	s.club = "test"
	s.club_inside = true
	s._process(0.1)
	assert_true(s._club_deck.playing)
	s.club_live = false
	s._process(0.1)
	assert_eq(s._club_playing, "", "the music stops")
	assert_false(s._club_next(), "and nothing new starts")


# ------------------------------------------------------------------ issue #392: the moon rave fills the station

## The station's ClubMusic counts the hall and the pit as inside: the rave mix and
## the score ducked in all three, a fight does not change it, and with the DJ dead
## there is neither.
func test_the_rave_mix_plays_in_the_dome_the_hall_and_the_pit() -> void:
	var t := TownLayout.new()
	t.load_from_dict(PlanetGen.build("grit_station").town)
	var zone := func(id: String) -> Dictionary: return t.zones().filter(func(z): return str(z.id) == id)[0]
	var who: Node3D = add_child_autofree(Node3D.new())
	var music: ClubMusic = ClubMusic.new().setup("salvage_rave", zone.call("cantina"), who)
	music.also_inside([zone.call("hall"), zone.call("landing_bay")])
	add_child_autofree(music)
	var s := Sound.lib()
	await get_tree().process_frame     # the library joins the tree deferred: its decks come in _ready
	s.music_on = true
	for where in [t.marker_pos("bar_front"), t.marker_pos("desert_exit"), t.spawn_pos()]:
		who.global_position = where
		music._process(0.1)
		assert_true(s.club_inside, "inside the rave at %s" % where)
		assert_eq(s.club_target(), 1.0, "all of the mix at %s" % where)
		for i in 60:
			s._club_process(0.1)
		assert_gt(s.club_level, 0.9, "the score is ducked at %s" % where)
	Sound.battle()            # a patron fires at you
	music._process(0.1)
	assert_eq(s.club_target(), 1.0, "a gunfight does not bring the battle music in")
	Sound.set_club_live(false)      # the DJ is dead
	for i in 30:
		s._club_process(0.1)
	assert_eq(s._club_playing, "", "no club music")
	assert_gt(s.club_level, 0.9, "and the score stays ducked: the station is quiet")
	music.free()
	Sound.set_club_live(true)
	s.battle_left = 0.0


# ------------------------------------------------------------------ issue #291: the ship's radio

func test_radio_steps_through_the_stations() -> void:
	assert_eq(cfg.club.radio, ["dust_lounge", "salvage_rave"], "the desert cantina mix, then the moon rave mix")
	var s := Sound.lib()
	s.set_radio("")
	assert_eq(Sound.radio_next(), "dust_lounge", "first J: the desert cantina mix")
	assert_eq(Sound.radio_next(), "salvage_rave", "second J: the moon rave mix")
	assert_eq(Sound.radio_next(), "", "third J: off, back to the score")
	assert_eq(s.radio, "")
	for id in cfg.club.radio + [""]:
		assert_ne(ShipPilot.radio_line(id), "", "a HUD line for " + (id if id != "" else "off"))
	assert_true(InputMap.has_action("flight_radio"), "J is bound")


func test_radio_plays_anywhere_and_ducks_the_score() -> void:
	var s := _club_sound()
	s.in_space = true
	s.battle_left = 10.0
	s.club_live = false                  # the radio has no band to kill
	s.set_radio("test")
	for i in 30:
		s._process(0.1)
	assert_true(s._club_deck.playing, "the radio plays in space, in a fight")
	assert_true(s.club_tracks("test").has(s.club_track), "from the station's playlist")
	assert_gt(s.club_level, 0.9, "full volume")
	assert_gt(s.club_open, 0.9, "not muffled")
	var si := AudioServer.get_bus_index(Sound.SCORE_BUS)
	assert_lt(AudioServer.get_bus_volume_db(si), -20.0, "the score ducks under it")
	var last := s.club_track
	assert_true(s._club_next(), "next song")
	assert_ne(s.club_track, last, "shuffled, not the same twice in a row")
	s.set_radio("")
	for i in 60:
		s._process(0.1)
	assert_eq(s.club_level, 0.0, "off")
	assert_false(s._club_deck.playing, "stopped")
	assert_gt(AudioServer.get_bus_volume_db(si), -0.1, "the score is back")
