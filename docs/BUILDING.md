# 运行、测试和构建

## 环境

- Godot **4.7.1 Standard**，项目使用 GDScript，不需要 .NET。
- Windows 是本次发行验证的平台，界面使用系统中文字体。Linux 可安装 Noto Sans CJK 以避免中文缺字。
- 导出程序需要与编辑器版本一致的 **4.7.1 export templates**，在 Godot 的 **Editor → Manage Export Templates** 中安装。
- 源码不包含 Godot 引擎安装包。下载地址：https://godotengine.org/download/archive/4.7.1-stable/

## 不熟悉命令行

下载仓库右上角 **Code → Download ZIP**，解压。打开 Godot，点 **Import**，选择本仓库根目录的 `project.godot`，等资源导入完成，按 **F5** 运行。

只想试玩可以下载 [Windows release](https://github.com/L1xy6/Trashbeats/releases)，无需安装编辑器。

## 命令行运行

以下命令在仓库根目录运行，`godot` 指加入 PATH 的 Godot 4.7.1 可执行文件：

```sh
godot --headless --editor --path . --import
godot --path .
```

Windows PowerShell 也可以使用下载的完整路径：

```powershell
$godot = 'C:\Tools\Godot_v4.7.1-stable_win64_console.exe'
& $godot --headless --editor --path . --import
& $godot --path .
```

示例路径需要换成自己的安装位置。

## 自动化检查

在 PowerShell 中运行：

```powershell
./tests/run_smoke.ps1 -Godot 'C:\Tools\Godot_v4.7.1-stable_win64_console.exe'
```

脚本将项目复制到独立临时目录，使用独立存档和 Dummy 音频驱动，检查音色处理、项目保存、网格操作、续写和未配置服务的行为。它不会访问实际麦克风，也不调用云端接口。不要把测试场景当作正常项目启动场景直接运行。

源文件发布检查（Python 3）：

```sh
python tools/check_publish.py
```

## Windows 导出

安装对应 export templates 后，先创建 `build/windows` 目录，然后运行：

```sh
godot --headless --editor --path . --import
godot --headless --path . --export-release "Windows Desktop" build/windows/Trashbeats.exe
```

Windows 导出采用内嵌资源包。发行 ZIP 还应包含项目 MIT 许可、字体 OFL、第三方说明和 Godot 的引擎许可/版权声明。不要把旧版预编译 EXE 当作新源码的构建产物。

## macOS 导出

直接试玩见 [Mac 使用说明](MACOS.md)。在 Mac 安装匹配的 Godot 编辑器与 macOS export template 后，可运行：

```sh
python3 tools/build_macos.py --godot /Applications/Godot.app/Contents/MacOS/Godot
```

脚本导出 Universal 2 `.app`，检查 arm64/x86_64 架构、ad-hoc 签名、麦克风权限及无界面启动，再用 macOS `ditto` 打包以保留执行权限。产物位于 `dist/`，包含双语使用说明、许可与校验值。不要在 Windows 解压并重新压缩这个应用包。

[macOS 自动构建](https://github.com/L1xy6/Trashbeats/actions/workflows/macos.yml)在 Apple Silicon 上导出、在 Intel 上验证同一个 ZIP，两边都执行隔离离线检查。构建使用经 SHA256 核对的官方 Godot 4.7.1 下载文件。Apple Developer ID 签名与公证尚未配置；无需向构建提供 Apple 账号或证书。

## Web 和其他平台

Web 导出是实验性开发配置，不是本次已经验证的试玩方式。安装匹配的 Web 模板后：

```sh
bash build_web.sh
python -m http.server 8080 --directory build/web
```

Windows 可设置 `GODOT` 为可执行文件路径后运行 `build_web.bat`。脚本从自身所在目录定位项目，不依赖调用时的工作目录。

当前代码会在 Web 环境禁用麦克风录制。系统字体、文件选择/导入、文件下载、音频自动播放限制和存档行为需要单独适配与测试；不能把桌面功能列表当作浏览器支持保证。不要将服务密钥嵌入 Web 导出中。

Linux 预设未经过完整验证。macOS 的真实麦克风、扬声器、图形界面和不同系统版本仍需人工验证。

## 可选的云端旋律

离线「智能续写」使用本地规则算法，不需要下面的配置。天琴旋律生成是另一项功能：它向第三方服务提交使用者填写的风格和歌词，轮询生成任务并下载音频。

只有拥有合法接口权限的开发者才需要配置进程环境变量：

```powershell
$env:TRASHBEATS_TIANQIN_APP_ID = '<your-app-id>'
$env:TRASHBEATS_TIANQIN_APP_KEY = '<your-app-key>'
& $godot --path .
```

应用不会自动加载 `.env` 文件。凭据必须由使用者提供，不能写进源码、提交历史、打包产物或问题反馈。该集成仍使用原项目的测试服务地址，本次未验证在线服务可用性。面向公共产品的部署应通过自己的服务端处理凭据，而不是给客户端附带共享密钥。

## 存档与数据

正常运行的文件保存在 Godot 的 `user://` 目录中。Windows 默认位置为 `%APPDATA%\Godot\app_userdata\TrashBeats\`，包括项目、收藏、样本与录音。删除文件前先备份，这些文件不是仓库源码的一部分。

自定义音色的可选图片目前记录本机路径。移动或删除原图可能使配图不可用；跨电脑搬运作品不是已实现的一键功能。录音默认保存在本机，离线体验不需要联网。

## 测试边界

自动化检查覆盖程序逻辑、macOS 包结构和无界面启动，现有界面截图来自 Windows。实际麦克风、不同音频设备、云端生成以及完整跨平台图形操作仍需要人工验证。节奏 WAV 导出不包含独立播放的背景旋律和麦克风音轨。
