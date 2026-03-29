import Core
import Foundation
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

enum CLIError: Error, LocalizedError {
    case usage(String)
    case missingValue(String)
    case invalidValue(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message), .missingValue(let message), .invalidValue(let message):
            return message
        }
    }
}

struct LoginOutput: Codable {
    let rid: String
    let serverURL: String
    let targetURL: String
    let transport: Transport
    let timeoutSeconds: Int
    let daemonPID: Int32
    let deepLink: String
    let qrText: String
    let detached: Bool

    enum CodingKeys: String, CodingKey {
        case rid
        case serverURL = "server_url"
        case targetURL = "target_url"
        case transport
        case timeoutSeconds = "timeout_seconds"
        case daemonPID = "daemon_pid"
        case deepLink = "deep_link"
        case qrText = "qr_text"
        case detached
    }
}

struct StatusSummary: Codable {
    let latestDaemon: StatusSnapshot?
    let latestSession: StatusSnapshot?

    enum CodingKeys: String, CodingKey {
        case latestDaemon = "latest_daemon"
        case latestSession = "latest_session"
    }
}

@main
enum HelpMeInCLI {
    static func main() {
        do {
            try run()
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            printUsage()
            return
        }
        args.removeFirst()

        switch command {
        case "login":
            try handleLogin(arguments: args)
        case "status":
            try handleStatus(arguments: args)
        case "help", "--help", "-h":
            printUsage()
        default:
            throw CLIError.usage("Unknown command: \(command)")
        }
    }

    private static func handleLogin(arguments: [String]) throws {
        guard let targetURL = arguments.first, !targetURL.hasPrefix("-") else {
            throw CLIError.usage("Usage: helpmein login <target_url> [--server URL] [--timeout 300] [--transport ws|poll] [--json] [--no-detach]")
        }

        let flags = try parseFlags(from: Array(arguments.dropFirst()))
        let context = try ConfigStore.bootstrap()

        let serverURLString = flags["server"] ?? context.config.defaultServer ?? "https://relay.example.com"
        guard let serverURL = URL(string: serverURLString) else {
            throw CLIError.invalidValue("Invalid --server value: \(serverURLString)")
        }

        let timeoutSeconds = try parseIntFlag("timeout", in: flags) ?? context.config.timeoutSeconds ?? 300
        let transport = try parseTransport(flags["transport"] ?? context.config.transport?.rawValue ?? Transport.ws.rawValue)
        let jsonOutput = flags["json"] != nil
        let noDetach = flags["no-detach"] != nil
        let rid = KeyManager.generateRequestID()
        let createdAt = Date()
        let manifest = LoginManifest(
            rid: rid,
            targetURL: targetURL,
            serverURL: serverURL.absoluteString,
            cliPublicKey: try KeyManager.x25519PublicKeyBase64(from: context.keypair),
            deviceFingerprint: context.deviceFingerprint,
            transportHint: transport,
            createdAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(TimeInterval(timeoutSeconds))
        )

        let relay = RelayClient(baseURL: serverURL)
        try relay.register(manifest: manifest)

        let deepLink = TerminalQRCode.deepLink(for: manifest)
        let qrText = TerminalQRCode.render(link: deepLink)

        if noDetach {
            let output = LoginOutput(
                rid: rid,
                serverURL: manifest.serverURL,
                targetURL: targetURL,
                transport: transport,
                timeoutSeconds: timeoutSeconds,
                daemonPID: Int32(getpid()),
                deepLink: deepLink,
                qrText: qrText,
                detached: false
            )
            try emitLoginOutput(output, asJSON: jsonOutput)
            try Daemon.runInline(context: context, manifest: manifest, timeoutSeconds: timeoutSeconds)
            return
        }

        let daemonPID = try Daemon.launchDetached(context: context, manifest: manifest, timeoutSeconds: timeoutSeconds)
        let output = LoginOutput(
            rid: rid,
            serverURL: manifest.serverURL,
            targetURL: targetURL,
            transport: transport,
            timeoutSeconds: timeoutSeconds,
            daemonPID: daemonPID,
            deepLink: deepLink,
            qrText: qrText,
            detached: true
        )
        try emitLoginOutput(output, asJSON: jsonOutput)
    }

    private static func handleStatus(arguments: [String]) throws {
        let flags = try parseFlags(from: arguments)
        let jsonOutput = flags["json"] != nil
        let watch = flags["watch"] != nil
        let latest = flags["latest"] != nil
        let ridArgument = arguments.first(where: { !$0.hasPrefix("-") })
        let context = try ConfigStore.bootstrap()

        if let ridArgument, latest {
            throw CLIError.usage("Use either [rid] or --latest, not both.")
        }

        if watch, ridArgument == nil, !latest {
            throw CLIError.usage("helpmein status --watch requires a rid or --latest.")
        }

        if ridArgument == nil, !latest {
            let summary = try latestSummary(context: context)
            try emit(summary, asJSON: jsonOutput)
            return
        }

        guard let rid = ridArgument ?? ConfigStore.latestRID(in: context.paths) else {
            throw CLIError.invalidValue("No local requests found.")
        }

        if watch {
            try watchStatus(rid: rid, context: context, asJSON: jsonOutput)
        } else {
            let snapshot = try resolveStatus(rid: rid, context: context)
            try emit(snapshot, asJSON: jsonOutput)
        }
    }

    private static func latestSummary(context: BootstrapContext) throws -> StatusSummary {
        let latestDaemon = try ConfigStore.latestDaemon(in: context.paths).map {
            ConfigStore.statusSnapshot(for: $0.rid, context: context)
        }
        let latestSession = try ConfigStore.latestSessionRID(in: context.paths).map {
            ConfigStore.statusSnapshot(for: $0, context: context)
        }
        return StatusSummary(latestDaemon: latestDaemon, latestSession: latestSession)
    }

    private static func watchStatus(rid: String, context: BootstrapContext, asJSON: Bool) throws {
        var lastPrinted: String?

        while true {
            let snapshot = try resolveStatus(rid: rid, context: context)
            let rendered = try render(snapshot, asJSON: asJSON)

            if rendered != lastPrinted {
                print(rendered)
                lastPrinted = rendered
            }

            switch snapshot.status {
            case .ready, .expired, .error, .orphaned, .missing:
                return
            case .waiting, .receiving:
                Thread.sleep(forTimeInterval: 1.0)
            }
        }
    }

    private static func resolveStatus(rid: String, context: BootstrapContext) throws -> StatusSnapshot {
        let local = ConfigStore.statusSnapshot(for: rid, context: context)
        if local.status != .missing {
            return local
        }

        guard let serverURLString = context.config.defaultServer,
              let serverURL = URL(string: serverURLString) else {
            return local
        }

        let relay = RelayClient(baseURL: serverURL)
        guard let remote = try relay.fetchStatus(rid: rid) else {
            return local
        }

        let status = CLIStatus(rawValue: remote.status?.lowercased() ?? "") ?? .missing
        return StatusSnapshot(
            rid: remote.rid ?? rid,
            status: status,
            pid: nil,
            targetURL: remote.targetURL,
            sessionPath: nil,
            updatedAt: remote.expiresAt,
            serverURL: serverURL.absoluteString,
            transport: nil,
            errorMessage: nil
        )
    }

    private static func emitLoginOutput(_ output: LoginOutput, asJSON: Bool) throws {
        if asJSON {
            try emit(output, asJSON: true)
            return
        }

        print("rid: \(output.rid)")
        print("target_url: \(output.targetURL)")
        print("server_url: \(output.serverURL)")
        print("transport: \(output.transport.rawValue)")
        print("timeout_seconds: \(output.timeoutSeconds)")
        print("daemon_pid: \(output.daemonPID)")
        print("deep_link: \(output.deepLink)")
        print(output.qrText)
    }

    private static func emit<T: Encodable>(_ value: T, asJSON: Bool) throws {
        if asJSON {
            print(try render(value, asJSON: true))
            return
        }

        print(try render(value, asJSON: false))
    }

    private static func render<T: Encodable>(_ value: T, asJSON: Bool) throws -> String {
        if asJSON {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(value)
            return String(decoding: data, as: UTF8.self)
        }

        if let snapshot = value as? StatusSnapshot {
            var lines = [
                "rid: \(snapshot.rid)",
                "status: \(snapshot.status.rawValue)"
            ]
            if let pid = snapshot.pid {
                lines.append("pid: \(pid)")
            }
            if let targetURL = snapshot.targetURL {
                lines.append("target_url: \(targetURL)")
            }
            if let sessionPath = snapshot.sessionPath {
                lines.append("session_path: \(sessionPath)")
            }
            if let updatedAt = snapshot.updatedAt {
                lines.append("updated_at: \(ISO8601DateFormatter().string(from: updatedAt))")
            }
            if let serverURL = snapshot.serverURL {
                lines.append("server_url: \(serverURL)")
            }
            if let transport = snapshot.transport {
                lines.append("transport: \(transport.rawValue)")
            }
            if let errorMessage = snapshot.errorMessage {
                lines.append("error: \(errorMessage)")
            }
            return lines.joined(separator: "\n")
        }

        if let summary = value as? StatusSummary {
            var lines = [String]()
            if let latestDaemon = summary.latestDaemon {
                lines.append("latest_daemon:")
                lines.append(try render(latestDaemon, asJSON: false))
            }
            if let latestSession = summary.latestSession {
                lines.append("latest_session:")
                lines.append(try render(latestSession, asJSON: false))
            }
            if lines.isEmpty {
                lines.append("No local requests found.")
            }
            return lines.joined(separator: "\n")
        }

        return String(describing: value)
    }

    private static func parseFlags(from arguments: [String]) throws -> [String: String] {
        var result: [String: String] = [:]
        var index = 0

        while index < arguments.count {
            let token = arguments[index]
            guard token.hasPrefix("--") else {
                index += 1
                continue
            }

            let flag = String(token.dropFirst(2))
            switch flag {
            case "json", "no-detach", "latest", "watch":
                result[flag] = "true"
                index += 1
            case "server", "timeout", "transport":
                let valueIndex = index + 1
                guard valueIndex < arguments.count else {
                    throw CLIError.missingValue("Missing value for --\(flag)")
                }
                result[flag] = arguments[valueIndex]
                index += 2
            default:
                throw CLIError.usage("Unknown flag: --\(flag)")
            }
        }

        return result
    }

    private static func parseIntFlag(_ name: String, in flags: [String: String]) throws -> Int? {
        guard let raw = flags[name] else {
            return nil
        }
        guard let value = Int(raw), value > 0 else {
            throw CLIError.invalidValue("Invalid --\(name) value: \(raw)")
        }
        return value
    }

    private static func parseTransport(_ raw: String) throws -> Transport {
        guard let transport = Transport(rawValue: raw.lowercased()) else {
            throw CLIError.invalidValue("Invalid --transport value: \(raw)")
        }
        return transport
    }

    private static func printUsage() {
        print(
            """
            Usage:
              helpmein login <target_url> [--server URL] [--timeout 300] [--transport ws|poll] [--json] [--no-detach]
              helpmein status [rid] [--latest] [--watch] [--json]
            """
        )
    }
}
