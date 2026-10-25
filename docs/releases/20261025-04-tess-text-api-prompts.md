# Tess build 26：国内文字服务与可编辑提示词

日期：2026-10-25。版本：0.2.0 build 26。本轮为本机迭代。

## 范围与使用入口

用户确认只接文字模型，语音识别继续本机处理。

- 设置 → 文字模型 → 添加配置：国内服务商优先，地址、模型 ID、API Key 均可修改；保留自定义兼容服务、海外服务和本机 Ollama。
- 设置 → 文字模型 → 编辑提示词：调整通用要求、轻量整理、列表整理、自然润色；可逐项或全部恢复默认，保存前取消不改变已保存内容。
- 每次请求使用“通用要求 + 当前模式规则”。所有文字服务共用提示词，当前录音／整理使用开始时的快照，修改从下次会话生效。
- 编辑 / 测试：选择三种整理模式之一，使用预置或自行编辑的文字测试已保存提示词。真实测试由用户发起，可能产生服务商 API 费用。

提示词不影响原文模式的本地听写。原有数字、术语、否定等变化检查继续生效；有疑问时保留原文及候选供对照。

## 国内覆盖与官方资料

覆盖 11 家国内服务商。腾讯保留原混元与 TokenHub 两个入口；智谱保留既有试用预设 ID。预设不代表账户已开通模型或逐家真实连接通过。

| 服务商 | 接口根地址 | 官方资料 |
| --- | --- | --- |
| DeepSeek | `https://api.deepseek.com` | [接口与模型](https://api-docs.deepseek.com/) |
| 阿里云百炼 | `https://dashscope.aliyuncs.com/compatible-mode/v1` | [地域与根地址](https://help.aliyun.com/zh/model-studio/base-url) |
| 火山方舟／豆包 | `https://ark.cn-beijing.volces.com/api/v3` | [兼容接口](https://docs.volcengine.com/docs/ark/compatible-with-openai-sdk?lang=zh) |
| Kimi | `https://api.moonshot.cn/v1` | [兼容说明](https://platform.kimi.com/docs/guide/migrating-from-openai-to-kimi) |
| 智谱 | `https://open.bigmodel.cn/api/paas/v4` | [兼容说明](https://docs.bigmodel.cn/cn/guide/develop/openai/introduction) |
| MiniMax | `https://api.minimax.cn/v1` | [国内接口](https://platform.minimax.cn/docs/api-reference/text-openai-api) |
| 腾讯 TokenHub／混元 | `https://tokenhub.tencentmaas.com/v1`；旧平台 `https://api.hunyuan.cloud.tencent.com/v1` | [TokenHub](https://cloud.tencent.com/document/product/1823/130078)、[旧混元](https://cloud.tencent.com/document/product/1729/111007) |
| 百度千帆／文心 | `https://qianfan.baidubce.com/v2` | [接口](https://cloud.baidu.com/doc/qianfan-docs/s/Fm9l6ocai) |
| 讯飞星火 | `https://spark-api-open.xf-yun.com/v1` | [HTTP 接口](https://www.xfyun.cn/doc/spark/HTTP调用文档.html) |
| 阶跃星辰 | `https://api.stepfun.com/v1` | [开放平台](https://platform.stepfun.com/) |
| 硅基流动 | `https://api.siliconflow.cn/v1` | [文字接口](https://docs.siliconflow.cn/docs/userguide/capabilities/text-generation) |

明确的官方模型示例已预填，其他按控制台填写。地域、套餐、模型开通状态和价格以对应账户为准，取消原先未经当前账户确认的“免费试用”表述。讯飞 API Key 栏使用对应 HTTP APIPassword。

请求等待上限由 10 秒延长至 60 秒，可取消。星火官方地址明确关闭默认联网搜索，并兼容其非流式成功响应缺少 `finish_reason` 的格式；该差异仅用于官方地址和协议，不放宽其他服务的响应检查。

## 本地数据与验证

提示词保存在偏好的可选 `textPrompts` 字段；旧设置缺少此字段仍能读取并采用原默认规则。保存失败不会替换当前生效提示词。API Key 仍只保存在 Keychain，旧服务 ID 和既有配置保留。

- 文字检查：两种协议与三种模式的请求体、原文与提示词分离、空提示词拒绝、原文离线、星火官方地址参数与响应差异。
- 交互检查：旧偏好解码、提示词保存与重启恢复、保存失败保护；原有会话检查通过。
- 存储检查：读取失败、恢复副本、重试及密钥删除回滚等原有检查通过。
- Release 构建通过；使用原 Developer ID（Team `9D6XC2T2G5`）、Bundle ID `life.baode.tess`，完整离线模型摘要核对通过。
- 已通过 Finder 替换安装至 `/Applications/Tess.app`，严格签名检查通过，安装包内容与本机候选一致，应用界面显示 `0.2.0 (26)`。已短暂检查文字模型和提示词入口；没有修改用户提示词、发起 API 测试或代做人工输入验收。

检查只用隔离数据与合成请求／响应，没有读取真实密钥或调用付费 API。真实连通、整理质量及人工使用验收仍待用户完成。未进行本轮公证、DMG 或公开发布。

候选：`.build/local/0.2.0-build26/Tess.app`。回退：本轮安装前保留的 `.build/local/0.2.0-build25/Tess.app`。详细构建、检查及源码依据位于本机 `evidence/20261025-text-api-prompts/`，不上传源码 Git。
