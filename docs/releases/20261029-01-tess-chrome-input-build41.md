# Tess Chrome 网页输入修复 build 41

日期：2026-10-29。实际安装版本：0.3.0 build 41。已使用原 Developer ID 签名，经 Finder 覆盖安装并启动；用户已确认小红书搜索框可以输入。

## 问题与依据

用户反馈小红书官网 `/explore` 搜索框显示“未识别”，不能自动输入。已安装 build 40 的多次诊断均为 `com.google.Chrome`、`focus_unavailable`、AX `-25212 / noValue`，随后 `copied_fallback`；不是模型没有识别出文字。

本机 Chrome 为 `156.0.8078.49`。网页与原生辅助功能界面均能显示可编辑搜索框，但 Tess 之前只为两个 ChatGPT 应用标识请求 `AXManualAccessibility`，没有准备 Chrome 的网页辅助功能信息。[Chromium 官方说明](https://www.chromium.org/developers/design-documents/accessibility/)和[当前实现](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/browser/chrome_browser_application_mac.mm)说明，其他辅助应用可通过 `AXEnhancedUserInterface` 请求完整网页信息；实现存在两秒防抖，重复请求会推迟完成。补齐此缺口后，用户确认可以输入；build 41 对应诊断为 `input_captured / AXTextArea`，随后 `paste_posted`。

## 修改

- `DeliveryService` 对 `com.google.Chrome` 请求 `AXEnhancedUserInterface`；保留 ChatGPT 原有请求，不扩展到其他应用。
- Tess 启动时准备已运行的 Chrome，Chrome 启动／激活时也准备。每个 Chrome 进程只提交一次已到达的请求，避免每次 Fn 重启浏览器的延迟；通信／授权失败不记为完成，后续可重试。
- 请求不读取或修改网页正文，不开启 VoiceOver，不变更系统授权。仍须通过可编辑性、非密码框、应用／元素身份与光标检查；无法确认时继续复制，不给 Chrome 增加盲粘贴窗口兼容路径。
- 若 Chrome 刚启动、网页信息尚未准备好，最初一次输入仍可能安全回退为复制；稍后重试。没有延后猜测原输入位置或放宽验证。

## 验证与安装

| 项目 | 结果 |
| --- | --- |
| 缺陷复现 | 先增加 Chrome 准备检查，原实现因没有发出请求而失败；修复后通过 |
| 输入回归 | Chrome／ChatGPT 请求范围与错误保留、取消、目标变化、兼容输入保护及剪贴板恢复检查通过；三个语音入口与迁移检查通过 |
| 构建与签名 | 生产构建通过；原 `Developer ID Application: Caine Chen (9D6XC2T2G5)`，Hardened Runtime、时间戳及 deep／strict 校验通过 |
| 实际安装 | `/Applications/Tess.app` 为 0.3.0 (41)，`life.baode.tess`；35 个载荷文件与候选完全一致，7 个模型文件与 build 40 一致，没有内部检查入口 |
| 用户数据 | 原 preferences 与 API 配置逐项语义一致；模型、快捷键、模板、引导保留，未重置权限或 Keychain |
| 简短界面核对 | 已确认 build 41 启动。尝试只核对小红书输入位置时，CUA 将 Tess 激活到前台，诊断为 `tess_frontmost`；主动取消，没有粘贴／发送或录音，因此不能据此宣称实际输入通过 |
| 真人复测 | 2026-10-29 用户回复“可以输入了”；本机 build 41 Chrome 诊断同时确认取得输入框并发出粘贴。此结论限定小红书搜索框恢复输入，不扩大为所有网页或其他保护场景均通过 |

本轮只修改输入准备、相关检查及 build；保留学习、识别模型、浮窗和其他 agent 的修改，未改 iPhone。没有公证、DMG、公开发布或 GitHub 同步。

本机证据：`evidence/20261029-chrome-input/`，包括修改前源码与故障诊断、先失败后通过的检查、构建／签名日志、安装与设置核对。完整候选位于 `.build/local/0.3.0-build41/Tess.app`，build 40 候选保留供回退。

## 人工复测

小红书搜索框正常 Fn 输入已由用户确认。以下其余保护行为保留为后续复查项。

1. Chrome 中点击小红书搜索框，出现光标后按 Fn 说一个短词；确认文字自动填入且不自动搜索。
2. 录音时切换目标输入框或应用，确认回退复制，不粘贴到新位置。
3. 若仍显示“未识别”，说明当前 build 41 的正常 Fn 复测结果；应用会保存不含正文的诊断，可据此继续定位。
