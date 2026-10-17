# TrashBeats

**Make instruments from everyday objects, then build a beat with them.**

[中文](../README.md) · [**Download for Windows**](https://github.com/L1xy6/Trashbeats/releases/download/v0.1.0-preview.1/Trashbeats-0.1.0-preview.1-windows-x86_64.zip) · [Build guide](BUILDING.en.md)

TrashBeats is a Godot music-making prototype developed by MTX music-interaction online group 1. Record an object being tapped, turn the recording into a short percussion sample, and arrange it in a step sequencer. Four synthesized sounds let you try the workflow without a microphone.

**Windows x64 · ~38 MB · unzip and run · no Godot installation required · Chinese UI · MIT** · [Release notes](https://github.com/L1xy6/Trashbeats/releases/tag/v0.1.0-preview.1)

[Hear an 8-second example (WAV, ~0.7 MB)](audio/quickstart-before-after.wav). The first four seconds play the quick-start seed pattern; the next four play its continuation. This is actual app output using procedural presets, not recorded objects.

![TrashBeats step sequencer](images/sequencer.png)

The screenshot’s “AI 模式” label refers to offline rules. Cloud melody generation is a separate, optional integration.

## Try it

Download the [Windows ZIP](https://github.com/L1xy6/Trashbeats/releases/download/v0.1.0-preview.1/Trashbeats-0.1.0-preview.1-windows-x86_64.zip), extract it, and run `Trashbeats.exe`. The current interface is in Chinese.

1. Click **编曲** (arrange) in the bottom navigation, then **新建编曲** (new arrangement).
2. Choose **4/4 · 16 格**. Click steps 1, 5, 9 and 13 in the first row and steps 5 and 13 in the second row.
3. Click **播放** (play), then **智能续写** (continue the pattern). Edit the result or use **取消智能续写** to undo it.

Left-click toggles a note. Drag an existing note vertically to change pitch. Right-click removes it. Patterns are saved locally.

## Make an instrument from an object

1. Open **寻宝** (sound collection). Enter a name and click **录制** (record).
2. Tap your object, click **停止** (stop), then **确定** (save). An image is optional.
3. Open your arrangement through **编曲**, then **添加轨道** (add track) and select the saved sound.
4. Place notes and play. The rhythm section’s **录制** (record) captures the beat. Stop recording, then click **保存** (save) in the recorded-clip row to export WAV. This exports the rhythm, not a combined backing/microphone mix.

If you do not have a microphone, the preset workflow above still works. Use headphones while recording to avoid recording speaker playback.

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

Use [Godot 4.7.1 Standard](https://godotengine.org/download/archive/4.7.1-stable/). Import `project.godot` from the repository root and press F5. See [the English build guide](BUILDING.en.md) for command-line instructions, isolated tests and exports.

## Team and rights

The defense credits 苏泓熹 (concept, prototype/visual direction and denoising), 刘小勇 (proposal, planning and playtesting), 汪景程 (implementation, generation/arrangement features and demonstration), and 李之乔 (playtesting, onboarding feedback and presentation). See the [Chinese README](../README.md) and [version history](VERSION_HISTORY.md) for context.

Original source code is available under the [MIT License](../LICENSE). Keep copyright and permission notices when redistributing. Third-party components have their own licenses, documented in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
