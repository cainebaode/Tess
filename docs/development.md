# Tess 苔丝

原生 macOS 菜单栏语音输入与原位截图标注工具，面向 Apple Silicon、macOS 26+。项目目录沿用早期名称 Faster，产品名称为 Tess。

源码与发行仓库：[cainebaode/Tess](https://github.com/cainebaode/Tess)，公开仓库。旧 Faster 作为只读历史归档。日常迭代和正式交付按 [迭代与发布流程](iteration-and-release.md) 执行。

## 当前状态

2026-10-26：**0.3.0 build 37 正式发布准备中。** 源码已同步 GitHub，正式离线归档和相关隔离检查通过。公证、DMG 和草稿资产上传在后台继续；按用户要求停止持续等待。官网本地页面已准备，线上仍为 build 25；公开发布、官网切换及最终安装复核待完成。详见 [0.3.0 发布记录](releases/20261025-10-tess-0.3.0-release.md)。

2026-10-25 最新：**0.2.0 build 36 已签名、覆盖安装并启动。** 按用户反馈取消不协调的玻璃外框和锐利高光，顶栏融入窗口，侧栏采用渐隐磨砂；减弱底色变化，柔化卡片、按钮与选中项边缘。构建、签名、最新设置保留、模型及安装一致性核对通过；已简短查看关于页；用户决定保留当前版本、停止视觉迭代。详见 [柔雾材质与界面统一](releases/20261025-09-tess-frosted-settings-ui.md)。本轮没有公证、DMG 或公开发布。

2026-10-25 上一轮：**0.2.0 build 35 已签名、经 Finder 覆盖安装并启动。** 根据用户反馈修正 build 34 玻璃感不足：侧栏、顶栏和弹窗操作层改用原生 Liquid Glass，移除厚遮罩并加入柔和鼠尾草底色，正文卡片保留阅读对比度。色块材质对照、构建、签名、设置保留、模型与安装一致性核对通过，实际观感待用户确认。详见 [玻璃材质与界面优化](releases/20261025-09-tess-frosted-settings-ui.md)。本轮没有公证、DMG 或公开发布。

2026-10-25 上一轮：**0.2.0 build 34 已签名、经 Finder 覆盖安装并启动。** 移除侧栏深色选中竖线，加入原生磨砂窗口层次，减淡卡片与按钮边线，统一分隔线、内边距和长说明行距。设置页、提示词库和文字配置弹窗保持同一风格。构建、签名、模型及安装一致性检查通过，原设置与快捷键绑定保留；实际界面观感待用户确认。详见 [磨砂材质与界面优化](releases/20261025-09-tess-frosted-settings-ui.md)。本轮没有公证、DMG 或公开发布。

2026-10-25 上一轮：**0.2.0 build 32 已签名、经 Finder 覆盖安装并启动。** 按用户澄清整理新增功能影响到的设置页：三个入口按行对齐，提示词编辑与快捷键操作更集中；模板库提供用途、示例和编辑。默认模板升级为轻量整理、自然表达、两种 AI 指令、英文翻译、条理清单、要点摘要、消息润色，保留用户编辑及绑定。构建、输入／文字／交互检查、迁移、签名和安装核对通过；实际口述效果与界面体验待用户反馈。详见 [设置页与提示词模板](releases/20261025-08-tess-settings-and-prompt-templates.md)。本轮没有公证、DMG 或公开发布。

2026-10-25 上一轮：**0.2.0 build 30 已签名、经 Finder 覆盖安装并启动。** 语音入口收敛为 Fn 基础听写及两个可自定义按键和绑定提示词的入口；提供五条默认提示词及新建、编辑、恢复默认功能。旧提示词、适用键位和用户配置已迁移保留。构建、文字／快捷键／输入／交互检查、签名、模型及安装一致性通过；界面确认绑定提示词编辑入口正确。实际录音、加工质量与输入体验待用户确认。详见 [三个语音入口与提示词](releases/20261025-07-tess-custom-voice-prompts.md)。本轮未公证、制作 DMG 或公开发布，公开下载仍为 build 25。

2026-10-25 上一轮：**0.2.0 build 28 已签名、经 Finder 覆盖安装并启动。** 用户的 build 27 诊断确认 ChatGPT `com.openai.codex` 不提供焦点输入框（AX `noValue`），辅助功能准备请求不受支持。本轮新增仅用于该应用、该错误条件的原窗口兼容输入，按原窗口 ID 和会话操作监测保护；点击、打字、切换窗口或应用后改为复制。构建、输入相关检查、签名、模型和安装一致性通过；用户随后确认 build 28 在 ChatGPT 桌面版的 Fn 自动输入正常。详见 [ChatGPT 原窗口输入](releases/20261025-06-tess-chatgpt-window-input.md)。本轮未公证、制作 DMG 或公开发布；公开下载仍为 build 25。

2026-10-25 上一轮：**0.2.0 build 27 已使用原 Developer ID 签名并经 Finder 覆盖安装、启动。** 针对 ChatGPT 桌面版补上辅助功能信息预准备，并增加不含正文的输入诊断、复制回退原因及诊断复制入口。构建、相关隔离检查、签名和安装一致性通过；ChatGPT 的实际 Fn 输入由用户测试确认。详见 [桌面输入诊断与兼容迭代](releases/20261025-05-tess-chatgpt-input.md)。本轮没有公证、DMG 或公开发布，公开下载仍为 build 25。

2026-10-25 本轮：**0.2.0 build 26 已使用原 Developer ID 签名并经 Finder 覆盖安装、启动。** 国内文字服务预设覆盖 11 家；通用及三种整理模式的提示词可编辑、恢复默认，样例测试可选择模式和编辑文字。本地语音识别保留。构建、隔离检查、签名及安装一致性通过，真实 API 连通与人工使用验收待用户完成；本轮没有公证、DMG 或公开发布。详见 [文字服务与提示词](releases/20261025-04-tess-text-api-prompts.md)。公开下载仍为 build 25。

2026-10-25 后续：用户要求卸载重装。`/Applications/Tess.app` 与全部 36 个本机历史／检查应用副本已移除；运行数据已移出原目录并备份。当前未安装 Tess，等待用户重新下载安装。源码、正式 DMG 与公开 Releases 保留。见 [本机卸载记录](releases/20261025-03-tess-local-uninstall.md)。

2026-10-25：[Tess 产品站](https://tess.baode.life/) 已上线，[公开下载仓库](https://github.com/cainebaode/Tess) 已完成 build 25 公开下载发布；文件大小与完整 SHA-256、公开下载及校验文件均已核对。接入与下载状态见 [网站与下载发布记录](releases/20261025-01-tess-website-and-download.md)。

2026-10-24：**Tess 0.2.0 build 25 正式离线安装包已完成，并已从实际下载的最终 DMG 经 Finder 覆盖安装至 `/Applications/Tess.app`、启动。**

- [最终 DMG](../dist/0.2.0-build25/20261024/Tess-0.2.0-build25-arm64.dmg)：616,302,726 字节，约 616.3 MB；[SHA-256](../dist/0.2.0-build25/20261024/Tess-0.2.0-build25-arm64.dmg.sha256)、[随包记录](../dist/0.2.0-build25/20261024/交付记录.md)。
- App 与 DMG 独立签名、公证票据、Gatekeeper 均通过；App Hardened Runtime、Apple 时间戳、完整离线模型及许可核对通过。
- 实际浏览器下载保留隔离标记；Finder 替换后代码与归档一致，偏好值、文字服务配置、用户模型和引导保留，未重置权限或 Keychain。
- build 25 候选集中人工清单已获用户“全部完成，推进发布”反馈。**最终安装版使用验收由用户自行进行，尚未收到通过反馈。**
- 绿色精灵、Humanist 字标、菜单栏与原位截图功能保留；本轮未修改应用实现。旧 `dist/0.2.0-build14/` 有已知输入故障，仅保留为历史。
- 10 月 24 日交付轮次未公开发布或提交 App Store；临时服务器、挂载和桌面操作助手已清理。10 月 25 日网站与公开下载另行推进。该次交付详见 [build 25 正式交付](releases/20261024-02-tess-build25-offline-delivery.md)。

## 工作入口

| 内容 | 文档 |
| --- | --- |
| 后续迭代和正式交付 | [迭代与发布流程](iteration-and-release.md) |
| 代码、依赖和目录关系 | [项目架构](project-map.md) |
| 本轮整理范围与保留清单 | [整理记录](workspace-organization.md) |
| 所有旧路径的新位置 | [路径映射](workspace-layout.json) |
| 产品需求 | [PRD](product/20261007-02-tess-prd.md)、[BRD](product/20261007-01-faster-brd.md) |
| 正式交付状态 | [发布进度](releases/20261020-03-tess-release-progress.md)、[安装验收](releases/20261020-04-tess-installer-acceptance.md) |
| 早期版本记录 | [历史 README](history/readme-through-build25.md) |
| 本机原始验收材料 | [证据目录说明](../evidence/README.md)，原始内容不上传 GitHub |

## 目录

```text
Tess/          当前应用工程、源码、资源、独立检查和实际编译的 Vendor 代码
scripts/       开发构建、检查、正式归档和打包；release/ 保存公开发行配置
assets/        品牌源素材
docs/         产品需求、固定流程、发布记录、历史记录和架构说明
evidence/     本机原始证据；Git 仅包含目录说明
.build/        本机产物，按 cache/local/releases/models/verification/history/tools/logs 分开
dist/         按版本和 build 存放交付物，不进入源码 Git；正式包独立经 Releases 分发
upstream/     上游参考副本，不上传 GitHub
```

## 开发构建

需要 Xcode 26+ 及对应 Metal 编译组件。在项目根目录运行：

```sh
./scripts/build.sh
```

开发输出为 `.build/local/<version>-build<build>/development/Tess.app` 和同目录 ZIP，日志在同目录 `build.log`；缓存统一在 `.build/cache/`。该命令不写 `dist`，不自动安装，不嵌入正式离线模型；默认临时签名。

本机已保留的完整候选位于版本目录直接下的 `Tess.app`，与 `development/Tess.app` 分开。覆盖更新须单独退出旧版，使用原签名身份和完整资源安装，保留配置、权限、模型与引导进度。需要实际操作验收时由用户完成。

## 正式交付

1. 冻结源码并记录 Git 提交和版本／build；必要人工验收结果分别记录。
2. 用 `scripts/archive-release.sh` 生成 `.build/releases/<version>-build<build>/archive/Tess.xcarchive`，基础模型源在 `.build/models/qwenSmall/`。
3. 沿用现有 Xcode 登录，以 `scripts/release/ExportOptions.plist` 完成 Apple 公证，将最终导出 App 放入同版本的 `notarized/Tess.app`。
4. 检查模型、签名、票据和 Gatekeeper，再运行 `scripts/package-dmg.sh`，输出到 `dist/<version>-build<build>/`。
5. 从最终 DMG 实际安装并完成用户复核，记录大小、SHA-256 和交付结论。

独立模型权重不进入源码仓库；正式离线 DMG 内含随包基础模型，经同一 Tess 仓库的 Releases分发。公开固定版本的校验收据与准备说明见 [发行配置](../scripts/release/README.md)。不使用旧包的公证结果代替新版本检查，也不将本机候选当作正式交付物。

## 数据与依赖

正常用户数据位于 `~/Library/Application Support/Tess/`，API Key 在 macOS Keychain；基础识别在本机运行，文字 API 为可选服务，截图不发送给文字模型。Tess 不自动发送消息。

Swift 依赖解析记录、实际 Vendor 源码、品牌素材与许可均纳入 Git；缓存、模型权重、App／DMG、原始证据和本机配置不纳入 Git。第三方许可位于 `Tess/Resources/` 和 `Tess/Vendor/SpeechSwift/`。
