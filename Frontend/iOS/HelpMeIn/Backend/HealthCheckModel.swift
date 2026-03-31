import Foundation
import Observation

@Observable
final class HealthCheckModel {
    enum Status {
        case idle
        case checking
        case healthy(APIHealthCheckResult)
        case failed(String)
    }

    private let client = APIClient(baseURL: AppEnvironment.productionAPIBaseURL)

    var status: Status = .idle

    func refresh() async {
        status = .checking

        do {
            status = .healthy(try await client.healthCheck())
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
