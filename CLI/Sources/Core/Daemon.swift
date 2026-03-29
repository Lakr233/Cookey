import Foundation
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

public enum DaemonError: Error, LocalizedError {
    case invalidDaemonPayload
    case detachFailed(String)
    case daemonDescriptorTimeout(String)
    case invalidServerURL(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDaemonPayload:
            return "Invalid daemon launch payload"
        case .detachFailed(let reason):
            return "Daemon detach failed: \(reason)"
        case .daemonDescriptorTimeout(let rid):
            return "Timed out waiting for daemon descriptor for \(rid)"
        case .invalidServerURL(let value):
            return "Invalid server URL: \(value)"
        }
    }
}

private struct DaemonExit: Error {
    let code: Int32
}

public struct DaemonLaunchPayload: Codable {
    public let manifest: LoginManifest
    public let timeoutSeconds: Int

    public init(manifest: LoginManifest, timeoutSeconds: Int) {
        self.manifest = manifest
        self.timeoutSeconds = timeoutSeconds
    }
}

public enum Daemon {
    public static func launchDetached(
        context: BootstrapContext,
        manifest: LoginManifest,
        timeoutSeconds: Int
    ) throws -> Int32 {
        let payload = DaemonLaunchPayload(manifest: manifest, timeoutSeconds: timeoutSeconds)
        let process = Process()
        process.executableURL = try resolveExecutableURL()
        process.arguments = ["__daemon", try encodeLaunchPayload(payload)]
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        process.standardInput = try devNullHandle(forReading: true)
        process.standardOutput = try devNullHandle(forReading: false)
        process.standardError = try devNullHandle(forReading: false)

        try process.run()
        try waitForDescriptor(rid: manifest.rid, expectedPID: process.processIdentifier, paths: context.paths)
        return process.processIdentifier
    }

    public static func runInline(
        context: BootstrapContext,
        manifest: LoginManifest,
        timeoutSeconds: Int
    ) throws {
        do {
            try runChild(context: context, manifest: manifest, timeoutSeconds: timeoutSeconds)
        } catch let exit as DaemonExit {
            _exit(exit.code)
        }
    }

    private static func runChild(
        context: BootstrapContext,
        manifest: LoginManifest,
        timeoutSeconds: Int
    ) throws {
        let pid = getpid()
        let descriptor = DaemonDescriptor(
            rid: manifest.rid,
            pid: pid,
            ppid: getppid(),
            status: .waiting,
            serverURL: manifest.serverURL,
            transport: manifest.transportHint,
            startedAt: manifest.createdAt,
            updatedAt: manifest.createdAt,
            targetURL: manifest.targetURL
        )

        try ConfigStore.writeDaemon(descriptor, paths: context.paths)

        guard let serverURL = URL(string: manifest.serverURL) else {
            let errored = descriptor.updating(status: .error, errorMessage: "invalid server URL")
            try ConfigStore.writeDaemon(errored, paths: context.paths)
            throw DaemonError.invalidServerURL(manifest.serverURL)
        }

        let relay = RelayClient(baseURL: serverURL)

        do {
            let envelope = try relay.waitForSession(
                rid: manifest.rid,
                transport: manifest.transportHint,
                timeoutSeconds: timeoutSeconds
            )
            let receiving = descriptor.updating(status: .receiving)
            try ConfigStore.writeDaemon(receiving, paths: context.paths)

            let session = try decodeSession(
                envelope: envelope,
                rid: manifest.rid,
                manifest: manifest,
                keypair: context.keypair,
                deviceFingerprint: context.deviceFingerprint
            )

            try ConfigStore.writeSession(session, rid: manifest.rid, paths: context.paths)
            let ready = receiving.updating(status: .ready)
            try ConfigStore.writeDaemon(ready, paths: context.paths)
        } catch RelayClientError.expired {
            let expired = descriptor.updating(status: .expired)
            try ConfigStore.writeDaemon(expired, paths: context.paths)
            throw DaemonExit(code: 3)
        } catch RelayClientError.timeout {
            let expired = descriptor.updating(status: .expired, errorMessage: "timeout waiting for encrypted session")
            try ConfigStore.writeDaemon(expired, paths: context.paths)
            throw DaemonExit(code: 3)
        } catch {
            let errored = descriptor.updating(status: .error, errorMessage: error.localizedDescription)
            try ConfigStore.writeDaemon(errored, paths: context.paths)
            throw DaemonExit(code: 5)
        }
    }

    private static func waitForDescriptor(rid: String, expectedPID: Int32, paths: AppPaths) throws {
        let deadline = Date().addingTimeInterval(5)
        let url = paths.daemonURL(for: rid)

        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path),
               let descriptor = try? ConfigStore.readJSON(DaemonDescriptor.self, from: url),
               descriptor.pid == expectedPID {
                return
            }

            Thread.sleep(forTimeInterval: 0.1)
        }

        throw DaemonError.daemonDescriptorTimeout(rid)
    }

    public static func decodeLaunchPayload(_ encoded: String) throws -> DaemonLaunchPayload {
        guard let data = Data(base64Encoded: encoded) else {
            throw DaemonError.invalidDaemonPayload
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DaemonLaunchPayload.self, from: data)
    }

    private static func decodeSession(
        envelope: EncryptedSessionEnvelope,
        rid: String,
        manifest: LoginManifest,
        keypair: KeypairFile,
        deviceFingerprint: String
    ) throws -> SessionFile {
        let decoder = JSONDecoder()
        let session = try decoder.decode(
            SessionFile.self,
            from: try KeyManager.decryptSessionEnvelope(envelope, using: keypair)
        )
        return SessionFile(
            cookies: session.cookies,
            origins: session.origins,
            metadata: SessionMetadata(
                rid: rid,
                receivedAt: Date(),
                serverURL: manifest.serverURL,
                targetURL: manifest.targetURL,
                deviceFingerprint: deviceFingerprint
            )
        )
    }

    private static func encodeLaunchPayload(_ payload: DaemonLaunchPayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload).base64EncodedString()
    }

    private static func resolveExecutableURL() throws -> URL {
        if let executableURL = Bundle.main.executableURL {
            return executableURL
        }

        let executable = CommandLine.arguments[0]
        if executable.contains("/") {
            let baseURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            return URL(fileURLWithPath: executable, relativeTo: baseURL).standardizedFileURL
        }

        let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for path in searchPaths {
            let candidate = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent(executable)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        throw DaemonError.detachFailed("unable to resolve current executable")
    }

    private static func devNullHandle(forReading: Bool) throws -> FileHandle {
        let handle = forReading ? FileHandle(forReadingAtPath: "/dev/null") : FileHandle(forWritingAtPath: "/dev/null")
        guard let handle else {
            throw DaemonError.detachFailed("unable to open /dev/null")
        }
        return handle
    }
}
