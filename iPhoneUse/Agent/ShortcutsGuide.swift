//
//  ShortcutsGuide.swift
//  iPhoneUse
//
//  How to start runs from outside the app: the "Run Agent" App Intent (Shortcuts,
//  Siri, Action button) and the iphoneuse://run?prompt=... deep link.
//

import SwiftUI
import UIKit

enum DeepLink {
    static let example = "iphoneuse://run?prompt=Turn%20on%20dark%20mode"

    /// The prompt of an `iphoneuse://run?prompt=...` link, nil for anything else.
    static func prompt(from url: URL) -> String? {
        guard url.scheme == "iphoneuse", url.host() == "run",
              let prompt = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "prompt" })?.value?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !prompt.isEmpty
        else { return nil }
        return prompt
    }
}

struct ShortcutsGuideView: View {
    @ObservedObject private var language = LanguageStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                GlassSection(t("快捷指令")) {
                    Step(1, t("打开「快捷指令」App，点右上角 + 新建一个快捷指令。"))
                        .glassRow()
                    GlassRowDivider()
                    Step(2, t("从 iPhone Use 添加「运行 Agent」操作。"))
                        .glassRow()
                    GlassRowDivider()
                    Step(3, t("填写提示词；留空则每次运行时询问。"))
                        .glassRow()
                    GlassRowDivider()
                    Step(4, t("可以从 Siri、操作按钮、轻点背面、小组件或自动化运行。"))
                        .glassRow()
                    GlassRowDivider()
                    Link(destination: URL(string: "shortcuts://")!) {
                        Label(t("打开快捷指令"), systemImage: "arrow.up.forward.app")
                    }
                    .glassRow()
                } footer: {
                    Text(t("不做任何设置，也可以直接对 Siri 说「询问 iPhone Use」。"))
                }

                GlassSection(t("深链")) {
                    Text(DeepLink.example)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .glassRow()
                    GlassRowDivider()
                    Button(t("复制示例"), systemImage: "doc.on.doc") { UIPasteboard.general.string = DeepLink.example }
                        .glassRow()
                } footer: {
                    Text(t("打开该链接会带上提示词开始一个新会话。提示词需要 URL 编码；在快捷指令里使用「打开 URL」操作。"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .navigationTitle(t("快捷指令与深链"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct Step: View {
    let number: Int
    let text: String

    init(_ number: Int, _ text: String) {
        self.number = number
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            Text(text)
        }
    }
}

