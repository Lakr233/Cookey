import Foundation
import Hummingbird
import HummingbirdWebSocket
import NIOCore

/// Route handlers for Cookey Relay Server
public struct Routes: Sendable {
    let storage: RequestStorage
    let config: ServerConfig
    let apnsClient: APNSClient?

    public init(storage: RequestStorage, config: ServerConfig, apnsClient: APNSClient? = nil) {
        self.storage = storage
        self.config = config
        self.apnsClient = apnsClient
    }

    // MARK: - Router Setup

    public func setupRouter() -> Router<BasicRequestContext> {
        let router = Router(context: BasicRequestContext.self)

        // Health check
        router.get("/health") { _, _ in
            textResponse(status: .ok, body: "OK")
        }

        // API v1 routes
        router.post("/v1/requests") { [self] request, context -> Response in
            try await createRequest(request: request, context: context)
        }

        router.get("/v1/requests/:rid") { [self] request, context -> Response in
            try await getRequest(request: request, context: context)
        }

        router.get("/v1/requests/:rid/wait") { [self] request, context -> Response in
            try await waitForRequest(request: request, context: context)
        }

        router.post("/v1/requests/:rid/session") { [self] request, context -> Response in
            try await uploadSession(request: request, context: context)
        }

        router.post("/v1/devices/:device_id/apn-token") { [self] request, context -> Response in
            try await registerAPNToken(request: request, context: context)
        }

        router.delete("/v1/devices/:device_id/apn-token") { [self] _, context -> Response in
            await unregisterAPNToken(context: context)
        }

        return router
    }

    public func setupWebSocketRouter() -> Router<BasicWebSocketRequestContext> {
        let router = Router(context: BasicWebSocketRequestContext.self)

        router.ws("/v1/requests/:rid/ws") { _, _ in
            .upgrade()
        } onUpgrade: { [self] inbound, outbound, context in
            try await handleWebSocket(
                rid: context.requestContext.parameters.get("rid"),
                inbound: inbound,
                outbound: outbound
            )
        }

        return router
    }

    // MARK: - POST /v1/requests

    private func createRequest(request: Request, context _: BasicRequestContext) async throws -> Response {
        let loginRequest: LoginRequest
        do {
            loginRequest = try await decodeJSONBody(LoginRequest.self, from: request, limit: 1024 * 10)
        } catch {
            return jsonResponse(
                status: .badRequest,
                payload: ["error": "Invalid request payload"]
            )
        }

        // Validate expiration
        guard loginRequest.expiresAt > Date() else {
            return jsonResponse(
                status: .badRequest,
                payload: ["error": "Invalid expiration time"]
            )
        }

        // Store request
        let stored = await storage.store(request: loginRequest)
        if let apnsClient,
           let registration = await storage.apnRegistration(deviceID: loginRequest.deviceID)
        {
            Task {
                await apnsClient.sendLoginRequestNotification(
                    request: stored,
                    serverURL: config.publicURL,
                    registration: registration,
                    storage: storage
                )
            }
        }

        // Return response
        let response = RequestStatusResponse(from: stored)
        return jsonResponse(status: .created, payload: response)
    }

    // MARK: - GET /v1/requests/:rid

    private func getRequest(request _: Request, context: BasicRequestContext) async throws -> Response {
        guard let rid = context.parameters.get("rid") else {
            return textResponse(status: .badRequest, body: "Missing request ID")
        }

        guard let stored = await storage.getRequest(rid: rid) else {
            return jsonResponse(status: .notFound, payload: ["error": "Request not found"])
        }

        // Check if expired
        if stored.expiresAt < Date() {
            _ = await storage.updateStatus(rid: rid, status: .expired)
            return jsonResponse(status: .gone, payload: ["error": "Request expired"])
        }

        let response = RequestStatusResponse(from: stored)
        return jsonResponse(status: .ok, payload: response)
    }

    // MARK: - GET /v1/requests/:rid/wait (Long Polling)

    private func waitForRequest(request: Request, context: BasicRequestContext) async throws -> Response {
        guard let rid = context.parameters.get("rid") else {
            return textResponse(status: .badRequest, body: "Missing request ID")
        }

        let timeout = min(
            request.uri.queryParameters.get("timeout").flatMap { Int($0) } ?? 30,
            60
        )

        guard let stored = await storage.getRequest(rid: rid) else {
            return jsonResponse(status: .notFound, payload: ["error": "Request not found"])
        }

        // Return immediately for terminal states
        if stored.status == .ready, stored.encryptedSession != nil {
            _ = await storage.markDelivered(rid: rid)
            return jsonResponse(
                status: .ok,
                payload: RequestWaitResponse(
                    rid: stored.rid,
                    status: stored.status,
                    encryptedSession: stored.encryptedSession,
                    deliveredAt: Date()
                )
            )
        }
        if stored.status == .expired || stored.expiresAt < Date() {
            _ = await storage.updateStatus(rid: rid, status: .expired)
            return jsonResponse(status: .gone, payload: ["error": "Request expired"])
        }
        if stored.status != .pending {
            return jsonResponse(
                status: .ok,
                payload: RequestWaitResponse(rid: rid, status: stored.status)
            )
        }

        // Long-poll: block until a message arrives or timeout
        guard let message = await storage.waitForMessage(rid: rid, timeoutSeconds: timeout) else {
            return jsonResponse(
                status: .ok,
                payload: RequestWaitResponse(rid: rid, status: .pending)
            )
        }

        return await respondToMessage(message, rid: rid)
    }

    private func respondToMessage(_ message: WebSocketMessage, rid: RequestID) async -> Response {
        switch message {
        case let .session(payload):
            _ = await storage.markDelivered(rid: rid)
            return jsonResponse(
                status: .ok,
                payload: RequestWaitResponse(
                    rid: rid,
                    status: .ready,
                    encryptedSession: payload.encryptedSession,
                    deliveredAt: payload.deliveredAt
                )
            )

        case let .status(payload) where payload.status == .expired:
            return jsonResponse(status: .gone, payload: ["error": "Request expired"])

        case let .status(payload):
            return jsonResponse(
                status: .ok,
                payload: RequestWaitResponse(rid: rid, status: payload.status)
            )

        case let .error(error) where error.code == "expired":
            return jsonResponse(status: .gone, payload: ["error": error.message])

        case let .error(error) where error.code == "missing":
            return jsonResponse(status: .notFound, payload: ["error": error.message])

        case .error:
            return jsonResponse(
                status: .ok,
                payload: RequestWaitResponse(rid: rid, status: .pending)
            )
        }
    }

    // MARK: - POST /v1/requests/:rid/session

    private func uploadSession(request: Request, context: BasicRequestContext) async throws -> Response {
        guard let rid = context.parameters.get("rid") else {
            return textResponse(status: .badRequest, body: "Missing request ID")
        }

        // Check if request exists
        guard let stored = await storage.getRequest(rid: rid) else {
            return jsonResponse(status: .notFound, payload: ["error": "Request not found"])
        }

        // Check if expired
        if stored.expiresAt < Date() {
            _ = await storage.updateStatus(rid: rid, status: .expired)
            return jsonResponse(status: .gone, payload: ["error": "Request expired"])
        }

        // Check if already has session
        guard stored.status == .pending else {
            return jsonResponse(status: .conflict, payload: ["error": "Session already uploaded"])
        }

        let session: EncryptedSession
        do {
            session = try await decodeJSONBody(EncryptedSession.self, from: request, limit: config.maxPayloadSize)
        } catch {
            return jsonResponse(status: .badRequest, payload: ["error": "Invalid session payload"])
        }

        // Store session
        guard let _ = await storage.storeSession(rid: rid, session: session) else {
            return jsonResponse(status: .badRequest, payload: ["error": "Failed to store session"])
        }

        return jsonResponse(status: .created, payload: ["status": "uploaded", "rid": rid])
    }

    private func registerAPNToken(request: Request, context: BasicRequestContext) async throws -> Response {
        guard let deviceID = context.parameters.get("device_id") else {
            return textResponse(status: .badRequest, body: "Missing device ID")
        }

        let registrationRequest: APNTokenRegistrationRequest
        do {
            registrationRequest = try await decodeJSONBody(
                APNTokenRegistrationRequest.self,
                from: request,
                limit: 1024 * 4
            )
        } catch {
            return jsonResponse(status: .badRequest, payload: ["error": "Invalid APN registration payload"])
        }

        await storage.storeAPNRegistration(
            deviceID: deviceID,
            token: registrationRequest.token,
            environment: registrationRequest.environment
        )
        return jsonResponse(status: .created, payload: ["status": "registered", "device_id": deviceID])
    }

    private func unregisterAPNToken(context: BasicRequestContext) async -> Response {
        guard let deviceID = context.parameters.get("device_id") else {
            return textResponse(status: .badRequest, body: "Missing device ID")
        }

        await storage.removeAPNRegistration(deviceID: deviceID)
        return textResponse(status: .noContent, body: "")
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
        try await outbound.write(.text(encodeJSON(statusMessage)))

        // If already ready, send session and close
        if stored.status == .ready, let session = stored.encryptedSession {
            let sessionMessage = WebSocketMessage.session(SessionPayload(
                encryptedSession: session,
                deliveredAt: Date()
            ))
            try await outbound.write(.text(encodeJSON(sessionMessage)))
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
            try await outbound.write(.text(encodeJSON(errorMessage)))
            return
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await frame in inbound {
                    switch frame.opcode {
                    case .text:
                        var data = frame.data
                        if let text = data.readString(length: data.readableBytes), text == "ping" {
                            try await outbound.write(.text("pong"))
                        }
                    case .binary:
                        break
                    default:
                        await storage.cancelWait(rid: rid)
                        return
                    }
                }
            }

            group.addTask {
                let message = await storage.waitForMessage(rid: rid)
                try Task.checkCancellation()
                try await outbound.write(.text(encodeJSON(message)))
                if case .session = message {
                    _ = await storage.markDelivered(rid: rid)
                }
            }

            try await group.next()
            group.cancelAll()
        }
    }

    // MARK: - Helpers

    private func encodeJSON(_ value: some Encodable) -> String {
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

    private func decodeJSONBody<T: Decodable>(_: T.Type, from request: Request, limit: Int) async throws -> T {
        let buffer = try await request.body.collect(upTo: limit)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(buffer.readableBytesView))
    }

    private func jsonResponse(status: HTTPResponse.Status, payload: some Encodable) -> Response {
        textResponse(status: status, body: encodeJSON(payload), contentType: "application/json")
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
