import Foundation

/// In-memory storage for pending requests and encrypted sessions
public actor RequestStorage {
    private var requests: [RequestID: StoredRequest] = [:]
    private var webSocketContinuations: [RequestID: [CheckedContinuation<WebSocketMessage, Never>]] = [:]
    
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
        // Check if request already has session ready
        if let request = requests[rid], request.status == .ready, let session = request.encryptedSession {
            return .session(SessionPayload(encryptedSession: session, deliveredAt: Date()))
        }
        
        // Check if request is expired
        if let request = requests[rid], request.expiresAt < Date() {
            return .error(ErrorPayload(code: "expired", message: "Request has expired"))
        }
        
        // Wait for message
        return await withCheckedContinuation { continuation in
            if webSocketContinuations[rid] == nil {
                webSocketContinuations[rid] = []
            }
            webSocketContinuations[rid]?.append(continuation)
        }
    }
    
    /// Notify WebSocket listeners for a request
    private func notifyWebSocketListeners(rid: RequestID, message: WebSocketMessage) {
        if let continuations = webSocketContinuations[rid] {
            for continuation in continuations {
                continuation.resume(returning: message)
            }
            webSocketContinuations[rid] = nil
        }
    }
    
    /// Cancel waiting for a request
    public func cancelWait(rid: RequestID) {
        if let continuations = webSocketContinuations[rid] {
            for continuation in continuations {
                continuation.resume(returning: .error(ErrorPayload(
                    code: "cancelled",
                    message: "Waiting cancelled"
                )))
            }
            webSocketContinuations[rid] = nil
        }
    }
}