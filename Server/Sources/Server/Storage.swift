import Foundation

/// In-memory storage for pending requests and encrypted sessions
public actor RequestStorage {
    private var requests: [RequestID: StoredRequest] = [:]
    private var webSocketContinuations: [RequestID: [UUID: CheckedContinuation<WebSocketMessage, Never>]] = [:]
    
    private let maxPayloadSize: Int
    
    public init(maxPayloadSize: Int = 1 * 1024 * 1024) {
        self.maxPayloadSize = maxPayloadSize
    }
    
    // MARK: - Request Management
    
    /// Store a new pending request
    public func store(request: LoginRequest) -> StoredRequest {
        let stored = StoredRequest(from: request)
        requests[request.rid] = stored
        return stored
    }
    
    /// Get a stored request by ID
    public func getRequest(rid: RequestID) -> StoredRequest? {
        return requests[rid]
    }
    
    /// Update request status
    public func updateStatus(rid: RequestID, status: RequestStatus) -> StoredRequest? {
        guard var request = requests[rid] else { return nil }
        request.status = status
        requests[rid] = request
        notifyWebSocketListeners(rid: rid, message: .status(StatusPayload(status: status, timestamp: Date())))
        return request
    }
    
    /// Store encrypted session for a request
    public func storeSession(rid: RequestID, session: EncryptedSession) -> StoredRequest? {
        guard var request = requests[rid] else { return nil }
        
        // Validate payload size
        let payloadSize = session.ciphertext.count + session.ephemeralPublicKey.count + session.nonce.count
        guard payloadSize <= maxPayloadSize else {
            return nil
        }
        
        request.encryptedSession = session
        request.status = .ready
        requests[rid] = request
        
        // Notify WebSocket listeners
        notifyWebSocketListeners(rid: rid, message: .session(SessionPayload(
            encryptedSession: session,
            deliveredAt: Date()
        )))
        
        return request
    }
    
    /// Mark request as delivered and remove encrypted session
    public func markDelivered(rid: RequestID) -> StoredRequest? {
        guard var request = requests[rid] else { return nil }
        request.status = .delivered
        request.encryptedSession = nil
        requests[rid] = request
        return request
    }
    
    /// Remove a request (used for cleanup)
    @discardableResult
    public func removeRequest(rid: RequestID) -> StoredRequest? {
        return requests.removeValue(forKey: rid)
    }
    
    /// Clean up expired requests
    public func cleanupExpired() -> [RequestID] {
        let now = Date()
        var expired: [RequestID] = []
        
        for (rid, request) in requests {
            if request.expiresAt < now {
                expired.append(rid)
            }
        }
        
        for rid in expired {
            requests.removeValue(forKey: rid)
            notifyWebSocketListeners(rid: rid, message: .error(ErrorPayload(
                code: "expired",
                message: "Request has expired"
            )))
        }
        
        return expired
    }
    
    /// Get all request IDs
    public func getAllRequestIDs() -> [RequestID] {
        return Array(requests.keys)
    }
    
    // MARK: - WebSocket Management
    
    /// Wait for WebSocket message for a specific request
    public func waitForMessage(rid: RequestID) async -> WebSocketMessage {
        if let message = immediateMessage(rid: rid) {
            return message
        }

        let continuationID = UUID()
        return await withCheckedContinuation { continuation in
            storeContinuation(rid: rid, id: continuationID, continuation: continuation)
        }
    }

    /// Wait for WebSocket message for a specific request with timeout
    public func waitForMessage(rid: RequestID, timeoutSeconds: Int) async -> WebSocketMessage? {
        if let message = immediateMessage(rid: rid) {
            return message
        }

        let continuationID = UUID()
        let message = await withCheckedContinuation { continuation in
            storeContinuation(rid: rid, id: continuationID, continuation: continuation)

            Task {
                do {
                    try await Task.sleep(for: .seconds(timeoutSeconds))
                } catch {
                    return
                }

                await self.resumeContinuationIfPresent(
                    rid: rid,
                    id: continuationID,
                    with: .error(ErrorPayload(code: "timeout", message: "Waiting timed out"))
                )
            }
        }

        if case .error(let payload) = message, payload.code == "timeout" {
            return nil
        }

        return message
    }
    
    /// Notify WebSocket listeners for a request
    private func notifyWebSocketListeners(rid: RequestID, message: WebSocketMessage) {
        if let continuations = webSocketContinuations[rid] {
            for continuation in continuations.values {
                continuation.resume(returning: message)
            }
            webSocketContinuations[rid] = nil
        }
    }
    
    /// Cancel waiting for a request
    public func cancelWait(rid: RequestID) {
        if let continuations = webSocketContinuations[rid] {
            for continuation in continuations.values {
                continuation.resume(returning: .error(ErrorPayload(
                    code: "cancelled",
                    message: "Waiting cancelled"
                )))
            }
            webSocketContinuations[rid] = nil
        }
    }

    private func immediateMessage(rid: RequestID) -> WebSocketMessage? {
        guard let request = requests[rid] else {
            return .error(ErrorPayload(code: "missing", message: "Request not found"))
        }

        if request.status == .ready, let session = request.encryptedSession {
            return .session(SessionPayload(encryptedSession: session, deliveredAt: Date()))
        }

        if request.status == .expired {
            return .error(ErrorPayload(code: "expired", message: "Request has expired"))
        }

        if request.status != .pending {
            return .status(StatusPayload(status: request.status, timestamp: Date()))
        }

        if request.expiresAt < Date() {
            return .error(ErrorPayload(code: "expired", message: "Request has expired"))
        }

        return nil
    }

    private func storeContinuation(
        rid: RequestID,
        id: UUID,
        continuation: CheckedContinuation<WebSocketMessage, Never>
    ) {
        var continuations = webSocketContinuations[rid] ?? [:]
        continuations[id] = continuation
        webSocketContinuations[rid] = continuations
    }

    private func resumeContinuationIfPresent(rid: RequestID, id: UUID, with message: WebSocketMessage) {
        guard var continuations = webSocketContinuations[rid],
              let continuation = continuations.removeValue(forKey: id)
        else {
            return
        }

        if continuations.isEmpty {
            webSocketContinuations[rid] = nil
        } else {
            webSocketContinuations[rid] = continuations
        }

        continuation.resume(returning: message)
    }
}
