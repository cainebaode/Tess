# Tess 产品站与 GitHub 下载发布

2026-10-25。基于 2026-10-24 已完成签名、公证和最终安装技术复核的 0.2.0 build 25，本轮只发布产品网站与公开下载，不重新构建 App。

## 入口和归属

- 产品站：https://tess.baode.life/；帮助 `/help/`，隐私 `/privacy/`。
- 主站：https://baode.life/；首页、作品页与关于页加入 Tess。
- 下载：https://github.com/cainebaode/tess-releases/releases/tag/v0.2.0-build25。
- `cainebaode/Faster` 继续私有；`cainebaode/tess-releases` 为独立公开下载仓库。

产品页面源码维护在 `/Users/caine/Documents/Project/BaodeLife/website/static-sites/tess/`；主站接入、TLS、备份和回退详见该项目 `docs/releases/20261024-01-Tess接入与产品域名统一.md`。本仓库 `scripts/release/public/` 保存公开 README、品牌头图和版本说明的维护副本，不包含二进制、用户数据或凭据。

产品入口统一为 `<产品名>.baode.life`，Windup 同步迁至 `windup.baode.life`，Skye 沿用既有 `skye.baode.life`。按用户要求，主站旧产品路径停用并返回 404。

## 品牌与呈现

使用 Tess 正式原版绿色精灵和 Humanist 矢量字标。曾实现的呼吸、跟随与眨眼方案被用户否决，最终已全部移除，保留静态原图。GitHub README 提供品牌头图、产品特点、安装步骤、系统要求、校验方法和帮助入口。

## 安装包与分发

固定文件 `Tess-0.2.0-build25-arm64.dmg`，616,302,726 字节。SHA-256：

```text
91b3d70c881f52b3abe816e3bfb25eb162a636f2a36007d27e3cd58af4ee8b50
```

DMG 与 `.sha256` 作为 Release 资产分发。下载直达 GitHub，不占主站 ECS 的下载带宽，也未开通 OSS。ECS 固定 3 Mbps，单包独占该带宽理论约 27 分钟；GitHub 实际速度取决于访问网络。

## 验证与边界

- GitHub 服务端资产大小和 SHA-256 与正式本机包一致；公开版本与校验文件可访问，安装包响应支持范围下载。
- 产品站首页、帮助、隐私、正式品牌资产及下载链接已复核；主站与 Windup 域名同步上线，旧路径 404。
- 未公开应用源码、用户配置、内部原始证据或模型源目录；基础模型仅包含在原本正式离线 App 包内。
- 本轮未修改 Bundle ID、签名、模型、权限、设置、引导进度或已安装 App。最终安装版用户使用验收仍以人工反馈为准，不由网站或下载校验替代。
- 已关闭本轮临时预览、上传与服务器操作标签页，保留正式应用、生产服务及回退材料。

本机到 GitHub 的上传缓慢，期间一次重传及一次 408 超时造成等待。用户随后明确授权一次性转存流程，运行记录为 https://github.com/cainebaode/tess-releases/actions/runs/40112876343 。转存完成后禁用并删除该流程；没有修改 GitHub 登录令牌或仓库默认权限。

![正式产品页](../../evidence/20261025-tess-site/tess-live-desktop.png)

后续变更：用户确认项目开源，源码与 Releases 已统一到公开的 `cainebaode/Tess`，旧 Faster 归档。以 [仓库统一记录](20261025-02-tess-repository-unification.md) 为当前状态；上文的私有／分仓描述仅代表首次上线时的状态。
