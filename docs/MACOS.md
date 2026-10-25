# TrashBeats 0.1.0 预览版 · macOS

支持 Apple 芯片（M 系列）和 Intel Mac，同一个 Universal 2 应用。系统最低要求为 macOS 11；旧系统与不同音频设备的完整兼容性仍需实际测试。界面为中文，内置中文与图标字体，无需安装 Godot 或额外字体。

## 打开

1. 在 Mac 上完整解压 `Trashbeats-0.1.0-preview.1-macos-universal.zip`，将 `Trashbeats.app` 拖到「应用程序」。请直接传输 ZIP，不要在 Windows 解压 `.app` 后再发送，以免丢失执行权限。
2. 双击打开。本版只有 ad-hoc 签名，尚未通过 Apple 公证。如果提示无法验证开发者，确认文件来自本项目后，在「系统设置 → 隐私与安全性」中找到本应用的「仍要打开」，再确认打开。不要关闭整个系统的安全保护。
3. 进入「编曲 → 新建编曲 → 4/4 · 16 格」，点格子放音符，点「播放」。内置音色与「智能续写」离线可用。
4. 想录自己的声音时，再到「寻宝」或编曲麦克风区点击「录制」，允许系统的麦克风请求。拒绝过权限可在「隐私与安全性 → 麦克风」中调整，然后重新打开应用；没有麦克风也能使用预置音色。

存档在 `~/Library/Application Support/Godot/app_userdata/TrashBeats/`。卸载前如需保留作品，请备份这个目录。节奏 WAV 导出不包含独立的背景音乐和麦克风轨混音。

如果系统提示「已损坏」或「会损坏电脑」，先停止打开，重新从项目 Release 下载并核对 `SHA256SUMS-macos.txt`，反馈完整提示；本说明不建议用删除隔离属性的命令绕过这种提示。

此包使用固定版本的官方 Godot 模板导出。自动流程检查双架构、签名完整性、麦克风权限声明、离线逻辑和无界面启动；不代表已完成真实麦克风、扬声器、图形界面或所有 macOS 版本的人工测试。云端旋律功能仍需自己的接口权限，未进行在线验证。

## English

One Universal 2 app for Apple Silicon and Intel Macs; macOS 11 or newer. Chinese and icon fonts are bundled; no Godot or extra font installation is required. Older OS releases and different audio devices still require manual compatibility testing.

1. Extract the entire ZIP **on your Mac**, then move `Trashbeats.app` to Applications. Transfer the original ZIP rather than an app folder unpacked on Windows, which can lose executable permissions.
2. Open the app. This preview is ad-hoc signed, **not Apple-notarized**. If the developer cannot be verified, confirm that the file came from this project, then use **System Settings → Privacy & Security → Open Anyway** for this app. Keep system security protection enabled.
3. Choose **编曲 → 新建编曲 → 4/4 · 16 格**, place notes and press **播放**. Preset sounds and **智能续写** work offline.
4. Grant microphone access only when you choose to record. If previously denied, review **Privacy & Security → Microphone** and restart the app. Preset sequencing does not require a microphone.

Saves: `~/Library/Application Support/Godot/app_userdata/TrashBeats/`. Back up this folder to keep your work. Rhythm WAV export does not mix in the independent backing melody or microphone track.

If macOS reports that the app is damaged or will harm your computer, stop and re-download from this project's release, check `SHA256SUMS-macos.txt`, and report the exact alert. Do not globally disable Gatekeeper.

The build workflow checks both binary architectures, signature integrity, microphone declarations, offline logic and headless startup. These checks do not validate physical microphones, speaker output, graphical interaction, every macOS release or the optional online melody service.

## Links / 链接

- Project and source: https://github.com/L1xy6/Trashbeats
- Downloads: https://github.com/L1xy6/Trashbeats/releases/tag/v0.1.0-preview.1
- Apple first-open guidance: https://support.apple.com/en-us/102445
- Godot macOS distribution: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html
