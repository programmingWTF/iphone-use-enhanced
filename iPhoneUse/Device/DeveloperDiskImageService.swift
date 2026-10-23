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
    private let session: URLSession

    init(fileManager: FileManager = .default, session: URLSession = .shared) {
        self.fileManager = fileManager
        self.session = session
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

        for item in Self.downloadItems {
            let destinationURL = Self.directoryURL.appendingPathComponent(item.fileName)
            guard replaceFiles || !fileManager.fileExists(atPath: destinationURL.path) else {
                continue
            }
            try await downloadFile(from: item.urlStrings, to: destinationURL)
        }
        try Self.mountMethod.rawValue.write(to: Self.mountMethodURL, atomically: true, encoding: .utf8)
    }

    func downloadFile(from urlStrings: [String], to destinationURL: URL) async throws {
        guard !urlStrings.isEmpty else {
            throw DDIDownloadError.invalidURL("")
        }
        var lastError: Error?
        for urlString in urlStrings {
            do {
                try await downloadFile(from: urlString, to: destinationURL)
                return
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError ?? DDIDownloadError.invalidURL(urlStrings.joined(separator: ", "))
    }

    func downloadFile(from urlString: String, to destinationURL: URL) async throws {
        guard let url = URL(string: urlString),
              url.scheme?.lowercased() == "https" else {
            throw DDIDownloadError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        let (temporaryURL, response) = try await session.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DDIDownloadError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
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

    func redownload(progressHandler: ((Double, String) -> Void)? = nil) async throws {
        let totalStages = Double(Self.downloadItems.count + 1)
        var completedStages = 0.0

        progressHandler?(0.0, "Removing existing DDI files...")
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

        completedStages += 1.0
        progressHandler?(completedStages / totalStages, "Starting downloads...")

        for item in Self.downloadItems {
            progressHandler?(completedStages / totalStages, "Downloading \(item.name)...")
            let destinationURL = Self.directoryURL.appendingPathComponent(item.fileName)
            try await downloadFile(from: item.urlStrings, to: destinationURL)
            completedStages += 1.0
            progressHandler?(completedStages / totalStages, "\(item.name) ready")
        }

        try Self.mountMethod.rawValue.write(to: Self.mountMethodURL, atomically: true, encoding: .utf8)

        progressHandler?(1.0, "DDI download complete.")
    }

    private func removeCryptexOnlyFiles() throws {
        for fileName in Self.cryptexOnlyFileNames {
            let fileURL = Self.directoryURL.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        }
    }

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
            name: "Build Manifest",
            fileName: "BuildManifest.plist",
            urlStrings: candidates("Xcode_iOS_DDI_Cryptex/BuildManifest.plist")
        ),
        .init(
            name: "Image",
            fileName: "Image.dmg",
            urlStrings: candidates("Xcode_iOS_DDI_Cryptex/Image.dmg")
        ),
        .init(
            name: "TrustCache",
            fileName: "Image.dmg.trustcache",
            urlStrings: candidates("Xcode_iOS_DDI_Cryptex/Image.dmg.trustcache")
        ),
        .init(
            name: "Cryptex Info",
            fileName: "Image.dmg.cryptex_info",
            urlStrings: candidates("Xcode_iOS_DDI_Cryptex/Image.dmg.cryptex_info")
        ),
        .init(
            name: "Root Hash",
            fileName: "Image.dmg.root_hash",
            urlStrings: candidates("Xcode_iOS_DDI_Cryptex/Image.dmg.root_hash")
        )
    ]

    private static let personalizedDownloadItems: [DDIDownloadItem] = [
        .init(
            name: "Build Manifest",
            fileName: "BuildManifest.plist",
            urlStrings: candidates("Xcode_iOS_DDI_Personalized/BuildManifest.plist")
        ),
        .init(
            name: "Image",
            fileName: "Image.dmg",
            urlStrings: candidates("Xcode_iOS_DDI_Personalized/Image.dmg")
        ),
        .init(
            name: "TrustCache",
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
            return "Invalid download URL: \(string)"
        case .invalidResponse:
            return "The DDI server returned an invalid response."
        case .badStatus(let statusCode):
            return "The DDI server returned HTTP \(statusCode)."
        }
    }
}
