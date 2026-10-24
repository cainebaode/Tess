# Tess 离线安装包验收记录

2026-10-24 最新状态：源码及本机应用为 **0.2.0 build 25**，包含原位截图和默认方框标注。构建、签名及本机安装完成，最新截图操作由用户人工验收，尚未收到通过反馈；新正式归档、公证、DMG 和最终包安装验收尚未完成。`dist` 仍为旧 build 14。后续按 [迭代与发布流程](docs/iteration-and-release.md) 执行；下文 build 20、17、14 等结论保留为对应版本的历史证据。

2026-10-24 更新。Apple Silicon，macOS 26 或更新版本。本机 `/Applications/Tess.app` 已更新为 **0.2.0 build 20** 绿色精灵 + Humanist 视觉版；安装签名、构建产物一致性、设置保留、基础离线模型及主要窗口核对通过。build 17 真人使用验收保留为既有证据，本轮未重复真人录音。正式公证与新 DMG 继续暂缓，dist 仍为旧 build 14。详见 [品牌更新记录](20261024-01-tess-brand-refresh.md)。 build 19 已移除正常界面中的 Talkify 标注，原版权与许可文本仍随包保留。 build 20 为状态栏精灵增加细深绿描边。

## build 17 本机实际验收

| 项目 | 结果 |
| --- | --- |
| 已安装应用 | 正式签名、完整离线模型；Finder 覆盖安装并启动，二进制/Info 匹配最终归档 |
| 微信 Fn 轻点与长按 | 两次均自动输入一次，无系统弹窗；用户确认成功 |
| TextEdit 取消与立即重录 | 取消内容不插入，仅新句自动输入，无迟到或重复 |
| Chrome 切换输入框 | 旧句不误插入；新位置重新录音后自动输入成功 |
| 微信跨应用切换 | 不向旧/新应用误插入；返回微信重新录音成功 |
| 真实休眠唤醒 | 旧录音取消、旧句不出现；唤醒后第一次 Fn 正常输入 |
| 设置、模型、引导 | 保留；没有重置用户权限或代点完成确认 |
| 正式发行 | 暂缓；未完成 build17 公证、新 DMG、下载隔离及最终覆盖安装 |

微信采用窗口兼容输入，无法检查框类型、光标和选区，使用边界已写入帮助。上述结果基于当前机器和实际测试场景，不代表所有输入框都已覆盖。真正空配置首次安装本轮未重验。

## 旧 build 14 安装包（有已知输入故障，非最终交付）

- [Tess 离线安装包](dist/Tess-0.2.0-arm64.dmg)，617,186,356 字节，约 617 MB。
- SHA-256：`f83cfc1f5f1d8fdd6c543764da491c8db3f2d06bacb1645b321dbea4749dbf49`。
- 打开 DMG，将 Tess 拖入 Applications，再从“应用程序”启动。
- 基础 Qwen3-ASR 0.6B 模型随应用提供；基础听写无需额外下载、账号或 API Key。首次使用按引导授予麦克风和辅助功能。截图权限在首次使用截图时申请。
- 更新时退出 Tess，复制新版并选择替换。当前版本为手动更新，设置中的帮助包含具体步骤。

## build 14 历史发行检查

下表仅记录 2026-10-20 的 build 14 检查，不代表当前候选版已通过相同检查。

| 项目 | 实际证据 |
| --- | --- |
| 正式签名 | Developer ID Application，团队 9D6XC2T2G5，Hardened Runtime，Apple 时间戳 |
| Apple 公证 | 最终离线 build 14 已公证；导出后与实际安装后 stapler 均验证成功 |
| Gatekeeper | 最终应用与实际安装后的应用均返回 accepted，来源 Notarized Developer ID |
| 下载与安装 | Chrome 从仅本机可见的 HTTP 验收页下载，保留 com.apple.quarantine；摘要与发布包一致。Finder 打开 DMG，经“替换”确认复制到“应用程序”，随后实际启动 |
| 配置与权限 | 覆盖安装前后设置结构一致，模型保留，麦克风与辅助功能权限无需重新授予，引导与已完成试说状态恢复 |
| 离线模型 | 发布前逐文件核对固定公开版本摘要；实际识别运行库从应用资源模型加载，空用户模型目录下完成合成语音检查；不依赖开发模型目录或网络 |
| 模型来源与许可 | aufklarer/Qwen3-ASR-0.6B-MLX-4bit，revision bc441bd1e4295c1f42d9879f056049a925b6e013；保留 Apache 2.0 许可与上游来源说明 |
| 存储与签名资源 | 下载缓存优先，删除缓存不会删除随包模型；模型资源可跨本机用户读取，权限规范化后签名仍有效 |
| 基础回归 | 引导取消／无声／失败不能标为通过；Fn 状态、输入迁移、剪贴板恢复、快速重入检查通过。均按日志区分隔离替身与实际推理 |
| 正式包边界 | 不含 HUD 演示、smoke、ASR benchmark 或数据目录覆盖等测试入口 |

浏览器下载检查使用本机回环地址，不代表已经建立公开下载网站；本次没有公开发布或提交 App Store 审核。

## 后续正式发行（用户要求暂缓）

- Logo 修改完成后，以最终源码和新构建号重新归档并核对载荷。
- 完成 Apple 公证，导出到明确的新目录，验证签名、票据和 Gatekeeper。
- 制作新 DMG、记录大小和 SHA-256，重新验证下载隔离、覆盖安装、配置及权限保留。
- 目前没有上传任务；最后一次公证在0%因网络客户端错误退出，未取得通过结果。此项不影响当前本机已安装 build17 的实际使用验收。

## build 15 本轮使用检查

| 项目 | 状态与边界 |
| --- | --- |
| 已安装应用与归档 | build 15，正式签名，包含离线模型；未公证，尚无新 DMG |
| TextEdit 真实自动输入 | 物理 Fn 轻点开始/结束、长按/释放通过，中文及中英混说通过；用户确认内容基本正确，不代表逐字准确率测评 |
| Chrome 普通输入框 | 真人自动输入通过 |
| Chrome 富文本输入框 | 首次未插入；测试页保持前台时物理 Fn 重测自动追加通过，保留生产可编辑性检查 |
| 微信 4.1.15 | 未通过；应用级/系统级输入焦点均 noValue，仍阻塞交付 |
| Fn 休眠状态清理 | 仅隔离复现及回归通过，真实休眠唤醒待测 |
| 取消重入、目标切换 | 真实场景待测 |
| 引导确认 | 未由代理点击“已确认输入成功”；未重置用户权限、模型或引导进度 |

## 证据

build 14 历史发行证据位于 [2026-10-20 证据目录](evidence/20261020-03-release)：`payload-audit.json`、`notary-offline-resume.log`、`notarized-offline-export.log`、`dmg-offline.log`、`browser-download.json`、`installation.json`、`included-model-asr.json` 和 `release-verification.json`。

build 15 本轮证据位于 [2026-10-23 证据目录](evidence/20261023-build15)：`archive-candidate.json`、`textedit-live-delivery.json`、`physical-fn-textedit.json`、`browser-and-chat-status.json`、`input-metadata-1792767351.040179.json`、`review-and-regression.md` 及 `wechat-input-method-research.md`。最后一份微信元数据补充了汇总文件中尚待检查的 system focus 结果。构建、签名、公证与隔离回归不能替代真实使用验收。


build 17 本机与归档证据见 [2026-10-23 build17 目录](evidence/20261023-build17)，以 `acceptance-status.json` 和各真人验收记录为当前状态。正式发行已按用户要求暂缓。
