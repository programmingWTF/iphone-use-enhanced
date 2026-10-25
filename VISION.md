# 愿景 · Vision

< 简体中文 | [English](#english) >

## 起点

上游 [iphone-use-app](https://github.com/EliotAndres/iphone-use-app) 证明了「让模型直接操作手机」这件事
在 iOS 上可行：用开发者服务和回环 VPN，让一个 App 控制它自己跑着的那台 iPhone。

但这个原型是为「有一台 Mac、在英文环境、网络通畅」的人写的。对想长期把它当工具用的人，
门槛不在原理，而在细节：没有 Mac 就编译不了、国内拉不到 DDI、中文打不进去、界面读不懂、
模型回复一团纯文本。

## 原则

1. **开箱即用优先**：默认配置应该是能用的配置。做不到就要在界面上说清楚缺什么。
2. **看得见**：每一步都有截图与一句话解释；失败必须说清原因，不允许静默失败。
3. **只用自己的设备**：这是给「想让自己手机更好用」的人的工具，不做群控、不做刷量。
4. **不隐藏边界**：哪些是 Apple 给的能力、哪些是我们绕的路，文档写明白；能失效的地方提前说。
5. **中文是一等公民**：不是翻译，而是按中文输入法、中文网络环境重新设计流程。

## 现在的样子

- 有 iPhone + 任意签名工具，就能装上用；CI 直接出包，挂在 Release。
- 中文输入走拼音；DDI 有多镜像与进度；界面全中文；回复按 Markdown 渲染。
- 可选网关让电脑把任务投递到手机，默认关闭、默认需要批准。

## 方向

- **降低安装门槛**：更清楚的一页式安装指引；签名工具的可选说明。
- **稳定性**：DDI、隧道、配对过期这几条最容易碎的地方，尽量给出可自愈的流程。
- **可观察性**：更完整的日志与失败分类，让「为什么连不上」不再靠猜。
- **界面**：继续收敛液态玻璃的用法，颜色只出现在有意义的地方。

## 不做的事

- 不做 App Store 版本（依赖开发者服务，无法过审）。
- 不做越狱、注入、破解类能力。
- 不做多设备群控与自动化营销。
- 不内置任何模型 Key，不代收 API 费用。

## 参与

改代码、提 issue、写文档都算。先读 [CONTRIBUTING.md](CONTRIBUTING.md)，标签体系见 [LABELS.md](LABELS.md)。

---

## English

The upstream project proved that a model can drive the phone it runs on. This fork makes that practical for
people who *don't* own a Mac, live behind a slow network, and read Chinese: CI builds the app, the DDI
download walks mirrors, Chinese text goes in as pinyin, the UI is localised, and replies render as Markdown.

Principles: **defaults must work**, **nothing fails silently**, **your own device only**, **state the
boundaries**, **Chinese is a first-class citizen**. Non-goals: App Store distribution, jailbreak or injection
tricks, multi-device farms, bundled model keys.
