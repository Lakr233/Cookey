import Crypto
import Foundation
#if canImport(Glibc)
    import Glibc
#else
    import Darwin
#endif

public struct AppPaths {
    public let root: URL
    public let keypair: URL
    public let config: URL
    public let deviceIdentifier: URL
    public let sessions: URL
    public let daemons: URL

    public init(homeDirectory: URL) {
        let root = homeDirectory.appendingPathComponent(".cookey", isDirectory: true)
        self.root = root
        keypair = root.appendingPathComponent("keypair.json")
        config = root.appendingPathComponent("config.json")
        deviceIdentifier = root.appendingPathComponent("device_id")
        sessions = root.appendingPathComponent("sessions", isDirectory: true)
        daemons = root.appendingPathComponent("daemons", isDirectory: true)
    }

    public func sessionURL(for rid: String) -> URL {
        sessions.appendingPathComponent("\(rid).json")
    }

    public func daemonURL(for rid: String) -> URL {
        daemons.appendingPathComponent("\(rid).json")
    }
}

public struct BootstrapContext {
    public let paths: AppPaths
    public let keypair: KeypairFile
    public let config: AppConfig
    public let deviceIdentifier: String
    public let deviceFingerprint: String

    public init(
        paths: AppPaths,
        keypair: KeypairFile,
        config: AppConfig,
        deviceIdentifier: String,
        deviceFingerprint: String
    ) {
        self.paths = paths
        self.keypair = keypair
        self.config = config
        self.deviceIdentifier = deviceIdentifier
        self.deviceFingerprint = deviceFingerprint
    }
}

public enum ConfigStore {
    public static func bootstrap() throws -> BootstrapContext {
        let paths = AppPaths(homeDirectory: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))

        try ensureDirectory(paths.root, permissions: 0o700)
        try ensureDirectory(paths.sessions, permissions: 0o700)
        try ensureDirectory(paths.daemons, permissions: 0o700)

        let keypair = try KeyManager.loadOrCreate(at: paths.keypair)
        let config = try loadConfig(from: paths.config)
        let deviceIdentifier = try loadOrCreateDeviceIdentifier(at: paths.deviceIdentifier)
        let fingerprint = try deviceFingerprint(for: keypair)

        try cleanupStaleDaemonFiles(in: paths)

        return BootstrapContext(
            paths: paths,
            keypair: keypair,
            config: config,
            deviceIdentifier: deviceIdentifier,
            deviceFingerprint: fingerprint
        )
    }

    public static func loadConfig(from url: URL) throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return AppConfig()
        }

        return try readJSON(AppConfig.self, from: url)
    }

    public static func ensureDirectory(_ url: URL, permissions: Int) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    public static func writeJSON(_ value: some Encodable, to url: URL, permissions: Int) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    public static func readJSON<T: Decodable>(_: T.Type, from url: URL) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    public static func loadOrCreateDeviceIdentifier(at url: URL) throws -> String {
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            let value = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }

        let identifier = UUID().uuidString.lowercased()
        try identifier.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return identifier
    }

    public static func deviceFingerprint(for keypair: KeypairFile) throws -> String {
        let hostname = currentHostname()
        let machineID = machineIdentifier() ?? ""
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let arch = currentArchitecture()
        let input = [
            keypair.publicKey,
            hostname,
            os,
            arch,
            machineID,
        ].joined(separator: "|")

        return Data(SHA256.hash(data: Data(input.utf8))).base64URLEncodedString()
    }

    public static func cleanupStaleDaemonFiles(in paths: AppPaths) throws {
        let urls = try daemonFiles(in: paths)
        for url in urls {
            guard let descriptor = try? readJSON(DaemonDescriptor.self, from: url) else {
                continue
            }

            if descriptor.status == .waiting || descriptor.status == .receiving {
                let sessionExists = FileManager.default.fileExists(atPath: paths.sessionURL(for: descriptor.rid).path)
                let processAlive = isProcessAlive(descriptor.pid)
                if !sessionExists, !processAlive {
                    let updated = descriptor.updating(status: .error, errorMessage: "stale daemon descriptor; process is not alive")
                    try writeJSON(updated, to: url, permissions: 0o600)
                }
            }
        }
    }

    public static func latestDaemon(in paths: AppPaths) throws -> DaemonDescriptor? {
        try latestFile(in: paths.daemons).flatMap { try? readJSON(DaemonDescriptor.self, from: $0) }
    }

    public static func latestSessionRID(in paths: AppPaths) throws -> String? {
        try latestFile(in: paths.sessions)?.deletingPathExtension().lastPathComponent
    }

    public static func latestRID(in paths: AppPaths) throws -> String? {
        let latestSessionURL = try latestFile(in: paths.sessions)
        let latestDaemonURL = try latestFile(in: paths.daemons)

        let candidates = [latestSessionURL, latestDaemonURL].compactMap(\.self)
        return candidates
            .max { modificationDate(for: $0) < modificationDate(for: $1) }?
            .deletingPathExtension().lastPathComponent
    }

    public static func statusSnapshot(for rid: String, context: BootstrapContext) -> StatusSnapshot {
        let sessionURL = context.paths.sessionURL(for: rid)
        if FileManager.default.fileExists(atPath: sessionURL.path) {
            let daemon = try? readJSON(DaemonDescriptor.self, from: context.paths.daemonURL(for: rid))
            return StatusSnapshot(
                rid: rid,
                status: .ready,
                pid: daemon?.pid,
                targetURL: daemon?.targetURL,
                sessionPath: sessionURL.path,
                updatedAt: modificationDate(for: sessionURL),
                serverURL: daemon?.serverURL,
                transport: daemon?.transport,
                errorMessage: daemon?.errorMessage
            )
        }

        let daemonURL = context.paths.daemonURL(for: rid)
        if FileManager.default.fileExists(atPath: daemonURL.path),
           let descriptor = try? readJSON(DaemonDescriptor.self, from: daemonURL)
        {
            let isActive = descriptor.status == .waiting || descriptor.status == .receiving
            let status: CLIStatus = if isActive, !isProcessAlive(descriptor.pid) {
                .orphaned
            } else {
                CLIStatus(rawValue: descriptor.status.rawValue) ?? .error
            }

            return StatusSnapshot(
                rid: rid,
                status: status,
                pid: descriptor.pid,
                targetURL: descriptor.targetURL,
                sessionPath: nil,
                updatedAt: descriptor.updatedAt,
                serverURL: descriptor.serverURL,
                transport: descriptor.transport,
                errorMessage: descriptor.errorMessage
            )
        }

        return StatusSnapshot(rid: rid, status: .missing)
    }

    public static func isProcessAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else {
            return false
        }

        let result = kill(pid, 0)
        if result == 0 {
            return true
        }

        return errno == EPERM
    }

    public static func writeSession(_ session: SessionFile, rid: String, paths: AppPaths) throws {
        try writeJSON(session, to: paths.sessionURL(for: rid), permissions: 0o600)
    }

    public static func writeDaemon(_ descriptor: DaemonDescriptor, paths: AppPaths) throws {
        try writeJSON(descriptor, to: paths.daemonURL(for: descriptor.rid), permissions: 0o600)
    }

    private static func latestFile(in directory: URL) throws -> URL? {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return urls.max(by: { modificationDate(for: $0) < modificationDate(for: $1) })
    }

    private static func daemonFiles(in paths: AppPaths) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: paths.daemons, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
    }

    private static func modificationDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    private static func currentHostname() -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        if gethostname(&buffer, buffer.count) == 0 {
            return String(cString: buffer)
        }
        return "unknown-host"
    }

    private static func machineIdentifier() -> String? {
        let candidates = [
            "/etc/machine-id",
            "/var/lib/dbus/machine-id",
        ]

        for path in candidates {
            if let value = try? String(contentsOfFile: path, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty
            {
                return value
            }
        }

        return nil
    }

    private static func currentArchitecture() -> String {
        #if arch(x86_64)
            return "x86_64"
        #elseif arch(arm64)
            return "arm64"
        #elseif arch(i386)
            return "i386"
        #else
            return "unknown"
        #endif
    }
}
