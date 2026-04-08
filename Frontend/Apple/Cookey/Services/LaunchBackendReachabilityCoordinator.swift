import Foundation

@MainActor
final class LaunchBackendReachabilityCoordinator {
    typealias HealthCheckOperation = @Sendable () async throws -> HealthCheckResult

    private let baseURLProvider: @Sendable () -> URL
    private let healthCheckOperation: HealthCheckOperation
    private var hasStarted = false

    init(
        baseURLProvider: @escaping @Sendable () -> URL = { AppEnvironment.effectiveAPIBaseURL },
        healthCheckOperation: HealthCheckOperation? = nil
    ) {
        self.baseURLProvider = baseURLProvider
        self.healthCheckOperation = healthCheckOperation ?? {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.waitsForConnectivity = false
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 5
            let session = URLSession(configuration: configuration)
            return try await RelayClient(baseURL: baseURLProvider(), session: session).healthCheck()
        }
    }

    func warmUpIfNeeded() {
        guard !hasStarted else {
            Logger.network.debugFile("Skipping launch backend reachability check because it already started")
            return
        }

        hasStarted = true
        let baseURL = baseURLProvider()
        Logger.network.infoFile("Starting launch backend reachability check to \(baseURL.host() ?? baseURL.absoluteString)")

        Task {
            do {
                let result = try await healthCheckOperation()
                Logger.network.infoFile("Launch backend reachability check succeeded with server \(result.serverName)")
            } catch {
                Logger.network.debugFile("Launch backend reachability check failed silently: \(error.localizedDescription)")
            }
        }
    }
}
