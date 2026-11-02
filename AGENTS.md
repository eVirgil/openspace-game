# Agents

Notes for AI agents working in this repo. Start with `README.md` (how to run,
layout, the IP rule), then `PLAN.md`, `DECISIONS.md` (why things are built the
way they are) and `KNOWN_ISSUES.md`.

## Skills

| Skill | Use it for |
|---|---|
| [`write-issue`](.claude/skills/write-issue/SKILL.md) | Writing, scoping or splitting a GitHub issue from what the player wants, and the PR that closes it. Checks open issues and recent PRs first, builds the request out of the game's existing parts (planets, towns, cantinas, outposts, native packs, the NPC kit) so every issue is a variation of something that exists, asks follow-up questions for must-haves and could-haves, keeps new renders to a minimum, lists what the architecture does not let an issue change, and gives the issue and PR formats (both open with the user's ask, quoted; screenshots for anything visual). |
| [`build-share-files`](.claude/skills/build-share-files/SKILL.md) | Building the Mac and Windows share builds from GitHub. Always asks which version first (the most recent is in `project.godot`): a new base version (`OpenSpace V1.4`, bumped in a PR and noted in the changelog as "New version is 1.4") or a feature demo (`OpenSpace V1.3 - Weapon Wheel`, no changelog). Puts the zips and the Mac app on the Desktop and writes the copy-paste list of what is new, by category. |

## Ground rules

- **Data first.** Names, dialogue, weapons and numbers live in `content/core/`,
  looks in `content/look/`. No franchise names anywhere
  (`tests/test_ip_neutral.gut.gd` fails the build).
- **One feature per branch** (`feature/...`, `fix/...`), merged by PR.
- **Reuse before building.** The parts list and the things that can not change
  are in the `write-issue` skill; they apply to building as much as to writing
  issues.
