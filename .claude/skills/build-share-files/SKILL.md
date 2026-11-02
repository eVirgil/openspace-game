---
name: build-share-files
description: Build the Mac and Windows share builds of OpenSpace from GitHub, name them by version ("OpenSpace V1.3") or as a feature demo ("OpenSpace V1.3 - Weapon Wheel"), put the zips and the unpacked Mac app on the user's Desktop, and write the copy-paste list of what is new, by category, to send with them. Use whenever the user asks to build, rebuild, export, package or re-run the export, make the share files or zips, put a build on the Desktop, cut a new version, or make a demo build of a feature.
---

# Building the share files

The share files are three things: the two zips and the "what's new" list that
goes with them. The user sends all three to collaborators. Build from GitHub,
never from the main checkout (it is often on someone else's branch).

## 1. Ask what is being built

Every time, before building, with AskUserQuestion. First read the current
version, so the question can say "the most recent is X":

```bash
git fetch -q origin && git show origin/main:project.godot | sed -n 's/^config\/version="\(.*\)"$/\1/p'
```

```bash
git show origin/main:CHANGELOG.md | grep -m1 "^## New version is"
```

Ask (one question each, recommended option first):

- **Which version?** "The most recent is X." Options: the same version again,
  the next base version (1.3 -> 1.4), or a demo of a feature.
- **For a demo: which feature, and from which branch?** The label is a few
  words in the player's terms ("Weapon Wheel"). Its branch may not be merged yet.
- **Since when does the list start?** Default: the last share build (for a base
  version, the previous "New version is" entry). Times are Pacific.

Do not guess the version, even when the last build was the same one.

## 2. The two kinds of build

| | Base version | Feature demo |
|---|---|---|
| Name | `OpenSpace V1.4` | `OpenSpace V1.3 - Weapon Wheel` |
| Built from | `origin/main` | the feature's branch (or `origin/main` once merged) |
| Version number | bumped in `project.godot` | unchanged |
| Changelog | `## New version is 1.4 (YYYY-MM-DD)` | nothing |
| Repo change | a PR, merged before the build | none |

**A new base version** is a PR of its own (`release/v1.4`), following the PR
rules in [`write-issue`](../write-issue/SKILL.md) ("Writing the PR"): the body
opens with the user's words, quoted.

- Set `config/version="1.4"` in `project.godot`. It is the only place: the build
  names and the version stamped in both builds come from it.
- Add on top of `CHANGELOG.md`:

  ```markdown
  ## New version is 1.4 (2026-11-02)

  - Share builds are now **OpenSpace V1.4**. Everything below, down to "New
    version is 1.3", is in it.
  ```

- Read `README.md` and `docs/SHARING.md` for the old version or build names
  (the download section, the player steps, the `xattr` line) and update them in
  the same PR.
- Ask the user to merge, then build from the new `origin/main`.

**The same version again** needs no PR: build `origin/main` as it is.

**A demo** changes nothing in the repo and never goes in the changelog. The
label rides on the package script: `./scripts/package.sh all "Weapon Wheel"`.

## 3. Build

In a temporary worktree at the commit asked for, with the import cache copied
over so the export does not re-import everything:

```bash
W=<scratchpad>/build-share && git worktree add -q --detach "$W" <origin/main or origin/<branch>> && cp -R .godot "$W/.godot"
```

```bash
cd "$W" && ./scripts/package.sh all ["<label>"]
```

Run the build in the background; it takes a few minutes. It needs the Godot
4.7.2 export templates (`docs/SHARING.md`). If the user merges something while
it runs, stop it and start again from the new commit.

Check before going on: no `ERROR` in the log, both `package:` lines with a
size, and the Mac signature verifies (the script stops otherwise).

## 4. Put them on the Desktop

- Copy both zips to `~/Desktop` and `cmp` each against the build.
- Move older OpenSpace builds on the Desktop (`OpenSpace*.zip`, `OpenSpace*.app`,
  including Finder's `OpenSpace 2.app` copies) to `~/.Trash/"<name> (old HHMMSS)"`.
  Never `rm`. Leave the promo videos and anything that is not a build.
- Unpack the Mac app next to them, `ditto -x -k "<Mac zip>" ~/Desktop/`, and run
  `codesign --verify --deep` on it.
- Remove the worktree (`git worktree remove --force "$W"`) and fetch again: if
  `main` moved during the build, say so.

## 5. Write the list

The list is what the user pastes to collaborators, so it goes in the reply as
one fenced block, not in a doc or a file.

```bash
gh pr list --state merged --base main --limit 100 --json number,title,mergedAt \
  --jq '.[] | select(.mergedAt >= "<start, UTC>") | "\(.mergedAt) #\(.number) \(.title)"' | sort
```

For a demo built from an unmerged branch, add that branch's PR on top.

```
OpenSpace V1.3 - what's new (15 PRs, Nov 1 5am - 10pm PT)

Combat & weapons
- Weapon wheel: hold Tab, point with mouse/WASD/arrows, let go to draw (#412)

Ships & flight
- ...
```

- One line per PR in the player's terms, with its number. Rewrite the PR
  title if it reads like code.
- Categories, in this order, with empty ones left out: Combat & weapons; Ships
  & flight; World, factions & map; Story & characters; UI & quality of life;
  Audio; AI mode; Builds, promo & docs.
- A demo leads with its feature, on its own line under the title.
- The heading says the version or demo name, how many PRs and the time window.
  Name a PR that sits right on the window's edge and say which side you put it.

Then tell the user, in a few lines: the file names on the Desktop, the commit
they were built from, what went to the Trash, and that nobody has played the
build yet.
