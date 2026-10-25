//
//  DeviceSession.swift
//  iPhoneUse
//
//  The CoreDevice tunnel to this iPhone's own developer services, reached through
//  the loopback VPN (TunnelProvider) and the imported RP pairing file.
//

import Foundation
import idevice
import Darwin

/// Finds the port remotepairingd listens on (it is not always 49152).
final class RemotePairingPortResolver: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    static let fallback: UInt16 = 49152
    private static let stateLock = NSLock()
    private static var selectedEndpoint = t("尚未尝试")

    /// The port and discovery method used for the latest connection attempt.
    static var lastAttemptDescription: String {
        stateLock.lock()
        defer { stateLock.unlock() }
        return selectedEndpoint
    }

    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var resolvedPort: UInt16?

    static func resolve(timeout: TimeInterval = 5) -> UInt16 {
        let worker = RemotePairingPortResolver()
        let completion = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            worker.search(timeout: timeout)
            completion.signal()
        }
        let found = completion.wait(timeout: .now() + timeout + 1) == .success ? worker.resolvedPort : nil
        let port = found ?? fallback
        let discovery = found == nil ? t("回退") : "Bonjour"
        stateLock.lock()
        selectedEndpoint = "\(DeviceSession.peerIP):\(port) (\(discovery))"
        stateLock.unlock()
        return port
    }

    private func search(timeout: TimeInterval) {
        browser.delegate = self
        browser.schedule(in: .current, forMode: .default)
        browser.searchForServices(ofType: "_remotepairing._tcp.", inDomain: "local.")
        let deadline = Date().addingTimeInterval(timeout)
        while resolvedPort == nil && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        browser.stop()
        services.forEach { $0.stop() }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 4)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        if (1...65535).contains(sender.port), resolvedPort == nil {
            resolvedPort = UInt16(sender.port)
        }
    }
}

final class DeviceSession {
    static let shared = DeviceSession()
    /// The loopback VPN's peer address; packets to it come back to this phone.
    static let peerIP = "10.7.0.1"
    static let ideviceLogURL = URL.documentsDirectory.appendingPathComponent("idevice_log.txt")

    fileprivate struct TunnelHandles {
        var adapter: OpaquePointer?
        var handshake: OpaquePointer?

        mutating func free() {
            if let handshake {
                rsd_handshake_free(handshake)
                self.handshake = nil
            }
            if let adapter {
                adapter_free(adapter)
                self.adapter = nil
            }
        }
    }

    private var tunnel = TunnelHandles()
    private let tunnelLock = NSLock()
    private var tunnelConnecting = false
    private var tunnelSemaphore: DispatchSemaphore?
    private var lastTunnelError: NSError?
    private var heartbeat: Heartbeat?

    var adapterHandle: OpaquePointer? { tunnel.adapter }
    var handshakeHandle: OpaquePointer? { tunnel.handshake }

    private init() {
        // ponytail: the idevice log is reset past 10 MB instead of rotated.
        let size = (try? FileManager.default.attributesOfItem(atPath: Self.ideviceLogURL.path)[.size] as? NSNumber)?.intValue ?? 0
        if size > 10_000_000 { try? FileManager.default.removeItem(at: Self.ideviceLogURL) }
        var path = Array(Self.ideviceLogURL.path.utf8CString)
        path.withUnsafeMutableBufferPointer { buffer in
            // Not Debug: it dumps every XPC message, screenshots included, as decimal byte lists.
            // Debug (not Trace): the tunnel handshake lines in idevice are all `debug!`.
        _ = idevice_init_logger(Info, Debug, buffer.baseAddress)
        }
    }

    func makeError(_ message: String, code: Int = -1) -> NSError {
        NSError(domain: "iPhoneUse", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    func error(from ffiError: UnsafeMutablePointer<IdeviceFfiError>?, fallback: String) -> NSError {
        guard let ffiError else { return makeError(fallback) }
        let detail = ffiError.pointee.message.flatMap { String(validatingUTF8: $0) } ?? fallback
        let error = makeError(detail == fallback ? fallback : "\(fallback): \(detail)", code: Int(ffiError.pointee.code))
        idevice_error_free(ffiError)
        return error
    }

    private func readPairingFile() throws -> OpaquePointer {
        let pairingFileURL = PairingFileStore.prepareURL()
        guard FileManager.default.fileExists(atPath: pairingFileURL.path) else {
            throw makeError(t("未找到配对文件。"), code: -17)
        }

        var pairingFile: OpaquePointer?
        let ffiError = pairingFileURL.path.withCString { rp_pairing_file_read($0, &pairingFile) }
        if let ffiError {
            throw error(from: ffiError, fallback: t("读取配对文件失败"))
        }
        guard let pairingFile else {
            throw makeError(t("读取配对文件失败。"), code: -17)
        }
        return pairingFile
    }

    /// Appends a line to the same file the idevice logger writes, so one file has both sides.
    static func appendLog(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "[\(stamp)] [iPhoneUse] \(line)\n"
        guard let data = text.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: ideviceLogURL.path) {
            try? data.write(to: ideviceLogURL)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: ideviceLogURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        _ = try? handle.write(contentsOf: data)
    }

    /// Plain TCP reachability check of the loopback peer, so a failure is attributable:
    /// "never connected" is the VPN, "connected then TLS" is the pairing/handshake.
    static func probeTCP(port: UInt16, timeout: TimeInterval = 3) -> String {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return "socket() errno=\(errno)" }
        defer { close(fd) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        _ = peerIP.withCString { inet_pton(AF_INET, $0, &addr.sin_addr) }
        let rc = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc == 0 { return "connected immediately" }
        if errno != EINPROGRESS { return "connect errno=\(errno) (\(String(cString: strerror(errno))))" }
        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let ready = poll(&pfd, 1, Int32(timeout * 1000))
        if ready == 0 { return "connect timed out after \(timeout)s" }
        if ready < 0 { return "poll errno=\(errno) (\(String(cString: strerror(errno))))" }
        var soError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &length) == 0 else {
            return "getsockopt errno=\(errno)"
        }
        if soError != 0 { return "connect so_error=\(soError) (\(String(cString: strerror(soError))))" }
        return "connected"
    }

    fileprivate func createTunnel(hostname: String) throws -> TunnelHandles {
        let pairingFile = try readPairingFile()
        defer { rp_pairing_file_free(pairingFile) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(RemotePairingPortResolver.resolve()).bigEndian
        _ = Self.peerIP.withCString { inet_pton(AF_INET, $0, &addr.sin_addr) }

        let port = addr.sin_port.bigEndian
        let probe = Self.probeTCP(port: port)
        Self.appendLog("tunnel: 10.7.0.1:\(port) probe -> \(probe)")

        var tunnel = TunnelHandles()
        let ffiError = hostname.withCString { hostname in
            withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    tunnel_create_rppairing(
                        $0,
                        socklen_t(MemoryLayout<sockaddr_in>.stride),
                        hostname,
                        pairingFile,
                        nil,
                        nil,
                        &tunnel.adapter,
                        &tunnel.handshake
                    )
                }
            }
        }

        if let ffiError {
            let detail = ffiError.pointee.message.flatMap { String(validatingUTF8: $0) } ?? "no message"
            Self.appendLog("tunnel: failed code=\(ffiError.pointee.code) sub=\(ffiError.pointee.sub_code) msg=\(detail)")
            throw error(from: ffiError, fallback: t("创建隧道失败 [tcp: %@]", probe))
        }
        guard tunnel.adapter != nil, tunnel.handshake != nil else {
            tunnel.free()
            throw makeError(t("隧道创建失败：句柄无效。"))
        }
        return tunnel
    }

    func startTunnel() throws {
        tunnelLock.lock()
        if tunnelConnecting {
            let waitSemaphore = tunnelSemaphore
            tunnelLock.unlock()

            if let waitSemaphore {
                guard waitSemaphore.wait(timeout: .now() + .seconds(15)) == .success else {
                    throw makeError(t("等待隧道连接超时"), code: -19)
                }
                waitSemaphore.signal()
            }
            if let lastTunnelError {
                throw lastTunnelError
            }
            return
        }

        tunnelConnecting = true
        let completionSemaphore = DispatchSemaphore(value: 0)
        tunnelSemaphore = completionSemaphore
        tunnelLock.unlock()

        var finalError: NSError?
        defer {
            tunnelLock.lock()
            tunnelConnecting = false
            tunnelSemaphore = nil
            lastTunnelError = finalError
            tunnelLock.unlock()
            completionSemaphore.signal()
        }

        let newTunnel: TunnelHandles
        do {
            newTunnel = try createTunnel(hostname: "iPhoneUse")
        } catch let tunnelError as NSError {
            finalError = tunnelError
            throw tunnelError
        }
        tunnel.free()
        tunnel = newTunnel
    }

    func ensureTunnel() throws {
        if tunnel.adapter == nil || tunnel.handshake == nil {
            try startTunnel()
        }
    }

    /// Keeps the device's CoreDevice services from dropping us during a long agent run.
    func startHeartbeat() {
        guard heartbeat == nil else { return }
        let heartbeat = Heartbeat(session: self)
        self.heartbeat = heartbeat
        DispatchQueue.global(qos: .utility).async {
            do {
                try heartbeat.start()
            } catch {
                appLog.error("Heartbeat failed to start: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func stopHeartbeat() {
        let heartbeat = self.heartbeat
        self.heartbeat = nil
        DispatchQueue.global(qos: .utility).async { heartbeat?.stop() }
    }
}

/// Heartbeat marco/polo loop on its own tunnel.
private final class Heartbeat {
    private static let defaultInterval: UInt64 = 2
    private static let maxInterval: UInt64 = 3

    private let queue = DispatchQueue(label: "blog.eliot.iphoneuse.heartbeat", qos: .utility)
    private let stateLock = NSLock()
    private let startupSemaphore = DispatchSemaphore(value: 0)
    private let stoppedSemaphore = DispatchSemaphore(value: 0)
    private unowned let session: DeviceSession
    private var startupError: NSError?
    private var stopRequested = false

    init(session: DeviceSession) {
        self.session = session
    }

    func start() throws {
        queue.async { [self] in run() }
        startupSemaphore.wait()
        if let startupError { throw startupError }
    }

    func stop() {
        stateLock.lock()
        stopRequested = true
        stateLock.unlock()
        _ = stoppedSemaphore.wait(timeout: .now() + .seconds(Int(Self.maxInterval + 1)))
    }

    private func shouldStop() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stopRequested
    }

    private func run() {
        var tunnel: DeviceSession.TunnelHandles
        var client: OpaquePointer?
        do {
            tunnel = try session.createTunnel(hostname: "iPhoneUseHeartbeat")
            if let ffiError = heartbeat_connect_rsd(tunnel.adapter, tunnel.handshake, &client) {
                tunnel.free()
                throw session.error(from: ffiError, fallback: "心跳连接失败") // l10n:keep log only
            }
        } catch let error as NSError {
            startupError = error
            startupSemaphore.signal()
            stoppedSemaphore.signal()
            return
        }

        defer {
            if let client { heartbeat_client_free(client) }
            tunnel.free()
            stoppedSemaphore.signal()
        }
        startupSemaphore.signal()

        var interval = Self.defaultInterval
        while !shouldStop(), let client {
            var suggestedInterval: UInt64 = 0
            let ffiError = heartbeat_get_marco(client, interval, &suggestedInterval)
            if shouldStop() { break }

            if let ffiError {
                // idevice's HeartbeatError is code 100; sub_code 1 = SleepyTime, 2 = Timeout.
                let (code, subCode) = (ffiError.pointee.code, ffiError.pointee.sub_code)
                let description = session.error(from: ffiError, fallback: "心跳失败").localizedDescription // l10n:keep log only
                if code == 100, subCode == 2 {
                    interval = Self.defaultInterval
                    continue
                }
                // Anything else ends the loop: a closed connection fails in microseconds, and
                // retrying it busy-loops until iOS kills the app for background CPU use.
                appLog.error("Heartbeat stopped: \(description, privacy: .public)")
                break
            }

            interval = min(max(suggestedInterval, 1), Self.maxInterval)
            if let ffiError = heartbeat_send_polo(client) {
                let description = session.error(from: ffiError, fallback: "心跳回应失败").localizedDescription // l10n:keep log only
                appLog.error("Heartbeat warning: \(description, privacy: .public)")
                interval = Self.defaultInterval
            }
        }
    }
}
