//
//  L10nWidget.swift
//  iPhoneUse
//
//  English copy for the Live Activity. Its language arrives through `ContentState` because the
//  widget extension cannot read the app's `UserDefaults`.
//

import Foundation

enum L10nWidget {
    static let table: [String: String] = [
        "第 %@ 步": "Step %@",
        "已完成": "Done",
        "停止运行": "Stop running",
    ]
}
