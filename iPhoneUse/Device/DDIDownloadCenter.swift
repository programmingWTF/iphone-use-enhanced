//
//  DDIDownloadCenter.swift
//  iPhoneUse
//
//  One live developer-disk-image download, shared by every screen that shows it.
//
//  The connect flow and the settings screen used to own separate progress state, which
//  is how two bars could appear for one download. Both now read this center, so there
//  is exactly one source of truth: which file, how far, how fast, what is left, which
//  mirror is being tried and which ones already failed.
//

import Foundation
import Observation

@MainActor
@Observable
final class DDIDownloadCenter {
    static let shared = DDIDownloadCenter()

    enum Phase: Equatable {
        case idle
        case running
        case finished
        case failed
    }

    private(set) var phase: Phase = .idle
    /// 1-based position of the file being fetched.
    private(set) var fileIndex = 0
    private(set) var fileCount = 0
    private(set) var fileName = ""
    private(set) var received: Int64 = 0
    private(set) var expected: Int64 = 0
    private(set) var bytesPerSecond: Double = 0
    /// Human name of the mirror currently in use, e.g. "ghfast.top 镜像".
    private(set) var source = ""
    private(set) var sourceIndex = 0
    private(set) var sourceCount = 0
    private(set) var failedSources: [String] = []
    private(set) var failure: String?

    private var lastSample = Date()
    private var lastReceived: Int64 = 0
    private var smoothedSpeed: Double = 0

    var isRunning: Bool { phase == .running }

    /// 0...1 over the whole set of files. Unknown lengths count as zero for the file in
    /// flight, so the bar still advances as files complete.
    var fraction: Double {
        guard fileCount > 0 else { return 0 }
        let inFile = expected > 0 ? min(1, Double(received) / Double(expected)) : 0
        return min(1, max(0, (Double(max(0, fileIndex - 1)) + inFile) / Double(fileCount)))
    }

    var remainingSeconds: Double? {
        guard expected > received, bytesPerSecond > 1 else { return nil }
        return Double(expected - received) / bytesPerSecond
    }

    func begin(fileCount count: Int) {
        let continuing = phase == .running && fileCount == count
        phase = .running
        fileCount = count
        if !continuing {
            fileIndex = 0
            fileName = ""
            received = 0
            expected = 0
            bytesPerSecond = 0
            source = ""
            sourceIndex = 0
            sourceCount = 0
            failedSources = []
            failure = nil
            smoothedSpeed = 0
            lastSample = Date()
            lastReceived = 0
        }
    }

    func setFile(index: Int, name: String) {
        phase = .running
        fileIndex = index
        fileName = name
        received = 0
        expected = 0
        bytesPerSecond = 0
        smoothedSpeed = 0
        lastSample = Date()
        lastReceived = 0
    }

    func setSource(_ name: String, index: Int, count: Int) {
        source = name
        sourceIndex = index
        sourceCount = count
    }

    func noteFailure(_ reason: String) {
        failedSources.append(reason)
    }

    func update(received bytes: Int64, expected total: Int64) {
        received = bytes
        if total > 0 { expected = total }
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSample)
        guard elapsed >= 0.25 else { return }
        let instant = Double(bytes - lastReceived) / elapsed
        smoothedSpeed = smoothedSpeed <= 0 ? instant : smoothedSpeed * 0.7 + instant * 0.3
        bytesPerSecond = max(0, smoothedSpeed)
        lastSample = now
        lastReceived = bytes
    }

    func finish() {
        phase = .finished
        received = expected
        bytesPerSecond = 0
        source = ""
        sourceIndex = 0
        sourceCount = 0
    }

    func fail(_ message: String) {
        phase = .failed
        failure = message
        bytesPerSecond = 0
    }

    func reset() {
        phase = .idle
        fileIndex = 0
        fileCount = 0
        fileName = ""
        received = 0
        expected = 0
        bytesPerSecond = 0
        source = ""
        sourceIndex = 0
        sourceCount = 0
        failedSources = []
        failure = nil
        smoothedSpeed = 0
    }

    // MARK: Formatting

    static func byteText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }

    static func speedText(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 1 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }

    static func remainingText(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite else { return "剩余时间未知" }
        if seconds < 1 { return "马上完成" }
        if seconds < 60 { return "还剩 \(Int(seconds.rounded())) 秒" }
        let minutes = Int((seconds / 60).rounded(.down))
        let rest = Int((seconds - Double(minutes) * 60).rounded())
        return "还剩 \(minutes) 分 \(rest) 秒"
    }
}
