class_name NpcBrain
extends RefCounted
## An AI character's turn logic (M12; shared since #42). One brain per character,
## built from that character's card (the Cantina Owner's by default, Skrugs's at
## the outpost): who they are, what they may do, their canned lines. Originally
## the cantina owner's turn logic (M12). Replaces the M6 scaffold (cantina_owner_ai.gd,
## kept only for the M6/M7 traces): this one actually sends the player's words to
## a model, streams the answer, and turns the model's proposals into game effects
## only after they pass the validator.
##
##   player text -> screen -> PromptBuilder (persona, rules, briefing from
##   WorldState + Relationship, last 8 turns) -> LLMService (local -> ollama ->
##   cloud) -> ReplyParser (streams "say") -> OutputFilter -> ActionValidator ->
##   apply (rumors known, jobs offered, drinks charged, trust) -> remember
##
## If every provider fails she still answers, from canned lines that use real
## data (a true rumor, a real job), so the bar never dead-ends.
##
## Issue #328: with AI characters off that is the only path. topics() is the menu
## the dialogue shows then (say_topic() answers one), and a hint the player's words
## set off is told in the card's own authored "line".

signal thinking(bark: String)                 ## no first word yet: a beat to cover it
signal line_delta(text_so_far: String)        ## streamed, filtered subtitle
signal line_done(turn: Dictionary)            ## final { say, mood, kept, dropped, ... }
signal job_offered(job: Dictionary)
signal drink_poured(drink: Dictionary)
signal sale_offered(item: Dictionary)          ## issue #42: { id, name, price }; the player confirms
signal item_offered(item: Dictionary)          ## issue #305: an upgrade or gear from wares { id, name, price }; the player confirms
signal ship_buy_offered(item: Dictionary)      ## issue #295: Skrugs would buy their ship { id, name, price }; the player confirms
signal comrade_declared                        ## issue #206: T-89 heard the player hates the Remnant
signal verdict(kind: String)                   ## the general let them go ("let_go") or had them searched ("search"); issue #303: the dark master heard "join" or "refuse"
signal vibe_changed(mood: String)              ## issue #261: she had the band change the song

var last_hints: Array = []                     ## the hint lines the last line set off (tests)
signal ended(reason: String)

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const CARD_PATH := "res://content/core/npcs/cantina_owner_card.json"   ## the default card
const BRIEF_PATH := "res://content/core/llm/world_briefing.json"
const SCHEMA_PATH := "res://content/core/llm/reply_schema.json"
const LOG_ROOT := "user://logs"         ## transcripts go to <root>/<card id>/
const BARK_AFTER_MS := 900
const TOPICS_PATH := "res://content/core/npcs/topics.json"   ## issue #328: the AI-off menu

var llm: LLMService
var card: Dictionary
var builder: PromptBuilder
var filter: OutputFilter
var rel := Relationship.new()
var _world_cache: Dictionary = {}    ## the world this bar is in (issue #15: names its town and planet)
var history: Array = []              ## this visit: [{ role, content }]
var insults := 0
var busy := false
var talking := false
var log_transcripts := true
var log_dir := LOG_ROOT + "/cantina_owner"
var last_turn: Dictionary = {}       ## for the debug overlay
var turns: Array = []                ## every finished turn this session (tests read it)
var extra_brief: Callable            ## () -> Array of lines: this character's own facts each turn (T-89: the pad)
var wares: Callable                  ## issue #305: () -> [{ id, name, price, text }] what they can sell you now (offer_item)
var ship_offer: Callable             ## issue #295: () -> { id, name, price, stolen } a ship they would buy now, or {}

var _turn_id := -1
var _raw := ""
var _shown := ""
var _ids: Dictionary = {}
var _messages: Array = []
var _player_text := ""
var _hostile := false
var _t0 := 0
var _barked := false
var _rng := RandomNumberGenerator.new()
var _summary_id := -1
var _topic_now := ""                 ## issue #328: the menu topic this turn answers ("" = by keyword)
var _hint_lines: Array = []          ## issue #328: the authored lines of the hints this turn set off
var recap_events: Array = []         ## issue #185: what happened since they last talked (newest first), this visit
var recap_wanted := false            ## issue #185: the model should open with a recap (recap_turn)
var _recap_now := false              ## the turn in flight is the recap


## `card_src`: a card's path, or (issue #75: a planet's own Oda) the card itself.
func _init(service: LLMService = null, card_src = CARD_PATH) -> void:
	card = card_src if card_src is Dictionary else _read(str(card_src))
	log_dir = LOG_ROOT + "/" + id()
	builder = PromptBuilder.new(card, _read(BRIEF_PATH), _read(SCHEMA_PATH))
	filter = OutputFilter.new(card)
	_rng.seed = 7
	if service != null:
		attach(service)


## The card's id ("cantina_owner", "skrugs"): the key for this character's
## relationship in the save and for their transcript folder.
func id() -> String:
	return str(card.get("id", "npc"))


func attach(service: LLMService) -> void:
	llm = service
	llm.delta.connect(_on_delta)
	llm.finished.connect(_on_finished)
	llm.fallback.connect(_on_fallback)
	if llm.config != null:
		log_transcripts = bool(llm.config.data.get("debug", {}).get("log_transcripts", true))


# ------------------------------------------------------------------ visits

## The player stepped up to the bar. Returns her greeting (no model call: instant).
func begin_visit() -> String:
	var returning := rel.visits > 0
	# Issue #185: what happened since they last talked, for a character with a
	# "recap" block on their card (Oda). Never on a first visit or a fresh game.
	recap_events = news() if returning and card.has("recap") else []
	recap_wanted = false
	rel.heard_until = WorldState.clock
	rel.begin_visit()
	history.clear()
	insults = 0
	talking = true
	if returning:
		rel.add_trust(1, "came back to the bar")
	_credit_jobs()
	rel.mood = baseline_mood()
	var g: Array = card.get("greetings", {}).get(rel.tier(), ["Yeah?"])
	var line := str(g[_rng.randi() % g.size()])
	if not recap_events.is_empty():
		if model_ready():
			recap_wanted = true          # the greeting now, then the model's recap (recap_turn)
		else:
			line = authored_recap()      # no model: the authored version, from the same events
	history.append({ "role": "assistant", "content": JSON.stringify({ "say": line, "then": [], "tone": rel.mood }) })
	return line


## Issue #185: the events since they last talked (WorldState.clock heard_until),
## newest first, at most the card's recap.max (3). Story bookkeeping is left out.
func news() -> Array:
	if rel.heard_until < 0.0:
		return []
	var out: Array = []
	for i in range(WorldState.events.size() - 1, -1, -1):
		var e: Dictionary = WorldState.events[i]
		if float(e.get("t", 0.0)) <= rel.heard_until:
			break
		var text := str(e.get("text", ""))
		if text == "" or text.begins_with("Story:"):
			continue
		out.append(e)
		if out.size() >= int(card.get("recap", {}).get("max", 3)):
			break
	return out


## Issue #185: a model is there to ask (AI characters on, a provider up).
func model_ready() -> bool:
	return llm != null and llm.ai_on() and not llm.active_chain().is_empty()


## Issue #185: the canned recap, built from the same events the model would get.
func authored_recap() -> String:
	var r: Dictionary = card.get("recap", {})
	var said: PackedStringArray = []
	for e in recap_events:
		said.append(str(e.text))
	return ("%s %s %s" % [_pick(r.get("open", ["Look who's back. Word travels."])), " ".join(said),
		_pick(r.get("close", ["So. What'll it be?"]))]).strip_edges()


## Issue #185: the model's turn that opens with the recap, in her own voice. The
## scene calls it right after the greeting; no player line is shown for it.
func recap_turn() -> bool:
	if not recap_wanted or busy:
		return false
	recap_wanted = false
	_recap_now = true
	if not say(str(card.get("recap", {}).get("cue", "(They come back up to the bar after some time away.)"))):
		_recap_now = false
		return false
	return true


## Issue #64: the story's line instead of the greeting begin_visit() picked.
func replace_greeting(line: String) -> void:
	if not history.is_empty():
		history[history.size() - 1] = { "role": "assistant", "content": JSON.stringify({ "say": line, "then": [], "tone": rel.mood }) }


## The player walked off. Summarize the visit in the background (if online).
func end_visit() -> void:
	talking = false
	rel.heard_until = WorldState.clock      # issue #185: what happened while they talked is not news
	if llm == null or not llm.ai_on() or history.size() < 3:
		return
	_summary_id = llm.chat(builder.summary_messages(rel, history), { "max_tokens": 80, "temperature": 0.3, "background": true })


## Can she serve right now? (false after she threw the player out)
func serving() -> bool:
	return WorldState.clock >= rel.banned_until


## Load provider `pid`'s model and warm its prompt cache with the static prefix
## (issue #328: in the background; player turns skip it until it answers).
func warm_up(pid: String = "local") -> int:
	if llm == null:
		return -1
	return llm.warm(pid, [builder.persona_message(), builder.rules_message(), { "role": "user", "content": "<player_says>...</player_says>" }])


func baseline_mood() -> String:
	for r in card.get("mood_rules", []):
		var all_ok := true
		for f in r.get("if_flags", []):
			if not WorldState.has_flag(str(f)):
				all_ok = false
		if all_ok:
			return str(r.mood)
	return "warm" if rel.tier() in ["trusted", "confidant"] else "wary"


## Issue #204: the open jobs that are this character's to give ("giver" on the
## board; Oda's by default).
func my_jobs(tier: String) -> Array:
	return WorldState.open_jobs(tier).filter(gives)


## Issue #188: "giver" is one card id or a list of them (the smuggling run and the
## contract are Oda's, the fence's, Skrugs's and T-89's). A planet's own Oda
## (cantina_owner_<planet>) gives what Oda gives.
func gives(j: Dictionary) -> bool:
	var g = j.get("giver", "cantina_owner")
	for who in (g if g is Array else [g]):
		if id() == str(who) or id().begins_with(str(who) + "_"):
			return true
	return false


# ------------------------------------------------------------------ hints (issues #204, #205, #210, #211)

## The card's "hints" this line touches: { words, event, say, requires }. Each
## one the player's words match (and whose requires hold, WorldState's rules)
## reports its event to the story (an optional quest unlocks) and returns a line
## for the briefing so the character tells them. Returns those lines.
func hints_for(text: String, tier: String = "stranger") -> Array:
	var out: Array = []
	var low := text.to_lower()
	for h in card.get("hints", []):
		if not (h.get("words", []) as Array).any(func(w): return low.contains(str(w))):
			continue
		if not WorldState._conditions_hold(h.get("requires", {}), tier):
			continue
		Story.event(str(h.get("event", "")))
		out.append("TELL THEM NOW, in your own words: " + str(h.get("say", "")))
		if str(h.get("line", "")) != "":
			_hint_lines.append(str(h.line))
	return out


# ------------------------------------------------------------------ a turn

## Issue #328: the topics this character can answer without a model, in the
## menu's order: [{ id, label, say }] (say: the player's line for it). A topic
## is on the menu when the card has its canned line and the action it needs.
func topics() -> Array:
	var menu: Dictionary = _read(TOPICS_PATH)
	var c: Dictionary = card.get("canned", {})
	var can: Array = builder.actions()
	var out: Array = []
	for t in menu.get("topics", []):
		var tid := str(t.get("id", ""))
		var need := str(t.get("needs", ""))
		if need != "" and not can.has(need):
			continue
		var keys: Array = t.get("canned", [])
		if not keys.is_empty() and not keys.any(func(k): return c.has(str(k))):
			continue
		out.append({ "id": tid, "label": str(t.get("label", tid)), "say": str(t.get("say", tid)) })
	return out


## Issue #328: the player picked a topic from the menu. Same turn as say(), but
## the canned answer is that topic's, whatever the words.
func say_topic(topic: String) -> bool:
	for t in topics():
		if str(t.id) == topic:
			_topic_now = topic
			var ok := say(str(t.say))
			if not ok:
				_topic_now = ""
			return ok
	return false


## The player said something. Returns false if she is mid-answer.
func say(text: String) -> bool:
	text = text.strip_edges()
	if busy or text == "":
		return false
	busy = true
	_player_text = text
	_hostile = filter.is_hostile(text)
	if _hostile:
		insults += 1
	var tier := rel.tier()
	_hint_lines.clear()
	var rumors := WorldState.rumors(tier, rel.known_rumors, 4)
	# Issue #204: a job is the giver's ("giver" on the board, Oda's by default).
	var jobs := my_jobs(tier)
	last_hints = hints_for(text, tier)
	var world := {
		"flags": WorldState.flags, "standing": WorldState.standing, "time": WorldState.time_of_day,
		"events": WorldState.events, "credits": WorldState.credits,
		"place": _place(), "people": NameHooks.known("npc:"),
		"story": Story.brief(id()),
		"beast": PlanetBeast.brief(GameFlow.planet()),     # everyone here knows the planet's beast
		"club_moods": Sound.lib().cfg.get("club", {}).get("moods", []),   # issue #261: what she can ask the band for
		"extra": (extra_brief.call() if extra_brief.is_valid() else []) + last_hints + _recap_brief(),
		"ship_buy": _ship_offer(),
		"wares": wares.call() if wares.is_valid() else [],
	}
	var built := builder.build(world, rel, rumors, jobs, history, text)
	_messages = built.messages
	_ids = built.ids
	_raw = ""
	_shown = ""
	_barked = false
	_t0 = Time.get_ticks_msec()
	if llm == null or llm.active_chain().is_empty():
		# No model to ask (issue #328: AI characters off, or every one down): canned now.
		_finish_turn({ "ok": false, "text": "", "provider": "none", "fell_back_from": [], "error": "no llm" if llm == null else "no provider" })
		return true
	var opts := { "schema": builder.schema }
	if card.has("temperature"):
		opts["temperature"] = float(card.temperature)
	_turn_id = llm.chat(_messages, opts)
	return true


## Issue #328: the reply in flight has shown its first words.
func has_words() -> bool:
	return _shown != ""


## Call every frame while busy (the scene does): emits the thinking beat.
func tick() -> void:
	if busy and not _barked and _shown == "" and Time.get_ticks_msec() - _t0 > BARK_AFTER_MS:
		_barked = true
		thinking.emit(_pick(card.get("stall_barks", ["Mm."])))


func _on_fallback(turn_id: int, _from: String, _reason: String) -> void:
	if turn_id == _turn_id and not _barked:
		_barked = true
		thinking.emit(_pick(card.get("stall_barks", ["Mm."])))


func _on_delta(turn_id: int, text: String) -> void:
	if turn_id != _turn_id:
		return
	_raw += text
	var s := ReplyParser.say_partial(_raw)
	if filter.has_meta_talk(s):
		return                         # hold the line; the final filter replaces it
	s = filter.scrub_terms(s.replace("*", ""))
	if s != _shown:
		_shown = s
		line_delta.emit(s)


func _on_finished(turn_id: int, result: Dictionary) -> void:
	if turn_id == _summary_id:
		_summary_id = -1
		if bool(result.ok):
			for line in str(result.text).split("\n"):
				var f := filter.scrub_terms(line.strip_edges().trim_prefix("-").strip_edges())
				if f.length() > 3 and f.length() < 90 and not filter.has_meta_talk(f):
					rel.remember(f)
		return
	if turn_id != _turn_id:
		return
	_finish_turn(result)


func _finish_turn(result: Dictionary) -> void:
	_turn_id = -1
	var parsed := ReplyParser.parse(str(result.get("text", ""))) if bool(result.get("ok", false)) else { "ok": false }
	var source := "model"
	var say_text := ""
	var proposed: Array = []
	var mood := ""
	if bool(parsed.get("ok", false)):
		say_text = str(parsed.say)
		proposed = parsed.actions
		mood = str(parsed.mood)
	else:
		source = "canned"
		var c := _canned_now()
		say_text = c.say
		proposed = c.actions
	var cleaned := filter.clean(say_text, _rng.randi())
	if (cleaned.flags as Array).has("empty"):
		source = "canned"
		var c2 := _canned_now()
		cleaned = filter.clean(c2.say)
		proposed = c2.actions
	_topic_now = ""
	_recap_now = false
	if source == "canned":
		# Issue #328: the hint their words set off, in the card's authored line
		# (after the sentence cap: it is written, not generated).
		for line in _hint_lines:
			cleaned.say = (str(cleaned.say) + " " + filter.scrub_terms(str(line))).strip_edges()
	var v := ActionValidator.validate(proposed, _ids, {
		"trust": rel.trust, "trust_this_visit": rel.trust_this_visit, "hostile": _hostile, "insults": insults,
	})
	_match_job_offer(v, str(cleaned.say))
	if mood in ["wary", "warm", "amused", "irritated", "scared", "sad"]:
		rel.mood = mood
	var applied := _apply(v.kept)
	rel.turns_total += 1
	history.append({ "role": "user", "content": PromptBuilder.wrap_player(_player_text) })
	history.append({ "role": "assistant", "content": JSON.stringify({ "say": cleaned.say, "then": v.kept, "tone": rel.mood }) })
	var turn := {
		"player": _player_text, "say": cleaned.say, "mood": rel.mood, "kept": v.kept, "dropped": v.dropped,
		"applied": applied, "filter": cleaned.flags, "source": source, "repaired": parsed.get("repaired", false),
		"provider": str(result.get("provider", "")), "model": str(result.get("model", "")),
		"ms_first_token": int(result.get("ms_first_token", -1)), "ms_total": int(result.get("ms_total", 0)),
		"usage": result.get("usage", {}), "fell_back_from": result.get("fell_back_from", []),
		"stalled": bool(result.get("stalled", false)), "error": str(result.get("error", "")),
		"raw": str(result.get("text", "")), "trust": rel.trust, "tier": rel.tier(),
		"prompt": _messages,
	}
	last_turn = turn
	turns.append(turn)
	busy = false
	_log(turn)
	line_done.emit(turn)
	if applied.has("end_conversation") or applied.has("call_guards"):
		ended.emit("call_guards" if applied.has("call_guards") else "end_conversation")


## The job card matches the line. A job with "words" (bar_board.json) whose words
## the line never says, while it says another of this character's jobs' words,
## is the wrong card (the general talking droids while offering the contraband
## run): it becomes that job if it is in the briefing, else it is dropped.
func _match_job_offer(v: Dictionary, say: String) -> void:
	var low := say.to_lower()
	for a in (v.kept as Array).duplicate():
		if str(a.type) != "offer_job" or _says_job(low, WorldState.job(str(a.id))) != 0:
			continue
		var to := ""
		for id in _ids.get("jobs", []):
			if str(id) != str(a.id) and _says_job(low, WorldState.job(str(id))) == 1:
				to = str(id)
				break
		if to != "":
			v.dropped.append({ "action": a.duplicate(), "why": "line is about " + to })
			a["id"] = to
		elif WorldState.board().filter(gives).any(func(j): return str(j.id) != str(a.id) and _says_job(low, j) == 1):
			v.kept.erase(a)
			v.dropped.append({ "action": a, "why": "line is about another job" })


## 1 when the line says one of the job's "words", 0 when it says none, -1 when
## the job has none to say.
static func _says_job(low: String, j: Dictionary) -> int:
	var words: Array = j.get("words", [])
	if words.is_empty():
		return -1
	return 1 if words.any(func(w): return low.contains(str(w))) else 0


## Apply validated actions. Returns the list of action types applied.
func _apply(kept: Array) -> Array:
	var applied: Array = []
	for a in kept:
		var t := str(a.type)
		match t:
			"share_rumor":
				if not rel.known_rumors.has(str(a.id)):
					rel.known_rumors.append(str(a.id))
			"hint_secret":
				if not rel.hinted_secrets.has(str(a.id)):
					rel.hinted_secrets.append(str(a.id))
					rel.remember("you let slip " + str(a.id))
			"offer_job":
				var j := WorldState.job(str(a.id))
				if not j.is_empty():
					job_offered.emit(j)
			"trust":
				rel.trust = clampi(rel.trust + int(a.delta), 0, 100)
				if int(a.delta) > 0:
					rel.trust_this_visit += int(a.delta)
			"pour_drink":
				_pour(a)
			"offer_speeder", "offer_ship":
				sale_offered.emit({ "id": a.id, "name": a.name, "price": int(a.price) })
			"offer_item":
				item_offered.emit({ "id": a.id, "name": a.name, "price": int(a.price) })
			"offer_ship_buy":
				ship_buy_offered.emit({ "id": a.id, "name": a.name, "price": int(a.price) })
			"call_guards":
				rel.banned_until = WorldState.clock + 90.0
				rel.add_trust(-5, "threatened you in your own bar")
				WorldState.change_standing("locals", -2, "Someone got thrown out of the cantina.")
			"comrade":
				comrade_declared.emit()
			"let_go", "search", "join", "refuse":
				verdict.emit(t)
			"club_vibe":
				Sound.club_vibe(str(a.mood))
				vibe_changed.emit(str(a.mood))
			"end_conversation", "refuse_topic":
				pass
		applied.append(t)
	return applied


func _pour(a: Dictionary) -> void:
	var price := int(a.price)
	var paid := false
	if WorldState.credits >= price + rel.tab:
		WorldState.credits -= price + rel.tab
		if rel.tab > 0:
			rel.add_trust(2, "paid off their tab")
			rel.tab = 0
		paid = true
		rel.drinks_this_visit += 1
		if rel.drinks_this_visit == 1:
			rel.add_trust(1, "pays for drinks")
	else:
		rel.tab += price
		rel.remember("drinks on the tab")
	drink_poured.emit({ "id": a.id, "name": a.name, "price": price, "paid": paid, "credits": WorldState.credits, "tab": rel.tab })


## The game thanks her for jobs she gave that are now done (verified by WorldState).
func _credit_jobs() -> void:
	for id in WorldState.jobs_taken:
		if WorldState.jobs_taken[id] == "done" and not rel.credited_jobs.has(id):
			rel.credited_jobs.append(id)
			rel.add_trust(5, "finished the job " + str(WorldState.job(id).get("title", id)))


## Issue #295: the ship this character would buy right now ({} for anyone but Skrugs).
func _ship_offer() -> Dictionary:
	return ship_offer.call() if ship_offer.is_valid() else {}


## The player accepted a job she offered (from the job card).
func accept_job(id: String) -> bool:
	if not WorldState.accept_job(id):
		return false
	rel.add_trust(1, "took the job " + str(WorldState.job(id).get("title", id)))
	return true


# ------------------------------------------------------------------ offline

## This turn's canned answer: the menu topic's, else the player's words'.
func _canned_now() -> Dictionary:
	if _recap_now:
		return { "say": authored_recap(), "actions": [] }     # issue #185
	return canned_reply(_player_text, _topic_now)


## Issue #185: the briefing lines for the recap turn ([] on any other turn).
func _recap_brief() -> Array:
	if not _recap_now or recap_events.is_empty():
		return []
	var said: PackedStringArray = []
	for e in recap_events:
		said.append("- " + str(e.text))
	return ["SINCE THEY WERE LAST HERE (newest first, all true):\n" + "\n".join(said),
		str(card.get("recap", {}).get("instruction", "They just walked back in. Open with a short recap of what has happened since they were last here, in your own voice, true to the list above (at most 2 sentences), then ask what they want. Do not invent anything else."))]


## A real answer without a model: keyword topic + true data. Only topics whose
## action this character has (no job board at Skrugs's stall, no drinks).
func canned_reply(text: String, topic: String = "") -> Dictionary:
	var c: Dictionary = card.get("canned", {})
	if topic == "":
		topic = _topic(text)
	var can: Array = builder.actions()
	if can.has("offer_ship") and topic in ["buy", "recommend"]:
		return _canned_ship(text, c)
	var needs := { "smuggle": "offer_job", "job": "offer_job", "drink": "pour_drink", "buy": "offer_speeder", "rumor": "share_rumor",
		"vibe": "club_vibe" }
	if needs.has(topic) and not can.has(needs[topic]):
		topic = ""
	if topic == "sell_ship" and not can.has("offer_ship_buy"):
		topic = ""
	match topic:
		"sell_ship":
			var o := _ship_offer()
			if o.is_empty():
				return { "say": _pick(c.get("no_ship_buy", ["Bring it round first."])), "actions": [] }
			return { "say": _pick(c.get("ship_buy", ["%s? %d credits."])) % [str(o.name), int(o.price)],
				"actions": [{ "type": "offer_ship_buy", "id": o.id }] }
		"rumor":
			var rs := WorldState.rumors(rel.tier(), rel.known_rumors, 1)
			if rs.is_empty():
				return { "say": _pick(c.get("no_rumor", ["Quiet week."])), "actions": [] }
			return { "say": _pick(c.get("rumor", ["%s"])) % str(rs[0].text), "actions": [{ "type": "share_rumor", "id": rs[0].id }] }
		"smuggle":
			var sj := my_jobs(rel.tier()).filter(func(j): return str(j.get("kind", "")) == "smuggle")
			if sj.is_empty():
				return { "say": _pick(c.get("no_smuggle", ["Nothing lined up."])), "actions": [] }
			return { "say": _pick(c.get("job", ["%s"])) % str(sj[0].text), "actions": [{ "type": "offer_job", "id": sj[0].id }] }
		"job":
			var js := my_jobs(rel.tier())
			if js.is_empty():
				return { "say": _pick(c.get("no_job", ["Nothing."])), "actions": [] }
			var asked := js.filter(func(j): return _says_job(text.to_lower(), j) == 1)      # "any droid work?"
			var jb: Dictionary = asked[0] if not asked.is_empty() else js[0]
			return { "say": _pick(c.get("job", ["%s"])) % str(jb.text), "actions": [{ "type": "offer_job", "id": jb.id }] }
		"war":
			return { "say": _pick(c.get("war", ["Both sides drink here."])), "actions": [] }
		"drink":
			return { "say": "Dust ale. You look like a dust ale.", "actions": [{ "type": "pour_drink", "name": "dust ale" }] }
		"buy":
			return { "say": _pick(c.get("sell", ["Yours for the price on the board."])), "actions": [{ "type": "offer_speeder" }] }
		"bye":
			return { "say": _pick(c.get("bye", ["Go on."])), "actions": [{ "type": "end_conversation" }] }
		"vibe":
			var mood := vibe_mood(text)
			return { "say": _pick(c.get("vibe", ["Something %s, coming up."])) % mood, "actions": [{ "type": "club_vibe", "mood": mood }] }
	return { "say": _pick(c.get("default", ["Hold on."])), "actions": [] }


func _topic(text: String) -> String:
	var low := text.to_lower()
	var tw: Dictionary = card.get("topic_words", {})
	for topic in ["bye", "vibe", "recommend", "sell_ship", "buy", "smuggle", "job", "rumor", "drink", "war"]:
		for w in tw.get(topic, []):
			if low.contains(str(w)):
				return topic
	return ""


## Issue #261: the club mood a music request asks for (the card's "vibe_words":
## mood -> words), else the card's first listed mood.
func vibe_mood(text: String) -> String:
	var low := text.to_lower()
	var vw: Dictionary = card.get("vibe_words", {})
	for mood in vw:
		for w in vw[mood]:
			if low.contains(str(w)):
				return str(mood)
	return str(vw.keys()[0]) if not vw.is_empty() else "chill"


## T-89 offline: the ship whose "good_for" words they used (else the dearest they
## can afford, else the cheapest), and if it is out of their reach, the best one
## that is not. Real ships, real prices.
func _canned_ship(text: String, c: Dictionary) -> Dictionary:
	var ships: Array = card.get("ships", [])
	if ships.is_empty():
		return { "say": _pick(c.get("default", ["Hold on."])), "actions": [] }
	var low := text.to_lower()
	var credits := WorldState.credits
	var want: Dictionary = {}
	for sh in ships:
		for w in sh.get("good_for", []):
			if low.contains(str(w)):
				want = sh
				break
		if not want.is_empty():
			break
	var best_ok: Dictionary = {}
	for sh in ships:
		if int(sh.price) <= credits and (best_ok.is_empty() or int(sh.price) > int(best_ok.price)):
			best_ok = sh
	if want.is_empty():
		want = best_ok if not best_ok.is_empty() else ships[0]
	if int(want.price) <= credits or best_ok.is_empty():
		return { "say": _pick(c.get("recommend", ["The %s. %d credits."])) % [want.name, int(want.price)],
			"actions": [{ "type": "offer_ship", "id": want.id }] }
	var line := _pick(c.get("recommend_short", ["The {want} is the one for you, but the {can} is what you can fly today."]))
	return { "say": line.format({ "want": want.name, "want_price": int(want.price), "can": best_ok.name,
			"can_price": int(best_ok.price), "credits": credits }),
		"actions": [{ "type": "offer_ship", "id": best_ok.id }] }


func _pick(arr: Array) -> String:
	if arr.is_empty():
		return ""
	return str(arr[_rng.randi() % arr.size()])


# ------------------------------------------------------------------ transcripts

func _log(turn: Dictionary) -> void:
	if not log_transcripts:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(log_dir))
	var path := log_dir + "/" + Time.get_date_string_from_system() + ".jsonl"
	var f := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	var row := turn.duplicate()
	row.erase("prompt")
	row["prompt_hash"] = str(JSON.stringify(_messages).hash())
	row["time"] = Time.get_datetime_string_from_system()
	f.store_line(JSON.stringify(row))


static func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## Issue #15: the town and planet she works in, by name. The world is the one the
## briefing names ("world" in world_briefing.json); generated once, saved, the same
## names the place card and the flight HUD show.
func _place() -> Dictionary:
	if _world_cache.is_empty():
		# Issue #45: the planet the player is on (its world names the town and the
		# planet); the briefing's own "world" only when no planet is current.
		_world_cache = GameFlow.planet().get("world", {})
		if _world_cache.is_empty():
			var cc := CoreContent.new()
			cc.load_from()
			_world_cache = cc.get_world(str(builder.world_text.get("world", "")))
	if _world_cache.is_empty():
		return {}
	return { "town": NameHooks.town(_world_cache), "planet": NameHooks.planet(_world_cache) }