# Tess 正式安装包实施进度

2026-10-24：本机已更新 **build 20** 绿色精灵 + Humanist 视觉版，构建、隔离交互回归、签名及主要窗口检查通过，设置和离线模型保留。build 17 真人使用验收仍为既有证据，本轮未重复真人录音。正式公证和 DMG 继续暂缓，dist 仍是旧 build 14。以 [品牌更新记录](../history/20261024-01-tess-brand-refresh.md) 为当前状态，下文为历史进展。 build 19 已移除正常界面中的 Talkify 标注，原版权与许可文本仍随包保留。 build 20 为状态栏精灵增加细深绿描边。

## 已完成

- 五步首次引导：欢迎、麦克风与辅助功能、模型准备、真实试说、外部输入确认。保存引导步骤；旧配置通过可选字段兼容。
- 试说走生产录音与识别管线，只有非空最终识别才标为成功；练习不写入剪贴板或其他应用。取消、无声、识别失败不能标为通过。
- Release 隐藏原有 HUD 演示、smoke 与 benchmark 入口；内部构建通过 `TESS_INTERNAL_CHECKS` 显式启用。加入单实例检查、再次打开应用入口、随包帮助与手动更新说明。
- 版本 0.2.0 build 13 已构建，并以 `Developer ID Application: Caine Chen (9D6XC2T2G5)` 签名，启用 Hardened Runtime 和 Apple 时间戳；签名完整性验证通过。
- 已安装 `/Applications/Tess.app` 并实际启动。首次引导与权限页面已检查，画面保存为 `evidence/20261020-03-release/onboarding-permissions.png`。
- 用户已亲自授予麦克风和辅助功能；实际界面显示两项“已允许”。暂停时停在第 2 步，尚未开始真人试说。
- 使用生产下载代码从 Hugging Face 完整下载并验证 Qwen 0.6B，712,777,119 字节。模型在 `.build/release-models/qwenSmall`，并未伪造用户首次下载完成状态。
- 引导及录音状态、输入迁移、剪贴板隔离回归通过；新引导用例验证取消、无声、失败、成功与外部输入分流。实际模型的合成语音中英文、中间转录、取消后最终识别及 5 分钟检查通过。
- 正式 Xcode 归档命令已完成，退出码 0。归档在 `.build/Tess-0.2.0.xcarchive`。暂停收尾时归档自然完成，没有继续上传。

## 第二轮已完成

- 最后的小修正已重建，最终 interaction 回归通过。
- 原联网版 build 13 已通过 Apple 公证，`stapler validate` 成功，Gatekeeper 返回 `accepted / source=Notarized Developer ID`。直接复用了 Xcode 已登录账号，无需新增 API 密钥。
- 已制作该联网版的签名 DMG，并验证磁盘镜像完整性。但随后实际界面的 712.8 MB 模型下载明显偏慢，因此按原方案允许的回退改为随包提供基础模型。
- **最新源码与已安装应用为 0.2.0 build 14 离线版本。**基础模型放在签名资源 `Contents/Resources/BaseSpeechModel.tessmodel`，仅只读使用；不复制到用户目录，不再次下载。
- 模型打包前逐文件核对原下载摘要。补齐 Apache 2.0 完整许可及 Qwen／转换作者来源说明，保留原权重。
- 本地有效下载模型优先；删除下载缓存会回退到随包模型。设置隐藏随包模型的删除按钮。模型校验对签名资源容许磁盘镜像复制导致的时间戳取整，仍校验文件列表、大小与模型来源；发行前对权重执行完整摘要校验。
- `scripts/check-bundled-model.sh` 通过：时间戳变化、prepare 路由、已下载模型优先、删除缓存不破坏签名资源、不完整包拒绝。运行时使用隔离替身；不等于真实录音证据。
- `scripts/archive-release.sh` 已准备并成功执行最终离线归档。最终帮助文件与源码逐字一致，二进制含最新说明；无 `--smoke-test`、`--hud-preview`、`--asr-benchmark`、`TESS_DATA_DIRECTORY` 测试入口。
- 已安全退出旧版并更新 `/Applications/Tess.app`。实际启动后，第 3 步显示“基础语音模型已随应用提供”“模型已校验，可以继续”。两项系统权限保留，进入第 4 步试说。**没有点击开始试说，未启动麦克风。**

## 暂停时的公证状态

最终离线 build 14 已通过 Xcode 开始上传公证，但用户正在开车，需要暂停。已向确切的 `xcodebuild -exportArchive ... -exportPath .build/notary-offline-export` 进程发送 SIGINT。上传最后观察约 16%，没有拿到最终通过结果。

联网 build 13 的公证成功不能当作离线 build 14 的成功。离线版归档仍保存在 `.build/Tess-0.2.0.xcarchive`，可以重新提交。继续时先确认上传进程已退出，并检查 Apple/Xcode 是否已经留有提交结果；不要仅凭旧公证记录跳过最终版验证。

## 当前文件对应关系

| 位置 | 实际版本和用途 |
| --- | --- |
| `/Applications/Tess.app` | build 14，带基础模型，已正式签名；最终版公证尚未通过 |
| `.build/Tess-0.2.0.xcarchive` | build 14 最终离线归档，模型摘要及源码一致性已核对 |
| `.build/notarized/Tess.app` | 已公证的旧联网 build 13 |
| `dist/Tess.app` | 已公证的旧联网 build 13 |
| `dist/Tess-0.2.0-arm64.dmg` | 约 7.9 MB，旧联网 build 13；**不是最终离线安装包** |
| `.build/release-models/qwenSmall` | 已完整下载校验的权重来源，712,777,119 字节 |
| `.build/acceptance/input.html` | 备用的本机浏览器输入测试页，尚未启动服务器或打开页面 |

## 继续顺序

1. 不重新询问公证凭据。继续使用现有 Xcode 登录：`xcodebuild -exportArchive -archivePath .build/Tess-0.2.0.xcarchive -exportOptionsPlist .build/release-tools/ExportOptions.plist -exportPath .build/notary-offline-export`。
2. Apple 通过后用 `xcodebuild -exportNotarizedApp` 导出到一个明确的新目录（例如 `.build/notarized-offline`）。必须确认 **build 14、随包模型存在、代码签名有效、stapler 成功、Gatekeeper accepted**，不能误用旧 build 13 的导出结果。
3. 将最终公证版替换 `dist/Tess.app`，运行 `scripts/package-dmg.sh`，覆盖旧的小 DMG。脚本要求正式 Developer ID、公证票据和 Gatekeeper 通过，输出 SHA-256；更新或移除旧 ZIP，避免交付错版本。
4. 用户方便后，继续第 4 步真实试说。上次尚未进行，不能标为成功。此后验证 Fn、文本编辑／浏览器／聊天输入框、取消重入、切换目标、休眠唤醒、覆盖更新保留数据，以及实际下载后 Gatekeeper 检查。
5. 全部完成才宣称达到全部交付标准。若用户暂不参与，则保留真人验收待办，交付状态如实表述。

日志统一在 `evidence/20261020-03-release/`。关键记录：`archive-offline-final.log`、`bundled-model.log`、`notary-offline-export.log`。`scripts/archive-release.sh` 负责完整权重摘要、归档、嵌入模型及正式签名；`scripts/package-dmg.sh` 负责公证后的安装包。当前没有运行麦克风或启动验收页面服务器。

## 第三轮恢复记录

- 自动审批两次拒绝公证上传，要求明确授权具体归档和 Apple 目的地。完成 `payload-audit.json` 后，用户明确回复“允许上传至 Apple 公证服务”。后续沿用该授权，不要再次询问。
- 已重新完整上传 build 14。导出曾返回“processing and not ready for distribution”，尚待 Apple 完成处理，不能当作失败或通过。
- 新增实际运行库检查：空用户模型目录下，直接使用应用内真实基础模型完成中英文合成语音、中间转录与最终结果、5 分钟检查。已通过，结果位于 `included-model-asr.json`。初次测试工具使用符号链接导致资源校验拒绝，改成与正式应用一致的实际文件布局后通过；未修改生产代码。
- Tess 已冷启动并恢复第 4 步，未开始录音。已保存覆盖安装前的 Tess 设置结构快照于 `.build/acceptance/preferences-before-install.json`。
- `.build/acceptance/serve.py` 已准备，用于仅绑定本机回环地址的浏览器下载和输入验收；尚未启动。

## 当前交付记录

- **最终离线 build 14 已通过 Apple 公证并导出**，`stapler validate` 成功，Gatekeeper 为 `accepted / Notarized Developer ID`。结果在 `.build/notarized-offline/Tess.app`。
- `dist/Tess.app` 已更新为已公证的离线 build 14，`dist/Tess-0.2.0-arm64.dmg` 也已覆盖为最终离线版；旧 ZIP 已移除。
- 最终 DMG 大小 617,186,356 字节，SHA-256 为 `f83cfc1f5f1d8fdd6c543764da491c8db3f2d06bacb1645b321dbea4749dbf49`。
- 已通过 Chrome 从仅本机 HTTP 页面实际下载至 `/Users/caine/Downloads/Tess-0.2.0-arm64.dmg`，保留下载隔离标记，摘要与发布包一致。不是公开下载站点验收。
- 已用 Finder 打开下载的 DMG，执行复制与“替换”，安装至 `/Applications/Tess.app`。模型、设置结构、权限和引导进度保留；实际安装后的签名、公证票据和 Gatekeeper 均通过，应用实际启动成功。
- 分发资源读取权限已规范化，基础模型可供不同本机用户读取，签名验证仍通过。两个发布脚本已同步处理权限。
- 退出安装前，生产界面已显示“试说成功”和“已完成语音识别”；持久化的 onboardingPracticePassed 为 true。没有替用户点击开始试说，也没有伪造结果；具体识别质量尚未获得用户确认。
- 已进入第 5 步并打开空白文本编辑文档。当前正在等待异步问题“按住 Fn 说指定句子，是否自动进入文档”的回复；读取的文档仍为空。请先接续这个反馈，不要重置权限、重装或要求重新下载。
- 浏览器／聊天输入框、真实取消重入和目标切换、休眠唤醒仍未验收。没有将这些项目标为通过。
- 临时本机 HTTP 服务器已关闭。安装说明与验收状态以 `20261020-04-tess-installer-acceptance.md` 为准，README 顶部已更新。

## 暂停交接：Fn 只复制，尚未完成修复交付

用户要求告一段落，由后续人员继续。本节覆盖上文等待反馈的旧状态。

### 已知故障和本轮改动

- 用户实测反馈“只提示已复制”。不能将外部自动输入标记通过。
- 使用与 Tess 相同 Developer ID 身份的只读诊断，检查空白 TextEdit 的辅助功能元数据：`AXIsProcessTrusted=true`、secure input=false、角色 `AXTextArea`、`AXSelectedTextRange=(0,0)`、`AXValue` 可写；但 `AXEnabled` 返回 `-25205 / attributeUnsupported`。
- `Tess/Sources/DeliveryService.swift` 原先强制 AXEnabled 必须存在且为 true，使该可编辑 NSTextView 被拒绝，转为复制。现允许 AXEnabled 未被支持时继续检查；显式 disabled、其他查询错误仍拒绝；可写 AXValue、密码框、终端、相同焦点和相同选区检查保留。
- `Tess/Checks/DeliveryCheck.swift` 新增上述属性判断回归，`scripts/check-delivery.sh` 已通过，日志 `evidence/20261020-03-release/delivery-build15.log`。该检查使用隔离剪贴板和本地回调，不代表真实粘贴成功。
- `Tess/Info.plist` 源码构建号已改为 **15**。没有运行正式归档；dist、Downloads、/Applications 仍为已公证的 **build 14**，不包含此修复。
- `.build/target-diagnosis/` 是临时诊断源码和应用，不是交付物。尝试用生产 DeliveryService 向空白 TextEdit 插入固定测试句，但自动化操作时前台/目标不稳定，诊断没有确认到 TextEdit，未证明实际粘贴通过。不要把诊断程序的结果当作修复验收。暂停前已停止 TessTargetCheck 进程；没有开始录音，没有改动引导完成状态。

### 后续必须完成

1. 先审查本轮最小修复与诊断证据。必要时继续检查 captureTarget、targetIsValid、HUD 不抢焦点，以及实际 Cmd+V 投递；不能仅凭隔离回归宣称已修复。所有桌面操作通过 CUA，禁止通过脚本模拟 UI。
2. 验证 TextEdit 实际输入，再由用户方便时确认物理 Fn 到自动插入的整条链路。不要在未真实输入成功时点击引导“已确认输入成功”。浏览器/聊天、真实取消重入、切换目标、休眠唤醒仍待验收。
3. 使用 `scripts/archive-release.sh` 正式构建 build 15，嵌入 `.build/release-models/qwenSmall`。按 `.build/release-tools/ExportOptions.plist` 使用 Xcode 现有登录上传 Apple 公证，再用 `xcodebuild -exportNotarizedApp` 导出到明确的新目录；不要误用 `.build/notarized-offline` 的 build 14 或 `.build/notarized` 的 build 13。
4. 用户已明确允许完整应用与公开模型上传 Apple 公证服务。沿用该目的和授权，不重新索要账号、密码或公证凭据；不提交 App Store、不公开发布。
5. 确认新导出应用构建号、模型、签名、stapler 和 Gatekeeper 后，再替换 dist 并运行 `scripts/package-dmg.sh`。重验下载隔离、安装/覆盖更新、配置权限保留，更新 SHA-256 和验收记录。`scripts/build.sh` 会覆盖 dist，且默认不是正式离线包，勿误用。

当前 build 14 DMG 仍是 617,186,356 字节，SHA-256 `f83cfc1f5f1d8fdd6c543764da491c8db3f2d06bacb1645b321dbea4749dbf49`。它有有效公证，但存在已报告的自动输入故障，不能作为达到全部标准的最终交付。

## 2026-10-23 继续记录：build 15 已安装，微信仍阻塞交付

本节覆盖上文暂停时的旧当前状态；历史 build 14 的公证、下载和覆盖安装证据不迁移到 build 15。

- 已审查并回归 TextEdit 缺失 AXEnabled 的修复，保留密码框、只读、焦点和选区检查。生产 DeliveryService 的固定句实际投递通过后，使用 `scripts/archive-release.sh` 生成含离线模型的正式签名 build 15，并安装 `/Applications/Tess.app`。归档现位于 `.build/Tess-0.2.0-build15.xcarchive`；旧 build 14 归档另存 `.build/Tess-0.2.0-build14.xcarchive`。
- 真人 TextEdit 验收：物理 Fn 轻点开始/结束、长按/释放均自动输入成功，样句包含“今天我们测试自动输入”和“明天 review the plan”。用户确认“两次都自动输入，内容基本正确”；不将此表述扩大成精确识别率结论。没有替用户点击“已确认输入成功”。见 `physical-fn-textedit.json`。
- Chrome 155.0.8059.85：普通 textarea 已通过；contenteditable 首次未插入，固定句投递检查后，在测试页保持前台的条件下，用户物理 Fn 重测确认“自动追加成功”。没有为此放宽生产可编辑性判断。见 `browser-and-chat-status.json`。
- 微信 4.1.15 (270115)：用户实测未插入。后续应用级及系统级 AXFocusedUIElement 均返回 `-25212 / noValue`；EnhancedUI=true，ManualAccessibility 不支持。窗口或按钮不代表可编辑输入框，当前没有把它们作为自动投递许可。最终元数据见 `input-metadata-1792767351.040179.json`，它补充浏览器/聊天汇总中尚待检查的 system focus 项。
- 用户明确要求微信必须自动输入后才交付。公证、DMG 与最终交付暂缓，继续解决微信；没有提交 App Store 或公开发布。InputMethodKit/palette 研究见 [微信输入法接口研究](../../evidence/20261023-build15/wechat-input-method-research.md)：可能需要新增系统输入法组件，尚未实现或启用，不构成微信通过证据。
- Fn 休眠状态修复已通过隔离复现及回归：休眠/会话失活时清理 Fn 持键状态，恢复时刷新监听，并保留快捷键录入的暂停状态。该结果没有让 Mac 实际休眠，也不能替代物理唤醒后的第一次 Fn 检查。见 `review-and-regression.md`。
- 真实取消后重开、目标切换、休眠唤醒仍待验收。用户权限、模型和引导进度没有重置；新正式包的覆盖更新与配置权限保留仍需重新检查。

### 当前发行文件

| 位置 | 当前状态 |
| --- | --- |
| `/Applications/Tess.app` | build 15，含离线模型、正式签名，用于本轮真实使用检查；未公证 |
| `.build/Tess-0.2.0-build15.xcarchive` | build 15 离线签名归档；未公证，后续修复若有代码变化须重新归档 |
| `dist/Tess.app`、`dist/Tess-0.2.0-arm64.dmg` | 仍是有已知输入故障的已公证 build 14；不是本轮最终交付 |
| `.build/notarized-offline/Tess.app`、`.build/notarized/Tess.app` | 分别是旧 build 14、旧 build 13，禁止误用为 build 15 |

本轮证据位于 [evidence/20261023-build15](../../evidence/20261023-build15)。继续时先解决微信并完成剩余真人验收，再以明确的新归档/导出目录完成 Apple 公证、签名票据/Gatekeeper、DMG、下载隔离及覆盖更新检查，更新新包摘要。沿用已授权的完整应用与公开模型 Apple 公证上传，无需重新索要凭据。


## 2026-10-23 微信兼容与 Globe 轻点问题：build 17 修复中

- 用户把路线选择交给开发，并强调先让产品可用，不必为罕见边界先重做系统输入法。选择仅微信的窗口级兼容投递：只在录音快捷键开始、微信缺失 AX 输入焦点且有标准窗口时启用。普通应用完整 AX 检查保留；微信仍无法验证输入框类型、光标和选区，这一限制已说明并写入帮助。
- 兼容目标记录 PID/窗口，普通键鼠输入、应用切换或监听中断使目标永久失效；取消、完成和目标替换立即释放监听。仅 Fn 或当前自定义录音快捷键豁免，不发送消息。隔离目标生命周期与剪贴板检查通过。
- 固定句“Tess 微信自动输入检查。”经生产投递代码和签名诊断程序自动进入微信，用户确认“出现”。随后 build 16 离线归档成功并通过 Finder 覆盖安装，设置语义和引导进度一致；模型全文件摘要、签名及载荷审计通过。归档为 `.build/Tess-0.2.0-build16.xcarchive`，证据位于 `evidence/20261023-build16/`。
- build 16 真实微信 Fn：用户确认长按成功，但轻点开始/结束只显示“已复制”。因此没有上传公证或制作最终 DMG。
- 只记事件类别的临时诊断定位到系统发出的 Globe `keyDown`，虚拟键码 179，无 Command/Control/Option 修饰，发生时微信仍在前台。它被兼容保护误判为普通输入。日志为 `wechat-guard-diagnostic.jsonl`；临时诊断副本未编入正式应用。
- 源码构建号提升为 17。正在修复兼容保护对 Globe 伴随事件的判断及 Fn 监听对该系统事件的处理，防止重复触发录音；尚未归档或真人复验。build 15/16 归档分别保留，dist 依然是旧 build 14。
- 完成轻点复验后还要进行真实取消重入、目标切换、休眠唤醒，再完成新的公证、DMG、下载隔离、覆盖安装及摘要。不得把本节检查当作这些项目通过。


### build 17 归档与候选安装完成，等待真人复验

- 修复 Fn 附带 Globe 179 事件：179 按绑定吞下并配对释放，不触发录音；63 仍是唯一录音触发来源。微信保护只对 Fn 会话豁免伴随事件，普通输入仍使目标失效。六种事件先后顺序和取消/目标生命周期回归通过。设置隐私说明同步为准确的事件处理描述。
- `scripts/archive-release.sh` 成功，最终归档为 `.build/Tess-0.2.0-build17.xcarchive`，源码与 `evidence/20261023-build17/source-final` 一致。第一次归档因文案修正保留在 `build17-before-copy-update` 路径，没有安装或提交。
- Finder 覆盖安装 `/Applications/Tess.app` 并实际启动；版本为17，二进制与 Info 匹配最终归档，设置语义和引导进度一致。未点击完成引导。见 `candidate-install.json`。
- 用户已确认 build 17 微信轻点/长按两次都自动输入成功，没有系统弹窗；见 `wechat-physical-fn.json`。取消重入、目标切换、真实休眠唤醒仍未完成。公证、新 DMG、下载隔离和最终覆盖安装均未完成。


### 2026-10-24 继续：微信、取消与浏览器通过；公证上传中

- build 17 微信物理 Fn 轻点与长按：用户确认“两次都成功，没有系统弹窗”。
- TextEdit：Esc 取消后立即重新录音，用户确认“只有第二句，输入正常”，无迟到或重复插入。
- Chrome：录音中由普通框切至富文本框，原句没有插入；在富文本框重新录音自动输入成功。用户确认符合预期。
- 最终归档已通过完整载荷、固定版本模型摘要和签名审计，见 `payload-audit.json`、`archive-signature.log`。归档含新版中英隐私说明，无诊断入口、用户录音、配置或凭据。
- Apple 首次上传在传输前因现有登录会话过期失败（portal 1100）。已通过 CUA 打开 Xcode 现有账号重新登录，由用户亲自完成；未索要或读取密码。随后对同一 build 17 归档重新开始上传，日志 `notary-upload-after-login.log`。尚未取得公证通过结果。
- 微信跨应用目标切换、真实休眠唤醒、新 DMG 下载与正式覆盖安装仍待完成。


## 2026-10-24 当前交接：本机可用，正式发行按用户要求暂缓

本节覆盖此前“公证上传中”等状态。用户最新要求：“先不用搞这么正式，我还要改logo。你先保证本机可用。”没有开始 Logo 设计或更换。

### 本机状态与实际验收

- `/Applications/Tess.app` 为 **0.2.0 build 17**，正式 Developer ID 签名，包含完整离线模型；通过 Finder 覆盖安装并启动，二进制/Info 与最终归档一致，设置语义和引导进度未改变。没有重置权限/模型，也没有代点“已确认输入成功”。
- 微信轻点开始/结束、长按/释放均自动输入一次，无系统表情/听写弹窗。用户确认“两次都成功，没有系统弹窗”。
- TextEdit：Esc 取消后立即重新录音，仅新句自动输入，没有取消内容、迟到或重复文字。
- Chrome：录音中从普通框切到富文本框，原句没有插入；重新录音后新句自动进入富文本框。
- 微信：录音中切到 TextEdit，不向旧/新应用误插入；回到微信重新录音输入成功。
- 真实休眠：录音中从苹果菜单休眠，唤醒后旧句没有出现，第一次 Fn 即可正常录音并自动输入。用户确认“符合：旧句没出现，唤醒第一次 Fn 正常”。
- 上述为本轮真人操作反馈，分别存于 `evidence/20261023-build17/` 的 `wechat-physical-fn.json`、`textedit-cancel-reentry.json`、`browser-target-switch.json`、`wechat-target-switch.json`、`sleep-wake.json`。不将隔离回归当作真人验收。
- 微信仍是仅限当前应用/窗口的兼容输入，无法验证框类型、光标和选区。帮助已说明先定位聊天输入框，中途键鼠操作或应用切换改为复制，不自动发送。

### 正式发行状态

- 最终源码快照：`evidence/20261023-build17/source-final`；最终归档：`.build/Tess-0.2.0-build17.xcarchive`。包含固定版本离线模型，载荷/签名/源码审计通过。
- 第一次公证在上传前因 Apple 登录会话过期失败；用户亲自恢复了 Xcode 的现有登录，没有把密码提供给代理。第二次上传在约4%被主动中断，以先完成真实休眠检查。
- 休眠后的最后一次上传返回 `AsyncHTTPClient.HTTPClientError error 1`，进程退出码70，未取得公证成功。用户随后要求暂缓正式发行；没有重试，也没有任何仍在运行的上传。日志 `notary-upload-final.log`。
- **未生成或交付 build 17 正式 DMG。** `dist/Tess.app` 与 `dist/Tess-0.2.0-arm64.dmg` 仍为旧 build 14，不能当作本机修复版或新发行包。
- 临时本机 HTTP 验收服务器已停止；诊断应用已退出。真实空配置首次安装本轮未重验，保留既有用户数据。
- 后续改完 Logo 后，重新提升构建号、归档并核对载荷，再沿用现有授权完成 Apple 公证、新明确目录导出、签名/票据/Gatekeeper、新 DMG、隔离下载和覆盖安装验收。此前正式公证上传授权仍有效；不提交 App Store、不公开发布。


## 2026-10-24 本机 build 21：截图编辑简化

新截图进入独立图片编辑页，提供红色椭圆圈选、文字、撤销、保存和完成。完成／回车先提交文字与标注，成功复制图片后关闭；保存或复制失败保留窗口。原始像素尺寸保持，未完成引导也可使用截图编辑，不改引导状态；保留本地存储错误提示与重试入口。

Release、隔离 InteractionCheck 和 CaptureCheck 通过；Developer ID 签名，包含既有离线模型。通过 Finder 安装到 /Applications/Tess.app，版本 0.2.0 (21)，应用二进制与候选一致、签名有效、安装前后偏好一致；CUA 确认版本与简洁截图页。候选 .build/local-screenshot21/Tess.app，证据 evidence/20261024-screenshot-editor/。

用户实际反馈“整体可用”，方形／圆形选择、颜色等留待后续迭代。没有将隔离测试表述为完整实机验收；本轮未重做语音真人验收。正式公证和 DMG 继续暂缓，dist 仍为 build 14。

## 2026-10-24 当前交接：build 25 与后续执行流程

本节覆盖此前本机 build 17／21 的旧当前状态。源码与 `/Applications/Tess.app` 已为 **0.2.0 build 25**：新品牌保留，截图为原位选区、全屏调暗、邻近工具栏，默认方框，支持圆圈、文字、六色、撤销、回车完成复制及 Esc 取消。build 24／25 的构建、签名与本机安装已完成，最新截图体验仍待用户人工确认；不能沿用 build 21 的“整体可用”作为本轮通过结论。

`dist` 仍为旧 build 14，本轮未开展正式归档、公证或 DMG。相关本机变更见 README 与 `evidence/20261024-screenshot-in-place/`、`evidence/20261024-screenshot-default-box/`。

用户已确认后续统一按 [迭代与发布流程](../iteration-and-release.md) 执行；项目结构见 [架构与目录地图](../project-map.md)。本轮仅落地流程、导航和结构说明，没有搬迁文件、清理旧包或开始正式发布。
