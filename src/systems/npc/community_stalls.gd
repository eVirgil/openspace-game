class_name CommunityStalls
extends Node
## Issue #147: the market's player-made stall keepers, in one town.
##
##   setup     which free stalls there are and who keeps each (CommunityNpc.assign),
##             before the people are built: TownDemo dresses the body at a kept
##             stall in its keeper's look (look_for) and names it (dressed)
##   attach    once the people and the cantina's host are up: a talk spot for
##             each keeper ([E] Talk to <name>), talk only, the town briefing as
##             their world, and the claim prompt at every free stall
##   builder   [E] at a free stall opens the NPC builder (CommunityNpcPanel) on
##             that stall's draft. "Try them out" dresses the stall's body in
##             the draft and puts a talk spot there that is never saved, with a
##             "Back to the builder" button over the chat box
##
## Their wares go on the counter through TownDecor (CommunityNpc.assign there too).

const REACH := 3.5                 ## metres from the keeper: the prompt shows (as the vendors')

var demo
var location := "port_town"
var stalls: Array = []             ## free stall markers, in the town's order
var keepers: Dictionary = {}       ## marker -> the NPC file of a merged keeper
var drafts: Dictionary = {}        ## marker -> the draft being tried out there
var spots: Dictionary = {}         ## marker -> its TalkSpot
var host: ConversationHost
var folk: Townsfolk
var panel: CommunityNpcPanel
var claim_marker := ""             ## the free stall whose prompt is up ("" none)
var _layer: CanvasLayer
var _prompt: Label
var _editing := ""                 ## the stall the builder is open on


## Before the people are built.
func setup(town_demo, town, location_id: String, content) -> void:
	demo = town_demo
	location = location_id
	stalls = CommunityNpc.free_stalls(town, location, content)
	keepers = CommunityNpc.assign(CommunityNpc.in_town(location), stalls)


## The soldier profile's look for the body at `marker` ({} = the merchant's own).
func look_for(marker: String) -> Dictionary:
	if not keepers.has(marker):
		return {}
	return CommunityNpc.soldier({}, keepers[marker])


## The body at `marker` is built: their name and build.
func dressed(marker: String, body: NpcBody) -> void:
	if body == null or not keepers.has(marker):
		return
	body.display_name = CommunityNpc.display_name(keepers[marker])
	body.set_look_scale(CommunityNpc.scale_of(keepers[marker]))


## Once the people and the host are up.
func attach(conversation_host: ConversationHost, townsfolk: Townsfolk) -> void:
	host = conversation_host
	folk = townsfolk
	for marker in keepers:
		_talker(marker, keepers[marker], false)
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -300
	_prompt.offset_right = 300
	_prompt.offset_top = -140
	_prompt.offset_bottom = -108
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.visible = false
	RetroUI.prompt(_prompt)
	_layer.add_child(_prompt)
	panel = CommunityNpcPanel.new()
	add_child(panel)
	panel.tried.connect(_try)
	panel.closed.connect(func(): _editing = "")


func body_at(marker: String) -> NpcBody:
	if folk == null:
		return null
	for g in folk.members:
		if g.post_id == marker and is_instance_valid(g):
			return g
	return null


## A talk spot for the keeper at `marker` (replacing any there). `draft`: a try-out.
func _talker(marker: String, npc: Dictionary, draft: bool) -> TalkSpot:
	var g := body_at(marker)
	if g == null or host == null:
		return null
	if spots.has(marker):
		host.remove_spot(spots[marker])
	var s := TalkSpot.new(NpcBrain.new(null, CommunityNpc.card(npc, draft)), g, g.post_pos)
	s.radius = REACH
	s.remember = not draft
	s.available = func() -> bool: return is_instance_valid(g) and folk.vendor_open(marker)
	if draft:
		s.shortcuts = func(): return [{ "id": "back_to_builder", "label": "Back to the builder" }]
		s.on_shortcut = func(_k: String) -> void:
			host.end_talk()
			open_builder(marker)
	host.add_spot(s)
	spots[marker] = s
	return s


# ------------------------------------------------------------------ the claim prompt

## A free stall (no merged keeper, nothing being tried) within reach of the player.
func claimable_in_range() -> String:
	if demo == null or host == null or host.is_talking() or host.spot_in_range() != null:
		return ""
	var p: Node3D = demo._player
	if p == null or not is_instance_valid(p) or p.get("piloting") == true or p.get("riding") == true:
		return ""
	var best := ""
	var best_d := REACH
	for marker in stalls:
		if keepers.has(marker) or spots.has(marker):
			continue
		var g := body_at(marker)
		if g == null or g.dead or not folk.vendor_open(marker):
			continue
		var d := Vector2(p.global_position.x - g.post_pos.x, p.global_position.z - g.post_pos.z).length()
		if d <= best_d and absf(p.global_position.y - g.post_pos.y) < 1.5:
			best_d = d
			best = marker
	return best


func _process(_dt: float) -> void:
	if _prompt == null:
		return
	claim_marker = "" if panel.visible else claimable_in_range()
	_prompt.visible = claim_marker != ""
	if claim_marker == "":
		return
	var has_draft := not CommunityNpc.load_draft(location, claim_marker).is_empty()
	_prompt.text = "[E]  %s" % ("Carry on with your stall keeper" if has_draft else "Make this stall keeper yours")
	if InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
		open_builder(claim_marker)


# ------------------------------------------------------------------ the builder

func open_builder(marker: String) -> void:
	if panel == null:
		return
	var draft := CommunityNpc.load_draft(location, marker)
	if draft.is_empty():
		draft = CommunityNpc.blank(location, marker, CommunityNpc.saved_author())
	draft["town"] = location
	draft["stall"] = marker
	_editing = marker
	_prompt.visible = false
	panel.open(draft, keepers.values())


## Dress the stall's body in the draft and let the player talk to them.
func _try(npc: Dictionary) -> void:
	var marker := str(npc.get("stall", ""))
	var g := body_at(marker)
	if g == null:
		return
	drafts[marker] = npc
	g.redress(str(CommunityNpc.config().get("look", {}).get("archetype", "local")), CommunityNpc.outfit(npc), CommunityNpc.scale_of(npc))
	g.display_name = CommunityNpc.display_name(npc)
	_talker(marker, npc, true)
