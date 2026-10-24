# Tess 绿色精灵与 Humanist 品牌更新

2026-10-24，用户选择第二版绿色精灵与 Humanist 字标，并要求全面应用。

## 已应用

- 字标：小写 `tess`，使用随包注册的 Source Sans 3 Semibold。字标单独定制呈现，正文继续使用系统字体。
- 形象：绿色引号豆精灵。应用图标、头像、菜单栏和录音浮层使用同一原生矢量轮廓；欢迎／关于页使用透明背景质感精灵。
- 状态：静止、眨眼、倾听共用固定轮廓与画布，仅眼睛变化；保留原有有限动作时序。
- 窗口：奶油白背景、松绿文字、浅绿选中状态，覆盖设置、文字配置编辑、欢迎、结果和帮助页。
- 录音浮层：深松绿底、奶油白文字、浅绿音量和按钮，错误保留橙色语义。
- 构建脚本：开发构建与正式归档都生成新图标，避免后续构建回退到旧像素人物。

正式素材在 `assets/branding/tess-spirit/`；原始方案在 `assets/branding/20261024-concepts/`。旧素材保留。角色透明图由内置 image_gen 生成，完整提示词见 `mascot-prompt.txt`；标志、状态图与字标由 `scripts/make-icon.swift` 从原生路径／字体生成，可重建。

字体取自 [Adobe Source Sans 3 官方 3.052R 发布](https://github.com/adobe-fonts/source-sans/releases/tag/3.052R)，随包保留 OFL 许可；下载地址与 SHA-256 记录在 `assets/branding/tess-spirit/font-source.json`。

## 本机交付

- `/Applications/Tess.app`：0.2.0 build 18，Developer ID 签名，包含完整基础模型，已通过 Finder 覆盖安装并实际打开。
- 本轮候选构建：`.build/local-brand18/Tess.app`。
- 安装后核对：可执行文件、Info、图标、字标字体、头像、Mascot 和帮助文件与候选一致，签名有效；启动前偏好文件逐字节一致。实际设置页显示原有快捷键、已授权辅助功能及就绪的 Qwen 基础模型。
- 版本 18 不含新业务功能。语音识别、快捷键、输出、权限和存储的实现未修改。

## 验证

- Release 构建成功：`evidence/20261024-brand-refresh/build18.log`。
- 隔离交互回归通过：取消／重入、目标跟踪、休眠中断、实时转录与最终输出等既有规则，见 `interaction.log`。
- 字体实际注册名称为 `SourceSans3-Semibold`；三帧头像／菜单栏透明轮廓逐像素一致。
- 原生离屏画板检查 18pt 菜单栏、34pt 状态、大小字标与录音 HUD；模拟信号／文本已明确标注，没有启动麦克风或写用户数据。
- 安装后的关于、通用设置、权限页已通过 CUA 查看；显示 0.2.0 (18)，配色、头像和字标正常。
- 打包模型逐文件匹配固定版本 receipt 摘要。签名与安装核对见 `signature.log`、`installed-signature.log`、`install-verification.json`。

画板：[品牌与 HUD](../../evidence/20261024-brand-refresh/BrandHUD.png)、[18pt 菜单栏](../../evidence/20261024-brand-refresh/MenuBar18pt.png)。源码／资源备份见同目录 `before/`。

build 17 的真人输入验收仍为既有证据，build 18 本轮未重复真人录音。正式公证、新 DMG 与分发验收继续暂缓；本轮没有提交 Apple 公证、制作新 DMG 或公开发布，`dist` 保持旧 build 14。


## 同日追加：build 19 关于页精简

按用户要求移除关于页的 Talkify 名称、源项目链接与版权展示行，以及 README 的可选来源宣传文字。`Talkify-LICENSE.txt`、内部来源信息和历史记录保持，安装包继续包含原始版权与 MIT 许可文本；MIT 文本没有要求在主界面展示。

Release 构建、Developer ID 签名、Finder 覆盖安装、二进制／许可一致性和偏好保留检查通过。本机当前为 `/Applications/Tess.app` **0.2.0 (19)**，候选保留在 `.build/local-brand19/Tess.app`。已通过 CUA 查看关于页，确认不再显示 Talkify、作者名或源项目链接。此次仅删除说明性界面行，未新增测试，未改业务逻辑。证据在 `evidence/20261024-about-cleanup/`；没有公证或发布。


## 同日追加：build 20 状态栏轮廓

用户指出浅米色状态栏中精灵可读性不足。仅给 18pt 菜单栏静止／眨眼／倾听三帧增加约 0.68pt 深松绿圆角描边；填色、眼睛、轮廓、位置和动作时序保留，其他品牌资源字节一致。原生生成脚本同步更新。

Release 构建、米色／白色／深绿背景对比、Finder 本机安装、签名和偏好保留核对通过。当前本机为 **0.2.0 (20)**，候选 `.build/local-brand20/Tess.app`。比较图及证据：`evidence/20261024-menubar-outline/`。仅资源微调，未重复业务回归或真人录音；正式发行继续暂缓。
