# Tess 源码与 Releases 仓库统一

2026-10-25。用户明确确认项目开源，要求以 Tess 仓库统一源码、产品介绍和 Releases。

- 正式仓库：https://github.com/cainebaode/Tess ，默认分支 main。
- 现有公开下载仓库更名为 Tess，保留原 Release、安装包与摘要，避免重新上传大文件。
- 合入原 Faster 源码历史；旧 Faster 作为历史归档，不再作为日常开发入口。
- 官网及 README 的仓库／下载入口统一到 Tess。
- 检查了 220 个历史 blob 及当前候选文件，未发现所检查的常见凭据模式；模型权重、原始 evidence、用户配置与 App／DMG 不进入源码 Git。
- 本轮未修改应用实现、版本、Bundle ID 或安装包内容。

状态：整合准备完成，远端合并、标签与公开下载验证待完成。
