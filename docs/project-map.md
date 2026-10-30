# Tess 项目架构与目录地图

核对日期：2026-10-25。根目录 `/Users/caine/Documents/Project/Faster` 沿用早期 Faster 项目名，当前产品名为 Tess；本轮保留根目录名称，已按功能迁移文档与本机产物，GitHub 仓库于 2026-10-25 统一为公开的 `cainebaode/Tess`，源码与 Releases 一起维护。

## 当前项目是什么

一个原生 macOS 菜单栏应用，面向 Apple Silicon、macOS 26+。SwiftUI 负责界面，AppKit 负责窗口、菜单栏和系统交互；`AppModel` 集中调度会话和各服务。没有自建 Tess 账号服务器或云端中转。语音识别在本机运行；用户启用文字整理时，文字直接发给其配置的外部服务。

```mermaid
flowchart TD
    Entry["快捷键 / 菜单栏"] --> App["AppModel：会话调度"]
    App --> Voice["录音 → 本地识别 → 可选文字整理 → 输入或复制"]
    App --> Capture["屏幕快照 → 拖拽选区 → 原位标注 → 复制图片"]
    App --> UI["录音浮层 / 结果 / 设置 / 引导"]
    App --> Store["设置、结果与模型的本地存储"]
```

## 目录各管什么

| 目录／文件 | 作用 | 日常是否需要关注 |
| --- | --- | --- |
| `README.md` | 公开产品介绍、下载和文档入口 | 每次开始先看 |
| `docs/development.md` | 当前源码、开发和交付状态 | 开发与交付前核对 |
| `AGENTS.md` | 后续代理的项目工作约定 | 按其中指向的流程执行 |
| `docs/` | 固定流程、架构和目录说明 | 维护长期规则时使用 |
| `Tess/` | 当前应用工程，含源码、资源、独立检查和实际编译的第三方代码 | 主要开发区域 |
| `scripts/` | 构建、归档、打包、图标生成和各项检查脚本 | 按本轮任务选用 |
| `assets/branding/` | 品牌源素材；当前选定方案为 `tess-spirit/` | 修改品牌时使用 |
| `evidence/` | 按轮次保存的日志、截图、人工反馈、源码及配置快照 | 查证具体构建时使用，不属于应用源码 |
| `upstream/` | Talkify 与 speech-swift 的上游参考副本，保留在本机 | 研究来源时使用，不参与 GitHub 同步 |
| `.build/` | 按 cache/local/releases/models/verification/history/tools/logs 分组 | 各类独立存放，见下方清单 |
| `dist/` | 按版本／build 分组的交付输出；当前包含 build 25 本轮包与 build 14 历史包 | 不进入源码 Git；公开正式包经 Tess 的 Releases 分发，不代表最新安装版 |
| `docs/product/` | BRD、PRD | 查产品依据 |
| `docs/releases/` | 安装计划、发布进度与验收 | 记录交付过程 |
| `docs/history/` | 优化、品牌及旧 README 等历史材料 | 旧状态有时间边界 |

## 应用工程内部

工程入口：`Tess/Tess.xcodeproj`。这是单个 Tess App target；当前 Swift 检查程序由脚本独立编译运行，不是另一个应用产品。

| 模块 | 文件／目录 | 职责 |
| --- | --- | --- |
| 应用与窗口 | `TessApp.swift` | 启动、菜单栏、设置／结果窗口、截图编辑层、应用生命周期 |
| 会话协调 | `AppModel.swift` | 录音／识别／整理／交付／截图状态，取消和重试，调用界面与服务 |
| 快捷键 | `HotkeyService.swift` | Fn 与组合键、按下／释放、取消及会话中断后的恢复 |
| 录音 | `AudioRecorder.swift`、`AudioLevelMeter.swift` | 麦克风、音频缓冲、时长和音量 |
| 本地识别 | `ASRService.swift` | Qwen／Whisper 的模型管理、准备、中间与最终识别 |
| 常用词与校正 | `SpeechVocabulary.swift`、`SpeechVocabularyView.swift` | 本地词库与场景、可选校正的结构和片段校验、词条管理；修改与候选随结果保留 |
| 人工纠正学习 | `SpeechLearning.swift`、`SpeechLearningView.swift` | 纯听写改稿的局部差异、用户确认、独立本地记忆及按应用组合的识别提示；结果页与主动提交入口 |
| 短期输入观察 | `SpeechInputObservation.swift` | 验证真实插入后观察单个可访问输入框；范围、焦点、通知、权限与时限保护，未支持时主动提交 |
| 文字整理 | `TextService.swift`、`APIConfiguration.swift`、`TextPromptEditor.swift` | Fn 原文及两个提示词绑定入口，外部 API 配置、密钥引用及提示词库 |
| 外部输入 | `DeliveryService.swift` | 识别输入目标、粘贴、剪贴板回退及微信／ChatGPT 窗口兼容保护 |
| 原位截图 | `CaptureService.swift`、`ScreenshotSelection.swift`、`ScreenshotEditorView.swift` | ScreenCaptureKit 快照、选区坐标、调暗层、标注、图片存储及复制 |
| 本地存储 | `LocalStore.swift` | 设置与结果文件、写入恢复及损坏文件的恢复副本 |
| 界面 | `SettingsView.swift`、`OnboardingView.swift`、`ResultView.swift`、`HUDView.swift` 等 | 设置、引导、结果与录音浮层 |
| 品牌与组件 | `Sources/Design/`、`TessMenuBarIcon.swift` | 颜色、精灵／字标、菜单栏及通用设置组件 |
| 内部诊断 | `HUDPreview.swift`、`ASRBenchmark.swift` | 内部检查入口，正式发行需确认相应入口未启用 |
| 检查 | `Tess/Checks/` | 交互、存储、快捷键、截图、输入等独立检查程序 |
| 随包资源 | `Tess/Resources/` | 图标、精灵图片、字体、帮助和第三方许可 |
| 本地依赖包 | `Tess/Vendor/SpeechSwift/` | 实际参与编译的 AudioCommon、MLXCommon、Qwen3ASR、WhisperASR 等源码 |

实际依赖链：Xcode 工程 → `Tess/Vendor/SpeechSwift/Package.swift` → MLX Swift、Swift Transformers 等 Swift Package 依赖。解析后的检出副本位于 `.build/cache/SourcePackages/`。`upstream/` 只是保留的参考来源，不应误把它的源码改动当作 Tess 已接入。

品牌源素材在 `assets/branding/tess-spirit/`，`scripts/make-icon.swift` 将相应素材生成到 `Tess/Resources/`。基础模型不放进源码资源目录，而是在正式归档时从 `.build/models/qwenSmall/` 嵌入 App 的 `Contents/Resources/BaseSpeechModel.tessmodel/`。

## 用户数据不在项目目录里

正常运行的数据目录为 `/Users/caine/Library/Application Support/Tess/`：

- `preferences.json`：偏好、快捷键及引导状态。
- `recent.json`、`draft.json`：最近结果和草稿。
- `api-configurations.json`：文字服务配置；API Key 本身在 macOS Keychain。
- `Models/`：用户主动下载的模型；有效下载模型优先，否则可使用随包基础模型。
- `Captures/`：选区图片暂存；`Recovery/`：存储恢复副本。
- `Diagnostics/input.json`：最近 100 条自动输入状态，包含应用标识、build、系统错误码及有限角色信息，不包含录音、转写、输入框正文或剪贴板内容。

应用安装路径为 `/Applications/Tess.app`。2026-10-25 曾按用户要求卸载，之后重新安装 build 25，再依次更新至 build 36。当前界面见 [磨砂材质与界面优化](releases/20261025-09-tess-frosted-settings-ui.md)，八个默认提示词见 [提示词模板记录](releases/20261025-08-tess-settings-and-prompt-templates.md)。项目候选、归档、正式 DMG 和用户数据是不同位置，更新安装不等于重置用户数据。

## 本机产物与回退

**2026-10-25 后续变更：** 用户要求全部卸载重装时，下表中的 `.app` 副本曾被移除，运行数据曾移出原目录；原位置与过程保存在本机 `evidence/20261025-tess-uninstall/removed-applications.json`，详见 [卸载记录](releases/20261025-03-tess-local-uninstall.md)。之后本机重新安装 build 25。文字服务和原窗口输入迭代后安装 build 28，用户已确认 ChatGPT Fn 自动输入正常；三个语音入口与提示词库在 build 30 收敛，设置布局与模板优化后安装至 build 32，界面优化后安装至 build 34，增强玻璃可见度后安装至 build 35，再按用户反馈柔化边缘并统一材质至 build 36；build 35、build 34、build 32、build 30 和 build 28 保留，见 [当前迭代](releases/20261025-09-tess-frosted-settings-ui.md)；其余历史条目仍只说明原产物位置。

| 位置 | 内容 |
| --- | --- |
| `.build/local/0.2.0-build36/Tess.app` | 当前柔雾材质与边缘优化候选，已签名并安装；待人工观感确认 |
| `.build/local/0.2.0-build35/Tess.app` | 原生玻璃层候选；用户反馈整体不协调、边缘锐利，保留回退 |
| `.build/local/0.2.0-build34/Tess.app` | 上一轮弱磨砂候选；用户反馈玻璃感不足，保留回退 |
| `.build/local/0.2.0-build33/Tess.app` | 本轮材质检查过渡候选；剩余重分隔线已在 build 34 统一 |
| `.build/local/0.2.0-build32/Tess.app` | 上一轮设置页与八个提示词模板候选，保留为本轮回退 |
| `.build/local/0.2.0-build31/Tess.app` | 本轮界面检查过渡候选；保存按钮与模板误标已在 build 32 修复 |
| `.build/local/0.2.0-build30/Tess.app` | 上一轮三个语音入口与提示词库候选，保留 |
| `.build/local/0.2.0-build29/Tess.app` | 本轮过渡候选；编辑入口首次选中问题已在 build 30 修复 |
| `.build/local/0.2.0-build28/Tess.app` | 上轮稳定回退；用户已确认 ChatGPT Fn 自动输入正常 |
| `.build/local/0.2.0-build27/Tess.app` | 诊断版；ChatGPT 自动输入未通过，作为紧邻回退保留 |
| `.build/local/0.2.0-build26/Tess.app` | 早期文字服务候选，保留 |
| `.build/local/0.2.0-build25/Tess.app` | 本轮更新前从已安装应用保留的回退副本 |
| `.build/local/0.2.0-build24/Tess.app` | 紧邻回退 |
| `.build/local/0.2.0-build21/Tess.app` | 用户曾确认整体可用的早期截图版 |
| `.build/releases/0.2.0-build25/20261024/` | 本轮正式离线归档、已公证 App、DMG 公证容器及暂存；上传专用容器不安装或交付 |
| `.build/releases/0.2.0-build14/` 至 `build17/` | 历史正式归档及相应公证导出，不能概括为都已公证 |
| `.build/history/` | 其余旧候选、备份、源码快照与旧打包暂存，保留未删 |
| `.build/cache/` | 当前编译与依赖缓存；迁移前预编译缓存在 `legacy/`，因包含绝对路径而单独留存 |
| `.build/models/` | 经校验的基础模型权重 |
| `.build/verification/` | 隔离检查、验收和诊断资料 |
| `.build/tools/release/` | 历史发行工具；当前公证配置已纳入 `scripts/release/` |
| `.build/logs/` | 历史构建与启动日志 |
| `dist/0.2.0-build25/20261024/` | 本轮 616,302,726 字节正式离线 DMG、摘要及安装说明；App／DMG 独立公证与 Gatekeeper 通过，实际隔离下载和 Finder 安装技术复核完成，使用验收由用户自行进行 |
| `dist/0.2.0-build14/` | 旧 App、DMG、摘要，有已知输入故障；保留为历史 |

项目已建立 Git main 分支和公开 GitHub 远端 `cainebaode/Tess`。整理前源码标签 `local-build25-baseline` 可用于查看当时的代码与目录；Git 不包含本机二进制和原始验收资料。GitHub 同步源码、必要品牌资源、文档、脚本、锁定依赖和公开校验清单。

原始 `evidence/` 可能包含配置快照及桌面材料，因此仅在本机保留。上游参考、缓存和独立模型权重不上传源码仓库。正式离线安装包经用户明确授权，在同一公开仓库 `cainebaode/Tess` 的 Releases 分发。整理范围及旧路径定位见 [整理记录](workspace-organization.md) 和 [完整路径映射](workspace-layout.json)。

## 版本核对快照

2026-10-24 核对：源码、正式 App、最终 DMG 及本机安装版均为 `0.2.0 build 25`。`dist/0.2.0-build25/20261024/` 为本轮正式交付目录；最终包实际下载隔离、Finder 替换和安装技术复核完成。候选完整清单已有用户通过反馈；最终安装版使用验收按用户最新要求由其自行进行，尚未收到通过确认。旧 build 14 保留为历史；详细证据与限制见 README 和本轮交付记录。

## 产品网站与公开下载

产品站源码位于 BaodeLife 工程 `website/static-sites/tess/`，入口为 https://tess.baode.life/。本项目保留应用实现、品牌源素材和公开说明维护副本 `scripts/release/public/`；源码、产品介绍和 Release 统一在公开的 Tess 仓库；旧 Faster 只保留为归档。当前状态见 [网站与下载记录](releases/20261025-01-tess-website-and-download.md)。
