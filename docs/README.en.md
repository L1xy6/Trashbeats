# TrashBeats

**Make instruments from everyday objects, then build a beat with them.**

[中文](../README.md) · [Windows download](https://github.com/L1xy6/Trashbeats/releases) · [Build guide](BUILDING.md)

TrashBeats is a Godot music-making prototype developed by MTX music-interaction online group 1. Record an object being tapped, turn the recording into a short percussion sample, and arrange it in a step sequencer. Four synthesized sounds let you try the workflow without a microphone.

![TrashBeats step sequencer](images/sequencer.png)

## Try it

Download the Windows ZIP from Releases, extract it, and run `Trashbeats.exe`. The current interface is in Chinese.

1. Click **编曲** (arrange) in the bottom navigation, then **新建编曲** (new arrangement).
2. Choose **4/4 · 16 格**. Click steps 1, 5, 9 and 13 in the first row and steps 5 and 13 in the second row.
3. Click **播放** (play), then **智能续写** (continue the pattern). Edit the result or use **取消智能续写** to undo it.

Left-click toggles a note. Drag an existing note vertically to change pitch. Right-click removes it. Patterns are saved locally.

## Features and boundaries

- Four procedural object sounds, recorded custom sounds, optional local pictures and favorites.
- Local sample processing and denoising.
- Multiple arrangements, a 16-step grid or 12-step triplet subdivision, tempo and pitch editing.
- Offline, rule-based continuation from your notes. It does not run a trained Music Transformer.
- WAV backing-track import, waveforms and adjustable beat alignment.
- Rhythm recording and separate microphone recording with WAV export. Rhythm exports do not combine all backing and microphone tracks into one final song.
- An optional Tianqin cloud melody integration. It requires your own authorized credentials and has not been tested online for this release.

This is a course prototype, validated primarily on Windows. Camera recognition, mobile delivery and multiplayer remain proposal ideas. Other platform export presets are experimental. The audio engine currently has 12 instrument slots. Hardware microphone capture has not been tested as part of automated checks.

## Development

Use [Godot 4.7.1 Standard](https://godotengine.org/download/archive/4.7.1-stable/). Import `project.godot` from the repository root and press F5. See [BUILDING.md](BUILDING.md) for command-line instructions, isolated tests and exports.

## Team and rights

The defense credits 苏泓熹 (concept, prototype/visual direction and denoising), 刘小勇 (proposal, planning and playtesting), 汪景程 (implementation, generation/arrangement features and demonstration), and 李之乔 (playtesting, onboarding feedback and presentation). See the [Chinese README](../README.md) and [version history](VERSION_HISTORY.md) for context.

Original source code is available under the [MIT License](../LICENSE). Keep copyright and permission notices when redistributing. Third-party components have their own licenses, documented in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
