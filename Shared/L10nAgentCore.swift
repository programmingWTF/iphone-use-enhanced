//
//  L10nAgentCore.swift
//  iPhoneUse
//
//  English copy for the agent loop, remote-gateway and voice UI. Agent system prompts, tool
//  results and protocol payloads (`error:`, `done:`) stay English and are not listed here.
//

import Foundation

enum L10nAgentCore {
    static let table: [String: String] = [
        // PhoneAgent: run status, demo conversation and step summary.
        "正在启动": "Starting",
        "帮我在星巴克点常喝的那杯咖啡": "Help me order the coffee I usually get at Starbucks",
        "直接打开星巴克。": "Just open Starbucks.",
        "「点单」标签在底部。": "The Order tab is at the bottom.",
        "往下翻找最近的订单。": "Scroll down to find recent orders.",
        "有两条最近的订单都符合，需要确认是哪一杯。": "Two recent orders match; need to confirm which one.",
        "把选好的饮品加入购物车。": "Add the selected drink to the cart.",
        "去结算。": "Go to checkout.",
        "你最近的订单有：燕麦拿铁（大杯）或冷萃（超大杯）。要哪一个？": "Your recent orders: Oat Latte (Large) or Cold Brew (Venti). Which one?",
        "已下单，8 分钟后可取。": "Order placed; ready in 8 minutes.",
        "已停止": "Stopped",
        "模型没有返回操作：%@": "Model returned no actions: %@",
        "%@ %@ %@（截图 %@s，LLM %@s）": "%@ %@ %@ (screenshot %@s, LLM %@s)",
        "提问：%@": "Question: %@",
        "回答：%@": "Answer: %@",
        "达到 %@ 步上限，已放弃": "Reached the %@ step limit; gave up",

        // RemoteGateway: status line and the approval card.
        "已关闭": "Off",
        "请填写 HTTPS 网关网址，不要附带令牌或查询参数": "Enter the HTTPS gateway URL without a token or query parameters",
        "请填写网关的设备令牌": "Enter the gateway device token",
        "后台不接收新任务": "Not accepting new tasks in the background",
        "正在连接网关…": "Connecting to the gateway…",
        "连接断开，正在重试…": "Connection lost; retrying…",
        "正在执行任务": "Running a task",
        "等待你确认任务": "Waiting for your approval",
        "正在确认执行": "Confirming execution",
        "正在回传结果": "Sending back the result",
        "已连接，前台可接收任务": "Connected; accepting tasks in the foreground",
        "%@ 请求使用这台 iPhone": "%@ requests to use this iPhone",
        "仅在你同意后执行。此请求会自动过期。": "Runs only after you approve. This request expires automatically.",
        "拒绝": "Decline",
        "同意并执行": "Approve and run",
        "远程任务确认": "Remote task approval",

        // Voice.swift: microphone and transcription errors.
        "请在设置中允许访问麦克风，才能使用语音。": "Allow microphone access in Settings to use voice.",
        "转写失败：%@": "Transcription failed: %@",
        "没有麦克风输入。": "No microphone input.",

        // ShortcutsGuideView: shortcut and deep-link instructions.
        "快捷指令": "Shortcuts",
        "打开「快捷指令」App，点右上角 + 新建一个快捷指令。": "Open the Shortcuts app, tap + at the top right and create a shortcut.",
        "从 iPhone Use 添加「运行 Agent」操作。": "Add the Run Agent action from iPhone Use.",
        "填写提示词；留空则每次运行时询问。": "Enter a prompt; leave it empty to be asked each time.",
        "可以从 Siri、操作按钮、轻点背面、小组件或自动化运行。": "Run it from Siri, the Action button, Back Tap, a widget or an automation.",
        "打开快捷指令": "Open Shortcuts",
        "不做任何设置，也可以直接对 Siri 说「询问 iPhone Use」。": "With no setup, you can also just ask Siri to Ask iPhone Use.",
        "深链": "Deep link",
        "复制示例": "Copy example",
        "打开该链接会带上提示词开始一个新会话。提示词需要 URL 编码；在快捷指令里使用「打开 URL」操作。": "Opening the link starts a new conversation with the prompt. The prompt must be URL-encoded; use the Open URL action in Shortcuts."
    ]
}
