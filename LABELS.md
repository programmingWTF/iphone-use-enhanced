# 标签体系 · Label Taxonomy

本仓库用一套按维度划分的标签。**标签名保持英文**（便于脚本与跨仓库复用），
描述与本文档是中文；每条都写清「什么时候该用」。

< 简体中文 | [English](#english) >

## 类型 Type（每个 issue / PR 必须有其一）

| 标签 | 什么时候用 |
|---|---|
| `🐛 bug` | 行为和预期不符，能复现 |
| `✨ enhancement` | 新功能或体验改进 |
| `📚 documentation` | 文档、注释、示例 |
| `❓ question` | 用法提问，不一定需要改代码 |
| `🙋 help wanted` | 想请社区帮忙，但维护者短期做不完 |
| `🌱 good first issue` | 适合第一次参与，范围小、上下文清楚 |

## 优先级 Priority

| 标签 | 什么时候用 |
|---|---|
| `P0` | 紧急：数据丢失、安全边界被突破、App 无法启动 |
| `P1` | 高：阻塞主要功能，或影响大量用户 |
| `P2` | 中：正常排期 |
| `P3` | 低：锦上添花 |

## 状态 Status

| 标签 | 什么时候用 |
|---|---|
| `🚧 in progress` | 已经有人在改 |
| `🧱 blocked` | 被外部条件卡住（等 Apple 修、等硬件、等上游） |
| `✅ ready to merge` | 评审通过，可以合并 |
| `🎉 merged` | 已合入 |
| `🚫 wontfix` | 决定不做，issue 里要写清原因 |

## 影响面 Area（改动落在哪一块）

| 标签 | 范围 |
|---|---|
| `area: app` | App 外壳、导航、设置、生命周期 |
| `area: agent` | 智能体循环、提示词、模型接入、聊天 |
| `area: device` | 隧道、配对、截图与触控注入、会话 |
| `area: ui` | 液态玻璃、排版、动效 |
| `area: ddi` | 开发者磁盘映像的下载、镜像与挂载 |
| `area: gateway` | `gateway/` 的 Cloudflare Worker |
| `area: ci` | GitHub Actions 与出包流程 |
| `area: docs` | README、文档、示例 |

## 严重程度 Impact（安全敏感项目专用）

| 标签 | 含义 |
|---|---|
| `impact: security` | 触碰到安全边界：凭据、隧道、网关鉴权、沙箱逃逸 |
| `impact: data-loss` | 会丢失或损坏配对文件、历史、配置 |
| `impact: availability` | 崩溃、卡死、无法连接 |
| `impact: compatibility` | 只在特定 iOS 版本、机型、签名方式下出问题 |
| `impact: ux-blocker` | 用户被卡住且没有出口（没有报错、没法重试） |
| `impact: ux-friction` | 能用但别扭，增加困惑或支持成本 |

## 质量分级 Rating（PR 评审用，从低到高）

评级用「玻璃」主题，越高越通透：

| 标签 | 含义 |
|---|---|
| `rating: 🌫 frosted` | 草稿：思路可行，但还需要明显打磨才能合入 |
| `rating: 🧊 clear` | 可用：逻辑清楚，缺测试或边界处理 |
| `rating: 🔷 tinted` | 完成度高：考虑周全，只剩一两处小问题 |
| `rating: 💎 polished` | 打磨到位：实现干净，边界完整，文案一致 |
| `rating: 🌈 liquid` | 标杆级：可以直接当作后续实现的参考 |

分级顺序固定为 **frosted < clear < tinted < polished < liquid**，评审时只升不降。

## 其它

| 标签 | 什么时候用 |
|---|---|
| `📦 dependencies` | 依赖升级（含 Dependabot） |
| `🔒 security` | 与安全相关但可公开讨论的改动 |
| `↩️ regression` | 以前能用、现在坏了 |
| `👯 duplicate` | 与已有 issue 重复 |
| `🚫 invalid` | 描述不清、无法复现，或不属于本项目范围 |

## 不用标签的约定

- 不用 `bug` + `enhancement` 同时标；先决定它到底是哪种。
- 不用标签当情绪表达（`critical`、`urgent` 一律用 `P0`/`P1` 代替）。
- 不手工创建新标签：先在这个文件里定义，再加到仓库。

---

## English

Label **names** stay English so scripts and cross-repo tooling keep working; descriptions are Chinese in the
table above. In short:

- **Type** (required): `🐛 bug` · `✨ enhancement` · `📚 documentation` · `❓ question` · `🙋 help wanted` · `🌱 good first issue`
- **Priority**: `P0` emergency · `P1` high · `P2` medium · `P3` low
- **Status**: `🚧 in progress` · `🧱 blocked` · `✅ ready to merge` · `🎉 merged` · `🚫 wontfix`
- **Area**: `area: app` · `area: agent` · `area: device` · `area: ui` · `area: ddi` · `area: gateway` · `area: ci` · `area: docs`
- **Impact**: `impact: security` · `impact: data-loss` · `impact: availability` · `impact: compatibility` · `impact: ux-blocker` · `impact: ux-friction`
- **Rating** (low → high): `rating: 🌫 frosted` → `rating: 🧊 clear` → `rating: 🔷 tinted` → `rating: 💎 polished` → `rating: 🌈 liquid`
- **Misc**: `📦 dependencies` · `🔒 security` · `↩️ regression` · `👯 duplicate` · `🚫 invalid`
