extends Node
## Optional ElevenLabs NPC speech. Text/gameplay are authoritative: missing keys,
## failed requests, and uncached audio are all silent and never block a turn.
## The player supplies their own key in the existing settings panel. Keys are kept
## in user://llm/keys.cfg; generated MP3s stay in user://npc_voice_cache/.
## Scripted (non-AI) lines are recorded into res://assets/audio/voice/ and play
## first, key or no key.
## Issue #164: a profile name is a key in voice_library.json ("man_goofy",
## "robot_male"), a voice picked by description; voice_profiles.json says who uses which.

const LLMConfigScript := preload("res://src/systems/llm/llm_config.gd")
const PROFILES_PATH := "res://content/core/npcs/voice_profiles.json"
const LIBRARY_PATH := "res://content/core/npcs/voice_library.json"
const SETTINGS_PATH := "user://npc_voice_settings.cfg"
const CACHE_DIR := "user://npc_voice_cache"
const BUNDLE_DIR := "res://assets/audio/voice"
const KEY_ID := "elevenlabs"
const API_URL := "https://api.elevenlabs.io/v1/text-to-speech/"
const FALLBACK_MODEL := "eleven_v4"

var _profiles: Dictionary = {}
var _library: Dictionary = {}      ## voice_library.json "voices": key -> voice
var _speed := 1.0
var _tokens: Dictionary = {}       ## target instance id -> latest utterance token
var _requests: Dictionary = {}     ## target instance id -> HTTPRequest


func _ready() -> void:
	_load_profiles()
	_load_settings()


func _load_profiles() -> void:
	_profiles = _read_json(PROFILES_PATH)
	_library = _read_json(LIBRARY_PATH).get("voices", {})


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		_speed = clampf(float(cfg.get_value("voice", "speed", 1.0)), 0.7, 1.2)


func speed() -> float:
	return _speed


func set_speed(value: float) -> bool:
	_speed = clampf(value, 0.7, 1.2)
	var cfg := ConfigFile.new()
	cfg.set_value("voice", "speed", _speed)
	return cfg.save(SETTINGS_PATH) == OK


func api_key() -> String:
	var cfg = LLMConfigScript.new()
	return cfg.api_key(KEY_ID)


func set_api_key(key: String) -> bool:
	var cfg = LLMConfigScript.new()
	return cfg.set_api_key(KEY_ID, key.strip_edges())


## Resolve a stable voice profile for a soldier or dialogue NPC. A supplied
## `voice_profile` always wins; role variants are assigned deterministically.
## `voice_role` picks a pool without giving the NPC a gameplay role (the Odas
## on other planets use "planet_owner").
func profile_for_npc(npc_id: String, npc_data: Dictionary) -> String:
	var explicit := str(npc_data.get("voice_profile", ""))
	if explicit != "":
		return explicit
	var named: Dictionary = _profiles.get("npc_profiles", {})
	if named.has(npc_id):
		return str(named[npc_id])
	var role := str(npc_data.get("voice_role", npc_data.get("role", "")))
	if role == "" and str(npc_data.get("faction", "")) == "imperial_remnant":
		role = "guard"
	var choices: Array = _profiles.get("role_profiles", {}).get(role, [])
	if choices.is_empty():
		return str(_profiles.get("default", "man_casual"))
	return str(choices[posmod(hash(npc_id), choices.size())])


## The library entry for a profile name ({} when it is not in the library).
func voice_for(profile_name: String) -> Dictionary:
	return _library.get(profile_name, {})


static func mood_tags_for(profile: Dictionary, mood: String, shout: bool = false) -> PackedStringArray:
	var tags := PackedStringArray()
	var fixed := str(profile.get("style_tag", ""))
	if fixed != "":
		tags.append(fixed)
	var mood_tags: Dictionary = profile.get("mood_tags", {})
	var tag := str(mood_tags.get(mood.to_lower(), ""))
	if shout:
		tag = "[shouts]"
	if tag != "":
		tags.append(tag)
	return tags


static func speech_text(text: String, tags: PackedStringArray) -> String:
	var parts := PackedStringArray()
	for tag in tags:
		if tag != "":
			parts.append(tag)
	if text.strip_edges() != "":
		parts.append(text.strip_edges())
	return " ".join(parts)


static func cache_key(text: String, voice_id: String, model_id: String, speed_value: float,
		stability_value: float = 0.55) -> String:
	return "%s|%s|%s|%.2f|%.2f" % [
		text, voice_id, model_id, clampf(speed_value, 0.7, 1.2), clampf(stability_value, 0.0, 1.0)
	]


static func build_payload(text: String, voice: Dictionary, model_id: String,
		speed_value: float, mood_map: Dictionary, mood: String, shout: bool = false) -> Dictionary:
	var tags := mood_tags_for({
		"style_tag": voice.get("style_tag", ""),
		"mood_tags": mood_map
	}, mood, shout)
	return {
		"text": speech_text(text, tags),
		"model_id": model_id,
		"voice_settings": {
			"speed": clampf(speed_value, 0.7, 1.2),
			"stability": clampf(float(voice.get("stability", 0.55)), 0.0, 1.0),
			"similarity_boost": 0.75
		}
	}


## The scripted line recorded into the repo for this voice (tools/audio/
## make_voice_lines.py), so non-AI lines are voiced with no key. It may not exist:
## lines with a runtime fill are never recorded ahead.
static func bundled_path(text: String, voice_id: String) -> String:
	return BUNDLE_DIR.path_join(("%s|%s" % [text.strip_edges(), voice_id]).sha256_text().left(16) + ".mp3")


## `live_line`: a fresh LLM line, spoken at the player's speed setting. Canned
## lines (barks, menus, the tutorial) always render at normal speed so their
## cached clips survive a change of the speed slider and are generated once.
func speak(text: String, profile_name: String, mood: String, target: Node3D, shout: bool = false,
		live_line: bool = false) -> void:
	if text.strip_edges() == "" or target == null or not is_instance_valid(target):
		return
	# Avoid accidental web requests from headless tests and server processes.
	if DisplayServer.get_name() == "headless":
		return
	var v := voice_for(profile_name)
	var voice_id := str(v.get("voice_id", ""))
	if voice_id == "":
		return
	var bundled := bundled_path(text, voice_id)
	if ResourceLoader.exists(bundled):
		stop(target)
		_play_stream(target, load(bundled) as AudioStream)
		return

	var mood_map: Dictionary = _profiles.get("mood_tags", {})
	var model_id := str(_profiles.get("model_id", FALLBACK_MODEL))
	var speed_value := _speed if live_line else 1.0
	var payload := build_payload(text, v, model_id, speed_value, mood_map, mood, shout)
	var spoken_text := str(payload.text)
	var key := cache_key(spoken_text, voice_id, model_id, speed_value, float(v.get("stability", 0.55)))
	var cache_path := CACHE_DIR.path_join(key.sha256_text() + ".mp3")
	var target_id := target.get_instance_id()
	stop(target)
	var token := int(_tokens.get(target_id, 0))

	if FileAccess.file_exists(cache_path):
		_play_bytes(target, FileAccess.get_file_as_bytes(cache_path))
		return
	var key_value := api_key()
	if key_value == "":
		return

	var request := HTTPRequest.new()
	request.timeout = 45.0
	add_child(request)
	_requests[target_id] = request
	request.request_completed.connect(
		func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			_request_finished(target, target_id, token, cache_path, request, result, response_code, body)
	)
	var headers := PackedStringArray([
		"xi-api-key: " + key_value,
		"Content-Type: application/json"
	])
	var url := API_URL + voice_id + "?output_format=mp3_44100_128"
	if request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload)) != OK:
		_requests.erase(target_id)
		request.queue_free()


func stop(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var target_id := target.get_instance_id()
	_tokens[target_id] = int(_tokens.get(target_id, 0)) + 1
	var request: HTTPRequest = _requests.get(target_id)
	if request != null and is_instance_valid(request):
		request.cancel_request()
		request.queue_free()
	_requests.erase(target_id)
	var player := target.get_node_or_null("ElevenLabsVoicePlayer") as AudioStreamPlayer3D
	if player != null:
		player.stop()


func _request_finished(target: Node3D, target_id: int, token: int, cache_path: String,
		request: HTTPRequest, result: int, response_code: int, body: PackedByteArray) -> void:
	if _requests.get(target_id) == request:
		_requests.erase(target_id)
	if is_instance_valid(request):
		request.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or body.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	var file := FileAccess.open(cache_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(body)
	file.close()
	if not is_instance_valid(target) or int(_tokens.get(target_id, 0)) != token:
		return
	_play_bytes(target, body)


func _play_bytes(target: Node3D, bytes: PackedByteArray) -> void:
	if bytes.is_empty() or target == null or not is_instance_valid(target):
		return
	_play_stream(target, AudioStreamMP3.load_from_buffer(bytes))


func _play_stream(target: Node3D, stream: AudioStream) -> void:
	if stream == null or target == null or not is_instance_valid(target):
		return
	var player := target.get_node_or_null("ElevenLabsVoicePlayer") as AudioStreamPlayer3D
	if player == null:
		player = AudioStreamPlayer3D.new()
		player.name = "ElevenLabsVoicePlayer"
		player.position = Vector3(0.0, 1.4, 0.0)
		player.volume_db = -3.0
		player.unit_size = 8.0
		player.max_distance = 55.0
		player.bus = "SFX"
		target.add_child(player)
	player.stream = stream
	player.play()
