class_name Story
extends RefCounted
## The main story line (issue #64). Pure and static, like WorldState, and its
## state lives there (WorldState.story, saved with the world):
##
##   T-89 says talk to Oda -> she sends you to practice at the range -> she pays
##   for it and tells you about the sparring droid (optional: go to the pit and
##   come back, on your honour) -> two smuggling runs
##   (the first with her old jetpack if she is amused or warm) -> Skrugs and a
##   bounty at a Remnant outpost -> the Remnant fleet in orbit (the port's ships
##   unlock): one mission, the general on the bridge of their star cruiser far out
##   east (issue #193; the fleet's fighters meet you on the way up, and beating
##   them is not the mission) -> back to Oda (issue #303: the debrief; the kill is
##   paid and saved on the spot) -> the end card -> free play: smuggling runs and
##   bounty contracts on repeat.
##
## Issue #303: after the general dies a dark master waits in the cruiser's bay
## (DarkMasterPost). Join him and the debrief can end the other way: clear the
## barracks' local guards and the Remnant hold the moon (DarkPact).
##
## Chapters and every line: content/core/story/main.json. Systems report what
## happened with event() (WorldState does most of it); a teller asks beat() when
## the player talks to them and says the line it gets back.
##
## The Remnant follow the story too: before the fleet is beaten the town's
## garrison respawns behind the barracks; after, the town is free of them (issue
## #187: the locals hold the barracks), and the desert outposts are always hostile
## (issue #303: unless you swore the dark master's oath; and the Remnant take the
## town back if its barracks guards all die).
## Who holds the outposts in between: Territory.

const PATH := "res://content/core/story/main.json"
## The Remnant's desert outposts, nearest the front gate first (issue #187: and
## four more round the other sides of the town).
const OUTPOSTS := ["remnant_outpost_near", "remnant_outpost_mid", "remnant_outpost_far",
	"remnant_outpost_north", "remnant_outpost_south", "remnant_outpost_west", "remnant_outpost_southwest"]
const JETPACK := "jetpack"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_data = d if d is Dictionary else {}
	return _data


static func chapters() -> Array:
	return data().get("chapters", [])


static func chapter_ids() -> Array:
	return chapters().map(func(c): return str(c.id))


static func chapter() -> String:
	return str(WorldState.story.get("chapter", _first()))


## Issue #215: a chapter is in this save's mode ("modes", default every mode).
## land, general and t89 are story only: a freeplay story starts at meet_oda.
static func applies(c: Dictionary) -> bool:
	var modes: Array = c.get("modes", [])
	return modes.is_empty() or modes.has(WorldState.mode)


static func _first() -> String:
	for c in chapters():
		if applies(c):
			return str(c.id)
	return ""


## The chapter a save holds, under its current id (old saves: chapter_renames).
static func renamed(id: String) -> String:
	return str(data().get("chapter_renames", {}).get(id, id))


static func chapter_cfg(id: String = "") -> Dictionary:
	if id == "":
		id = chapter()
	for c in chapters():
		if str(c.id) == id:
			return c
	return {}


static func index(id: String) -> int:
	return chapter_ids().find(id)


## The story has got as far as `id` (or past it).
static func reached(id: String) -> bool:
	return index(chapter()) >= index(id) and index(id) >= 0


## A fresh story: the first chapter of this save's mode, nothing told.
static func fresh() -> Dictionary:
	return { "chapter": _first(), "told": false }


## Jump straight to a chapter (settings, tests). Earlier chapters' unlocks apply:
## what finishing each one leaves behind (_skipped), as if it had been played.
static func skip_to(id: String) -> void:
	if index(id) < 0:
		return
	var from := index(chapter())
	var told := bool(WorldState.story.get("told", false))
	for c in chapters().slice(0, index(id)):
		if applies(c):
			var at := index(str(c.id))
			_skipped(c, at >= from, at > from or not told)
	WorldState.story = { "chapter": id, "told": id == "free" }
	if reached("fleet"):
		WorldState.set_flag("ships_unlocked")


## Chapter `c` skipped past: its "skipped" flags and counters (at least), its
## one-off job card done, and in a story save the quests its telling unlocks (the
## blade on the tower). Not finished yet (`unplayed`): also its credits and
## standing, once (not when its done_flag is set or its counters are met already:
## skipping back and on again in free roam), and its "pays" when it was not told
## yet (`untold`: the teller pays with the intro).
static func _skipped(c: Dictionary, unplayed: bool, untold: bool) -> void:
	var s: Dictionary = c.get("skipped", {})
	var cs: Dictionary = s.get("counters", {})
	var done_flag := str(c.get("done_flag", ""))
	var done := (done_flag != "" and WorldState.has_flag(done_flag)) \
		or (not cs.is_empty() and cs.keys().all(func(n): return WorldState.count(str(n)) >= int(cs[n])))
	if unplayed and not done:
		var pay := (int(c.get("pays", 0)) if untold else 0) + int(s.get("credits", 0))
		if pay > 0:
			WorldState.credits += pay
			WorldState.log_event("Skipped %s: %d cr." % [str(c.id).replace("_", " "), pay])
		var st: Dictionary = s.get("standing", {})
		for f in st:
			WorldState.change_standing(str(f), int(st[f]))
	for f in s.get("flags", []):
		WorldState.set_flag(str(f))
	for n in cs:
		WorldState.counters[str(n)] = maxi(WorldState.count(str(n)), int(cs[n]))
	var job := str(c.get("job", ""))
	for j in WorldState.board():
		if str(j.id) == job and str(j.get("completes_on", "")) != "" and WorldState.jobs_taken.get(job, "") != "done":
			WorldState.jobs_taken[job] = "done"
			WorldState.set_flag("job_done_" + job)
	if WorldState.story_mode():
		Quests.event("told:" + str(c.id))


# ------------------------------------------------------------------ events

## Something happened. Moves the story on when it is what this chapter waits for.
## Returns true if it did. Issue #201: every event reaches the optional quests too.
static func event(name: String) -> bool:
	Quests.event(name)
	var c := chapter_cfg()
	if c.is_empty() or name == "":
		return false
	if not ends_on(c, name):
		return _step_event(c, name)
	var next := chapter()
	for later in chapters().slice(index(chapter()) + 1):
		if applies(later):
			next = str(later.id)
			break
	WorldState.story = { "chapter": next, "told": false }
	WorldState.log_event("Story: " + next.replace("_", " ") + ".")
	if reached("debrief") and not remnant_gone():
		# Issue #303: at the kill, not the end card: the locals hold the barracks by
		# the time you are home (the dark master's oath needs their guards there).
		WorldState.set_flag("remnant_fleet_beaten")
		WorldState.log_event("The Remnant fleet in orbit was broken. The garrison is pulling out of town.")
	catch_up()
	var next_line := str(Objective.chapter_objective().get("text", ""))
	if next_line != "":
		QuestNews.push("objective", next_line)      # the banner: what the story wants now
	return true


## Issue #303: chapter `c` ends on event `name` ("done_on": one event, or a list).
static func ends_on(c: Dictionary, name: String) -> bool:
	var want = c.get("done_on", "")
	return (want as Array).has(name) if want is Array else str(want) == name


# ------------------------------------------------------------------ steps

## A chapter's steps ("steps": [{ id, done_on, text, target }]): its objective one
## step at a time, each with its own waypoint (the fleet: land in the cruiser's
## bay, reach the stairs, kill the general). A step is done when its flag is set.
static func steps(c: Dictionary = {}) -> Array:
	if c.is_empty():
		c = chapter_cfg()
	return c.get("steps", [])


static func step_flag(c: Dictionary, s: Dictionary) -> String:
	return "%s_%s" % [str(c.get("id", "")), str(s.get("id", ""))]


static func step_done(c: Dictionary, s: Dictionary) -> bool:
	return WorldState.has_flag(step_flag(c, s))


## The step the chapter is on (the first not done), or {}.
static func current_step(c: Dictionary = {}) -> Dictionary:
	if c.is_empty():
		c = chapter_cfg()
	for s in steps(c):
		if not step_done(c, s):
			return s
	return {}


## A step of chapter `c` ends on `name` (never the chapter's own event: that ends
## the chapter): it and every step before it are done, and once the chapter is
## told the banner says what it wants next. True if a step was done by it.
static func _step_event(c: Dictionary, name: String) -> bool:
	if not steps(c).any(func(s): return str(s.get("done_on", "")) == name):
		return false
	var changed := false
	for s in steps(c):
		if not step_done(c, s):
			WorldState.set_flag(step_flag(c, s))
			changed = true
		if str(s.get("done_on", "")) == name:
			break
	if not changed:
		return false
	WorldState.log_event("Story: %s, %s." % [str(c.id).replace("_", " "), name.replace("_", " ")])
	var next_line := str(Objective.chapter_objective().get("text", ""))
	if bool(WorldState.story.get("told", false)) and next_line != "":
		QuestNews.push("objective", next_line)
	return true


## A step's text with the general's name in it ("Kill %s on the bridge").
static func fill_step(text: String) -> String:
	if not text.contains("%s"):
		return text
	var n := cruiser_general_name()
	return text % (n if n != "" else Objective.line("general_unknown"))


## The general aboard the Remnant cruiser by name ("General So-and-so") before you
## have met him: the name engine names him off the same key his body will get
## (NameHooks.person), and keeps it in the book, so the two agree.
static func cruiser_general_name() -> String:
	var cfg := CruiserHull.data()
	var soldier := str(cfg.get("general", {}).get("soldier", "cruiser_general"))
	var profile := ItemKit._read_json("res://content/core/soldiers/%s.json" % soldier)
	return NameHooks.person(profile.get("naming", {}), "npc:%s/general" % str(cfg.get("id", "remnant_cruiser")))


## Issue #193: the chapter is done before it was asked (the cruiser taken before
## Oda sent you, or in a save from before the general ended the fleet chapter).
static func catch_up() -> void:
	var c := chapter_cfg()
	var flag := str(c.get("done_flag", ""))
	var on = c.get("done_on", "")
	if flag != "" and WorldState.has_flag(flag):
		event(str(on[0]) if on is Array and not on.is_empty() else str(on))


# ------------------------------------------------------------------ tellers

## What `teller` says when the player walks up, if the story has something to
## say: { say, job } (job = a job id whose card goes with it, or ""), else {}.
## Talking to Oda for the first time finishes "meet_oda" and starts the range.
static func beat(teller: String) -> Dictionary:
	if teller == "cantina_owner" and chapter() == "meet_oda":
		event("met_oda")
	var c := chapter_cfg()
	if c.is_empty() or str(c.get("teller", "")) != teller:
		return {}
	var first := not bool(WorldState.story.get("told", false))
	WorldState.story.told = true
	if first and str(c.id) == "debrief":
		DarkPact.on_debrief()            # issue #303: telling Oda first breaks the oath
	var out := _tell(c, first)
	if first:
		# Issue #201/#215: "told:<chapter>" unlocks quests (the blade on the tower) and
		# ends a chapter that is only the telling (T-89's).
		var before := chapter()
		event("told:" + str(c.id))
		if chapter() == before and str(c.get("job", "")) == "":
			_told_news(c)
	return out


## Told a chapter that sends you somewhere, with no job card to be the news: the
## banner says the objective it wants now, after a "New Quest" with the chapter's
## title when it has one (the fleet). A "talk to the teller" banner still waiting
## from the chapter before (met Oda, and she told the range in the same breath)
## is dropped: it is answered.
static func _told_news(c: Dictionary) -> void:
	var o := Objective.chapter_objective()
	if str(o.get("target", "")) == "" or str(o.get("text", "")) == "":
		return
	QuestNews.retract("objective", str(data().get("objectives", {}).get("teller", {}).get("text", "")))
	if str(c.get("title", "")) != "":
		QuestNews.push("quest_new", str(c.title))
	QuestNews.push("objective", str(o.text))


static func _tell(c: Dictionary, first: bool) -> Dictionary:
	if first and int(c.get("pays", 0)) > 0:
		WorldState.credits += int(c.pays)
		WorldState.log_event("Oda paid %d cr for the practice." % int(c.pays))
	if chapter() == "fleet":
		WorldState.set_flag("ships_unlocked")
	if chapter() == "free":
		return _free_beat(first)
	var job := str(c.get("job", ""))
	var job_open := job != "" and WorldState.open_jobs("confidant").any(func(j): return str(j.id) == job)
	var say := line_of(c, "intro" if first else "remind")
	if job_open and not first:
		say = str(c.get("intro", ""))       # the job is on offer again: say what it is
	if job == "j_bounty" and job_open:
		say += " " + str(WorldState.job(job).get("text", ""))
	if say == "":
		return {}
	return { "say": say, "job": job if job_open else "" }


## After the fleet: a bounty contract whenever none is out, else nothing (she
## talks as usual, and the smuggling job is hers to offer).
static func _free_beat(first: bool) -> Dictionary:
	var c := chapter_cfg()
	var intro := str(c.get("intro_dark" if DarkPact.town_retaken() and c.has("intro_dark") else "intro", ""))
	var lead := intro + " " if first else ""
	if WorldState.open_jobs("confidant").any(func(j): return str(j.id) == "j_bounty"):
		return { "say": lead + str(WorldState.job("j_bounty").get("text", "")), "job": "j_bounty" }
	return { "say": lead.strip_edges(), "job": "" } if lead != "" else {}


## Extra lines for the teller's model briefing: what the story wants right now.
static func brief(teller: String) -> String:
	var c := chapter_cfg()
	if str(c.get("teller", "")) != teller:
		return ""
	var out := line_of(c, "remind")
	if chapter() == "smuggle_1" and not WorldState.has_flag("pit_jetpack_taken"):
		out += " " + str(c.get("jetpack_hint", ""))
	return out.strip_edges()


## A chapter's line; "%d" in it is how many droids the droid merchant still needs.
static func line_of(c: Dictionary, key: String) -> String:
	var s := str(c.get(key, ""))
	if s.contains("%d") and c.has("deliver"):
		s = s % droids_wanted()
	return s


# ------------------------------------------------------------------ the droid merchant (issue #212)

## Cargo droids Oda's friend still needs (0 outside that chapter).
static func droids_wanted() -> int:
	var d: Dictionary = chapter_cfg().get("deliver", {})
	return maxi(0, int(d.get("count", 0)) - WorldState.count("merchant_droids")) if not d.is_empty() else 0


## The kind of droid the merchant wants now, or "".
static func droid_wanted_kind() -> String:
	return str(chapter_cfg().get("deliver", {}).get("kind", "")) if droids_wanted() > 0 else ""


## One droid of that kind handed over at a droid post. The last one ends the
## chapter, and Oda's job card for it (taken or not).
static func on_droid_delivered() -> void:
	if droids_wanted() <= 0:
		return
	WorldState.bump("merchant_droids")
	WorldState.log_event("Delivered a droid to Oda's friend, the droid merchant.")
	if droids_wanted() == 0:
		var job := str(chapter_cfg().get("job", ""))
		if job != "" and not WorldState.jobs_taken.has(job):
			WorldState.jobs_taken[job] = "active"
		WorldState._complete_jobs("droids_delivered")
		event("droids_delivered")


## Oda's mood after a line (or when the player takes her job). In the first
## smuggling run, amused or warm, she lent the player her jetpack, once, while
## the chapter had a "jetpack_line". Issue #210: it has none now (she tells you
## about the one hidden on top of the cantina tower). Returns her line about it, or "".
static func on_owner_mood(mood: String) -> String:
	if chapter() != "smuggle_1" or WorldState.has_flag("story_jetpack_given") or not mood in ["amused", "warm"] \
			or str(chapter_cfg().get("jetpack_line", "")) == "":
		return ""
	WorldState.set_flag("story_jetpack_given")
	if not WorldState.inventory.has(JETPACK):
		WorldState.inventory.add(JETPACK)
	WorldState.log_event("Oda lent out her old jetpack.")
	return str(chapter_cfg().get("jetpack_line", ""))


## Oda has bounty contracts: the story's first one, then after the fleet, on repeat.
static func bounties_open() -> bool:
	return chapter() in ["bounty", "free"]


# ------------------------------------------------------------------ the Remnant

## The port's ships fly (Oda told you about the fleet).
static func ships_unlocked() -> bool:
	return WorldState.has_flag("ships_unlocked")


## The fleet is beaten: the garrison has left town (the barracks are the locals'
## until the Remnant take them back) and the general wears the desert armour.
static func remnant_gone() -> bool:
	return WorldState.has_flag("remnant_fleet_beaten")


## What is left of the Remnant shoots on sight: the fleet is beaten and you did not
## swear the dark master's oath (issue #303: with it they are on your side).
static func remnant_hostile() -> bool:
	return remnant_gone() and not DarkPact.joined()


## The Remnant hold the town's barracks (issue #187: until the story is done or
## they are driven off; then the locals do, Territory.owner).
static func town_garrison() -> bool:
	return Territory.owner(Territory.BARRACKS) == Territory.REMNANT


## Issue #193: the cruiser's general is dead; nobody is left aboard.
static func cruiser_taken() -> bool:
	return WorldState.has_flag("cruiser_taken")


## Oda has sent you after the general and the cruiser is not taken yet: climbing
## out meets its escort, the fleet's fighters.
static func cruiser_mission() -> bool:
	return chapter() == "fleet" and not cruiser_taken()


static func remnant_cfg() -> Dictionary:
	return data().get("remnant", {})


static func line(key: String) -> String:
	return str(data().get(key, key))


static func bounty_cfg() -> Dictionary:
	return data().get("bounty", {})


## What the outpost is called in a line ("the dry wash outpost"): its location's label.
static func outpost_label(id: String) -> String:
	var f := FileAccess.open("res://content/core/locations/%s.json" % id, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return str(d.get("label", id)) if d is Dictionary else id


## The bounty target's soldier profile (content/core/soldiers/bounty_target.json).
static func target_profile() -> Dictionary:
	var f := FileAccess.open("res://content/core/soldiers/bounty_target.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d if d is Dictionary else {}


static func target_naming() -> Dictionary:
	return target_profile().get("naming", {})
