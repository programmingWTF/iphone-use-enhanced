//
//  MessageTextSheet.swift
//  iPhoneUse
//
//  The "选择文本" item of a message's long-press menu: the whole message, scrollable
//  and selectable, with 复制 and 完成 in the top bar.
//

import SwiftUI
import UIKit

/// One chat message in full, because the bubble itself wraps (and markdown replies are
/// rendered, not raw). Plain glass, like every other surface except the identity colours.
struct MessageTextSheet: View {
    let text: String
    let isMarkdown: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                GlassCard {
                    if isMarkdown {
                        MarkdownText(text: text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    } else {
                        Text(text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("消息全文")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(copied ? "已复制" : "复制") { copy() }
                        .disabled(copied)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func copy() {
        UIPasteboard.general.string = text
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeOut(duration: 0.15)) { copied = false }
        }
    }
}
