# Tess 0.3.0 build 41 公开发布

日期：2026-10-30。用户明确授权“现在发布”。本轮发布 Mac 当前 build 41，沿用公开仓库 `cainebaode/Tess`；iPhone 原型及其未提交资料保留在本机。

## 状态

**已公开发布，GitHub Latest 与官网均为 0.3.0 build 41。** [正式 Release](https://github.com/cainebaode/Tess/releases/tag/v0.3.0-build41) · [官网下载入口](https://tess.baode.life/#download)。Mac 源码已同步 GitHub main，冻结提交为 `0be8320e8cd11348fc37a51b0b23bae3e6988899`；必要检查、正式离线归档、App／DMG 公证、最终下载覆盖安装以及公开完整下载校验均已完成。

| 阶段 | 当前结果 |
| --- | --- |
| 源码与检查 | Mac 源码已公开同步；输入、学习、交互、文字、存储、上下文校正、实时转写、浮窗、离线模型与评测统计检查通过 |
| App | 正式离线归档及精确载荷审计通过；原 Developer ID、Hardened Runtime、时间戳、公证票据、Gatekeeper 和 syspolicy 检查通过 |
| DMG | 独立公证、签名、票据、Gatekeeper 和完整性检查通过；616,760,479 字节，SHA-256 `339661eb5bca9d3886ff886fb7a1aff4618abe8792d039413277cd93c7387b70` |
| 最终安装 | Chrome 下载最终 DMG，隔离标记保留、摘要一致；经 Finder 覆盖安装并启动；安装载荷与正式归档一致，原偏好、API 配置、模型、快捷键、提示词、引导和辅助功能授权保留 |
| GitHub 资产 | DMG 与 `.sha256` 均已完整上传；GitHub 资产大小与 digest 匹配，Release 已公开并设为 Latest；完整匿名下载重新计算 SHA-256 通过 |
| 官网 | 首页、帮助与隐私已切换到独立 build 41 目录，公开页面逐字节摘要与本机一致，下载链接指向已公开的最终资产 |

本轮公开发布步骤已完成。学习功能的真人准确率及收益仍未验证，发布说明已明确标为默认关闭的试用功能；这项限制不因上传和公证完成而改变。

## 上传过程与最终记录

- 16:25 时正式包已经完成公证及本机安装，但 GitHub 上传慢，按用户要求停止前台等待。后续代理上传连接被重置，后台恢复又遭 GitHub `408 / Upload body timed out due to inactivity`；`nettop -p gh` 显示空白是因为当时的 `gh` 上传已退出。
- 16:43 起改为 `upload-with-progress.py`：使用 HTTP/1.1、不显式连接 HTTP 代理，既有凭据只经内存管道传给 curl，不写入命令参数或日志。16:43:55 开始上传，16:45:11 完成并核对资产，实际约 76 秒；先前的小时级估算已失效。该进程只上传及核对，随后由本轮继续执行已授权的公开发布和官网切换。
- 上传与故障证据为本机 `upload-state.json`、`upload-curl-background.log`、`upload-progress.log`；旧 `upload-background.log`、`github-proxy-upload.log`、`github-detached-upload.log` 保留失败原因。`public-release.json` 确认正式 Latest，`anonymous-download-verification.json` 确认完整匿名下载，`public-site-verification.json` 确认公开三页摘要。
- GitHub 发布 ID `428773157`，标签 `v0.3.0-build41`。最终说明维护在 `scripts/release/public/release-notes-0.3.0-build41.md`。
- 最终产物：`dist/0.3.0-build41/20261030/`；正式归档和公证导出：`.build/releases/0.3.0-build41/20261030/`。本轮临时本机 HTTP 服务已关闭，安装卷已推出。
- 官网本地源码：BaodeLife `website/static-sites/tess/`。服务器正式目录为 `/var/www/tess-site/releases/20261030-01-tess-build41`，旧目录 `/var/www/tess-site/releases/20261024-01-tess-products-r3` 仍保留，完整备份位于 `/var/backups/baodelife/20261030-01-tess-build41`。仅更改 Tess 静态目录，不涉及主站构建、数据库、环境变量或 PM2。
- 官网第一次切换后立即读取到旧 worker 页面，摘要不符时已自动回退。补充最多 10 次、间隔 1 秒的重载生效校验并明确绕过回环代理后，第二次切换通过全部三页校验。其余 nginx 配置按替换前后完整文本比对保留；回退依据为备份中的 `before-switch.conf`，后续使用前须先核对是否还有新的部署修改。

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
