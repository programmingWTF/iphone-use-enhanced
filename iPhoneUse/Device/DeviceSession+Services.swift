//
//  DeviceSession+Services.swift
//  iPhoneUse
//
//  Calls into idevice over the tunnel.
//

import Foundation
import UIKit
import idevice

private enum IdeviceBridge {
    static func makeError(
        domain: String = "iPhoneUse",
        code: Int = -1,
        message: String
    ) -> NSError {
        NSError(
            domain: domain,
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    static func string(from cString: UnsafePointer<CChar>?) -> String? {
        guard let cString else { return nil }
        return String(validatingUTF8: cString)
    }

    static func consumeFFIError(
        _ ffiError: UnsafeMutablePointer<IdeviceFfiError>?,
        fallback: String,
        domain: String = "iPhoneUse"
    ) -> NSError {
        guard let ffiError else {
            return makeError(domain: domain, message: fallback)
        }

        let code = Int(ffiError.pointee.code)
        let detail = string(from: ffiError.pointee.message) ?? fallback
        let message = detail == fallback ? fallback : "\(fallback): \(detail)"
        idevice_error_free(ffiError)
        return makeError(domain: domain, code: code, message: message)
    }

    static func mappedFileData(atPath path: String, description: String) throws -> Data {
        let url = URL(fileURLWithPath: path)

        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard !data.isEmpty else {
                throw makeError(message: "\(description) 为空")
            }
            return data
        } catch let error as NSError {
            throw makeError(code: error.code, message: "读取 \(description) 失败：\(error.localizedDescription)")
        }
    }

    static func uint64Value(from plist: plist_t?, fieldName: String) throws -> UInt64 {
        guard let plist else {
            throw makeError(message: "lockdownd 未返回 \(fieldName)")
        }

        var value: UInt64 = 0
        plist_get_uint_val(plist, &value)

        guard value != 0 else {
            throw makeError(message: "无法解析 \(fieldName)")
        }

        return value
    }

    static func withTunnelHandles<T>(
        for context: DeviceSession,
        _ body: (OpaquePointer, OpaquePointer) throws -> T
    ) throws -> T {
        let handles = try activeTunnelHandles(for: context)
        return try body(handles.adapter, handles.handshake)
    }

    static func connectClient(
        fallback: String,
        missingClientMessage: String,
        domain: String = "iPhoneUse",
        connect: (UnsafeMutablePointer<OpaquePointer?>) -> UnsafeMutablePointer<IdeviceFfiError>?
    ) throws -> OpaquePointer {
        var client: OpaquePointer?
        if let ffiError = connect(&client) {
            throw consumeFFIError(ffiError, fallback: fallback, domain: domain)
        }

        guard let client else {
            throw makeError(domain: domain, message: missingClientMessage)
        }

        return client
    }

    static func withConnectedClient<T>(
        fallback: String,
        missingClientMessage: String,
        domain: String = "iPhoneUse",
        connect: (UnsafeMutablePointer<OpaquePointer?>) -> UnsafeMutablePointer<IdeviceFfiError>?,
        cleanup: (OpaquePointer) -> Void,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        let client = try connectClient(
            fallback: fallback,
            missingClientMessage: missingClientMessage,
            domain: domain,
            connect: connect
        )
        defer { cleanup(client) }
        return try body(client)
    }

    static func plistDictionaries(adapter: OpaquePointer, handshake: OpaquePointer) throws -> [[String: Any]] {
        try withConnectedClient(
            fallback: "无法连接安装代理服务",
            missingClientMessage: "安装代理客户端未能创建",
            connect: { installation_proxy_connect_rsd(adapter, handshake, $0) },
            cleanup: { installation_proxy_client_free($0) }
        ) { client in
            var rawApps: UnsafeMutableRawPointer?
            var count = 0
            if let ffiError = installation_proxy_get_apps(client, nil, nil, 0, &rawApps, &count) {
                throw consumeFFIError(ffiError, fallback: "获取已安装 App 列表失败")
            }

            guard let rawApps, count > 0 else { return [] }

            let apps = rawApps.assumingMemoryBound(to: plist_t?.self)
            defer {
                for index in 0..<count {
                    plist_free(apps[index])
                }
                idevice_data_free(
                    rawApps.assumingMemoryBound(to: UInt8.self),
                    UInt(count * MemoryLayout<plist_t?>.stride)
                )
            }

            var dictionaries: [[String: Any]] = []
            dictionaries.reserveCapacity(count)

            for index in 0..<count {
                var binaryPlist: UnsafeMutablePointer<CChar>?
                var binaryLength: UInt32 = 0
                let app = apps[index]

                guard plist_to_bin(app, &binaryPlist, &binaryLength) == PLIST_ERR_SUCCESS,
                      let binaryPlist,
                      binaryLength > 0 else {
                    continue
                }

                let data = Data(bytes: binaryPlist, count: Int(binaryLength))
                plist_mem_free(binaryPlist)

                guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
                      let dictionary = plist as? [String: Any] else {
                    continue
                }

                dictionaries.append(dictionary)
            }

            return dictionaries
        }
    }

    static func appName(from dictionary: [String: Any]) -> String {
        if let displayName = dictionary["CFBundleDisplayName"] as? String, !displayName.isEmpty {
            return displayName
        }
        if let name = dictionary["CFBundleName"] as? String, !name.isEmpty {
            return name
        }
        return "未知"
    }

    static func appDictionary(
        adapter: OpaquePointer,
        handshake: OpaquePointer
    ) throws -> [String: String] {
        let dictionaries = try plistDictionaries(adapter: adapter, handshake: handshake)
        var result: [String: String] = [:]
        result.reserveCapacity(dictionaries.count)

        for dictionary in dictionaries {
            guard let bundleID = dictionary["CFBundleIdentifier"] as? String,
                  !bundleID.isEmpty else {
                continue
            }

            result[bundleID] = appName(from: dictionary)
        }

        return result
    }

    static func activeTunnelHandles(for context: DeviceSession) throws -> (adapter: OpaquePointer, handshake: OpaquePointer) {
        try context.ensureTunnel()

        guard let adapterHandle = context.adapterHandle,
              let handshakeHandle = context.handshakeHandle else {
            throw makeError(message: "隧道未连接")
        }

        return (adapterHandle, handshakeHandle)
    }
}

extension DeviceSession {
    /// Bundle id -> display name for every installed app.
    func getAllApps() throws -> [String: String] {
        try IdeviceBridge.withTunnelHandles(for: self) { adapter, handshake in
            try IdeviceBridge.appDictionary(adapter: adapter, handshake: handshake)
        }
    }

    func isDeveloperDiskImageMounted() throws -> Bool {
        try IdeviceBridge.withTunnelHandles(for: self) { adapter, handshake in
            var cryptexQuerySucceeded = false
            var cryptexQueryError: NSError?
            if DeveloperDiskImageService.usesCryptexDDI {
                var installed: UnsafeMutablePointer<InstalledCryptexC>?
                defer { cryptexd_free_installed_cryptex(installed) }
                if let ffiError = cryptexd_installed_ddi(adapter, handshake, &installed) {
                    cryptexQueryError = IdeviceBridge.consumeFFIError(ffiError, fallback: "查询已安装的 DDI cryptex 失败")
                } else {
                    cryptexQuerySucceeded = true
                    if installed != nil {
                        return true
                    }
                }
            }

            do {
                return try IdeviceBridge.withConnectedClient(
                    fallback: "无法连接映像挂载服务",
                    missingClientMessage: "映像挂载客户端未能创建",
                    connect: { image_mounter_connect_rsd(adapter, handshake, $0) },
                    cleanup: { image_mounter_free($0) }
                ) { client in
                    var devices: UnsafeMutablePointer<plist_t?>?
                    var deviceCount = 0
                    if let error = image_mounter_copy_devices(client, &devices, &deviceCount) {
                        throw IdeviceBridge.consumeFFIError(error, fallback: "获取已挂载设备失败")
                    }
                    if let devices {
                        for index in 0..<deviceCount {
                            plist_free(devices[index])
                        }
                        idevice_data_free(
                            UnsafeMutableRawPointer(devices).assumingMemoryBound(to: UInt8.self),
                            UInt(deviceCount * MemoryLayout<plist_t?>.stride)
                        )
                    }
                    return deviceCount > 0
                }
            } catch {
                if cryptexQuerySucceeded {
                    return false
                }
                throw cryptexQueryError ?? (error as NSError)
            }
        }
    }

    func installCryptexDDI(from directoryPath: String) throws {
        var assets: OpaquePointer?
        if let ffiError = cryptex1_assets_load(directoryPath, &assets) {
            throw IdeviceBridge.consumeFFIError(ffiError, fallback: "加载 DDI cryptex 资源失败")
        }

        guard let assets else {
            throw IdeviceBridge.makeError(message: "DDI cryptex 资源未能加载")
        }
        defer { cryptex1_assets_free(assets) }

        try IdeviceBridge.withTunnelHandles(for: self) { adapter, handshake in
            if let ffiError = cryptexd_install_ddi(adapter, handshake, assets, nil) {
                throw IdeviceBridge.consumeFFIError(ffiError, fallback: "安装 DDI cryptex 失败")
            }
        }
    }

    func mountPersonalDDI(withImagePath imagePath: String, trustcachePath: String, manifestPath: String) throws {
        let imageData = try IdeviceBridge.mappedFileData(atPath: imagePath, description: "开发者磁盘映像")
        let trustcacheData = try IdeviceBridge.mappedFileData(atPath: trustcachePath, description: "开发者磁盘映像信任缓存")
        let manifestData = try IdeviceBridge.mappedFileData(atPath: manifestPath, description: "开发者磁盘映像清单")

        try IdeviceBridge.withTunnelHandles(for: self) { adapter, handshake in
            let uniqueChipID = try IdeviceBridge.withConnectedClient(
                fallback: "无法连接 lockdownd",
                missingClientMessage: "lockdownd 客户端未能创建",
                connect: { lockdownd_connect_rsd(adapter, handshake, $0) },
                cleanup: { lockdownd_client_free($0) }
            ) { lockdownClient in
                var uniqueChipIDPlist: plist_t?
                if let ffiError = lockdownd_get_value(lockdownClient, "UniqueChipID", nil, &uniqueChipIDPlist) {
                    throw IdeviceBridge.consumeFFIError(ffiError, fallback: "查询 UniqueChipID 失败")
                }
                defer { plist_free(uniqueChipIDPlist) }
                return try IdeviceBridge.uint64Value(from: uniqueChipIDPlist, fieldName: "UniqueChipID")
            }

            try IdeviceBridge.withConnectedClient(
                fallback: "无法连接映像挂载服务",
                missingClientMessage: "映像挂载客户端未能创建",
                connect: { image_mounter_connect_rsd(adapter, handshake, $0) },
                cleanup: { image_mounter_free($0) }
            ) { imageMounterClient in
                let ffiError = imageData.withUnsafeBytes { imageBuffer in
                    trustcacheData.withUnsafeBytes { trustcacheBuffer in
                        manifestData.withUnsafeBytes { manifestBuffer in
                            image_mounter_mount_personalized_rsd(
                                imageMounterClient,
                                adapter,
                                handshake,
                                imageBuffer.bindMemory(to: UInt8.self).baseAddress,
                                imageData.count,
                                trustcacheBuffer.bindMemory(to: UInt8.self).baseAddress,
                                trustcacheData.count,
                                manifestBuffer.bindMemory(to: UInt8.self).baseAddress,
                                manifestData.count,
                                nil,
                                uniqueChipID
                            )
                        }
                    }
                }

                if let ffiError {
                    throw IdeviceBridge.consumeFFIError(ffiError, fallback: "挂载个性化 DDI 失败")
                }
            }
        }
    }
}

// MARK: - Agent: CoreDevice screenshot / HID / launch on this same phone

extension DeviceSession {
    func agentScreenshot(jpeg: Bool = true) throws -> Data {
        try IdeviceBridge.withTunnelHandles(for: self) { adapter, handshake in
            var bytes: UnsafeMutablePointer<UInt8>?
            var length = UInt(0)
            if let ffiError = probe_screenshot(adapter, handshake, jpeg ? 1 : 0, &bytes, &length) {
                throw IdeviceBridge.consumeFFIError(ffiError, fallback: "截屏失败", domain: "agent")
            }
            guard let bytes else { throw IdeviceBridge.makeError(domain: "agent", message: "截屏结果为空") }
            defer { idevice_data_free(bytes, length) }
            return Data(bytes: bytes, count: Int(length))
        }
    }

    /// Normalized 0...1 coordinates; equal start and end points tap.
    func agentTouch(from: CGPoint, to: CGPoint) throws {
        func scale(_ v: CGFloat) -> UInt16 { UInt16(max(0, min(1, v)) * 65535) }
        try IdeviceBridge.withTunnelHandles(for: self) { adapter, handshake in
            if let ffiError = probe_touch(adapter, handshake, scale(from.x), scale(from.y), scale(to.x), scale(to.y)) {
                throw IdeviceBridge.consumeFFIError(ffiError, fallback: "触摸失败", domain: "agent")
            }
        }
    }

    /// Long press at a normalized point: opens the system edit menu on a text field.
    func agentLongPress(at point: CGPoint, holdMillis: UInt16 = 700) throws {
        func scale(_ v: CGFloat) -> UInt16 { UInt16(max(0, min(1, v)) * 65535) }
        try IdeviceBridge.withTunnelHandles(for: self) { adapter, handshake in
            if let ffiError = probe_long_press(
                adapter,
                handshake,
                scale(point.x),
                scale(point.y),
                holdMillis
            ) {
                throw IdeviceBridge.consumeFFIError(ffiError, fallback: "长按失败", domain: "agent")
            }
        }
    }

    func agentHome() throws {
        try IdeviceBridge.withTunnelHandles(for: self) { adapter, handshake in
            if let ffiError = probe_button(adapter, handshake, 0x0C, 0x40, 80) {
                throw IdeviceBridge.consumeFFIError(ffiError, fallback: "返回主屏失败", domain: "agent")
            }
        }
    }

    /// Types `text` on the focused field.
    ///
    /// Two routes, picked by the content itself:
    ///
    /// 1. **Clipboard route** — as soon as the text contains anything outside US-ASCII
    ///    (Chinese, emoji, accented letters, …) the whole string goes through the
    ///    pasteboard and we press Command+V. HID keycodes only know the US layout, so a
    ///    single non-ASCII character would otherwise be dropped.
    /// 2. **Keystroke route** — pure ASCII is typed key by key, which is faster and does
    ///    not touch the pasteboard.
    ///
    /// The pasteboard write has to be finished *before* Command+V reaches the device,
    /// so it is done synchronously (and verified by reading it back); otherwise the
    /// target app pastes whatever the user had copied earlier.
    func agentType(_ text: String) throws {
        guard !text.isEmpty else { return }
        let viaClipboard = !text.allSatisfy(\.isASCII)
        try IdeviceBridge.withTunnelHandles(for: self) { adapter, handshake in
            if viaClipboard {
                // Route 1: put the whole string on the pasteboard, then press Command+V.
                // The write is synchronous and verified, so the paste cannot pick up
                // whatever the owner had copied earlier.
                try Self.stageOnPasteboard(text)
                Thread.sleep(forTimeInterval: 0.15)
            }
            let ffiError = viaClipboard
                ? probe_paste(adapter, handshake)
                : probe_type(adapter, handshake, text)
            if let ffiError {
                throw IdeviceBridge.consumeFFIError(
                    ffiError,
                    fallback: viaClipboard ? "粘贴失败" : "输入失败",
                    domain: "agent"
                )
            }
        }
    }

    /// Writes `text` to the shared pasteboard and blocks until it is really there.
    private static func stageOnPasteboard(_ text: String) throws {
        func writeOnce() -> Bool {
            UIPasteboard.general.string = text
            return UIPasteboard.general.string == text
        }

        for attempt in 0..<3 {
            var written = false
            if Thread.isMainThread {
                written = writeOnce()
            } else {
                let done = DispatchSemaphore(value: 0)
                DispatchQueue.main.async {
                    written = writeOnce()
                    done.signal()
                }
                if done.wait(timeout: .now() + 2) == .timedOut {
                    written = false
                }
            }
            if written { return }
            if attempt < 2 { Thread.sleep(forTimeInterval: 0.05) }
        }
        throw IdeviceBridge.makeError(
            domain: "agent",
            message: "剪贴板写入失败：系统剪贴板没有接受这段文字。"
        )
    }

    func agentLaunch(bundleID: String) throws {
        try IdeviceBridge.withTunnelHandles(for: self) { adapter, handshake in
            try IdeviceBridge.withConnectedClient(
                fallback: "无法打开 AppService",
                missingClientMessage: "AppService 客户端未能创建",
                connect: { app_service_connect_rsd(adapter, handshake, $0) },
                cleanup: { app_service_free($0) }
            ) { appService in
                var response: UnsafeMutablePointer<LaunchResponseC>?
                let ffiError = app_service_launch_app(appService, bundleID, nil, 0, 0, 0, nil, &response)
                if let response { app_service_free_launch_response(response) }
                if let ffiError {
                    throw IdeviceBridge.consumeFFIError(ffiError, fallback: "启动 \(bundleID) 失败", domain: "agent")
                }
            }
        }
    }
}
