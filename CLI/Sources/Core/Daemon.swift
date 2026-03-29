import Foundation
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

public enum DaemonError: Error, LocalizedError {
    case forkFailed
    case detachFailed(String)
    case daemonDescriptorTimeout(String)
    case sessionDecryptionUnsupported(String)
    case invalidServerURL(String)

    public var errorDescription: String? {
        switch self {
        case .forkFailed:
            return "fork() failed"
        case .detachFailed(let reason):
            return "Daemon detach failed: \(reason)"
        case .daemonDescriptorTimeout(let rid):
            return "Timed out waiting for daemon descriptor for \(rid)"
        case .sessionDecryptionUnsupported(let algorithm):
            return "Session payload algorithm is not supported by this build: \(algorithm)"
        case .invalidServerURL(let value):
            return "Invalid server URL: \(value)"
        }
    }
}

private struct DaemonExit: Error {
    let code: Int32
}

public enum Daemon {
    public static func launchDetached(
        context: BootstrapContext,
        manifest: LoginManifest,
        timeoutSeconds: Int
    ) throws -> Int32 {
        let pid = fork()
        if pid < 0 {
            throw DaemonError.forkFailed
        }

        if pid > 0 {
            try waitForDescriptor(rid: manifest.rid, expectedPID: pid, paths: context.paths)
            return pid
        }

        do {
            try detachFromTerminal()
            try runChild(context: context, manifest: manifest, timeoutSeconds: timeoutSeconds)
            _exit(0)
        } catch let exit as DaemonExit {
            _exit(exit.code)
        } catch {
            _exit(1)
        }
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

    private static func detachFromTerminal() throws {
        if setsid() < 0 {
            throw DaemonError.detachFailed("setsid() returned an error")
        }

        let devNull = open("/dev/null", O_RDWR)
        if devNull < 0 {
            throw DaemonError.detachFailed("unable to open /dev/null")
        }

        for handle in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
            if dup2(devNull, handle) < 0 {
                close(devNull)
                throw DaemonError.detachFailed("dup2() failed")
            }
        }

        if devNull > STDERR_FILENO {
            close(devNull)
        }
    }

    private static func decodeSession(
        envelope: EncryptedSessionEnvelope,
        rid: String,
        manifest: LoginManifest,
        deviceFingerprint: String
    ) throws -> SessionFile {
        if envelope.algorithm.lowercased() == "plaintext-json",
           let raw = Data(base64Encoded: envelope.ciphertext) {
            let decoder = JSONDecoder()
            let session = try decoder.decode(SessionFile.self, from: raw)
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

        throw DaemonError.sessionDecryptionUnsupported(envelope.algorithm)
    }
}
