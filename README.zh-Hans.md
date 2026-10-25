# Sandy

<img src="Resources/AppIcon.png" alt="Sandy" width="160">

[English](README.md) · [Русский](README.ru.md) · [Қазақша](README.kk.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [Español](README.es.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md)

完整安装指南：[English](README.md) · [Русский](README.ru.md)。
手机访问功能尚在规划中。Sandy 基于采用 MIT 许可证的
[Cyclop](https://github.com/akalikbergenov/cyclop) 项目。

一款原生 macOS 工具，将 MacBook 的刘海区域变成工作面板。将指针移到刘海上，
即可打开媒体控制、文件架、剪贴板历史、常用文本、日历、翻译、货币换算、提词器和便笺。

**智能体**标签页通过本地辅助程序 `sandy-agent` 监视受支持的 Claude Code 和 Codex
会话，显示并行会话、当前操作以及按项目保存的统计信息。你可以选择启用回答就绪、等待输入
和错误通知。在设置中启用监视和来源；Claude 钩子仅通过专用按钮安装。
配置方法和限制见[智能体监视](docs/agent-monitor.md)（俄语）。

Sandy 由 Abdirakhym 维护，项目从 **0.1.0** 版本开始使用独立的 Git 历史。
第三方代码的来源说明记录在 `THIRD_PARTY_NOTICES.md` 中。

## 语言

界面支持英语、俄语、哈萨克语、德语、法语、西班牙语、简体中文和日语。
在“设置 → 通用 → 语言”中选择语言，面板会立即切换。“系统语言”跟随 macOS 的语言偏好。
系统权限对话框会在重启 Sandy 后使用所选语言。界面语言不会改变“翻译”标签页的语言对。

## 键盘快捷键

按 **Control + Option + 空格** 可在指针所在的屏幕上打开面板。再次按下快捷键、按 Esc
或点击其他应用即可关闭。使用键盘操作时，面板会保持打开。在“设置 → 通用”中可以选择
其他组合或关闭快捷键。此功能不需要辅助功能权限。

## 编译与运行

需要 macOS 15 或更高版本以及 Swift 6。安装 Xcode Command Line Tools 即可。
在项目目录中运行：

```sh
./Scripts/bundle.sh
open build/Sandy.app
```

本地构建使用 ad-hoc 签名。发布带有 Developer ID 签名并经 Apple 公证的版本，需要你自己的
Apple Developer 凭据，详见[签名指南](docs/signing.md)（俄语）。

```sh
./Scripts/test.sh        # 检查测试和翻译
./Scripts/test-helper.sh # 编译后检查媒体辅助程序
./Scripts/dmg.sh         # 创建 build/Sandy-0.1.0.dmg
```

版本号在 `Scripts/version` 中设置。使用 `Scripts/release.sh` 前，请配置自己的远程仓库。

## 数据与权限

- 应用标识符：`com.abdirakhym.sandy`。
- 设置、常用文本和便笺：`~/Library/Application Support/Sandy`。
- 剪贴板截屏：`~/Pictures/Sandy`。
- 日历和键盘锁定功能仅在使用时请求日历和辅助功能权限。
- 仅在启用智能体通知时请求通知权限。历史记录保存在
  `~/Library/Application Support/Sandy/Agents/history.json`；监视界面不保存提示词和回答。
- 翻译使用 macOS Translation 框架以及下载的语言包。
- 货币换算获取公开汇率。Spotify 的备用机制可能下载专辑封面。
  智能体统计信息保留在此 Mac 上；没有遥测或自动更新服务。

Sandy 使用自己的存储和设置，不会自动导入其他应用的数据。
详细说明见 [SECURITY.md](SECURITY.md)（俄语）。

## 开发

SwiftUI 和 AppKit 代码位于 `Sources/Sandy`，媒体辅助程序位于 `Sources/SandyMediaHelper`。
翻译和图标位于 `Resources`，构建与打包脚本位于 `Scripts`。

更改行为之前，请阅读[架构说明](docs/architecture.md)（英语）、
[贡献指南](CONTRIBUTING.md)和[发布检查清单](docs/release-checklist.md)（俄语）。
Now Playing 使用 macOS 私有框架和系统 Perl 辅助程序，未来的 macOS 更新可能需要适配。
此应用不适合通过 App Store 分发。

## 许可证

[MIT](LICENSE)。分发源代码或应用时，请保留许可证及第三方代码声明。
应用包中的相关文档位于 `Sandy.app/Contents/Resources`。
