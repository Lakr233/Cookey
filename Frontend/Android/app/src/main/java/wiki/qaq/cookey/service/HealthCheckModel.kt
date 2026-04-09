package wiki.qaq.cookey.service

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import wiki.qaq.cookey.network.RelayClient

enum class HealthStatus {
    IDLE, CHECKING, HEALTHY, FAILED
}

class HealthCheckModel {

    private val _status = MutableStateFlow(HealthStatus.IDLE)
    val status = _status.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage = _errorMessage.asStateFlow()

    suspend fun check(serverURL: String) {
        _status.value = HealthStatus.CHECKING
        _errorMessage.value = null

        try {
            val client = RelayClient(serverURL)
            val healthy = client.healthCheck()
            if (healthy) {
                _status.value = HealthStatus.HEALTHY
            } else {
                _status.value = HealthStatus.FAILED
                _errorMessage.value = "Server returned unhealthy status"
            }
        } catch (e: Exception) {
            _status.value = HealthStatus.FAILED
            _errorMessage.value = e.localizedMessage ?: "Connection failed"
        }
    }
}
