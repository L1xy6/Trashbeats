# Source version history

This repository starts from the supplied `最终软甲n/godot08030040（答辩最终版` project. The selection was based on source comparisons and the contents of the existing Windows builds, not only folder names or timestamps.

The paths below describe the original material relative to its supplied `MTX` folder. Those archives, binaries, editor caches and private working documents are not part of this source repository.

| Original material | What differs | Decision |
|---|---|---|
| `trashbeats/godot07310120/` | Earlier project with custom percussion sounds, favorites, saved arrangements and optional cloud melody integration. | Historical source. |
| `trashbeats/godot080201（编曲界面仍优化中.zip` | Adds a separate microphone recording track, its playback/export/persistence, undo for local smart continuation, and clearer pixel rendering. | Intermediate source. |
| `godot080201（编曲界面仍优化中 (1).zip` | Byte-for-byte identical to the previous ZIP. | Duplicate archive. |
| `最终软甲n/godot08030040（答辩最终版/` | Adds three independently scrolling, resizable areas for rhythm, melody and microphone recordings. | Canonical source used here. |
| `Last/Trashbeats.exe` | Contains the microphone-track and undo additions, but lacks the final source's three-pane layout. | Intermediate build, despite the `Last` folder name. |
| `testing/trashbeats07310120win.exe` | Lacks the later microphone-track and undo additions. The EXE inside the accompanying ZIP is identical. | Earlier build; ZIP is a packaging duplicate. |

## Why this is the canonical source

Only two meaningful files differ between the 080201 archive and 08030040 source:

- `scripts/screens/sequencer.gd` adds nested vertical split containers and separate scrolling areas. It also rebuilds rhythm and microphone recording controls inside their respective areas.
- `export_presets.cfg` changes the original Windows output path. This does not add an application feature.

The audio engine, saved-project data, sound library, recording tools, font and shaders otherwise match between those versions. The final folder therefore preserves the intermediate functionality while adding the later arrangement layout.

Compared with 07310120, eight meaningful files changed: the sequencer, audio engine, state storage, UI helpers, CRT shader, project settings, export settings and README.

## How the existing builds were checked

The embedded resource tables were read without launching the supplied applications. Compiled-script payload hashes were checked, then known identifiers were inspected in their decompressed token buffers. Both builds identify Godot 4.7.1.

The `Last` build contains microphone playback, microphone persistence and continuation-undo identifiers. It lacks `_rhythm_vb`, `_mic_vb` and `VSplitContainer`, which appear in the final source. This establishes that it is not a build of the final arrangement interface; it does not establish complete byte-for-byte equivalence to the intermediate source archive.

## Preparing this repository for publication

The supplied README described an older design. Documentation here is based on the implemented code: microphone sampling with an optional local image, a sound library and saved arrangements. Camera-based material recognition and community ensemble are not implemented in this snapshot. Local rule-based continuation and optional cloud melody generation are separate features.

The supplied sources and Windows builds contained embedded cloud-service credentials. They were excluded from the public source and existing binaries were not reused as releases. Any distributed build must be produced from the sanitized source. Editor caches, personal recordings, backups and original archives are also excluded.

This history records the supplied snapshots. Subsequent fixes, documentation changes and releases are tracked by this repository's Git history.
