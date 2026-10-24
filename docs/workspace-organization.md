# 2026-10-24 项目整理与 Git 建立

项目保持在 `/Users/caine/Documents/Project/Faster`，本机产品仍为 Tess 0.2.0 build 25。本轮只整理目录、构建输出路径和文档，建立版本管理并同步私有 GitHub；没有退出、重装或修改 `/Applications/Tess.app`，没有开始正式公证或制作新 DMG。

## Git 与上传范围

- 私有仓库：[cainebaode/Faster](https://github.com/cainebaode/Faster)，主分支 `main`。
- 整理前源码基线：提交 `d6aa0f9`，标签 `local-build25-baseline`。
- 同步：应用及实际 Vendor 源码、独立检查、品牌素材与字体许可、文档、脚本、Swift 依赖锁定文件、公开模型校验收据和 Developer ID 导出配置。
- 仅本机保留：原始证据／配置快照、模型权重、App／DMG、正式归档、公证上传记录、缓存、上游参考仓库。`evidence/README.md` 是证据目录唯一跟踪文件。
- 当前应用源码和版本号不变；整理后的代码位置可以由 Git 提交定位。回退源码与回退 App 是两个独立动作，不会自动替换正在使用的应用。

## 已分开的目录

| 内容 | 新位置 |
| --- | --- |
| BRD／PRD | `docs/product/` |
| 安装计划、发布进度、验收记录 | `docs/releases/` |
| 旧优化、品牌记录与旧 README | `docs/history/` |
| 当前及必要回退候选 | `.build/local/` |
| 各构建正式归档／公证导出 | `.build/releases/` |
| 编译及依赖缓存 | `.build/cache/` |
| 基础模型源 | `.build/models/qwenSmall/` |
| 检查程序、隔离验收和诊断资料 | `.build/verification/` |
| 其他历史包、源码快照及旧暂存 | `.build/history/` |
| 历史发行工具 | `.build/tools/release/` |
| 日志 | `.build/logs/` |
| 旧正式 App、DMG 与摘要 | `dist/0.2.0-build14/` |

迁移未删除旧包、归档、模型或缓存。完整旧路径到新路径对应关系见 [workspace-layout.json](workspace-layout.json)。旧文档中的历史命令和日志保留当时语境；可点击的文档链接已随目录迁移更新。原始证据中的历史路径不改写。

## 保留的当前版本和回退

- `.build/local/0.2.0-build25/Tess.app`：与当前本机版本对应的完整候选；最新截图操作仍待用户人工确认。
- `.build/local/0.2.0-build24/Tess.app`：紧邻回退。
- `.build/local/0.2.0-build21/Tess.app`：用户曾确认整体可用的旧截图版。
- build 17 的正式归档和真人语音／目标切换／休眠证据保留；该归档没有本轮最新截图功能，也没有成功公证结论。
- build 14 旧正式包已公证但有已知输入故障，仅作历史依据。其余旧候选、备份和替代归档统一留在 `.build/history/`。

## 构建脚本调整

- `scripts/build.sh`：开发 App、ZIP 和日志写入 `.build/local/<version>-build<build>/development/`，不覆盖完整保留候选或 `dist`。
- `scripts/archive-release.sh`：读取源码版本／build，归档写入对应 `.build/releases/`；已有归档不会自动覆盖。
- `scripts/package-dmg.sh`：读取待打包 App 的版本／build，公证后产物写入对应 `dist/` 子目录。
- 检查脚本的程序输出统一进入 `.build/verification/`，模块缓存进入 `.build/cache/`；HUD 预览入口跟随开发 App 新路径。
- 预编译缓存包含旧绝对路径，迁移前的缓存已留在 `.build/cache/legacy/`，当前路径下重新构建缓存。

## 核对

整理后的开发构建、开发候选签名及隔离 CaptureCheck 通过。未运行麦克风、桌面截图或剪贴板操作，未重做实际功能验收；最终状态仍以用户反馈和正式发行流程为准。

整理前后摘要核对确认：本机 App 的 35 个文件、29 个应用源码文件及用户配置一致；保留的 build 25／24／21 候选签名有效，基础模型六个文件和旧 build 14 DMG 摘要通过。上传清单为 179 个文件、约 21 MB，未包含忽略目录或扫描命中的私钥／访问令牌；90 个本机文档链接与 57 项迁移目标已核对。

本轮详细迁移清单、整理前后应用／源码／配置摘要、上传内容检查和构建日志保留在本机 `evidence/20261024-project-organization/`，不推送 GitHub。
