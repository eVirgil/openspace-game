extends GutTest
## Issue #83: voice selection and spoken-only tone tags stay deterministic and
## independent from dialogue text. No API calls or credentials are used here.

const VoiceScript := preload("res://src/systems/voice/npc_voice.gd")


func _voice():
	var voice = VoiceScript.new()
	voice._load_profiles()
	return voice


func test_voice_profiles_cover_guards_merchants_locals_and_t89() -> void:
	var voice = _voice()
	assert_true(voice.profile_for_npc("gate-01", { "role": "gate" }) in ["man_serious", "man_gruff"])
	assert_true(voice.profile_for_npc("tower-01", { "role": "sentry" }) in ["man_serious", "man_gruff"])
	assert_eq(voice.profile_for_npc("stall-01", { "role": "merchant" }), "man_laid_back")
	assert_true(voice.profile_for_npc("resident-01", { "role": "local" }) in
		["man_casual", "man_old", "man_southern", "woman_quirky", "woman_confident"])
	assert_eq(voice.profile_for_npc("t89", {}), "robot_retro")
	assert_eq(voice.profile_for_npc("cantina_owner", {}), "woman_relaxed")
	assert_eq(voice.profile_for_npc("mechanic", {}), "man_southern")
	assert_eq(voice.profile_for_npc("fence-01", { "role": "merchant", "voice_profile": "man_shady" }), "man_shady")


## Issue #164: Skrugs is a goofy man, T-89 a retro robot, and the Odas off the home
## planet each get a woman's voice instead of the male fallback.
func test_issue_164_voice_picks() -> void:
	var voice = _voice()
	assert_eq(voice.voice_for(voice.profile_for_npc("skrugs", {})).label, "Man (goofy)")
	assert_eq(voice.voice_for(voice.profile_for_npc("t89", {})).label, "Robot (retro)")
	var odas := {}
	for pid in ["dune_2", "ice_7", "jungle_3", "rock_9", "ocean_1"]:
		var p: String = voice.profile_for_npc("cantina_owner_" + pid, { "voice_role": "planet_owner" })
		assert_true(str(voice.voice_for(p).label).begins_with("Woman"), "%s gets a woman's voice" % pid)
		odas[p] = true
	assert_gte(odas.size(), 2, "the off-world Odas do not all share one voice")


## Every name voice_profiles.json hands out is a library voice with an ID and a
## description to pick it by.
func test_every_profile_resolves_to_a_described_library_voice() -> void:
	var voice = _voice()
	var names: Array = [voice._profiles.get("default", "")]
	names.append_array(voice._profiles.get("npc_profiles", {}).values())
	for pool in voice._profiles.get("role_profiles", {}).values():
		names.append_array(pool)
	for n in names:
		var v: Dictionary = voice.voice_for(str(n))
		assert_ne(str(v.get("voice_id", "")), "", "%s has a voice id" % n)
		assert_ne(str(v.get("label", "")), "", "%s has a description" % n)
	var ids := {}
	var labels := {}
	for k in voice._library:
		ids[voice._library[k].voice_id] = true
		labels[voice._library[k].label] = true
	assert_eq(ids.size(), voice._library.size(), "no voice is in the library twice")
	assert_eq(labels.size(), voice._library.size(), "every description is unique")


func test_voice_assignment_is_stable_and_varies_across_locals() -> void:
	var voice = _voice()
	assert_eq(voice.profile_for_npc("resident-a", { "role": "local" }),
		voice.profile_for_npc("resident-a", { "role": "local" }))
	var assigned := {}
	for i in 40:
		assigned[voice.profile_for_npc("resident-%d" % i, { "role": "local" })] = true
	assert_gte(assigned.size(), 2, "locals do not all share one voice")


func test_mood_tags_and_shouts_are_added_only_to_speech_payload() -> void:
	var profile := {
		"style_tag": "[robotic, metallic voice]",
		"mood_tags": { "warm": "[warm, friendly delivery]", "angry": "[angry, forceful delivery]" }
	}
	var tags := VoiceScript.mood_tags_for(profile, "warm")
	var subtitle := "Welcome, pilot."
	assert_eq(VoiceScript.speech_text(subtitle, tags), "[robotic, metallic voice] [warm, friendly delivery] Welcome, pilot.")
	assert_eq(subtitle, "Welcome, pilot.", "the visible subtitle remains unchanged")
	var shout := VoiceScript.mood_tags_for(profile, "warm", true)
	assert_true(shout.has("[shouts]"))
	assert_false(shout.has("[warm, friendly delivery]"), "shouting replaces the mood delivery tag")


func test_elevenlabs_payload_carries_mood_speed_and_v4_model() -> void:
	var profile := {
		"style_tag": "[low, metallic, robotic voice]",
		"stability": 0.82
	}
	var payload := VoiceScript.build_payload("Stand by.", profile, "eleven_v4", 0.85,
		{ "wary": "[cautious, restrained delivery]" }, "wary")
	assert_eq(payload.model_id, "eleven_v4")
	assert_eq(payload.text, "[low, metallic, robotic voice] [cautious, restrained delivery] Stand by.")
	assert_eq(payload.voice_settings.speed, 0.85)
	assert_eq(payload.voice_settings.stability, 0.82)


func test_cache_key_changes_with_voice_speed_and_model() -> void:
	var baseline := VoiceScript.cache_key("hello", "voice-a", "eleven_v4", 1.0)
	assert_ne(baseline, VoiceScript.cache_key("hello", "voice-b", "eleven_v4", 1.0))
	assert_ne(baseline, VoiceScript.cache_key("hello", "voice-a", "eleven_v4", 0.9))
	assert_ne(baseline, VoiceScript.cache_key("hello", "voice-a", "another-model", 1.0))
	assert_ne(baseline, VoiceScript.cache_key("hello", "voice-a", "eleven_v4", 1.0, 0.8))


## Scripted lines are recorded into the repo (tools/audio/make_voice_lines.py) so
## they are voiced with no key: the gate guards' barks have clips that load.
func test_scripted_lines_have_bundled_clips() -> void:
	var voice = _voice()
	var guard := str(voice.voice_for("man_serious").voice_id)
	assert_eq(VoiceScript.bundled_path("  Papers.  ", guard), VoiceScript.bundled_path("Papers.", guard),
		"edges do not change the clip")
	var recorded := 0
	var lines: Dictionary = VoiceScript._read_json("res://content/core/dialogue/gate_guard_lines.json").get("lines", {})
	for key in lines:
		for line in lines[key]:
			var path: String = VoiceScript.bundled_path(str(line), guard)
			if ResourceLoader.exists(path):
				recorded += 1
				assert_true(load(path) is AudioStream, "%s loads as audio" % line)
	assert_gt(recorded, 0, "the guards' barks are recorded")
	assert_false(ResourceLoader.exists(VoiceScript.bundled_path("never a scripted line", guard)))
