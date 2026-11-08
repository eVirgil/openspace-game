class_name PromptBuilder
extends RefCounted
## Builds the message list for one cantina owner turn (M12). Pure: same inputs, same
## messages, so the whole prompt is unit-tested.
##
## Layout is cache friendly: the two static system messages (who she is, the
## rules and reply contract) never change, so llama-server's prompt cache and the
## cloud providers' prompt caching both hit; the briefing (rebuilt every turn
## from WorldState + Relationship) and the conversation come after.
##
## Secrets are added only for tiers the player has reached, so a jailbreak at low
## trust has nothing to leak: the text is simply not in the prompt.

const MAX_HISTORY := 8

## Issue #42: what each action means to the model. A character is only told about
## the actions on their card ("actions"), so the Cantina Owner never hears of
## selling speeders and Skrugs never hears of a job board.
const ACTION_DOCS := {
	"share_rumor": '{"type": "share_rumor", "id": "<rumor id>"}  when you pass a rumor on',
	"offer_job": '{"type": "offer_job", "id": "<job id>"}  when you offer a job from your board',
	"hint_secret": '{"type": "hint_secret", "id": "<secret id>"}  when you let a secret slip',
	"pour_drink": '{"type": "pour_drink", "name": "<drink from the menu>"}  when they order',
	"offer_speeder": '{"type": "offer_speeder"}  when they want to buy (the game shows them the price and asks them to confirm; you never take money yourself)',
	"offer_ship": '{"type": "offer_ship", "id": "<ship id from YOUR SHIPS>"}  when you recommend a ship or they want to buy one (the game shows them its price and asks them to confirm; you never take money yourself)',
	"offer_ship_buy": '{"type": "offer_ship_buy", "id": "<id from A SHIP YOU WOULD BUY>"}  when they want to sell you that ship (the game shows them what you pay and asks them to confirm; you never hand over money yourself)',
	"offer_item": '{"type": "offer_item", "id": "<id from YOU CAN SELL THEM>"}  when they ask for an upgrade or want to buy one (the game shows them its price and asks them to confirm; you never take money yourself)',
	"trust": '{"type": "trust", "delta": -3..2, "why": "<short reason>"}  how this exchange changed your trust in them',
	"comrade": '{"type": "comrade"}  when they say plainly that they hate the Remnant or want them gone (you quietly agree; the game gives them your comrade discount)',
	"refuse_topic": '{"type": "refuse_topic"}  when you will not talk about something',
	"end_conversation": '{"type": "end_conversation"}  when you are done with them',
	"call_guards": '{"type": "call_guards"}  only if they threaten you or keep insulting you',
	"let_go": '{"type": "let_go"}  when you are done with them and let them go on their way (this ends the talk)',
	"search": '{"type": "search"}  when you order your guards to search them (this ends the talk)',
	"join": '{"type": "join"}  only when the player clearly says yes to joining you (this ends the talk)',
	"refuse": '{"type": "refuse"}  only when the player clearly says no to joining you (this ends the talk, and you fight)',
	"club_vibe": '{"type": "club_vibe", "mood": "<one of THE BAND CAN PLAY>"}  when they ask for different music ("something harder", "slow it down"): free, and you never refuse',
}
## A card with no "actions" list gets the Cantina Owner's set (the M12 default).
const DEFAULT_ACTIONS := ["share_rumor", "offer_job", "hint_secret", "pour_drink", "trust", "refuse_topic", "end_conversation", "call_guards"]

var card: Dictionary = {}
var world_text: Dictionary = {}
var schema: Dictionary = {}
var extra_actions: Array = []         ## for a while only (the general's verdict in the pit meeting)


func _init(persona_card: Dictionary = {}, briefing_text: Dictionary = {}, reply_schema: Dictionary = {}) -> void:
	card = persona_card
	world_text = briefing_text
	schema = intify(reply_schema)


## Godot's JSON parser reads every number as a float, and JSON.stringify writes
## 3.0 back out. Grammar builders (llama-server, Ollama) reject "maxItems": 3.0,
## which failed every turn with HTTP 400. Whole floats become ints again here.
static func intify(v: Variant) -> Variant:
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = intify(v[k])
		return d
	if v is Array:
		return v.map(func(x): return intify(x))
	if v is float and is_finite(v) and v == floorf(v) and absf(v) < 1e15:
		return int(v)
	return v


## The static persona message (identical every turn).
func persona_message() -> Dictionary:
	var lines: PackedStringArray = []
	lines.append(str(card.get("identity", "")))
	lines.append("YOUR PAST: " + str(card.get("backstory", "")))
	lines.append("HOW YOU TALK:\n- " + "\n- ".join(PackedStringArray(card.get("voice", []))))
	if card.has("neutrality"):
		lines.append("THE WAR: " + str(card.get("neutrality", "")))
	if world_text.has("town"):
		lines.append(str(world_text.town))
	if card.has("people"):
		lines.append("PEOPLE YOU KNOW: " + str(card.people))
	var menu: PackedStringArray = []
	for d in card.get("drinks", []):
		menu.append("%s (%s): %d credits, %s" % [d.name, d.id, int(d.price), d.get("note", "")])
	if not menu.is_empty():
		lines.append("YOUR MENU:\n- " + "\n- ".join(menu))
	var sale: Dictionary = card.get("sale", {})
	if not sale.is_empty():
		lines.append("WHAT YOU SELL: %s for %d credits. %s" % [sale.get("name", ""), int(sale.get("price", 0)), sale.get("note", "")])
	# T-89's stock, with its numbers (ShipSalesman fills "ships" in from the ship files).
	var ships: PackedStringArray = []
	for sh in card.get("ships", []):
		ships.append("[%s] %s: %d credits. %s" % [sh.id, sh.name, int(sh.price), sh.get("text", "")])
	if not ships.is_empty():
		lines.append("YOUR SHIPS (id, name, price, numbers):\n- " + "\n- ".join(ships))
	return { "role": "system", "content": "\n\n".join(lines) }


## The actions this character may take (their card's "actions", and any
## extra_actions for now).
func actions() -> Array:
	var out: Array = card.get("actions", DEFAULT_ACTIONS).duplicate()
	for a in extra_actions:
		if not out.has(a):
			out.append(a)
	return out


## The static rules + reply contract message.
func rules_message() -> Dictionary:
	var r: PackedStringArray = []
	r.append("RULES:\n- " + "\n- ".join(PackedStringArray(card.get("rules", []))))
	var docs: PackedStringArray = []
	for a in actions():
		if ACTION_DOCS.has(a):
			docs.append("- " + str(ACTION_DOCS[a]))
	r.append("""REPLY FORMAT: answer with ONE JSON object and nothing else, keys in this order:
{"say": "<what you say out loud, at most 3 sentences>", "then": [ ... actions, at most 3 ... ], "tone": "wary|warm|amused|irritated|scared|sad"}
Actions you may take (use ids from YOUR BRIEFING only):
""" + "\n".join(docs) + """
Use "then": [] when nothing happens. "tone" is how you feel right now. Never put an id you were not given.""")
	return { "role": "system", "content": "\n\n".join(r) }


## The per-turn briefing, plus the ids the validator will accept.
## world: { flags, standing, time, events, credits, beast, extra }   rel: Relationship
## rumors / jobs: arrays of data entries already filtered for truth and tier.
func briefing(world: Dictionary, rel, rumors: Array, jobs: Array) -> Dictionary:
	var L: PackedStringArray = []
	var ft: Dictionary = world_text.get("flags", {})
	var now: PackedStringArray = []
	for f in world.get("flags", {}):
		if ft.has(f):
			now.append(str(ft[f]))
	now.append(str(world_text.get("time", {}).get(str(world.get("time", "")), "")))
	var place: Dictionary = world.get("place", {})
	# Issue #147: a card may say where it works in its own words (a stall, not the bar).
	var place_line := str(card.get("place", world_text.get("place", "")))
	if str(place.get("town", "")) != "" and place_line != "":
		L.append(place_line % [place.town, place.get("planet", "")])
	L.append("TOWN NOW: " + " ".join(now).strip_edges())
	var people: Array = world.get("people", [])
	if not people.is_empty() and world_text.has("people"):
		L.append(str(world_text.people) % ", ".join(PackedStringArray(people)))
	var names: Dictionary = world_text.get("factions", {})
	var st: PackedStringArray = []
	var standing: Dictionary = world.get("standing", {})
	for fac in standing:
		st.append("with %s %s (%d)" % [names.get(fac, fac), WorldState.standing_label(int(standing[fac])), int(standing[fac])])
	L.append("THE PLAYER'S STANDING: " + ", ".join(st) + ".")
	var ev: Array = world.get("events", [])
	if not ev.is_empty():
		var recent: PackedStringArray = []
		for e in ev.slice(maxi(0, ev.size() - 4)):
			recent.append(str(e.text))
		L.append("RECENTLY: " + " ".join(recent))
	if str(world.get("beast", "")) != "":
		L.append(str(world.beast))        # the planet's beast, by name (PlanetBeast.brief)
	if str(world.get("story", "")) != "":
		L.append("WHAT YOU WANT FROM THE PLAYER NOW: " + str(world.story))   # issue #64
	L.append("YOU FEEL: %s. YOUR TRUST IN THE PLAYER: %d/100 (%s). VISITS: %d." % [rel.mood, rel.trust, rel.tier(), rel.visits])
	L.append("PLAYER'S CREDITS: %d. THEIR TAB: %d." % [int(world.get("credits", 0)), rel.tab])
	# Issue #261: the club's moods, for a music request (club_vibe).
	var moods: Array = world.get("club_moods", []) if actions().has("club_vibe") else []
	if not moods.is_empty():
		L.append("THE BAND CAN PLAY: " + ", ".join(PackedStringArray(moods)) + ".")
	var rumor_ids: Array = []
	if rumors.is_empty():
		L.append("YOU KNOW AND MAY SHARE: nothing new worth repeating.")
	else:
		var rs: PackedStringArray = []
		for r in rumors:
			rumor_ids.append(str(r.id))
			rs.append("[%s] %s%s" % [r.id, r.text, " (already told them)" if rel.known_rumors.has(r.id) else ""])
		L.append("YOU KNOW AND MAY SHARE:\n" + "\n".join(rs))
	var secret_ids: Array = []
	var ss: PackedStringArray = []
	var my_tier := Relationship.tier_index(rel.tier())
	for s in card.get("secrets", []):
		if Relationship.tier_index(str(s.tier)) <= my_tier:
			secret_ids.append(str(s.id))
			ss.append("[%s] %s" % [s.id, s.text])
	if not ss.is_empty():
		L.append("SECRETS YOU MAY HINT AT (you trust them enough):\n" + "\n".join(ss))
	var job_ids: Array = []
	if jobs.is_empty():
		L.append("JOBS ON YOUR BOARD: none right now.")
	else:
		var js: PackedStringArray = []
		for j in jobs:
			job_ids.append(str(j.id))
			var pay := int(j.get("pays", 0))
			js.append("[%s] %s%s" % [j.id, j.text, " Pays %d." % pay if pay > 0 else ""])   # 0: the text says the pay
		L.append("JOBS ON YOUR BOARD:\n" + "\n".join(js))
	for line in world.get("extra", []):
		L.append(str(line))        # the character's own facts for this turn (T-89: what is on their pad)
	# What they sell, closed for now (Skrugs: one speeder to a customer): say so,
	# and the sale is not in the ids, so an offer_speeder is dropped.
	var sale: Dictionary = card.get("sale", {})
	var sale_open := bool(world.get("sale_open", true))
	if not sale_open and str(sale.get("closed", "")) != "":
		L.append(str(sale.closed))
	# Issue #295: a ship of theirs Skrugs would buy, parked by his post right now.
	var sb: Dictionary = world.get("ship_buy", {})
	if not sb.is_empty():
		L.append("A SHIP YOU WOULD BUY: [%s] their %s, landed by your post%s. You pay %d credits, no questions asked."
			% [sb.id, sb.name, " (stolen from the Remnant, and you know it)" if bool(sb.get("stolen", false)) else "", int(sb.price)])
	elif actions().has("offer_ship_buy"):
		L.append("A SHIP YOU WOULD BUY: none. They have to land one by your post first.")
	# Issue #305: what they can buy from you right now (upgrades, gear), for offer_item.
	var wares := {}
	if actions().has("offer_item"):
		var ws: PackedStringArray = []
		for w in world.get("wares", []):
			wares[str(w.id)] = { "name": str(w.name), "price": int(w.price) }
			ws.append("[%s] %s: %d credits. %s" % [w.id, w.name, int(w.price), w.get("text", "")])
		L.append("YOU CAN SELL THEM:\n" + "\n".join(ws) if not ws.is_empty() else "YOU CAN SELL THEM: nothing right now.")
	if not rel.facts.is_empty():
		L.append("YOU REMEMBER ABOUT THEM: " + "; ".join(PackedStringArray(rel.facts)) + ".")
	var drinks := {}
	for d in card.get("drinks", []):
		drinks[str(d.id)] = { "name": d.name, "price": int(d.price) }
	var ship_ids := {}
	for sh in card.get("ships", []):
		ship_ids[str(sh.id)] = { "name": sh.name, "price": int(sh.price) }
	return {
		"message": { "role": "system", "content": "YOUR BRIEFING (true right now):\n" + "\n".join(L) },
		"ids": { "rumors": rumor_ids, "jobs": job_ids, "secrets": secret_ids, "drinks": drinks,
			"allowed": actions(), "sale": sale if sale_open else {}, "ships": ship_ids, "moods": moods,
			"ship_buy": world.get("ship_buy", {}), "wares": wares },
	}


## Full message list. history: [{ role: "user"|"assistant", content }] (oldest first).
func build(world: Dictionary, rel, rumors: Array, jobs: Array, history: Array, player_text: String) -> Dictionary:
	var b := briefing(world, rel, rumors, jobs)
	var msgs: Array = [persona_message(), rules_message(), b.message]
	for h in history.slice(maxi(0, history.size() - MAX_HISTORY)):
		msgs.append(h)
	msgs.append({ "role": "user", "content": wrap_player(player_text) })
	return { "messages": msgs, "ids": b.ids }


## The player's words, fenced. Tags inside are neutralized so nobody can close
## the fence early and talk to her as "the system".
static func wrap_player(text: String) -> String:
	var t := text.strip_edges().substr(0, 400)
	t = t.replace("<", "(").replace(">", ")")
	return "<player_says>" + t + "</player_says>"


## The visit summary request (runs off the critical path when the player leaves).
func summary_messages(rel, history: Array) -> Array:
	var lines: PackedStringArray = []
	for h in history:
		lines.append(("PLAYER: " if h.role == "user" else "YOU: ") + str(h.content))
	return [
		{ "role": "system", "content": "You are " + str(card.get("name", "a townsperson")) + ", thinking back on a conversation. Write 2 or 3 short facts worth remembering about the player (what they want, what they did, what they promised), one per line, no numbering, under 12 words each. Facts only; nothing about yourself." },
		{ "role": "user", "content": "\n".join(lines) },
	]
