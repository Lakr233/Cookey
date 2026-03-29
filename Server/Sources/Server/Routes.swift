import Foundation
import Hummingbird
import HummingbirdWebSocket
import NIOCore

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
            return self.textResponse(status: .ok, body: "OK")
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
        
        return router
    }

    public func setupWebSocketRouter() -> Router<BasicWebSocketRequestContext> {
        var router = Router(context: BasicWebSocketRequestContext.self)

        router.ws("/v1/requests/:rid/ws") { _, _ in
            .upgrade()
        } onUpgrade: { [self] inbound, outbound, context in
            try await self.handleWebSocket(
                rid: context.requestContext.parameters.get("rid"),
                inbound: inbound,
                outbound: outbound
            )
        }

        return router
    }
    
    // MARK: - POST /v1/requests

    private func createRequest(request: Request, context: BasicRequestContext) async throws -> Response {
        let loginRequest: LoginRequest
        do {
            loginRequest = try await self.decodeJSONBody(LoginRequest.self, from: request, limit: 1024 * 10)
        } catch {
            return self.jsonResponse(
                status: .badRequest,
                payload: ["error": "Invalid request payload"]
            )
        }
        
        // Validate expiration
        guard loginRequest.expiresAt > Date() else {
            return self.jsonResponse(
                status: .badRequest,
                payload: ["error": "Invalid expiration time"]
            )
        }
        
        // Store request
        let stored = await storage.store(request: loginRequest)
        
        // Return response
        let response = RequestStatusResponse(from: stored)
        return self.jsonResponse(status: .created, payload: response)
    }
    
    // MARK: - GET /v1/requests/:rid
    
    private func getRequest(request: Request, context: BasicRequestContext) async throws -> Response {
        guard let rid = context.parameters.get("rid") else {
            return self.textResponse(status: .badRequest, body: "Missing request ID")
        }
        
        guard let stored = await storage.getRequest(rid: rid) else {
            return self.jsonResponse(status: .notFound, payload: ["error": "Request not found"])
        }
        
        // Check if expired
        if stored.expiresAt < Date() {
            _ = await storage.updateStatus(rid: rid, status: .expired)
            return self.jsonResponse(status: .gone, payload: ["error": "Request expired"])
        }
        
        let response = RequestStatusResponse(from: stored)
        return self.jsonResponse(status: .ok, payload: response)
    }
    
    // MARK: - GET /v1/requests/:rid/wait (Long Polling)
    
    private func waitForRequest(request: Request, context: BasicRequestContext) async throws -> Response {
        guard let rid = context.parameters.get("rid") else {
            return self.textResponse(status: .badRequest, body: "Missing request ID")
        }
        
        // Get timeout from query parameter (default 30s)
        let timeoutSeconds = request.uri.queryParameters.get("timeout").flatMap { Int($0) } ?? 30
        let timeout = min(timeoutSeconds, 60) // Cap at 60 seconds
        
        // Check if request exists
        guard let stored = await storage.getRequest(rid: rid) else {
            return self.jsonResponse(status: .notFound, payload: ["error": "Request not found"])
        }
        
        // If already ready, return immediately
        if stored.status == .ready, stored.encryptedSession != nil {
            _ = await storage.markDelivered(rid: rid)
            return self.jsonResponse(
                status: .ok,
                payload: RequestWaitResponse(
                    rid: stored.rid,
                    status: stored.status,
                    encryptedSession: stored.encryptedSession,
                    deliveredAt: Date()
                )
            )
        }

        if stored.status == .expired {
            return self.jsonResponse(status: .gone, payload: ["error": "Request expired"])
        }

        if stored.status != .pending {
            return self.jsonResponse(
                status: .ok,
                payload: RequestWaitResponse(rid: rid, status: stored.status)
            )
        }
        
        // If expired, return error
        if stored.expiresAt < Date() {
            _ = await storage.updateStatus(rid: rid, status: .expired)
            return self.jsonResponse(status: .gone, payload: ["error": "Request expired"])
        }
        
        // Wait for session with timeout
        guard let message = await storage.waitForMessage(rid: rid, timeoutSeconds: timeout) else {
            return self.jsonResponse(
                status: .ok,
                payload: RequestWaitResponse(rid: rid, status: .pending)
            )
        }

        switch message {
        case .session(let payload):
            _ = await storage.markDelivered(rid: rid)
            return self.jsonResponse(
                status: .ok,
                payload: RequestWaitResponse(
                    rid: rid,
                    status: .ready,
                    encryptedSession: payload.encryptedSession,
                    deliveredAt: payload.deliveredAt
                )
            )

        case .status(let payload):
            if payload.status == RequestStatus.expired {
                return self.jsonResponse(status: .gone, payload: ["error": "Request expired"])
            }
            return self.jsonResponse(
                status: .ok,
                payload: RequestWaitResponse(rid: rid, status: payload.status)
            )

        case .error(let error):
            let errorPayload: [String: String] = ["error": error.message]
            switch error.code {
            case "expired":
                return self.jsonResponse(status: .gone, payload: errorPayload)
            case "missing":
                return self.jsonResponse(status: .notFound, payload: errorPayload)
            default:
                return self.jsonResponse(
                    status: .ok,
                    payload: RequestWaitResponse(rid: rid, status: .pending)
                )
            }
        }
    }
    
    // MARK: - POST /v1/requests/:rid/session
    
    private func uploadSession(request: Request, context: BasicRequestContext) async throws -> Response {
        guard let rid = context.parameters.get("rid") else {
            return self.textResponse(status: .badRequest, body: "Missing request ID")
        }
        
        // Check if request exists
        guard let stored = await storage.getRequest(rid: rid) else {
            return self.jsonResponse(status: .notFound, payload: ["error": "Request not found"])
        }
        
        // Check if expired
        if stored.expiresAt < Date() {
            _ = await storage.updateStatus(rid: rid, status: .expired)
            return self.jsonResponse(status: .gone, payload: ["error": "Request expired"])
        }
        
        // Check if already has session
        guard stored.status == .pending else {
            return self.jsonResponse(status: .conflict, payload: ["error": "Session already uploaded"])
        }
        
        let session: EncryptedSession
        do {
            session = try await self.decodeJSONBody(EncryptedSession.self, from: request, limit: config.maxPayloadSize)
        } catch {
            return self.jsonResponse(status: .badRequest, payload: ["error": "Invalid session payload"])
        }

        // Store session
        guard let _ = await storage.storeSession(rid: rid, session: session) else {
            return self.jsonResponse(status: .badRequest, payload: ["error": "Failed to store session"])
        }

        return self.jsonResponse(status: .created, payload: ["status": "uploaded", "rid": rid])
    }
    
    // MARK: - WebSocket /v1/requests/:rid/ws
    
    private func handleWebSocket(
        rid: RequestID?,
        inbound: WebSocketInboundStream,
        outbound: WebSocketOutboundWriter
    ) async throws {
        guard let rid else {
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
                    switch frame.opcode {
                    case .text:
                        // Handle client messages (ping, etc.)
                        var data = frame.data
                        if let text = data.readString(length: data.readableBytes), text == "ping" {
                            try await outbound.write(.text("pong"))
                        }
                    case .binary:
                        break
                    default:
                        await self.storage.cancelWait(rid: rid)
                        return
                    }
                }
            }
            
            // Task 2: Wait for session updates
            group.addTask {
                let message = await self.storage.waitForMessage(rid: rid)
                try Task.checkCancellation()
                try await outbound.write(.text(self.encodeJSON(message)))
                
                // If session delivered, mark and close
                if case .session(_) = message {
                    _ = await self.storage.markDelivered(rid: rid)
                }
                
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

    private func decodeJSONBody<T: Decodable>(_ type: T.Type, from request: Request, limit: Int) async throws -> T {
        let buffer = try await request.body.collect(upTo: limit)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(buffer.readableBytesView))
    }

    private func jsonResponse<T: Encodable>(status: HTTPResponse.Status, payload: T) -> Response {
        self.textResponse(status: status, body: self.encodeJSON(payload), contentType: "application/json")
    }

    private func textResponse(
        status: HTTPResponse.Status,
        body: String,
        contentType: String = "text/plain; charset=utf-8"
    ) -> Response {
        var headers = HTTPFields()
        headers[.contentType] = contentType

        return Response(
            status: status,
            headers: headers,
            body: .init(byteBuffer: ByteBuffer(string: body))
        )
    }
}
