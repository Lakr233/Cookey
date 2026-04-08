@testable import Cookey
import Foundation
import Testing

@MainActor
struct LaunchBackendReachabilityCoordinatorTests {
    actor InvocationCounter {
        private(set) var count = 0

        func increment() {
            count += 1
        }
    }

    @Test("LaunchBackendReachabilityCoordinator runs startup health check only once")
    func runsHealthCheckOnlyOnce() async throws {
        let counter = InvocationCounter()
        let coordinator = LaunchBackendReachabilityCoordinator(
            baseURLProvider: { URL(string: "https://api.cookey.test")! },
            healthCheckOperation: {
                await counter.increment()
                return HealthCheckResult(body: "ok", serverName: "test-relay", checkedAt: Date())
            }
        )

        coordinator.warmUpIfNeeded()
        coordinator.warmUpIfNeeded()
        try await Task.sleep(for: .milliseconds(50))

        let count = await counter.count
        #expect(count == 1)
    }

    @Test("LaunchBackendReachabilityCoordinator swallows startup health check failures")
    func swallowsHealthCheckFailures() async throws {
        struct ExpectedFailure: LocalizedError {
            var errorDescription: String? { "offline" }
        }

        let counter = InvocationCounter()
        let coordinator = LaunchBackendReachabilityCoordinator(
            baseURLProvider: { URL(string: "https://api.cookey.test")! },
            healthCheckOperation: {
                await counter.increment()
                throw ExpectedFailure()
            }
        )

        coordinator.warmUpIfNeeded()
        try await Task.sleep(for: .milliseconds(50))

        let count = await counter.count
        #expect(count == 1)
    }
}
