# Tess 源码与 Releases 仓库统一

2026-10-25。用户明确确认项目开源，要求以 Tess 仓库统一源码、产品介绍和 Releases。

- 正式仓库：https://github.com/cainebaode/Tess ，默认分支 main。
- 现有公开下载仓库更名为 Tess，保留原 Release、安装包与摘要，避免重新上传大文件。
- 合入原 Faster 源码历史；旧 Faster 作为历史归档，不再作为日常开发入口。
- 官网及 README 的仓库／下载入口统一到 Tess。
- 检查了 220 个历史 blob 及当前候选文件，未发现所检查的常见凭据模式；模型权重、原始 evidence、用户配置与 App／DMG 不进入源码 Git。
- 本轮未修改应用实现、版本、Bundle ID 或安装包内容。

## 合并与版本对应

- 公开 Tess 仓库 ID 为 `1432333706`，沿用原下载仓库；原 Release ID 为 `422822253`。
- 源码历史与公开发布历史通过合并提交 `0184752` 保留，main 未改写历史。
- 原 `v0.2.0-build25` 标签指向仅含发布介绍的 `4cc8fb756c3efcf7b6c49bb55fcc760d8b9fa290`；本轮将标签纠正到包含完整源码的合并历史，使 GitHub 自动生成的 Source code 归档包含实际源码。应用 `Tess/` 与原 build 25 源码提交 `3271f5a` 一致。
- 安装包保持 616,302,726 字节，SHA-256 `91b3d70c881f52b3abe816e3bfb25eb162a636f2a36007d27e3cd58af4ee8b50`，不重新打包或上传。

状态：源码合并已推送；标签、旧仓库归档与官网链接待最终核对。
