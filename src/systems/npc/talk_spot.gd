class_name TalkSpot
extends RefCounted
## One AI character you can walk up to and talk to (issue #42): their brain, their
## body, and the spot the player stands on. The ConversationHost owns the parts
## every character shares (the model service, the chat box, the save) and runs
## whichever spot the player is at.
##
## The body is any Node3D. If it has `act_named(name, seconds)` ("idle",
## "thinking", "talking", "pouring") and `speak_pulse()`, the host drives them; a
## plain character just stands there.

var brain: NpcBrain
var body: Node3D
var stand := Vector3.ZERO          ## where the player stands to talk (the bar front, the stall)
var radius := 1.9
var height_tolerance := 1.5
var face_height := 1.5             ## the two-shot frames this height on the body
var manual := false                ## true: the character's own [E] starts the talk (T-89's menu), not the host's
var hold_line := ""                ## not "": Esc can't leave (the general's pit meeting); the chat box says this instead
var near_voice := false            ## true: heard as if beside them, however far off (the general's pit meeting opens wherever you stand)
var shortcuts := Callable()        ## issue #305: valid: () -> [{ id, label }], the keyword row over the chat box, always shown ("Ships", "Upgrades"); ids are node names (no ":")
var on_shortcut := Callable()      ## issue #305: (id) a keyword was picked: the character puts up a price card, or ends the talk and opens their menu
var opener := Callable()           ## valid: asked as the talk opens for { say, sale } (Skrugs's ship offer): "say" replaces the greeting, "sale" goes up on the chat box at once; {} = greet as usual


func _init(npc_brain: NpcBrain = null, npc_body: Node3D = null, stand_at: Vector3 = Vector3.ZERO) -> void:
	brain = npc_brain
	body = npc_body
	stand = stand_at


func id() -> String:
	return brain.id() if brain != null else ""


## What the prompt and the chat box call them ("Oda Vell", "Skrugs").
func display_name() -> String:
	return str(brain.card.get("name", brain.card.get("label", "them"))) if brain != null else "them"


func in_range(p: Node3D) -> bool:
	if p == null or not is_instance_valid(p) or p.get("piloting") == true or p.get("riding") == true:
		return false
	var d := Vector2(p.global_position.x - stand.x, p.global_position.z - stand.z).length()
	return d <= radius and absf(p.global_position.y - stand.y) < height_tolerance


func distance_to(p: Node3D) -> float:
	return Vector2(p.global_position.x - stand.x, p.global_position.z - stand.z).length()


## Over the player's shoulder, framing them in the top half of the screen (the
## chat box owns the bottom).
func two_shot(player: Node3D) -> Transform3D:
	var them := body.global_position + Vector3(0, face_height, 0)
	var me: Vector3 = player.global_position + Vector3(0, 1.62, 0)
	var to_them := Vector3(them.x - me.x, 0, them.z - me.z).normalized()
	var side := to_them.cross(Vector3.UP).normalized()
	var eye := me - to_them * 0.9 - side * 0.62 + Vector3(0, 0.05, 0)
	return Transform3D(Basis(), eye).looking_at(them + Vector3(0, -0.28, 0) - side * 0.1, Vector3.UP)


func act(name: String, seconds: float = 0.0) -> void:
	if body != null and body.has_method("act_named"):
		body.act_named(name, seconds)


func speak_pulse() -> void:
	if body != null and body.has_method("speak_pulse"):
		body.speak_pulse()
