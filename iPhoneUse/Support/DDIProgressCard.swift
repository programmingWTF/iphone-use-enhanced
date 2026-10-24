//
//  DDIProgressCard.swift
//  iPhoneUse
//
//  The single progress card for the developer disk image. The connect flow and the
//  settings screen both render this one view, which is what keeps a download to one bar.
//

import SwiftUI

struct DDIProgressCard: View {
    /// Inside a settings section the card already sits on glass, so it drops its own
    /// surface and keeps only the content.
    var embedded = false

    private var center: DDIDownloadCenter { .shared }

    var body: some View {
        if center.isRunning {
            if embedded {
                details
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            } else {
                details
                    .padding(14)
                    .glassSurface(cornerRadius: 20)
                    .padding(.horizontal, 12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ProgressView(value: center.fraction)
                .progressViewStyle(.linear)
                .tint(.blue)
                .animation(.linear(duration: 0.25), value: center.fraction)
            transfer
            sources
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("正在下载开发者磁盘映像")
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(percentText)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
        }
    }

    private var transfer: some View {
        HStack(spacing: 6) {
            Text(transferText)
            Text("·")
            Text(DDIDownloadCenter.speedText(center.bytesPerSecond))
            Text("·")
            Text(DDIDownloadCenter.remainingText(center.remainingSeconds))
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private var sources: some View {
        if !center.source.isEmpty || !center.failedSources.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if !center.source.isEmpty {
                    Label(sourceText, systemImage: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.secondary)
                }
                ForEach(center.failedSources, id: \.self) { failure in
                    HStack(spacing: 5) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(failure)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.caption2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sourceText: String {
        guard center.sourceCount > 1 else { return "来源：\(center.source)" }
        return "来源：\(center.source)（第 \(center.sourceIndex)/\(center.sourceCount) 个）"
    }

    private var subtitle: String {
        guard center.fileCount > 0 else { return "准备中…" }
        let name = center.fileName.isEmpty ? "文件" : center.fileName
        return "\(name) · 第 \(center.fileIndex)/\(center.fileCount) 个"
    }

    private var percentText: String {
        "\(Int((center.fraction * 100).rounded()))%"
    }

    private var transferText: String {
        let done = DDIDownloadCenter.byteText(center.received)
        guard center.expected > 0 else { return done }
        return "\(done) / \(DDIDownloadCenter.byteText(center.expected))"
    }
}
