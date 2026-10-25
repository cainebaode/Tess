# Tess build 28：ChatGPT 原窗口兼容输入

日期：2026-10-25。版本：0.2.0 build 28。本机已安装，实际 Fn 输入待用户确认。

## 诊断结论

用户提供的 build 27 两次会话均为同一失败路径：`com.openai.codex` 的 `AXManualAccessibility` 返回 `-25205 / attributeUnsupported`，焦点输入框返回 `-25212 / noValue`，随后自动复制。错误含义已核对本机 Apple SDK `AXError.h`。因此，build 27 的辅助功能准备不足以解决本机问题，不能记为成功。

同一应用标识有 [未向辅助功能 API 暴露窗口的公开问题报告](https://github.com/openai/codex/issues/25740)。该报告是参考线索；本机已直接证实的是用户诊断中的焦点缺失和准备请求不受支持，没有通过桌面工具读取当前聊天应用或代做物理 Fn 验收。

## 修复与保护

- 普通可识别输入框继续走原校验。仅在当前应用为 `com.openai.codex`、没有焦点输入框、错误为 `noValue` 或 `attributeUnsupported`，且由录音快捷键触发时，启用原窗口兼容路径；权限错误、忙碌、可识别但校验失败的输入框均不进入该路径。
- 从 Window Server 的可见窗口元数据中选取该进程最前面的普通窗口，仅使用 ID 和几何位置，不读取窗口标题、文字或图像。输出前再次检查同一进程和同一窗口 ID。
- 复用微信已有的会话操作保护，命名统一为 `InputInteractionGuard`：点击、打字、滚动、切换应用、监听失效后不可恢复为有效目标；Fn 轻点／长按与系统 Globe 事件保留原兼容规则。
- 继续检查系统安全输入；不模拟发送键。原窗口路径无法核对输入框类型和光标，用户必须先点进聊天输入框，不用于密码；录音中操作会改为复制。设置的诊断区域已说明这一限制。
- 诊断增加 `chatgpt_window_captured` 和窗口 ID；保留 `paste_posted`、`interaction_changed`、`window_changed` 及复制回退等状态。旧 build 27 诊断仍可读取，诊断继续不含正文。

## 检查与安装

- 输入交付检查通过：复现焦点 `noValue` 的判定、限定应用与错误范围、拒绝可识别输入框绕过校验、窗口筛选／前后顺序／ID 变化、共享 Fn 与操作保护、诊断隐私和剪贴板保护。使用模拟窗口元数据、独立剪贴板及本地回调，未查询真实窗口、安装事件监听或发出真实按键。
- 四种 Fn 模式、手势、取消与复制回退检查通过。Release 构建通过，已有 OnboardingView Combine 导入警告未在本轮修改范围内处理。
- 原 Bundle ID `life.baode.tess`、Developer ID Team `9D6XC2T2G5`、Hardened Runtime 和时间戳保留；候选及安装版严格签名验证通过。随包基础模型 7 个文件与 build 27 逐个摘要一致。
- 已退出旧版，经 Finder 替换 `/Applications/Tess.app`，完整安装文件与签名候选一致。启动后界面确认 `0.2.0 (28)`、辅助功能已授权、Fn 启用、基础语音模型就绪，旧诊断可加载。未重置用户数据目录、模型或授权；没有修改偏好存储逻辑。

候选：`.build/local/0.2.0-build28/Tess.app`。回退：`.build/local/0.2.0-build27/Tess.app`。技术记录、本轮修改前后源码及 build 27 故障摘要位于 `evidence/20261025-chatgpt-window-input/`。未公证、制作 DMG 或公开发布；公开下载仍为 build 25。

## 用户待测试

先点击 ChatGPT 桌面聊天输入框，分别测试 Fn 长按和轻点；确认文字只进入一次、不自动发送。再测试录音期间点击或切换应用，确认只复制、不误插入。如仍不进入输入框，复制新的输入诊断继续排查；技术检查通过不等于已收到真人自动输入成功反馈。
