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

## 完成与验证

- `v0.2.0-build25` 已指向 `bb624f0571891ea06ad099344c078bf6a80c479a`，匿名读取该标签下的 `TessApp.swift` 与本机源码字节一致；版本源码目录包含 24 个直接条目。
- 旧 `cainebaode/Faster` 已归档，保持私有；本机 origin 已切换到 `git@github.com:cainebaode/Tess.git`，main 跟踪 origin/main。
- GitHub Release ID、两个资产、大小及 SHA-256 保持不变；匿名读取 DMG 前 1,024 字节与正式本机包一致，Content-Range 总大小正确；完整校验文件与正式本机文件一致。
- GitHub 不再存在一次性转存 workflow；临时服务器转存 URL 继续返回 404。
- 官网三个 GitHub 入口已更新为 Tess。线上与本地 HTML SHA-256 一致：`e7d3622ea7df8308d78c8bb54721d373f403db3d04f562b34f104374bcab0bdb`。
- 本轮仅更新 Tess 静态 HTML 的三个 URL，未切换主站构建、修改 nginx、数据库或运行服务；静态页无需重建 Next.js。
- 官网 HTTPS 返回 200，旧主站 `/tess/` 返回 404，主站返回 200。
- 原页面备份：服务器 `/var/backups/baodelife/20261025-02-tess-github-unification/tess-index-before.html`。回退本轮官网改动只需恢复此静态 HTML，不回退主站或数据库。
- 本机核对文件与页面截图保留在 `evidence/20261025-tess-site/`；整合前 Git bundle 保留在 `/private/tmp/tess-repo-unification/Faster-before-unification.bundle`。

状态：仓库、版本源码、正式下载和官网入口统一完成。本轮未重新构建或安装应用，既有真人验收状态仍见对应交付记录。
