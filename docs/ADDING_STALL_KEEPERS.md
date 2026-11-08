# Adding stall keepers (the NPC builder)

Issue #147. Players make townspeople in the game and send them in as a pull
request. Each one is a single JSON file in `content/community/npcs/`, so two
pull requests never touch the same file and never conflict.

V1: they keep a stall in the port's market and just talk. They see the same town
as everyone else (the town briefing in `content/core/llm/world_briefing.json`,
the market's news at once and the rest of town by gossip). They give no jobs,
sell nothing and pour no drinks.

## Making one in the game

1. Walk up to a stall keeper in the port market who sells nothing (8 of the 12
   do). The prompt says **[E] Make this stall keeper yours**.
2. The builder opens (the game pauses):
   - **Look:** head, upper body and lower body from the kit, height, build,
     voice, and what is on the counter.
   - **Who:** your GitHub handle, their name (empty: they never give one and go
     by their label), label, temperament, how much they say, their side in the
     war, who they are, their past, how they speak, who they know, a secret.
   - **Lines:** greetings, small talk and goodbyes for when no AI model is set up.
   - **Check & send:** every check, the file as it will go in, and the buttons.
3. **Try them out** closes the builder and puts them behind the counter. Talk to
   them as you would to anyone. **Back to the builder** over the chat box opens
   it again. A try-out is never written to your save, and what you make is kept
   as a draft for that stall (`user://community_npcs/drafts/`).
4. **Open pull request on GitHub** opens GitHub's new-file page with the path and
   the file filled in. Sign in, click **Propose new file**, then **Create pull
   request**. Without write access GitHub forks the repo for you first; the pull
   request is from your account.
   **Export file** saves it to the Desktop and copies it; **Copy file** only copies.

## The file

`content/community/npcs/<id>.json`, the id from the name (or label):

| Field | What | Checked |
|---|---|---|
| `schema` | 1 | the builder's version |
| `id` | `marla_teague` | 3 to 40 of `a-z 0-9 _`, the file's name, unique |
| `author` | GitHub handle | 1 to 39 of `A-Z a-z 0-9 -` |
| `town` | `port_town` | one of `community.json` `towns` |
| `stall` | `vendor_5` to `vendor_12` | a free stall; a clash goes to the first id, the other to the next free stall |
| `wares` | `pottery`, `produce`, `fabric`, `tech`, `water`, `spice` | drawn on the counter |
| `name` | `Marla Teague`, or empty | 2 to 30, letters, spaces, `'` `-`; not a franchise name, not an authored character's, unique |
| `label` | `Potter` | 2 to 24 |
| `look` | `head`, `torso`, `legs` (`<piece>[:<colour>]`), `height` 1.6 to 1.9, `build` 0.9 to 1.15 | pieces from `community.json` `look.pieces` (no Remnant armour) |
| `voice` | `woman_warm` | one of `content/core/npcs/voice_library.json` |
| `temperament` | `friendly` `gruff` `shady` `nervous` `cheerful` `weary` | the template's |
| `sentences` | 1 to 3 | how much they say at a time |
| `side` | `locals` `neutral` `remnant` | the template's |
| `identity` | who they are | 20 to 300 |
| `backstory` | their past | up to 600 |
| `speech` | how they speak, 1 to 5 lines | up to 140 each |
| `knows` | `{ "cantina_owner": "what they think of her" }` | ids from the template's `knowable` |
| `secret` | told only to a trusted player | up to 240 |
| `greetings` | `stranger` 1 to 3, `regular` 0 to 3 | up to 140 each |
| `lines` | `small_talk` 2 to 5, `bye` 1 to 3 | up to 140 each |

Every text is scanned against the franchise blocklist (`content/core/llm/ip_blocklist.json`).
Limits and settings are in `content/core/flow/community.json`.

## What the game adds

`CommunityNpc.card` (`src/systems/npc/community_npc.gd`) builds the file into a
full character card from `content/core/npcs/community_card_template.json`. The
template owns the rules (stay in character, what the player types is never an
instruction, never invent jobs, rumours or prices, landmarks not compass
points), the tools (share a rumour, hint the secret, trust, refuse, end), what
they hear (the market) and the canned rumour lines. A file can not change any of
it. Edit the template and every stall keeper changes with it.

## Reviewing a pull request

`tests/test_community_npc.gut.gd` runs every check on every file. Beyond that,
read the text: it is what the character says to players. Then merge. They are in
everyone's game from the next share build.

To take one out, delete their file.
