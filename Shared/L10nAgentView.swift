//
//  L10nAgentView.swift
//  iPhoneUse
//
//  English copy for the chat screen and its supporting views. Keys are the Simplified Chinese
//  source strings exactly as they appear in `t(...)`; values are the English rendering.
//

import Foundation

enum L10nAgentView {
    static let table: [String: String] = [
        // Chat screen
        "完成": "Done",
        "停止会话": "Stop session",
        "会话列表": "Sessions",
        "新会话": "New session",
        "历史记录": "History",
        "使用该提示词": "Use this prompt",
        "删除": "Delete",
        "还没有会话": "No sessions yet",
        "对话": "Chat",
        "设置，需先完成配置": "Settings, setup incomplete",
        "设置": "Settings",
        "复制": "Copy",
        "选择文本": "Select text",
        "已复制": "Copied",
        "步骤": "Steps",
        "关闭": "Close",
        "消息全文": "Full message",
        "已复制代码": "Code copied",
        "复制代码": "Copy code",
        // Composer
        "问点什么": "Ask anything",
        "回答": "Answer",
        "发送": "Send",
        "发送回答": "Send answer",
        "停止录音": "Stop recording",
        "语音输入": "Voice input",
        // Starter prompts
        "看看微信里有没有等我回的消息，列出来，先别回": "Look for WeChat messages waiting on my reply and list them; don't reply yet",
        "用美团外卖点一份附近评分高的午饭，别超过 30 元": "Order a highly rated lunch nearby on Meituan; keep it under ¥30",
        "打开支付宝，看看这个月的账单都花在哪了": "Open Alipay and show where this month's spending went",
        // Cellular-data help
        "iOS 不允许通过蜂窝数据连接这台 iPhone。请接入 Wi-Fi，或在连接时先关闭蜂窝数据：连上之后可以再打开。": "iOS won't connect to this iPhone over cellular data. Join Wi-Fi, or turn cellular data off while connecting — you can turn it back on afterwards.",
        "方式一": "Option 1",
        "在控制中心关闭蜂窝数据，然后：": "Turn cellular data off in Control Center, then:",
        "连接": "Connect",
        "安装蜂窝数据开关快捷指令": "Install the Cellular Data Toggle shortcut",
        "方式二": "Option 2",
        "这个快捷指令只需添加一次。之后连接时 App 会自行关闭再打开蜂窝数据。": "You only need to add this shortcut once. On later connections the app turns cellular data off and back on by itself.",
        "使用蜂窝数据时": "When Using Cellular Data",
        "去设置": "Open Settings",
        // Connection status
        "未连接": "Not connected",
        "已连接这台 iPhone": "Connected to this iPhone",
        // Shared alerts
        "重试": "Retry",
        "取消": "Cancel",
        "好": "OK",
    ]
}
