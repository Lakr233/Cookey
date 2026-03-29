import Foundation
import Hummingbird
import HummingbirdWebSocket
import Logging

enum HelpMeInServer {
    // MARK: - Argument Parsing
    
    static func parseArguments() -> ServerConfig {
        let arguments = CommandLine.arguments
        
        var host = "0.0.0.0"
        var port = 8080
        var defaultTTL: TimeInterval = 300
        var maxPayloadSize = 1 * 1024 * 1024 // 1MB
        var publicURL: String? = nil
        
        var i = 1
        while i < arguments.count {
            let arg = arguments[i]
            
            switch arg {
            case "--host", "-h":
                if i + 1 < arguments.count {
                    host = arguments[i + 1]
                    i += 2
                } else {
                    i += 1
                }
                
            case "--port", "-p":
                if i + 1 < arguments.count, let p = Int(arguments[i + 1]) {
                    port = p
                    i += 2
                } else {
                    i += 1
                }
                
            case "--public-url", "-u":
                if i + 1 < arguments.count {
                    publicURL = arguments[i + 1]
                    i += 2
                } else {
                    i += 1
                }
                
            case "--ttl", "-t":
                if i + 1 < arguments.count, let t = Double(arguments[i + 1]) {
                    defaultTTL = t
                    i += 2
                } else {
                    i += 1
                }
                
            case "--max-payload", "-m":
                if i + 1 < arguments.count, let m = Int(arguments[i + 1]) {
                    maxPayloadSize = m
                    i += 2
                } else {
                    i += 1
                }
                
            case "--help":
                printHelp()
                exit(0)
                
            default:
                i += 1
            }
        }
        
        // Use environment variables as fallback
        if let envHost = ProcessInfo.processInfo.environment["HELPMEIN_HOST"] {
            host = envHost
        }
        if let envPort = ProcessInfo.processInfo.environment["HELPMEIN_PORT"], let p = Int(envPort) {
            port = p
        }
        if let envPublicURL = ProcessInfo.processInfo.environment["HELPMEIN_PUBLIC_URL"] {
            publicURL = envPublicURL
        }
        
        return ServerConfig(
            host: host,
            port: port,
            defaultTTL: defaultTTL,
            maxPayloadSize: maxPayloadSize,
            publicURL: publicURL
        )
    }
    
    static func printHelp() {
        print("""
        HelpMeIn Relay Server
        
        Usage: HelpMeInServer [OPTIONS]
        
        Options:
          -h, --host <host>         Bind host (default: 0.0.0.0)
          -p, --port <port>         Bind port (default: 8080)
          -u, --public-url <url>    Public URL for QR codes
          -t, --ttl <seconds>       Default request TTL (default: 300)
          -m, --max-payload <bytes> Max payload size (default: 1048576)
          --help                    Show this help message
        
        Environment Variables:
          HELPMEIN_HOST             Bind host
          HELPMEIN_PORT             Bind port
          HELPMEIN_PUBLIC_URL       Public URL
        
        Examples:
          HelpMeInServer
          HelpMeInServer --port 3000
          HelpMeInServer --host 127.0.0.1 --port 8080
        """)
    }
    
    // MARK: - Cleanup Task
    
    static func runCleanupTask(storage: RequestStorage, logger: Logger) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(30))
                let expired = await storage.cleanupExpired()
                if !expired.isEmpty {
                    logger.debug("Cleaned up \(expired.count) expired requests")
                }
            } catch {
                break
            }
        }
    }
}

func runServer() async throws {
    let config = HelpMeInServer.parseArguments()

    LoggingSystem.bootstrap {
        var handler = StreamLogHandler.standardOutput(label: $0)
        handler.logLevel = .info
        return handler
    }
    let logger = Logger(label: "HelpMeInServer")

    logger.info("🚀 HelpMeIn Relay Server starting...")
    logger.info("   Host: \(config.host)")
    logger.info("   Port: \(config.port)")
    logger.info("   Public URL: \(config.publicURL)")
    logger.info("   Default TTL: \(config.defaultTTL)s")
    logger.info("   Max Payload: \(config.maxPayloadSize / 1024)KB")

    let storage = RequestStorage(maxPayloadSize: config.maxPayloadSize)
    let routes = Routes(storage: storage, config: config)
    let router = routes.setupRouter()
    let webSocketRouter = routes.setupWebSocketRouter()

    let app = Application(
        router: router,
        server: .http1WebSocketUpgrade(webSocketRouter: webSocketRouter),
        configuration: .init(
            address: .hostname(config.host, port: config.port),
            serverName: "HelpMeIn-Relay/1.0"
        ),
        logger: logger
    )

    let cleanupTask = Task {
        await HelpMeInServer.runCleanupTask(storage: storage, logger: logger)
    }
    defer { cleanupTask.cancel() }

    logger.info("✅ Server ready")
    try await app.runService()
}

try await runServer()
