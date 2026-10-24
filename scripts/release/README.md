# 正式发行配置与模型清单

本目录跟随源码进入 GitHub，不包含账号密码、公证令牌或模型权重。

- `ExportOptions.plist`：现有 Developer ID 导出配置，使用 Xcode 的已登录账号；团队标识不是登录凭据。
- `base-model-receipt.json`：公开基础模型固定版本、六个文件的大小与摘要；从现有已校验模型源复制，未包含权重。

模型来源为 [aufklarer/Qwen3-ASR-0.6B-MLX-4bit](https://huggingface.co/aufklarer/Qwen3-ASR-0.6B-MLX-4bit)，固定 revision `bc441bd1e4295c1f42d9879f056049a925b6e013`。许可和来源说明位于 `Tess/Resources/Qwen3-ASR-LICENSE.txt`、`Qwen3-ASR-NOTICE.txt`。

正式归档前，在项目的 `.build/models/qwenSmall/` 准备该 revision 下收据所列的原始文件，目录内保留 `.tess-verified.json`。本机已有完整模型，无需重新下载。全新克隆时，可按公开收据逐文件取得并核对来源，将本目录收据作为 `.tess-verified.json` 放入模型目录；`scripts/archive-release.sh` 会再次校验每个文件的大小与完整摘要，不通过则停止。

在项目根目录执行正式归档后，归档位置为：

```text
.build/releases/<version>-build<build>/archive/Tess.xcarchive
```

公证上传与导出使用同一版本目录内的独立位置；最终已公证 App 放在 `notarized/Tess.app`。`scripts/package-dmg.sh` 默认从该 App 读取实际版本／build，输出到 `dist/<version>-build<build>/`，打包暂存位于对应发行目录的 `stage/dmg/`。

不要把旧版本的公证、模型验证或人工验收结论迁移为新版本通过。完整流程见 [迭代与发布](../../docs/iteration-and-release.md)。
