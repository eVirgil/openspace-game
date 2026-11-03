class_name ShipSalesman
extends Node3D
## T-89, the ship salesman in the pit (issue #58). A droid on the assassin droid's
## frame that never fights:
##   - nothing hurts him: his body is solid (you walk round him, bolts stop on
##     him) but nothing on him takes damage,
##   - the first time you play he says hello and offers the tutorial: the
##     controls and how things work, a page at a time. The player already spawns
##     armed; he only explains the weapons. Every game after that (the save says he
##     has met you) he only calls out one of his "returning" lines,
##   - [E] beside him opens his menu: Talk, "Buy or sell a ship", "Upgrade your
##     ships" and the tutorial again (and the rebuild while your wreck waits). The
##     two shops are submenus (Back returns). He sells every ship in
##     content/core/ships that flies in the atmosphere. A bought ship lands on the spare pad and is yours to fly
##     like any other parked ship (ShipPilot.add_berth); one at a time, and he buys
##     it back at resale_rate. WorldState.hangar keeps it across saves.
##   - when the town has a conversation host, he is an AI character too (his card,
##     content/core/npcs/t89_card.json): "Talk" in his shop opens the chat box. His
##     prompt carries every ship's price and numbers, so he can recommend one, and
##     his offer_ship puts its price card in front of you; Buy is the shop's buy().
##   - issue #206: in a story save the ship you landed in is a wreck on the pit pad.
##     He quotes the rebuild whenever you talk (the "Rebuild your ship" quest) and
##     rebuild() makes it yours to fly. Tell him you can't stand the Remnant (his
##     menu, or his comrade action in the chat) and it costs 1 credit. His menu's
##     way works with AI characters off: he tells his story and asks what you
##     think; "Down with the Tyrants!" makes you a comrade, siding with the
##     Remnant does not, and you can ask him again.
## Words, prices and his spot: content/core/npcs/t89.json. Looks: DroidKit.
##
## The headless test calls greet(), talk(), buy(), sell() and the menu's choose()
## directly: the same code paths as the keys. A headless run never greets on its own.

const CFG_PATH := "res://content/core/npcs/t89.json"
const CARD_PATH := "res://content/core/npcs/t89_card.json"
const PIT_RIM_Y := -0.5              ## above this you are up out of the pit (the street is 0)
const MET_FLAG := "met_t89"          ## saved: he has said his first hello to this player
const CoreContent := preload("res://src/systems/dataload/core_content.gd")

static var greeted := false          ## the hello happens once per run of the game
static var _cfg_cache: Dictionary = {}

var demo                             ## the town scene (town, decor, pilot, bar)
var player: CharacterBody3D
var gear: GearController             ## for its HUD (prompt, toast) and its focus (E is shared)
var cfg: Dictionary = {}
var labels: Dictionary = {}
var lines: Dictionary = {}
var content
var menu: DroidMenu
var body: StaticBody3D               ## T-89 himself
var pos := Vector3.INF
var in_reach := false
var page := -1                       ## the tutorial page showing, -1 = none
var card: TutorialCard               ## the tutorial's page: a small card you walk about under
var pit_rect := Rect2()              ## the sunken floor he stands on (x, z); empty = no pit found
var story_page := -1                 ## his Remnant story's page showing, -1 = none
var bought_ship: Node3D              ## your ship on the spare pad (model, or a stand-in in the greybox)
var said := ""                       ## his last line, for tests
var host: ConversationHost           ## the town's AI characters' host (null: shop only)
var spot: TalkSpot                   ## him, as one of them
var _offered: Dictionary = {}        ## the ship on the chat box's price card
var _greet_left := -1.0
var _was_locked := false


func setup(p_demo, p_player: CharacterBody3D, p_gear: GearController) -> void:
	demo = p_demo
	player = p_player
	gear = p_gear


func _ready() -> void:
	name = "ShipSalesman"
	var f := FileAccess.open(CFG_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	cfg = d if d is Dictionary else {}
	labels = cfg.get("labels", {})
	lines = cfg.get("lines", {})
	content = CoreContent.new()
	content.load_from()
	menu = DroidMenu.new()
	add_child(menu)
	menu.option_selected.connect(_on_option_selected)
	card = TutorialCard.new()
	add_child(card)
	card.next_pressed.connect(advance_tutorial)
	card.end_pressed.connect(skip_tutorial)
	_build_body()
	park_owned()
	if not greeted and DisplayServer.get_name() != "headless":
		_greet_left = float(cfg.get("greet_delay", 1.5))


func npc_name() -> String:
	return str(cfg.get("name", "T-89"))


func _l(key: String) -> String:
	return str(labels.get(key, key))


func _line(key: String) -> String:
	return str(lines.get(key, key))


# ------------------------------------------------------------------ body

## Where the marker says, facing its "face" point. The look is the assassin
## droid's, in his own colours; the collider is a cylinder round all of him (his
## height, wide enough for his shoulders and hanging arm, whichever way he turns)
## on the default layer, so the player walks round him and bolts stop on him.
func _build_body() -> void:
	var town = demo.town if demo != null and "town" in demo else null
	var mk := str(cfg.get("marker", "t89"))
	if town == null or town.get_marker(mk).is_empty():
		push_warning("ShipSalesman: no marker " + mk)
		return
	pos = town.marker_pos(mk)
	pit_rect = _pit_under(town, pos)
	body = StaticBody3D.new()
	body.name = "T89"
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.height = height()
	cyl.radius = 0.5
	cs.shape = cyl
	cs.position = Vector3(0, cyl.height * 0.5, 0)
	body.add_child(cs)
	var look_cfg: Dictionary = cfg.get("look", {})
	var mats: LookMaterials = demo._flat_mats() if demo.has_method("_flat_mats") else LookMaterials.new()
	var look := DroidKit.build(str(look_cfg.get("kind", "assassin")), look_cfg, mats, model_look(look_cfg))
	_disarm(look)
	body.add_child(look)
	DroidKit.set_awake(look, true)
	add_child(body)
	body.global_position = pos
	var m: Dictionary = town.get_marker(mk)
	if m.has("face"):
		_face(Vector3(float(m.face[0]), float(m.face[1]), float(m.face[2])) - pos)


## The pit he stands in: the sunken floor box under his marker (x, z), or an empty
## rect when the town has none (the tutorial then lets go at "tutorial_leash" metres).
static func _pit_under(town, at: Vector3) -> Rect2:
	for b in town.boxes():
		if str(b.kind) != "floor" or float(b.max[1]) >= -0.1:
			continue
		var r := Rect2(float(b.min[0]), float(b.min[2]), float(b.max[0]) - float(b.min[0]), float(b.max[2]) - float(b.min[2]))
		if r.has_point(Vector2(at.x, at.z)):
			return r
	return Rect2()


## Still in the pit: on its floor or up its ramps, not yet over the rim.
func in_pit(p: Vector3) -> bool:
	if pit_rect.has_area():
		return pit_rect.has_point(Vector2(p.x, p.z)) and p.y < PIT_RIM_Y
	return _flat_dist(p, pos) <= float(cfg.get("tutorial_leash", 32.0))


## How tall he stands: his kind's height (the assassin frame's 2.3 m).
func height() -> float:
	return float(DroidRoster.kind_cfg(str(cfg.get("look", {}).get("kind", "assassin"))).get("height", 2.3))


## Issue #25: his kind's model (the rigged assassin), with nothing in his hand and
## the relaxed idle ("calm") instead of the ready stance.
static func model_look(look_cfg: Dictionary) -> Dictionary:
	var m: Dictionary = DroidRoster.kind_cfg(str(look_cfg.get("kind", "assassin"))).get("look", {}).duplicate(true)
	m.erase("carry")
	var anims: Dictionary = m.get("anims", {})
	if anims.has("calm"):
		anims["idle"] = anims["calm"]
	return m


## No pistol: the assassin frame's gun arm keeps only its arm, and lets it hang.
## (The primitive frame only; the model carries nothing for him.)
static func _disarm(look: Node3D) -> void:
	var arm := look.find_child("GunArm", true, false) as Node3D
	if arm == null:
		return
	for i in range(arm.get_child_count() - 1, 0, -1):
		var c := arm.get_child(i)
		arm.remove_child(c)
		c.free()
	arm.name = "Arm"
	arm.rotation.x = -PI * 0.45


## The look faces -Z.
func _face(dir: Vector3) -> void:
	if body != null and Vector2(dir.x, dir.z).length() > 0.01:
		body.rotation.y = atan2(-dir.x, -dir.z)


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	if player == null or body == null:
		return
	if _greet_left >= 0.0:
		_greet_left -= dt
		if _greet_left < 0.0:
			if WorldState.story_mode():
				_greet_left = -1.0        # the story's waypoint after the general: you walk over and [E]
			elif _busy():
				_greet_left = 0.25        # wait until nothing else has the player
			else:
				greet()
	if _flat_dist(player.global_position, pos) < 10.0:
		var to := player.global_position - pos
		var want := atan2(-to.x, -to.z)
		body.rotation.y = lerp_angle(body.rotation.y, want, minf(1.0, dt * 4.0))
	_tick_focus()
	_tick_tutorial()


## The tutorial runs while you walk about the pit. It ends when you leave the pit,
## or when something else takes you: his menu, a talk, a ship, the general.
func _tick_tutorial() -> void:
	if page < 0:
		return
	if _busy():
		end_tutorial("busy")
	elif not in_pit(player.global_position):
		end_tutorial("left")


## Something else has the player: flying, a menu, a conversation, the general
## (his pit meeting, and a moment after it: his last word is his).
func _busy() -> bool:
	if player.piloting or player.locked or menu.is_open():
		return true
	var g = demo.get("general_post") if demo != null else null
	if g != null and is_instance_valid(g) and g.holding():
		return true
	return demo != null and demo.bar != null and demo.bar.is_talking()


func _tick_focus() -> void:
	if menu.is_open() or (host != null and host.is_talking()):
		return
	if _was_locked:
		player.locked = false
		_was_locked = false
	var p := player.global_position
	in_reach = not player.piloting and _flat_dist(p, pos) <= float(cfg.get("reach", 3.2)) \
		and absf(p.y - pos.y) <= 2.0 and (gear == null or gear.focus.is_empty())
	if not in_reach:
		return
	if gear != null and gear.hud != null:
		gear.hud.set_prompt(_l("talk") % npc_name())
	if not player.locked and InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
		talk()


# ------------------------------------------------------------------ talk

## The hello at startup, and the offer of the tutorial. A player he has met
## before (the save's MET_FLAG) gets one of his returning lines instead, called
## out across the pit: no menu, nothing in their way.
func greet() -> void:
	greeted = true
	_greet_left = -1.0
	_beep()
	if WorldState.has_flag(MET_FLAG):
		_say(returning_line())
		return
	WorldState.set_flag(MET_FLAG)
	_open(str(cfg.get("greeting", "")) + _repair_line() + _story_line() + "\n\n" + str(cfg.get("offer_tutorial", "")),
		[{ "id": "yes", "text": _l("yes_tutorial") }, { "id": "no", "text": _l("no_tutorial") }], _on_offer)


func returning_line() -> String:
	var all: Array = cfg.get("returning", [])
	return str(all[randi() % all.size()]) if not all.is_empty() else _line("hello_again")


func _on_offer(id: String) -> void:
	if id == "yes":
		start_tutorial()
	else:
		_say(_line("skipped"))


## [E] beside him: the chat box (issue #305: talk first; his shops are on its
## keyword row), or his top menu with no conversation host. In the story he never
## calls out first, so the first [E] is his hello and the tutorial offer.
func talk() -> void:
	if not greeted and not WorldState.has_flag(MET_FLAG):
		greet()
		return
	if spot != null and chat():
		return
	_beep()
	_open(_line("hello_again") + _repair_line() + _story_line(), top_options(), _on_top)


## Issue #64: while the story starts with him, he sends you to Oda.
func _story_line() -> String:
	var b := Story.beat("t89")
	return " " + str(b.say) if not b.is_empty() else ""


## Issue #206: the rebuild's price, while your wreck waits (the quest goes in the log).
func _repair_line() -> String:
	if not needs_rebuild():
		return ""
	Story.event("repair_quoted")
	var comrade := WorldState.has_flag(WorldState.COMRADE)
	return " " + _line("repair_quote_comrade" if comrade else "repair_quote") % rebuild_price()


func _open(text: String, opts: Array, pick: Callable) -> void:
	end_tutorial("busy")     # his menu has you now
	said = text
	menu.open(_l("menu_title") % [npc_name(), WorldState.credits], opts, pick, text)
	if body != null:
		NpcVoice.speak(text, NpcVoice.profile_for_npc("t89", {}), "calm", body)
	if player != null and not player.locked:
		player.locked = true
		_was_locked = true


func _say(text: String) -> void:
	said = text
	if gear != null and gear.hud != null and text != "":
		gear.hud.toast("%s: %s" % [npc_name(), text], 4.5)
	if body != null:
		NpcVoice.speak(text, NpcVoice.profile_for_npc("t89", {}), "calm", body)


func _on_option_selected(_id: String) -> void:
	if body != null:
		NpcVoice.stop(body)


# ------------------------------------------------------------------ tutorial

func tutorial_pages() -> Array:
	return cfg.get("tutorial", [])


func start_tutorial() -> void:
	page = 0
	_show_page()


## One page on the small card. Nothing is locked: you can walk the pit while it
## is up, and try what it says.
func _show_page() -> void:
	var pages := tutorial_pages()
	if page < 0 or page >= pages.size():
		page = -1
		return
	var last := page == pages.size() - 1
	said = str(pages[page])
	var keys := "[Enter]  %s" % _l("done" if last else "next")
	if not last:
		keys += "\n[Backspace]  %s" % _l("skip")
	card.show_page("%s   (%d/%d)" % [npc_name(), page + 1, pages.size()], said, keys)
	if body != null:
		NpcVoice.stop(body)
		NpcVoice.speak(said, NpcVoice.profile_for_npc("t89", {}), "calm", body)


## Enter: the next page, or the end of the last one.
func advance_tutorial() -> void:
	if page < 0:
		return
	if page >= tutorial_pages().size() - 1:
		end_tutorial("done")
	else:
		page += 1
		_show_page()


## Backspace: skip the rest.
func skip_tutorial() -> void:
	end_tutorial("skip")


## Put the card away. why: "done" (thanked him), "skip" (backspace), "left" (out of
## the pit), "busy" (something else has you: no word from him).
func end_tutorial(why: String) -> void:
	if page < 0:
		return
	page = -1
	card.close()
	if why == "skip":
		_say(_line("skipped"))
	elif why == "left":
		_say(_line("tutorial_left"))
	elif body != null and why != "done":
		NpcVoice.stop(body)


# ------------------------------------------------------------------ shop

## Every ship that flies in the atmosphere and has a model, cheapest first.
func stock() -> Array:
	var out := []
	for id in content.ships:
		var s: Dictionary = content.ships[id]
		if s.has("atmosphere") and str(s.get("look", "")) != "":
			out.append(str(id))
	out.sort_custom(func(a, b): return price(a) < price(b) or (price(a) == price(b) and a < b))
	return out


func price(ship_id: String) -> int:
	return _price_in(cfg, ship_id)


func resale(ship_id: String) -> int:
	return _resale_in(cfg, ship_id)


## Issue #295: his prices without him (Skrugs pays by them too): from t89.json.
static func config() -> Dictionary:
	if _cfg_cache.is_empty():
		var f := FileAccess.open(CFG_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_cfg_cache = d if d is Dictionary else {}
	return _cfg_cache


static func list_price(ship_id: String) -> int:
	return _price_in(config(), ship_id)


static func resale_price(ship_id: String) -> int:
	return _resale_in(config(), ship_id)


static func _price_in(c: Dictionary, ship_id: String) -> int:
	return int(c.get("prices", {}).get(ship_id, c.get("default_price", 1500)))


static func _resale_in(c: Dictionary, ship_id: String) -> int:
	return int(round(_price_in(c, ship_id) * float(c.get("resale_rate", 0.6))))


## Issue #295: the ship he sold you is sold on (back to him, or to Skrugs): paid,
## his pad free again, its upgrades gone with it (issue #207). The one place both
## sales settle, so they never drift apart.
static func settle_sale(ship_id: String, paid: int) -> void:
	WorldState.credits += paid
	if WorldState.hangar == ship_id:
		Fleet.lose(Fleet.T89)              # issue #368: and where it was left, and the primary mark
	if not ShipUpgrades.owned().has(ship_id):
		WorldState.ship_fits.erase(ship_id)


func ship_label(ship_id: String) -> String:
	return str(content.get_ship(ship_id).get("label", ship_id))


## His top menu: a chat (when he has a brain), the rebuild while your wreck waits,
## the two shops (submenus) and the tutorial again. Upgrades only once you own a ship.
func top_options() -> Array:
	var out := []
	if spot != null:
		out.append({ "id": "chat", "text": _l("chat") })
	if needs_rebuild():
		out.append({ "id": "rebuild", "text": _l("rebuild") % [ship_label(wreck_id()), rebuild_price()] })
		if not WorldState.has_flag(WorldState.COMRADE):
			out.append({ "id": "comrade", "text": _l("comrade") })
	out.append({ "id": "group:ships", "text": _l("menu_ships") })
	if not ShipUpgrades.owned().is_empty():
		out.append({ "id": "group:upgrades", "text": _l("menu_upgrades") })
	out.append({ "id": "tutorial", "text": _l("tutorial") })
	return out


## "Buy or sell a ship": every ship in stock, then yours on the pad to sell back.
func ship_options() -> Array:
	var out := []
	var taken := WorldState.hangar != ""
	for id in stock():
		out.append({ "id": "buy:" + id, "text": _l("buy_taken" if taken else "buy") % [ship_label(id), price(id)] })
	if taken:
		out.append({ "id": "sell", "text": _l("sell") % [ship_label(WorldState.hangar), resale(WorldState.hangar)] })
	out.append({ "id": "back", "text": _l("back") })
	return out


## "Upgrade your ships": each upgrade not yet on each ship you own.
func upgrade_options() -> Array:
	var out := []
	for sid in ShipUpgrades.owned():
		for up in ShipUpgrades.ids():
			if not ShipUpgrades.has(sid, up):
				out.append({ "id": "fit:%s:%s" % [sid, up],
					"text": _l("fit") % [ShipUpgrades.label(up).to_lower(), ship_label(sid), ShipUpgrades.price(up)] })
	out.append({ "id": "back", "text": _l("back") })
	return out


## Opening a submenu: his line for it (what each ship you own carries, for upgrades).
func _group_line(group: String) -> String:
	if group == "ships":
		return _line("ships_pitch")
	var text := _line("upgrades_pitch" if upgrade_options().size() > 1 else "all_fitted")
	return text + "\n\n" + "\n".join(PackedStringArray(ShipUpgrades.owned_lines()))


func _group_options(group: String) -> Array:
	return ship_options() if group == "ships" else upgrade_options()


func _on_top(id: String) -> void:
	if id.begins_with("group:"):
		var g := id.substr(6)
		said = _group_line(g)
		_menu(_group_options(g), _on_group.bind(g))
	elif id == "rebuild":
		rebuild()
		_menu(top_options(), _on_top, true)
	elif id == "comrade":
		start_remnant_talk()
	elif id == "tutorial":
		start_tutorial()
	elif id == "chat":
		chat()


## A buy, a sale or a fit does not end the talk: the same submenu again, with what
## he just said and the new prices, the cursor where it was. Back is his top menu;
## Esc walks away.
func _on_group(id: String, group: String) -> void:
	if id == "back":
		said = _line("anything_else")
		_menu(top_options(), _on_top)
		return
	if id.begins_with("buy:"):
		buy(id.substr(4))
	elif id == "sell":
		sell()
	elif id.begins_with("fit:"):
		fit(id.get_slice(":", 1), id.get_slice(":", 2))
	else:
		return
	_menu(_group_options(group), _on_group.bind(group), true)


## The menu again, quietly (no beep, no voice), with his last line on top.
func _menu(opts: Array, pick: Callable, keep_cursor: bool = false) -> void:
	menu.open(_l("menu_title") % [npc_name(), WorldState.credits], opts, pick, said, keep_cursor)


## Buy a ship: it lands on the spare pad. Returns "bought", "taken",
## "cant_afford" or "" (not for sale).
func buy(ship_id: String) -> String:
	if not stock().has(ship_id):
		return ""
	if WorldState.hangar != "":
		_say(_line("pad_taken") % ship_label(WorldState.hangar))
		return "taken"
	var cost := price(ship_id)
	if WorldState.credits < cost:
		_say(_line("cant_afford") % [ship_label(ship_id), cost, WorldState.credits])
		return "cant_afford"
	WorldState.credits -= cost
	WorldState.hangar = ship_id
	WorldState.log_event(_l("event_bought") % ship_label(ship_id), "pit")
	park_owned()
	Sound.play("droid_wake", pos)
	_say(_line("bought") % ship_label(ship_id))
	return "bought"


## Sell your bought ship back. Not while you fly it. Returns the price or -1.
func sell() -> int:
	var id := WorldState.hangar
	if id == "":
		return -1
	var pilot = demo.pilot if demo != null else null
	var i: int = pilot.berth_of(Fleet.T89) if pilot != null else -1
	if i >= 0 and i == pilot.berths.size() - 1 and pilot.berths[i].visual == bought_ship:
		if not pilot.remove_last_berth():
			_say(_line("flying_it") % ship_label(id))
			return -1
	elif i >= 0:
		# Issue #368: wherever else it stands (the pit as your primary, the sand).
		if not pilot.sell_berth(i):
			_say(_line("flying_it") % ship_label(id))
			return -1
	elif bought_ship != null:
		if demo != null and demo.decor != null:
			demo.decor.parked_ships.erase(bought_ship)
		bought_ship.queue_free()
	bought_ship = null
	var paid := resale(id)
	settle_sale(id, paid)                  # issue #207: its upgrades go with it
	_say(_line("sold") % paid)
	return paid


# ------------------------------------------------------------------ the wreck (issue #206)

## A story save's own ship still waits on the pit pad as a wreck.
static func needs_rebuild() -> bool:
	return WorldState.story_mode() and not WorldState.has_flag(WorldState.SHIP_REBUILT)


func rebuild_price() -> int:
	var r: Dictionary = cfg.get("rebuild", {})
	return int(r.get("comrade_price", 1)) if WorldState.has_flag(WorldState.COMRADE) else int(r.get("price", 500))


## The ship on the pit pad (the one you landed in).
func wreck_id() -> String:
	var pilot = demo.pilot if demo != null and "pilot" in demo else null
	return str(pilot.berths[0].ship_id) if pilot != null and not pilot.berths.is_empty() else "interceptor"


## Rebuild the wreck: it is yours to fly from the pit pad. Returns "rebuilt",
## "cant_afford" or "" (nothing to rebuild).
func rebuild() -> String:
	if not needs_rebuild():
		return ""
	var cost := rebuild_price()
	if WorldState.credits < cost:
		_say(_line("cant_afford_rebuild") % [cost, WorldState.credits])
		return "cant_afford"
	WorldState.credits -= cost
	WorldState.set_flag(WorldState.SHIP_REBUILT)
	WorldState.wreck_ship = wreck_id()
	WorldState.log_event(_l("event_rebuilt") % ship_label(wreck_id()), "pit")
	var pilot = demo.pilot if demo != null and "pilot" in demo else null
	if pilot != null:
		pilot.refresh_wreck_look()          # good as new
	Story.event("ship_rebuilt")
	_beep()
	_say(_line("rebuilt") % ship_label(wreck_id()))
	return "rebuilt"


## The player can't stand the Remnant: neither can he. The comrade discount, once.
## Returns true the first time. `say`: his line for it (the chat's, or the menu's).
func comrade(say: String = "comrade") -> bool:
	if WorldState.has_flag(WorldState.COMRADE):
		_say(_line("comrade_again") % rebuild_price())
		return false
	WorldState.set_flag(WorldState.COMRADE)
	WorldState.log_event("T-89 and the player found they agree about the Remnant.", "pit")
	if needs_rebuild():
		_say(_line(say) % rebuild_price())
	return true


## His menu's "Tell him what you think of the Remnant": his story a page at a time,
## then the question. Walk away (Esc) or side with the Remnant and the row is still
## on his menu: ask again until you are his comrade.
func remnant_pages() -> Array:
	return cfg.get("remnant_story", [])


func start_remnant_talk() -> void:
	story_page = 0
	_show_story_page()


func _show_story_page() -> void:
	var pages := remnant_pages()
	if story_page >= pages.size():
		story_page = -1
		_open(_line("remnant_question"), [{ "id": "down", "text": _l("down_with_them") },
			{ "id": "side", "text": _l("side_with_them") }], _on_remnant_answer)
		return
	_open("(%d/%d)  %s" % [story_page + 1, pages.size(), str(pages[story_page])],
		[{ "id": "next", "text": _l("go_on") }, { "id": "skip", "text": _l("to_the_point") }], _on_story_page)


func _on_story_page(id: String) -> void:
	if id == "next":
		story_page += 1
	elif id == "skip":
		story_page = remnant_pages().size()
	else:
		story_page = -1
		return
	_show_story_page()


## "Down with the Tyrants!": a comrade. The Remnant's side: no discount, and he
## sends you back to his menu to buy a ship or leave him be.
func _on_remnant_answer(id: String) -> void:
	if id == "down":
		comrade("comrade_won")
	elif id == "side":
		_say(_line("sided_remnant"))
	else:
		return
	_menu(top_options(), _on_top)


# ------------------------------------------------------------------ upgrades (issue #207)

## Fit upgrade `up` to ship `ship_id` (one you own). Returns "fitted",
## "cant_afford" or "" (not yours, unknown, or on already).
func fit(ship_id: String, up: String) -> String:
	if not ShipUpgrades.owned().has(ship_id) or not ShipUpgrades.ids().has(up) or ShipUpgrades.has(ship_id, up):
		return ""
	var cost := ShipUpgrades.price(up)
	if WorldState.credits < cost:
		_say(_line("cant_afford_fit") % [ShipUpgrades.label(up), cost, WorldState.credits])
		return "cant_afford"
	WorldState.credits -= cost
	ShipUpgrades.fit(ship_id, up)
	WorldState.log_event(_l("event_fitted") % [ShipUpgrades.label(up).to_lower(), ship_label(ship_id)], "pit")
	var pilot = demo.pilot if demo != null and "pilot" in demo else null
	if pilot != null:
		pilot.refit()
	_beep()
	_say(_line("fitted") % [ShipUpgrades.label(up), ship_label(ship_id)])
	return "fitted"


## Put WorldState.hangar's ship on the spare pad (bought now, or loaded from a
## save) and make it boardable. Issue #368: not when it is somewhere else already
## (on the pit pad as your primary, or left elsewhere: ShipPilot.place_fleet).
func park_owned() -> void:
	if WorldState.hangar == "" or bought_ship != null or demo == null:
		return
	var box: Dictionary = demo.town.get_box(str(cfg.get("pad", "spare_pad")))
	if box.is_empty():
		push_warning("ShipSalesman: no pad box " + str(cfg.get("pad", "")))
		return
	if demo.pilot != null and demo.pilot.berth_of(Fleet.T89, true) >= 0:
		return
	var s := Fleet.spot(Fleet.T89)
	if not s.is_empty():
		var c := (WorldGround._v3(box.min) + WorldGround._v3(box.max)) * 0.5
		var at := Fleet.spot_xf(s).origin
		if str(s.get("planet", "")) != GameFlow.current_planet_id() or Vector2(at.x - c.x, at.z - c.z).length() > 8.0:
			return
	if demo.decor != null:
		bought_ship = demo.decor.park_ship(WorldState.hangar, box)
	if bought_ship == null:
		# The greybox: no models, so a bare node stands in (as ShipPilot does for the pit ship).
		bought_ship = Node3D.new()
		bought_ship.name = "Parked_" + str(box.id)
		demo.add_child(bought_ship)
		bought_ship.global_position = Vector3((float(box.min[0]) + float(box.max[0])) * 0.5, float(box.min[1]),
			(float(box.min[2]) + float(box.max[2])) * 0.5)
		bought_ship.rotation.y = deg_to_rad(float(box.get("parked_yaw_deg", 0.0)))
	if demo.pilot != null:
		demo.pilot.add_berth(bought_ship, WorldState.hangar, str(box.id), Fleet.T89)   # issue #206: yours to fly


# ------------------------------------------------------------------ AI

## Join the town's conversation host as one of its AI characters. Safe to call
## twice. His [E] stays his shop's; "Talk" there starts the chat (chat()).
func attach_host(h: ConversationHost) -> void:
	if h == null or host == h or body == null:
		return
	host = h
	var brain := NpcBrain.new(null, persona_card())
	brain.extra_brief = pad_brief
	spot = TalkSpot.new(brain, body, pos)
	spot.manual = true
	spot.radius = float(cfg.get("reach", 3.2))
	spot.face_height = height() - 0.25
	spot.shortcuts = shortcuts
	spot.on_shortcut = _on_shortcut
	spot.opener = _chat_opener
	brain.wares = wares
	host.add_spot(spot)
	brain.sale_offered.connect(_on_ship_offered)
	brain.item_offered.connect(_on_upgrade_offered)
	brain.comrade_declared.connect(func(): comrade())
	host.panel.sale_answered.connect(_on_ship_answer)


## Issue #305: the keyword row over his chat box: his shops, a click away.
func shortcuts() -> Array:
	var out := [{ "id": "go_ships", "label": _l("key_ships") }]
	if not ShipUpgrades.owned().is_empty():
		out.append({ "id": "go_upgrades", "label": _l("key_upgrades") })
	out.append({ "id": "go_menu", "label": _l("key_menu") })
	return out


## A keyword picked: the chat closes and that shop (or his top menu) opens; its
## "Talk" brings the chat back.
func _on_shortcut(id: String) -> void:
	host.end_talk()
	_beep()
	if id in ["go_ships", "go_upgrades"]:
		var g := id.substr(3)
		_open(_group_line(g), _group_options(g), _on_group.bind(g))
	else:
		_open(_line("anything_else"), top_options(), _on_top)


## The chat's first line while your wreck waits: the rebuild's price (and the
## quest), as his menu used to say it.
func _chat_opener() -> Dictionary:
	if not needs_rebuild():
		return {}
	return { "say": (_line("hello_again") + _repair_line()).strip_edges() }


## Issue #305: what he can fit for them now, for his offer_item: each upgrade not
## yet on each ship they own, at its price.
func wares() -> Array:
	var out := []
	for sid in ShipUpgrades.owned():
		for up in ShipUpgrades.ids():
			if not ShipUpgrades.has(sid, up):
				out.append({ "id": "fit:%s:%s" % [sid, up], "name": _l("fit_name") % [ShipUpgrades.label(up), ship_label(sid)],
					"price": ShipUpgrades.price(up) })
	return out


## Open the chat box with him (from his shop's "Talk").
func chat() -> bool:
	if host == null or spot == null or host.is_talking():
		return false
	_was_locked = false               # the host locks the player now, and frees them after
	host.start_talk(spot)
	return host.active == spot


## His card, with what he sells filled in: each ship in stock with its price and
## its numbers from the ship file, so the model can compare them and recommend one.
func persona_card() -> Dictionary:
	var card := NpcBrain._read(CARD_PATH)
	var notes: Dictionary = card.get("ship_notes", {})
	var ships := []
	for id in stock():
		var n: Dictionary = notes.get(id, {})
		ships.append({ "id": id, "name": ship_label(id), "price": price(id), "text": ship_text(id, card),
			"good_for": n.get("good_for", []) })
	card["ships"] = ships
	return card


## One ship's numbers in plain words (and his pitch for it):
## "Hull 80, shields 60. Top speed 210, 380 on boost. 2 cannons at 70% power. ..."
func ship_text(ship_id: String, card: Dictionary = {}) -> String:
	var s: Dictionary = content.get_ship(ship_id)
	var air: Dictionary = s.get("atmosphere", {})
	var cannons := 0
	var seekers := 0
	for h in s.get("hardpoints", []):
		if str(h.get("weapon", "")) == "ship_missile":
			seekers += 1
		else:
			cannons += 1
	var guns := "%d cannons at %d%% power" % [cannons, int(round(float(s.get("blaster_power", 1.0)) * 100.0))]
	if seekers > 0:
		guns += " and a seeker rack"
	var parts := [
		"Hull %d, shields %d." % [int(s.get("hull", 0)), int(s.get("shield", {}).get("max", 0))],
		"Top speed %d, %d on boost." % [int(air.get("max_speed", 0)), int(air.get("boost_speed", 0))],
		guns + ".",
	]
	var ability := str(s.get("flight", {}).get("ability", {}).get("kind", ""))
	var ab: Dictionary = card.get("abilities", {})
	if ab.has(ability):
		parts.append(str(ab[ability]) + ".")
	var pitch := str(card.get("ship_notes", {}).get(ship_id, {}).get("pitch", ""))
	if pitch != "":
		parts.append(pitch)
	return " ".join(PackedStringArray(parts))


## His briefing each turn: what is on their pad (only one ship fits), and the
## wreck they landed in while it waits (issue #206).
func pad_brief() -> Array:
	if needs_rebuild():
		return ["THEIR WRECK: the %s they landed in, on the pit pad. You rebuild it for %d credits (they rebuild it from your shop with E)."
			% [ship_label(wreck_id()), rebuild_price()]] + _pad_line()
	return _pad_line()


func _pad_line() -> Array:
	if WorldState.hangar == "":
		return ["THEIR PAD: empty, ready for a ship."]
	return ["THEIR PAD: holds the %s you sold them (you would buy it back for %d). Nothing else fits until they sell it."
		% [ship_label(WorldState.hangar), resale(WorldState.hangar)]]


func _on_ship_offered(item: Dictionary) -> void:
	if host == null or host.active != spot:
		return
	_offered = item.duplicate()
	_offered["text"] = ship_text(str(item.id), spot.brain.card)
	if WorldState.hangar != "":
		_offered["text"] += "\n\n" + _line("pad_taken") % ship_label(WorldState.hangar)
	host.panel.show_sale(_offered, WorldState.credits)


## Issue #305: his offer_item: an upgrade's price card in the chat box.
func _on_upgrade_offered(item: Dictionary) -> void:
	if host == null or host.active != spot:
		return
	_offered = item.duplicate()
	_offered["text"] = _line("fit_card") % ship_label(str(item.id).get_slice(":", 1))
	host.panel.show_sale(_offered, WorldState.credits)


## Buy on the price card: the shop's buy() (or fit(), for an upgrade), and his
## answer in the chat box.
func _on_ship_answer(id: String, accepted: bool) -> void:
	if not accepted or host == null or host.active != spot or id != str(_offered.get("id", "")):
		return
	_offered = {}
	var done := fit(id.get_slice(":", 1), id.get_slice(":", 2)) if id.begins_with("fit:") else buy(id)
	if done != "":
		host.panel.set_line(said)
		host.panel.set_money(WorldState.credits, spot.brain.rel.tab)


# ------------------------------------------------------------------ helpers

func _beep() -> void:
	if body != null:
		Sound.play("assassin_beep", pos)


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
