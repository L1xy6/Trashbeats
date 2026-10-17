# Run and build TrashBeats

[中文](BUILDING.md) · [English overview](README.en.md)

## Play the Windows preview

Download [Trashbeats for Windows x64](https://github.com/L1xy6/Trashbeats/releases/download/v0.1.0-preview.1/Trashbeats-0.1.0-preview.1-windows-x86_64.zip) (~38 MB), extract the ZIP, and run `Trashbeats.exe`. Godot, an account and API credentials are not required for the offline sequencer. This is an unsigned course prototype with a Chinese interface. The release includes `START-HERE.txt` in both languages.

## Open the source

Install [Godot 4.7.1 Standard](https://godotengine.org/download/archive/4.7.1-stable/). In the project manager, choose **Import**, select the repository's root `project.godot`, wait for import, and press **F5**. No .NET installation is needed.

If Godot is on PATH:

```sh
git clone https://github.com/L1xy6/Trashbeats.git
cd Trashbeats
godot --headless --editor --path . --import
godot --path .
```

The interface uses a system CJK font. Windows normally supplies Microsoft YaHei. On Linux, install a font such as Noto Sans CJK if Chinese characters are missing.

## Checks

Run the following in PowerShell from the repository root, replacing the executable path with yours:

```powershell
./tests/run_smoke.ps1 -Godot 'C:\Tools\Godot_v4.7.1-stable_win64_console.exe'
```

The runner copies the project to a temporary folder, isolates save data, disables audio input and clears cloud credentials in the child process. It checks synthesis, sample processing, save/load behavior, projects, grid editing, pattern continuation/undo and missing-credential behavior. It does not call a cloud service or test physical microphones. Do not run the smoke scene directly with normal user saves.

With Python 3, `python tools/check_publish.py` checks repository hygiene and local Markdown links. [GitHub Actions](https://github.com/L1xy6/Trashbeats/actions/workflows/checks.yml) runs these checks for every main-branch update and pull request.

## Export Windows

Install matching **4.7.1 export templates** through Godot's **Editor → Manage Export Templates**. Create `build/windows`, then:

```sh
godot --headless --editor --path . --import
godot --headless --path . --export-release "Windows Desktop" build/windows/Trashbeats.exe
```

Include the project MIT license, font OFL and Godot notices when distributing the binary. The repository's Linux, macOS and Web presets are experimental and have not had complete platform validation. This prototype disables microphone input on Web; do not assume the desktop feature set works unchanged in a browser.

## Optional cloud melody generation

Offline **智能续写** (pattern continuation) works without configuration. The separate Tianqin integration submits the entered style and lyrics to a third-party music-generation service. It requires your own authorized credentials and was not validated online for this preview.

Set `TRASHBEATS_TIANQIN_APP_ID` and `TRASHBEATS_TIANQIN_APP_KEY` in the app process environment. The app does not automatically read `.env`. Do not commit credentials or embed a shared key in a distributed client. A production integration should keep shared service credentials on a server you control.

## Saves and limitations

On Windows, normal saves live under `%APPDATA%\Godot\app_userdata\TrashBeats\`. Back up that folder before deleting data. Optional images for custom sounds refer to local file paths, so moving the image can break the attachment.

Rhythm WAV export captures the rhythm engine. It does not combine the separately playing backing melody and microphone track into a finished song. Device recording, online generation and complete cross-platform behavior need further manual testing.
