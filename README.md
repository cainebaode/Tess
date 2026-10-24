# Tess 苔丝

原生 macOS 菜单栏语音输入与原位截图标注工具，面向 Apple Silicon、macOS 26+。项目目录沿用早期名称 Faster，产品名称为 Tess。

源码仓库：[cainebaode/Faster](https://github.com/cainebaode/Faster)，私有仓库。日常迭代和正式交付按 [迭代与发布流程](docs/iteration-and-release.md) 执行。

## 当前状态

2026-10-24 核对：源码和本机 `/Applications/Tess.app` 均为 **0.2.0 build 25**。本轮目录整理未修改应用源码、未重装或退出本机 Tess。

- 原位截图：全屏调暗、选区高亮、邻近工具栏；默认方框，可选圆圈、文字、六色与撤销。
- 回车／完成提交正在输入的文字及标注，复制图片并收起；Esc／⌘W 取消，⌘Z 撤销，⌘S 另存 PNG。
- 最新截图体验待用户人工确认；build 17 的真人语音、目标切换及休眠证据保留为历史记录。
- 当前对应候选：`.build/local/0.2.0-build25/Tess.app`；保留 build 24、21 回退和更早历史包。
- `dist/0.2.0-build14/` 是有已知输入故障的旧正式包；本轮没有制作新公证包或公开发布。

## 工作入口

| 内容 | 文档 |
| --- | --- |
| 后续迭代和正式交付 | [迭代与发布流程](docs/iteration-and-release.md) |
| 代码、依赖和目录关系 | [项目架构](docs/project-map.md) |
| 本轮整理范围与保留清单 | [整理记录](docs/workspace-organization.md) |
| 所有旧路径的新位置 | [路径映射](docs/workspace-layout.json) |
| 产品需求 | [PRD](docs/product/20261007-02-tess-prd.md)、[BRD](docs/product/20261007-01-faster-brd.md) |
| 正式交付状态 | [发布进度](docs/releases/20261020-03-tess-release-progress.md)、[安装验收](docs/releases/20261020-04-tess-installer-acceptance.md) |
| 早期版本记录 | [历史 README](docs/history/readme-through-build25.md) |
| 本机原始验收材料 | [证据目录说明](evidence/README.md)，原始内容不上传 GitHub |

## 目录

```text
Tess/          当前应用工程、源码、资源、独立检查和实际编译的 Vendor 代码
scripts/       开发构建、检查、正式归档和打包；release/ 保存公开发行配置
assets/        品牌源素材
docs/         产品需求、固定流程、发布记录、历史记录和架构说明
evidence/     本机原始证据；Git 仅包含目录说明
.build/        本机产物，按 cache/local/releases/models/verification/history/tools/logs 分开
dist/         按版本和 build 存放交付物，不上传 GitHub
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

模型权重不进入 GitHub。公开固定版本的校验收据与准备说明见 [发行配置](scripts/release/README.md)。不使用旧包的公证结果代替新版本检查，也不将本机候选当作正式交付物。

## 数据与依赖

正常用户数据位于 `~/Library/Application Support/Tess/`，API Key 在 macOS Keychain；基础识别在本机运行，文字 API 为可选服务，截图不发送给文字模型。Tess 不自动发送消息。

Swift 依赖解析记录、实际 Vendor 源码、品牌素材与许可均纳入 Git；缓存、模型权重、App／DMG、原始证据和本机配置不纳入 Git。第三方许可位于 `Tess/Resources/` 和 `Tess/Vendor/SpeechSwift/`。
