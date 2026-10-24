//
//  App.swift
//  iPhoneUse
//

import SwiftUI
import UIKit

@main
struct IPhoneUseApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var wasInBackground = false

    init() {
        UserDefaults.standard.register(defaults: ["keepAliveAudio": true, "keepAliveLocation": true])
    }

    var body: some Scene {
        WindowGroup {
            AgentView() // Settings opens from its toolbar
            .buttonStyle(.haptic(.automatic))
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    wasInBackground = true
                case .active where wasInBackground:
                    // The tunnel often dies while suspended. Don't swap it under a running agent.
                    wasInBackground = false
                    auditClipboard()
                    if !PhoneAgent.shared.isRunning {
                        Task { await Connection.shared.connect(force: true) }
                    }
                default:
                    break
                }
            }
        }
    }

    /// The agent types by writing the shared pasteboard while another app is in front, and iOS
    /// only lets a foreground app read the pasteboard back — so the write can't be verified from
    /// the place that makes it. Now that this app is frontmost again, compare what the clipboard
    /// holds with what was requested and report the verdict in the chat (once per run).
    private func auditClipboard() {
        guard let expected = DeviceSession.stagedClipboardText else { return }
        DeviceSession.stagedClipboardText = nil
        let actual = UIPasteboard.general.string
        let message: String
        if let actual, actual == expected {
            message = "剪贴板自检：写入成功（\(expected.count) 字，内容一致）"
        } else if let actual {
            message = "剪贴板自检：内容对不上（期望 \(expected.count) 字，剪贴板里是 \(actual.count) 字）"
        } else {
            message = "剪贴板自检：读不到剪贴板内容"
        }
        DeviceSession.appendLog(message)
        PhoneAgent.shared.entries.append(ChatEntry(kind: .step, text: message))
    }
}
