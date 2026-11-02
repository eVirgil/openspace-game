# Sharing a build (Windows and Mac)

How to build the slice for someone on Windows or a Mac and what to send them. The
shared build talks to Anthropic directly for Oda and Skrugs; the player brings
their own key and pastes it in F10. No key is ever in the build.

## What is different in the shared build

The **Windows Share** and **macOS Share** presets in `export_presets.cfg` add the
export feature `share`. With it, `LLMConfig.default_path()` loads
`content/core/llm/defaults_share.json` instead of `defaults.json`:

- the chain is cloud only (no local llama-server, no Ollama to wait on),
- the cloud profile is `anthropic` against `https://api.anthropic.com/v1`, switched on,
- transcripts are not logged.

The editor and CI never have the `share` feature, so they keep the normal defaults.

## Build it (macOS)

Once: install the Godot 4.7.2 export templates (editor: Editor > Manage Export
Templates > Download and Install, or unpack the official `.tpz` into
`~/Library/Application Support/Godot/export_templates/4.7.2.stable/`). Windows
needs `windows_release_x86_64.exe` from it, the Mac build `macos.zip`.

```sh
./scripts/package.sh            # both
./scripts/package.sh windows    # builds/OpenSpace-windows.zip
./scripts/package.sh mac        # builds/OpenSpace-mac.zip
```

`builds/` is git-ignored. Send the zip for the player's machine.

The Mac build is one universal app (Apple Silicon and Intel), signed ad hoc only:
there is no Apple Developer ID, so it is not notarized and macOS warns about it
the first time (below).

Before sending, set a spend limit on the Anthropic key in the Anthropic console.
Send the key separately (password manager or a private message), never inside
the zip.

## For the player (Windows)

1. Unzip `OpenSpace-windows.zip` anywhere.
2. Run `OpenSpace.exe`. Windows SmartScreen warns about an unknown app
   because the build is not signed: click **More info**, then **Run anyway**.
3. Set the key (below).

The key is saved in `%APPDATA%\Godot\app_userdata\Desert Spaceport Slice\llm\keys.cfg`,
outside the game folder.

## For the player (Mac)

1. Double-click `OpenSpace-mac.zip` and drag `OpenSpace.app` into
   **Applications**.
2. Open it. macOS says it cannot check the app for malware: click **Done**, open
   **System Settings > Privacy & Security**, scroll down, click **Open Anyway**
   next to OpenSpace, and confirm. Only the first launch asks.
   (Or in Terminal: `xattr -dr com.apple.quarantine /Applications/OpenSpace.app`.)
3. Set the key (below).

The key is saved in
`~/Library/Application Support/Godot/app_userdata/Desert Spaceport Slice/llm/keys.cfg`,
outside the app.

## Setting the key (both)

1. In game, press **F10**, paste the Anthropic key into **Cloud key**, press
   **Save**, then **Test** ("OK via cloud ..." means it works), then **Close**.
   Leave the other fields as they are.
2. Talk to Oda in the cantina or Skrugs outside the back gate (**E**). The top
   right says which brain is answering; "(canned: no brain answered)" means the
   key or connection is not working.

Controls are in `LAUNCH.md`. Neither build is routinely tested; report anything
odd (crash on start, black screen, missing text).
