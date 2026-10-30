# Tess 0.3.0 build 41 公开发布

日期：2026-10-30。用户明确授权“现在发布”。本轮发布 Mac 当前 build 41，沿用公开仓库 `cainebaode/Tess`；iPhone 原型及其未提交资料保留在本机。

## 状态

截至 2026-10-30 16:25（北京时间）：Mac 源码已同步 GitHub main，冻结提交 `0be8320e8cd11348fc37a51b0b23bae3e6988899`；必要检查、正式离线归档、App 与 DMG 公证及最终下载／安装复核均已完成。GitHub 约 616.8 MB 的 DMG 上传很慢，按用户要求停止前台等待，后台继续；**Release 仍是草稿，官网仍未切换**。

| 阶段 | 当前结果 |
| --- | --- |
| 源码与检查 | Mac 源码已公开同步；输入、学习、交互、文字、存储、上下文校正、实时转写、浮窗、离线模型与评测统计检查通过 |
| App | 正式离线归档及精确载荷审计通过；原 Developer ID、Hardened Runtime、时间戳、公证票据、Gatekeeper 和 syspolicy 检查通过 |
| DMG | 独立公证、签名、票据、Gatekeeper 和完整性检查通过；616,760,479 字节，SHA-256 `339661eb5bca9d3886ff886fb7a1aff4618abe8792d039413277cd93c7387b70` |
| 最终安装 | Chrome 下载最终 DMG，隔离标记保留、摘要一致；经 Finder 覆盖安装并启动；安装载荷与正式归档一致，原偏好、API 配置、模型、快捷键、提示词、引导和辅助功能授权保留 |
| GitHub 资产 | `.sha256` 已上传；DMG 后台上传中，当前使用本机既有 HTTP 代理。早先的低速直接上传已停止，没有重新归档或公证 |
| 官网 | 本地三页和服务器独立目录已准备，帮助／隐私补齐学习说明；页面摘要与本机一致，生产未切换 |

尚需：确认 DMG 上传完成并与本机摘要一致 → 公开 `v0.3.0-build41` Release、设为 Latest → 核对匿名下载 → 切换官网并复核公开页面。用户本轮要求稍后回来检查，后台进程只完成上传和摘要核对，不自动公开或切换网站。

## 回来后的接续入口

- 首先读取本机 `evidence/20261030-release-build41/upload-state.json`、`upload-background.log` 和 `github-proxy-upload.log`。独立后台进程记录在 `upload-background.pid`；它保留已运行上传，若原会话提前退出只做一次恢复上传。若状态为 `needs_attention`，先读错误，不重复归档／公证。
- GitHub 草稿：`v0.3.0-build41`，发布 ID `428773157`。公开前核对 DMG 的 `state=uploaded`、大小及 GitHub `digest` 与上述 SHA-256 一致；最终说明维护在 `scripts/release/public/release-notes-0.3.0-build41.md`。
- 最终产物：`dist/0.3.0-build41/20261030/`；正式归档和公证导出：`.build/releases/0.3.0-build41/20261030/`。本轮临时本机 HTTP 服务已关闭，安装卷已推出。
- 官网本地源码：BaodeLife `website/static-sites/tess/`，三个页面已更新，尚未部署为生产。
- 服务器已准备 `/var/www/tess-site/releases/20261030-01-tess-build41`，备份为 `/var/backups/baodelife/20261030-01-tess-build41`；生产仍指向 `/var/www/tess-site/releases/20261024-01-tess-products-r3`。仅更改 Tess 静态目录，不涉及主站构建、数据库、环境变量或 PM2。
- 服务器 `/tmp/tess-build41-site/activate.py` 已暂存切换脚本；公开 Release 后才运行。它先核对公开 `.sha256`、本地页面摘要和现行目录，保留切换前配置，经 `nginx -t` 后重载并校验三个回环 HTTPS 页面，失败时恢复配置。接续时须重新核对服务器现状和脚本，不能直接复用旧会话状态。

## 版本内容

- Fn 基础听写及两个可绑定提示词的自定义入口，八个默认模板与自建提示词。
- 保留柔雾设置界面、build 38 浮窗正文与回看、截图标注及兼容输入保护。
- 默认关闭的手动常用词、独立上下文校正与人工纠正学习；学习须用户确认，可停用、撤销、删除和清空，仅用于后续本地 Qwen 提示。
- Chrome 网页输入框信息预准备；用户已确认小红书搜索框恢复输入。

## 已知边界与验收

个人纠正学习属于试用功能，真人准确率及收益尚未验证。现有 8 条合成录音只用于技术测量；Qwen 1.7B 与 Whisper 下载超时，未取得实测对照，不推荐替换用户当前模型。不会保存日常录音或新增云端 ASR。

外部改稿只在学习开启、真实插入验证通过且普通输入框具备所需接口时短期观察；微信等不支持的场景使用主动提交。密码框、终端及无法确认原位置时按现有保护处理。用户对小红书的实际输入反馈已记录在 [build 41 修复记录](20261029-01-tess-chrome-input-build41.md)，不扩大为所有应用验收通过。

## 证据

本机原始证据位于 `evidence/20261030-release-build41/`，不进入 GitHub。源码、必要资源、检查脚本、产品依据和发布记录进入 Git；权重、用户配置、凭据、录音、App 与 DMG 不进入源码 Git。最终 DMG 与 `.sha256` 作为同一仓库的 Release 资产发布。
