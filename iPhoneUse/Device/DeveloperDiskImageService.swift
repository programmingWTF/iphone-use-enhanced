//
//  DeveloperDiskImageService.swift
//  iPhoneUse
//

import Foundation

final class DeveloperDiskImageService {
    static let shared = DeveloperDiskImageService()
    static let directoryURL = URL.documentsDirectory.appendingPathComponent("DDI", isDirectory: true)

    static var cachedFilesAreComplete: Bool {
        downloadItems.allSatisfy {
            FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent($0.fileName).path)
        }
    }

    static var filesAreReady: Bool {
        cachedFilesAreComplete
            && (try? String(contentsOf: mountMethodURL, encoding: .utf8)) == mountMethod.rawValue
    }

    static var usesCryptexDDI: Bool {
        mountMethod == .cryptex
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func downloadMissingFiles() async throws {
        let installedMethod = try? String(contentsOf: Self.mountMethodURL, encoding: .utf8)

        // Files can be copied in through the Files app (or iTunes file sharing) instead of
        // being downloaded. Adopt them once all of them are present.
        if installedMethod != Self.mountMethod.rawValue, Self.cachedFilesAreComplete {
            try fileManager.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
            try Self.mountMethod.rawValue.write(to: Self.mountMethodURL, atomically: true, encoding: .utf8)
            return
        }

        let replaceFiles = installedMethod != Self.mountMethod.rawValue

        if !Self.usesCryptexDDI {
            try removeCryptexOnlyFiles()
        }

        let pending = Self.downloadItems.filter { item in
            let destinationURL = Self.directoryURL.appendingPathComponent(item.fileName)
            return replaceFiles || !fileManager.fileExists(atPath: destinationURL.path)
        }

        guard !pending.isEmpty else { return }

        await MainActor.run { DDIDownloadCenter.shared.begin(fileCount: pending.count) }
        do {
            try await download(pending)
            try Self.mountMethod.rawValue.write(to: Self.mountMethodURL, atomically: true, encoding: .utf8)
            await MainActor.run { DDIDownloadCenter.shared.finish() }
        } catch {
            await MainActor.run { DDIDownloadCenter.shared.fail(error.localizedDescription) }
            throw error
        }
    }

    /// Drops the cached image and fetches every file again, reporting through the same
    /// `DDIDownloadCenter` the automatic download uses, so only one bar is ever shown.
    func redownload() async throws {
        if fileManager.fileExists(atPath: Self.mountMethodURL.path) {
            try fileManager.removeItem(at: Self.mountMethodURL)
        }
        if !Self.usesCryptexDDI {
            try removeCryptexOnlyFiles()
        }
        let completionMarker = Self.directoryURL.appendingPathComponent("Image.dmg.root_hash")
        if fileManager.fileExists(atPath: completionMarker.path) {
            try fileManager.removeItem(at: completionMarker)
        }
        for item in Self.downloadItems {
            let fileURL = Self.directoryURL.appendingPathComponent(item.fileName)
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        }

        let items = Self.downloadItems
        await MainActor.run { DDIDownloadCenter.shared.begin(fileCount: items.count) }
        do {
            try await download(items)
            try Self.mountMethod.rawValue.write(to: Self.mountMethodURL, atomically: true, encoding: .utf8)
            await MainActor.run { DDIDownloadCenter.shared.finish() }
        } catch {
            await MainActor.run { DDIDownloadCenter.shared.fail(error.localizedDescription) }
            throw error
        }
    }

    // MARK: - Downloading

    private func download(_ items: [DDIDownloadItem]) async throws {
        for (offset, item) in items.enumerated() {
            try await download(item, index: offset + 1, count: items.count)
        }
    }

    private func download(_ item: DDIDownloadItem, index: Int, count: Int) async throws {
        await MainActor.run {
            DDIDownloadCenter.shared.setFile(index: index, name: item.name)
        }

        let destinationURL = Self.directoryURL.appendingPathComponent(item.fileName)
        var lastError: Error?

        for (sourceIndex, urlString) in item.urlStrings.enumerated() {
            let sourceName = Self.sourceName(for: urlString)
            await MainActor.run {
                DDIDownloadCenter.shared.setSource(
                    sourceName,
                    index: sourceIndex + 1,
                    count: item.urlStrings.count
                )
            }
            do {
                try await downloadFile(from: urlString, to: destinationURL) { received, expected in
                    Task { @MainActor in
                        DDIDownloadCenter.shared.update(received: received, expected: expected)
                    }
                }
                return
            } catch {
                lastError = error
                let reason = Self.shortReason(error)
                await MainActor.run {
                    DDIDownloadCenter.shared.noteFailure("\(sourceName)：\(reason)")
                }
            }
        }

        throw lastError ?? DDIDownloadError.invalidURL(item.urlStrings.joined(separator: ", "))
    }

    func downloadFile(from urlStrings: [String], to destinationURL: URL) async throws {
        try await downloadFile(from: urlStrings, to: destinationURL, progress: nil)
    }

    private func downloadFile(
        from urlStrings: [String],
        to destinationURL: URL,
        progress: (@Sendable (Int64, Int64) -> Void)?
    ) async throws {
        guard !urlStrings.isEmpty else {
            throw DDIDownloadError.invalidURL("")
        }
        var lastError: Error?
        for urlString in urlStrings {
            do {
                try await downloadFile(from: urlString, to: destinationURL, progress: progress)
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? DDIDownloadError.invalidURL(urlStrings.joined(separator: ", "))
    }

    private func downloadFile(
        from urlString: String,
        to destinationURL: URL,
        progress: (@Sendable (Int64, Int64) -> Void)?
    ) async throws {
        guard let url = URL(string: urlString),
              url.scheme?.lowercased() == "https" else {
            throw DDIDownloadError.invalidURL(urlString)
        }

        let downloader = ProgressDownloader(progress: progress)
        let (temporaryURL, httpResponse) = try await downloader.download(url)
        guard (200..<300).contains(httpResponse.statusCode) else {
            try? fileManager.removeItem(at: temporaryURL)
            throw DDIDownloadError.badStatus(httpResponse.statusCode)
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    }

    private func removeCryptexOnlyFiles() throws {
        for fileName in Self.cryptexOnlyFileNames {
            let fileURL = Self.directoryURL.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        }
    }

    // MARK: - Naming for the progress card

    private static func sourceName(for urlString: String) -> String {
        if urlString.hasPrefix("https://ghfast.top/") { return "ghfast.top 镜像" }
        if urlString.hasPrefix("https://gh-proxy.com/") { return "gh-proxy 镜像" }
        if urlString.contains("raw.githubusercontent.com") { return "GitHub Raw" }
        if urlString.contains("github.com") { return "GitHub" }
        return URL(string: urlString)?.host ?? "镜像源"
    }

    private static func shortReason(_ error: Error) -> String {
        if let ddi = error as? DDIDownloadError {
            switch ddi {
            case .badStatus(let statusCode): return "HTTP \(statusCode)"
            case .invalidResponse: return "响应无效"
            case .invalidURL: return "地址无效"
            }
        }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return nsError.localizedDescription
        }
        switch nsError.code {
        case NSURLErrorTimedOut: return "超时"
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost: return "连不上"
        case NSURLErrorNetworkConnectionLost: return "连接中断"
        case NSURLErrorNotConnectedToInternet: return "没有网络"
        case NSURLErrorSecureConnectionFailed: return "TLS 失败"
        default: return nsError.localizedDescription
        }
    }

    // MARK: - What to download

    private static var mountMethod: DDIMountMethod {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return version.majorVersion > 26 || (version.majorVersion == 26 && version.minorVersion >= 4)
            ? .cryptex
            : .personalized
    }

    private static let mountMethodURL = directoryURL.appendingPathComponent("MountMethod")
    private static let cryptexOnlyFileNames = ["Image.dmg.cryptex_info", "Image.dmg.root_hash"]

    private static var downloadItems: [DDIDownloadItem] {
        switch mountMethod {
        case .cryptex:
            return cryptexDownloadItems
        case .personalized:
            return personalizedDownloadItems
        }
    }

    /// The upstream files live in a GitHub repository, which is unreachable from some
    /// networks. Each item lists the canonical URL followed by mirrors that forward to it.
    private static func candidates(_ relativePath: String) -> [String] {
        let raw = "https://raw.githubusercontent.com/doronz88/DeveloperDiskImage/main/PersonalizedImages/" + relativePath
        return [
            "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/" + relativePath,
            raw,
            "https://ghfast.top/" + raw,
            "https://gh-proxy.com/" + raw
        ]
    }

    private static let cryptexDownloadItems: [DDIDownloadItem] = [
        .init(
            name: "构建清单",
            fileName: "BuildManifest.plist",
            urlStrings: candidates("Xcode_iOS_DDI_Cryptex/BuildManifest.plist")
        ),
        .init(
            name: "映像",
            fileName: "Image.dmg",
            urlStrings: candidates("Xcode_iOS_DDI_Cryptex/Image.dmg")
        ),
        .init(
            name: "信任缓存",
            fileName: "Image.dmg.trustcache",
            urlStrings: candidates("Xcode_iOS_DDI_Cryptex/Image.dmg.trustcache")
        ),
        .init(
            name: "Cryptex 信息",
            fileName: "Image.dmg.cryptex_info",
            urlStrings: candidates("Xcode_iOS_DDI_Cryptex/Image.dmg.cryptex_info")
        ),
        .init(
            name: "根哈希",
            fileName: "Image.dmg.root_hash",
            urlStrings: candidates("Xcode_iOS_DDI_Cryptex/Image.dmg.root_hash")
        )
    ]

    private static let personalizedDownloadItems: [DDIDownloadItem] = [
        .init(
            name: "构建清单",
            fileName: "BuildManifest.plist",
            urlStrings: candidates("Xcode_iOS_DDI_Personalized/BuildManifest.plist")
        ),
        .init(
            name: "映像",
            fileName: "Image.dmg",
            urlStrings: candidates("Xcode_iOS_DDI_Personalized/Image.dmg")
        ),
        .init(
            name: "信任缓存",
            fileName: "Image.dmg.trustcache",
            urlStrings: candidates("Xcode_iOS_DDI_Personalized/Image.dmg.trustcache")
        )
    ]

}

private enum DDIMountMethod: String {
    case cryptex
    case personalized
}

private struct DDIDownloadItem {
    let name: String
    let fileName: String
    let urlStrings: [String]
}

enum DDIDownloadError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let string):
            return "下载地址无效：\(string)"
        case .invalidResponse:
            return "DDI 服务器返回了无效的响应。"
        case .badStatus(let statusCode):
            return "DDI 服务器返回了 HTTP \(statusCode)。"
        }
    }
}

/// Streams one file and reports byte progress. `URLSession.download(for:)` cannot report
/// progress and the image is about 16 MB, so a bar driven by it would sit still and then
/// jump to the next file.
private final class ProgressDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: (@Sendable (Int64, Int64) -> Void)?
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(URL, HTTPURLResponse), Error>?
    private var response: HTTPURLResponse?
    private var savedURL: URL?
    private var failure: Error?
    private var session: URLSession?

    init(progress: (@Sendable (Int64, Int64) -> Void)?) {
        self.progress = progress
    }

    func download(_ url: URL) async throws -> (URL, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 300
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session

        var request = URLRequest(url: url)
        request.timeoutInterval = 45

        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, HTTPURLResponse), Error>) in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            session.downloadTask(with: request).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        progress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        lock.lock()
        response = downloadTask.response as? HTTPURLResponse
        do {
            // `location` is deleted as soon as this call returns.
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("ddi-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: location, to: copy)
            savedURL = copy
        } catch {
            failure = error
        }
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let response = self.response ?? task.response as? HTTPURLResponse
        let saved = savedURL
        let failure = error ?? self.failure
        lock.unlock()

        guard let continuation else { return }
        if let failure {
            continuation.resume(throwing: failure)
        } else if let saved, let response {
            continuation.resume(returning: (saved, response))
        } else {
            continuation.resume(throwing: DDIDownloadError.invalidResponse)
        }
    }
}
