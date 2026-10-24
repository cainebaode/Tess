# Tess 0.2.0 build 25 正式离线交付

2026-10-24。正式安装包与安装技术交付已完成；最终使用验收按用户最新指令由用户自行进行，未标为通过。不包含公开发布或 App Store 提交。

## 最终文件

| 内容 | 路径／结果 |
| --- | --- |
| 正式 DMG | `/Users/caine/Documents/Project/Faster/dist/0.2.0-build25/20261024/Tess-0.2.0-build25-arm64.dmg` |
| 大小 | 616,302,726 字节，约 616.3 MB |
| SHA-256 | `91b3d70c881f52b3abe816e3bfb25eb162a636f2a36007d27e3cd58af4ee8b50` |
| 实际下载文件 | `/Users/caine/Downloads/Tess-0.2.0-build25-arm64.dmg`，摘要一致，真实 Chrome 隔离标记和本机来源地址保留 |
| 正式归档 | `.build/releases/0.2.0-build25/20261024/archive/Tess.xcarchive` |
| 公证导出 App | `.build/releases/0.2.0-build25/20261024/notarized/Tess.app` |
| 已安装应用 | `/Applications/Tess.app`，0.2.0 build 25，从上述下载 DMG 经 Finder 替换并启动 |
| 随包说明 | 同目录及 DMG 内的 `安装说明.txt`；本记录、`.sha256` 与 `交付记录.md` 保留在交付目录 |

## 源码与载荷

应用源码冻结于 Git `3271f5a5f462358ab418948e2d898120a031552f`，应用实现与 build 25 基线一致。141 个应用与品牌文件在交付期间未变化。只调整发行脚本的独立目录、防覆盖和安装说明打包，并增加不写死旧 build 的载荷审计工具；未改变应用代码或复用 build 指代新实现。

基础离线模型包含 6 个文件、712,777,119 字节，全部摘要匹配 `aufklarer/Qwen3-ASR-0.6B-MLX-4bit` revision `bc441bd1e4295c1f42d9879f056049a925b6e013`。绿色精灵、Humanist 字标、菜单栏、字体、帮助及 Apache 2.0／OFL／原第三方许可均与源码一致。资源清单无额外用户配置、凭据、录音、截图或已知内部诊断入口。运行库只依赖系统及 Swift 库，无项目或 Xcode 运行路径依赖。

使用 `scripts/archive-release.sh` 正式离线归档，未使用开发构建脚本。新产物均位于含版本、build 和日期的独立目录，旧 build 14 与历史归档保留；旧 build 14 有已知输入故障，不作为本轮交付。

## 技术检查

| 项目 | 结果 |
| --- | --- |
| 针对性回归 | CaptureCheck、InteractionCheck 通过；均为隔离检查 |
| 正式 App | 代码及资源与最终归档一致，模型完整摘要通过 |
| App 签名 | Developer ID Application: Caine Chen (9D6XC2T2G5)，Hardened Runtime、Apple 时间戳，原音频 entitlement 保留 |
| App 公证 | 本轮正式导出成功，stapler validate 通过 |
| App Gatekeeper | accepted / Notarized Developer ID，Apple 分发预检通过 |
| DMG | 独立 Developer ID 签名、本轮公证和票据通过，Gatekeeper accepted / Notarized Developer ID，hdiutil 完整性通过 |
| 实际安装版 | 完整载荷与归档匹配；签名、票据、Gatekeeper、分发预检通过；启动进程路径为 `/Applications/Tess.app` |

为沿用现有 Xcode 登录，DMG 通过仅供上传的独立容器提交 Apple。容器未运行或安装，不作为交付应用。Xcode 上传／导出中的 DMG 字节与打包文件完全一致；随后对实际 DMG 附加票据并重算最终摘要。App 和 DMG 的结果分别记录，没有迁移旧 build 的公证结论。

## 实际下载、安装与保留

Chrome 最初显示“已被您的组织屏蔽”；代理未改动策略，交由用户亲自完成下载。实际下载文件的大小、摘要、`com.apple.quarantine` 和来源地址均已核对。镜像实际来源为 Downloads 中的最终 DMG，挂载于 `/Volumes/Tess`。通过 Finder 选取其中的 Tess.app，复制至 Applications、点击“替换”，观察拷贝完成，再从安装位置启动；未直接复制本机开发候选包代替该步骤。

覆盖安装后首次启动前，偏好与文字服务配置逐字节一致，用户模型文件未变化。启动后所有偏好值、API 配置及用户模型仍一致；Swift 字典序列化仅重排了快捷键条目，已通过原摘要的精确排列匹配核对。Xcode 正式导出的签名要求表达式与试用包文字不同，但已安装 App 仍满足旧版已授权的要求。未重置权限、Keychain、设置、模型或引导，未代点“已确认输入成功”。

## 人工验收与边界

- build 25 候选完整清单：用户回复“全部完成，推进发布”，按该反馈记录通过。范围为 TextEdit、浏览器普通／富文本框、微信 Fn 轻点／长按；取消重录、目标切换、真实休眠唤醒；原位截图、边缘工具栏、默认方框、圆圈、文字／颜色、撤销、输入文字时回车、Esc、PNG 及粘贴图片效果。
- 最终 DMG 安装版：用户最新回复“你别管这些了，我自己验收”。最终实际使用由用户自行进行，尚无通过反馈；不以技术检查或候选验收替代。
- 支持 Apple Silicon、macOS 26+。微信为窗口级兼容投递，不能验证框类型、光标和选区；先定位输入框，中途普通键鼠或应用切换改为复制，不自动发送消息。
- 本轮是当前机器的覆盖安装；未重验空配置新用户、另一台 Mac 或所有多屏缩放组合。

## 收尾与证据

临时下载服务器已停止，下载页已关闭，最终 DMG 已经 Finder 推出，CUA 会话已重置，本轮桌面操作助手已停止。正式 App、归档、DMG、下载文件和本机证据保留，Tess 留在安装位置供用户使用。

证据目录：`evidence/20261024-release-build25/`。关键文件：`source-freeze.json`、`shipping-source-verification.json`、`human-acceptance.json`、`archive-payload.json`、`notarized-payload.json`、`app-release-checks.json`、`dmg-release-checks.json`、`dmg-upload-comparison.json`、`browser-download.json`、`mounted-payload.json`、`installed-payload.json`、`preservation-comparison.json`、`installation.json`、`cleanup.json`、`delivery-status.json`。详细模型与资源摘要、签名和分发结果在对应 JSON／日志中，仅保留本机。
