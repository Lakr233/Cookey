import Foundation
import Hummingbird
import HummingbirdWebSocket

/// Route handlers for HelpMeIn Relay Server
public struct Routes: Sendable {
    let storage: RequestStorage
    let config: ServerConfig
    
    public init(storage: RequestStorage, config: ServerConfig) {
        self.storage = storage
        self.config = config
    }
    
    // MARK: - Router Setup
    
    public func setupRouter() -> Router<BasicRequestContext> {
        var router = Router(context: BasicRequestContext.self)
        
        // Health check
        router.get("/health") { _, _ in
            return Response(status: .ok, body: .init(string: "OK"))
        }
        
        // API v1 routes
        router.post("/v1/requests") { [self] request, context -> Response in
            try await self.createRequest(request: request, context: context)
        }
        
        router.get("/v1/requests/:rid") { [self] request, context -> Response in
            try await self.getRequest(request: request, context: context)
        }
        
        router.get("/v1/requests/:rid/wait") { [self] request, context -> Response in
            try await self.waitForRequest(request: request, context: context)
        }
        
        router.post("/v1/requests/:rid/session") { [self] request, context -> Response in
            try await self.uploadSession(request: request, context: context)
        }
        
        // WebSocket endpoint
        router.ws("/v1/requests/:rid/ws") { [self] request, context, inbound, outbound in
            try await self.handleWebSocket(
                request: request,
                context: context,
                inbound: inbound,
                outbound: outbound
            )
        }
        
        return router
    }
    
    // MARK: - POST /v1/requests
    
    private func createRequest(request: Request, context: BasicRequestContext) async throws -> Response {
        // Decode request body
        let body = try await request.body.collect(upTo: 1024 * 10) // 10KB limit for manifest
        let loginRequest = try JSONDecoder().decode(LoginRequest.self, from: body)
        
        // Validate expiration
        guard loginRequest.expiresAt > Date() else {
            return Response(
                status: .badRequest,
                body: .init(string: "{\"error\":\"Invalid expiration time\"}")
            )
        }
        
        // Store request
        let stored = await storage.store(request: loginRequest)
        
        // Return response
        let response = RequestStatusResponse(from: stored)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        
        return Response(
            status: .created,
            headers: headers,
            body: .init(string: self.encodeJSON(response))
        )
    }
    
    // MARK: - GET /v1/requests/:rid
    
    private func getRequest(request: Request, context: BasicRequestContext) async throws -> Response {
        guard let rid = context.parameters.get("rid") else {
            return Response(status: .badRequest, body: .init(string: "Missing request ID"))
        }
        
        guard let stored = await storage.getRequest(rid: rid) else {
            return Response(
                status: .notFound,
                body: .init(string: "{\"error\":\"Request not found\"}")
            )
        }
        
        // Check if expired
        if stored.expiresAt < Date() {
            _ = await storage.updateStatus(rid: rid, status: .expired)
            return Response(
                status: .gone,
                body: .init(string: "{\"error\":\"Request expired\"}")
            )
        }
        
        let response = RequestStatusResponse(from: stored)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        
        return Response(
            status: .ok,
            headers: headers,
            body: .init(string: self.encodeJSON(response))
        )
    }
    
    // MARK: - GET /v1/requests/:rid/wait (Long Polling)
    
    private func waitForRequest(request: Request, context: BasicRequestContext) async throws -> Response {
        guard let rid = context.parameters.get("rid") else {
            return Response(status: .badRequest, body: .init(string: "Missing request ID"))
        }
        
        // Get timeout from query parameter (default 30s)
        let timeoutSeconds = context.uri.queryParameters.get("timeout").flatMap { Int($0) } ?? 30
        let timeout = min(timeoutSeconds, 60) // Cap at 60 seconds
        
        // Check if request exists
        guard let stored = await storage.getRequest(rid: rid) else {
            return Response(
                status: .notFound,
                body: .init(string: "{\"error\":\"Request not found\"}")
            )
        }
        
        // If already ready, return immediately
        if stored.status == .ready {
            _ = await storage.markDelivered(rid: rid)
            var headers = HTTPFields()
            headers[.contentType] = "application/json"
            return Response(
                status: .ok,
                headers: headers,
                body: .init(string: self.encodeJSON(["status": "ready", "rid": rid]))
            )
        }
        
        // If expired, return error
        if stored.expiresAt < Date() {
            _ = await storage.updateStatus(rid: rid, status: .expired)
            return Response(
                status: .gone,
                body: .init(string: "{\"error\":\"Request expired\"}")
            )
        }
        
        // Wait for session with timeout
        let result = await withTimeout(seconds: timeout) {
            await storage.waitForMessage(rid: rid)
        }
        
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        
        switch result {
        case .success(let message):
            switch message {
            case .session(_):
                _ = await storage.markDelivered(rid: rid)
                return Response(
                    status: .ok,
                    headers: headers,
                    body: .init(string: "{\"status\":\"ready\",\"rid\":\"\(rid)\"}")
                )
            case .status(let payload):
                if payload.status == .expired {
                    return Response(
                        status: .gone,
                        headers: headers,
                        body: .init(string: "{\"error\":\"Request expired\"}")
                    )
                }
                return Response(
                    status: .ok,
                    headers: headers,
                    body: .init(string: "{\"status\":\"\(payload.status.rawValue)\",\"rid\":\"\(rid)\"}")
                )
            case .error(let error):
                if error.code == "expired" {
                    return Response(
                        status: .gone,
                        headers: headers,
                        body: .init(string: "{\"error\":\"\(error.message)\"}")
                    )
                }
                return Response(
                    status: .ok,
                    headers: headers,
                    body: .init(string: "{\"status\":\"pending\",\"rid\":\"\(rid)\"}")
                )
            }
            
        case .timeout:
            return Response(
                status: .ok,
                headers: headers,
                body: .init(string: "{\"status\":\"pending\",\"rid\":\"\(rid)\"}")
            )
        }
    }
    
    // MARK: - POST /v1/requests/:rid/session
    
    private func uploadSession(request: Request, context: BasicRequestContext) async throws -> Response {
        guard let rid = context.parameters.get("rid") else {
            return Response(status: .badRequest, body: .init(string: "Missing request ID"))
        }
        
        // Check if request exists
        guard let stored = await storage.getRequest(rid: rid) else {
            return Response(
                status: .notFound,
                body: .init(string: "{\"error\":\"Request not found\"}")
            )
        }
        
        // Check if expired
        if stored.expiresAt < Date() {
            _ = await storage.updateStatus(rid: rid, status: .expired)
            return Response(
                status: .gone,
                body: .init(string: "{\"error\":\"Request expired\"}")
            )
        }
        
        // Check if already has session
        guard stored.status == .pending else {
            return Response(
                status: .conflict,
                body: .init(string: "{\"error\":\"Session already uploaded\"}")
            )
        }
        
        // Decode session
        let body = try await request.body.collect(upTo: config.maxPayloadSize)
        let session = try JSONDecoder().decode(EncryptedSession.self, from: body)
        
        // Validate algorithm
        guard session.algorithm == "x25519-xsalsa20poly1305" else {
            return Response(
                status: .badRequest,
                body: .init(string: "{\"error\":\"Unsupported algorithm\"}")
            )
        }
        
        // Store session
        guard let _ = await storage.storeSession(rid: rid, session: session) else {
            return Response(
                status: .badRequest,
                body: .init(string: "{\"error\":\"Failed to store session\"}")
            )
        }
        
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        
        return Response(
            status: .created,
            headers: headers,
            body: .init(string: "{\"status\":\"uploaded\",\"rid\":\"\(rid)\"}")
        )
    }
    
    // MARK: - WebSocket /v1/requests/:rid/ws
    
    private func handleWebSocket(
        request: Request,
        context: BasicRequestContext,
        inbound: WebSocketInboundStream,
        outbound: WebSocketOutboundWriter
    ) async throws {
        guard let rid = context.parameters.get("rid") else {
            try await outbound.write(.text("{\"error\":\"Missing request ID\"}"))
            return
        }
        
        // Check if request exists
        guard let stored = await storage.getRequest(rid: rid) else {
            try await outbound.write(.text("{\"error\":\"Request not found\"}"))
            return
        }
        
        // Send initial status
        let initialStatus = StatusPayload(status: stored.status, timestamp: Date())
        let statusMessage = WebSocketMessage.status(initialStatus)
        try await outbound.write(.text(self.encodeJSON(statusMessage)))
        
        // If already ready, send session and close
        if stored.status == .ready, let session = stored.encryptedSession {
            let sessionMessage = WebSocketMessage.session(SessionPayload(
                encryptedSession: session,
                deliveredAt: Date()
            ))
            try await outbound.write(.text(self.encodeJSON(sessionMessage)))
            _ = await storage.markDelivered(rid: rid)
            return
        }
        
        // If expired, send error and close
        if stored.expiresAt < Date() {
            _ = await storage.updateStatus(rid: rid, status: .expired)
            let errorMessage = WebSocketMessage.error(ErrorPayload(
                code: "expired",
                message: "Request has expired"
            ))
            try await outbound.write(.text(self.encodeJSON(errorMessage)))
            return
        }
        
        // Handle incoming messages and wait for updates
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Task 1: Handle incoming client messages
            group.addTask {
                for try await frame in inbound {
                    switch frame {
                    case .text(let text):
                        // Handle client messages (ping, etc.)
                        if text == "ping" {
                            try await outbound.write(.text("pong"))
                        }
                    case .binary(_):
                        break
                    case .close:
                        await self.storage.cancelWait(rid: rid)
                        return
                    }
                }
            }
            
            // Task 2: Wait for session updates
            group.addTask {
                let message = await self.storage.waitForMessage(rid: rid)
                try await outbound.write(.text(self.encodeJSON(message)))
                
                // If session delivered, mark and close
                if case .session(_) = message {
                    _ = await self.storage.markDelivered(rid: rid)
                }
                
                // Close connection after sending message
                try await outbound.write(.close())
            }
            
            // Wait for either task to complete
            try await group.next()
            group.cancelAll()
        }
    }
    
    // MARK: - Helpers
    
    private func encodeJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        
        do {
            let data = try encoder.encode(value)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }
    
    private func withTimeout<T>(seconds: Int, operation: @escaping () async -> T) async -> Result<T, TimeoutError> {
        await withTaskGroup(of: Result<T, TimeoutError>.self) { group in
            group.addTask {
                let result = await operation()
                return .success(result)
            }
            
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return .failure(.timeout)
            }
            
            let result = await group.next()!
            group.cancelAll()
            return result
        }
    }
}

enum TimeoutError: Error {
    case timeout
}

enum Result<T, E: Error> {
    case success(T)
    case failure(E)
}