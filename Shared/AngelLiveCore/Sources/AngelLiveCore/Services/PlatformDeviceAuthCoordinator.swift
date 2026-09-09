import Foundation

/// Secrets stay inside the coordinator/vault and never enter observable UI state.
struct DeviceAPICredential: Codable, Sendable {
    let schemaVersion: Int
    let kind: String
    let clientId: String
    let accessToken: String
    let refreshToken: String
    let expireAt: Double
    var userId: String?
    var userName: String?

    var isWellFormed: Bool {
        schemaVersion == 1 && kind == "oauth_device_code" && expireAt.isFinite && expireAt > 0
            && [clientId, accessToken, refreshToken].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    var browsePayload: [String: String] {
        var result = ["credentialKind": kind, "clientId": clientId, "apiToken": accessToken]
        if let userId { result["userId"] = userId }
        return result
    }
}

struct DeviceLoginChallenge: Sendable {
    let loginId: String
    let userCode: String
    let verificationUri: URL
    let expiresAt: Double
    let retryAfter: Double
}

private struct DeviceLoginResponse: Decodable, Sendable {
    let state: String?
    let loginId: String?
    let userCode: String?
    let verificationUri: String?
    let expiresAt: Double?
    let interval: Double?
    let retryAfter: Double?
    let credential: DeviceAPICredential?
}

enum DeviceLoginProgress: Sendable {
    case waiting(Double), confirmed, denied, expired, failed
}

/// One coordinator per manager; each plugin's operation chain serializes work
/// across suspension points. Actor isolation alone does not serialize refreshes.
actor PlatformDeviceAuthCoordinator {
    private struct Attempt {
        let id: String
        let generation: UUID
        let lease: LiveParsePluginRuntimeLease
        var challenge: DeviceLoginChallenge?
        var nextPoll: Double = 0
        var committing = false
    }
    private var attempts: [String: Attempt] = [:]
    private var connectedAttempts: [String: String] = [:]
    private var cancelledAttempts: Set<String> = []
    private var tails: [String: Task<Void, Never>] = [:]
    private var validated: [String: (generation: UUID, token: String, at: Double)] = [:]
    private let now: @Sendable () -> Double

    init(now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }) { self.now = now }

    private func serial<T: Sendable>(_ pluginId: String, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tails[pluginId]
        let task = Task {
            await previous?.value
            return try await operation()
        }
        tails[pluginId] = Task { _ = try? await task.value }
        return try await task.value
    }

    func start(pluginId: String, loginId: String, manager: LiveParsePluginManager) async throws -> DeviceLoginChallenge {
        try await serial(pluginId) { try await self.startOperation(pluginId: pluginId, loginId: loginId, manager: manager) }
    }

    private func startOperation(pluginId: String, loginId: String, manager: LiveParsePluginManager) async throws -> DeviceLoginChallenge {
        guard !cancelledAttempts.contains(loginId) else { throw CancellationError() }
        guard UUID(uuidString: loginId) != nil, await manager.apiTokenVault.isEnabled else { throw APITokenError.invalid }
        _ = await cancel(pluginId: pluginId, manager: manager)
        let baseline = try await manager.apiTokenVault.snapshot(pluginId: pluginId)
        guard !cancelledAttempts.contains(loginId) else { throw CancellationError() }
        let lease = try manager.deviceLoginRuntimeLease(pluginId: pluginId)
        guard lease.credentialKinds.contains("oauth_device_code") else { throw APITokenError.invalid }
        attempts[pluginId] = Attempt(id: loginId, generation: baseline.generation, lease: lease)
        do {
            let response: DeviceLoginResponse = try await manager.callDeviceAuth(using: lease, function: "startDeviceLogin", payload: ["loginId": loginId])
            guard attempts[pluginId]?.id == loginId else { throw APITokenError.changed }
            guard response.state == "waiting", response.loginId == loginId,
                  let code = response.userCode, !code.isEmpty, code.utf8.count <= 256,
                  let uri = response.verificationUri, uri.utf8.count <= 2331,
                  let url = URL(string: uri), url.scheme?.lowercased() == "https", url.host != nil,
                  url.user == nil, url.password == nil,
                  let expiry = response.expiresAt, expiry.isFinite, expiry > now() else { throw APITokenError.invalid }
            let delay = try pollingDelay(response, fallback: 5)
            let challenge = DeviceLoginChallenge(loginId: loginId, userCode: code, verificationUri: url, expiresAt: expiry, retryAfter: delay)
            attempts[pluginId]?.challenge = challenge
            attempts[pluginId]?.nextPoll = now() + delay
            return challenge
        } catch {
            _ = await cancel(pluginId: pluginId, loginId: loginId, manager: manager)
            throw APITokenCallPolicy.safeError(error)
        }
    }

    func poll(pluginId: String, loginId: String, manager: LiveParsePluginManager) async throws -> DeviceLoginProgress {
        try await serial(pluginId) { try await self.pollOperation(pluginId: pluginId, loginId: loginId, manager: manager) }
    }

    private func pollOperation(pluginId: String, loginId: String, manager: LiveParsePluginManager) async throws -> DeviceLoginProgress {
        if connectedAttempts[pluginId] == loginId { return .confirmed }
        guard let attempt = attempts[pluginId], attempt.id == loginId, let challenge = attempt.challenge else { throw APITokenError.changed }
        if now() >= challenge.expiresAt { return .expired }
        if now() < attempt.nextPoll { return .waiting(attempt.nextPoll - now()) }
        let response: DeviceLoginResponse = try await manager.callDeviceAuth(using: attempt.lease, function: "pollDeviceLogin", payload: ["loginId": loginId])
        guard attempts[pluginId]?.id == loginId else { throw APITokenError.changed }
        guard response.loginId == nil || response.loginId == loginId else { throw APITokenError.invalid }
        switch response.state {
        case "waiting":
            let delay = try pollingDelay(response, fallback: challenge.retryAfter)
            attempts[pluginId]?.nextPoll = now() + delay
            return .waiting(delay)
        case "authorized":
            guard var credential = response.credential, credential.isWellFormed, credential.expireAt > now() else { throw APITokenError.invalid }
            let status = try await validate(credential, lease: attempt.lease, manager: manager)
            guard attempts[pluginId]?.id == loginId else { throw APITokenError.changed }
            credential.userId = status.userId
            credential.userName = status.userName
            attempts[pluginId]?.committing = true
            do {
                let retired = try await manager.apiTokenVault.replace(pluginId: pluginId,
                    record: .init(deviceCredential: credential, status: status), expectedGeneration: attempt.generation, manager: manager)
                connectedAttempts[pluginId] = loginId
                attempts[pluginId] = nil
                await manager.finishDeviceAuth(attempt.lease, loginId: loginId)
                await PlatformAPITokenService.shared.deviceCredentialCommitted(pluginId: pluginId, status: status, runtimes: retired, manager: manager)
                return .confirmed
            } catch {
                attempts[pluginId]?.committing = false
                throw error
            }
        case "denied": return .denied
        case "expired": return .expired
        case "failed": return .failed
        default: throw APITokenError.invalid
        }
    }

    /// Cancels only this attempt. A save already in progress reaches its commit
    /// point before cancellation reports whether the connection was committed.
    @discardableResult
    func cancel(pluginId: String, loginId: String? = nil, manager: LiveParsePluginManager) async -> Bool {
        if let loginId { cancelledAttempts.insert(loginId) }
        guard let attempt = attempts[pluginId], loginId == nil || attempt.id == loginId else {
            return loginId != nil && connectedAttempts[pluginId] == loginId
        }
        if attempt.committing {
            await tails[pluginId]?.value
            if connectedAttempts[pluginId] == attempt.id { return true }
        }
        guard attempts[pluginId]?.id == attempt.id else { return false }
        attempts[pluginId] = nil
        await manager.finishDeviceAuth(attempt.lease, loginId: attempt.id)
        return false
    }

    func forgetValidation(pluginId: String, disconnected: Bool = false) {
        validated[pluginId] = nil
        if disconnected { connectedAttempts[pluginId] = nil }
    }

    func ensure(pluginId: String, manager: LiveParsePluginManager, forceValidation: Bool = false, rejectedToken: String? = nil) async throws -> PlatformAPITokenVault.Snapshot {
        try await serial(pluginId) {
            try await self.ensureOperation(pluginId: pluginId, manager: manager, forceValidation: forceValidation, rejectedToken: rejectedToken)
        }
    }

    private func ensureOperation(pluginId: String, manager: LiveParsePluginManager, forceValidation: Bool, rejectedToken: String?) async throws -> PlatformAPITokenVault.Snapshot {
        // Retry only persistence after a failed rotation write; never refresh from
        // the older on-disk token. This must happen before validation or browsing.
        try await manager.apiTokenVault.flushRotation(pluginId: pluginId)
        let snapshot = try await manager.apiTokenVault.snapshot(pluginId: pluginId)
        guard let record = snapshot.record, var credential = record.deviceCredential else { return snapshot }
        guard credential.isWellFormed, let userId = credential.userId, !userId.isEmpty else { throw APITokenError.invalid }
        guard record.status.state != "invalid" else { throw reauthError() }
        let lease = try manager.runtimeLease(pluginId: pluginId)
        guard lease.credentialKinds.contains("oauth_device_code") else { throw APITokenError.invalid }
        try await manager.registerDeviceRuntime(lease, generation: snapshot.generation)
        var needsValidation = forceValidation
        if credential.expireAt <= now() + 60 || rejectedToken == credential.accessToken {
            let encoded = try JSONEncoder().encode(credential)
            let payload = try JSONSerialization.jsonObject(with: encoded)
            let response: DeviceLoginResponse
            do {
                response = try await manager.callDeviceAuth(using: lease, function: "refreshDeviceCredential", payload: ["credential": payload])
            } catch {
                if Self.isReauth(error) || Self.isMalformedResponse(error) {
                    try await markInvalid(pluginId: pluginId, snapshot: snapshot, manager: manager)
                }
                throw error
            }
            guard var rotated = response.credential, rotated.isWellFormed,
                  rotated.clientId == credential.clientId, rotated.expireAt > now(),
                  rotated.userId == nil || rotated.userId == userId else {
                // A successful exchange may have consumed the previous token.
                // An unusable replacement must not trigger another old-token exchange.
                try await markInvalid(pluginId: pluginId, snapshot: snapshot, manager: manager)
                throw APITokenError.invalid
            }
            rotated.userId = userId
            rotated.userName = credential.userName
            credential = rotated
            let pendingStatus = CredentialStatus(state: "unknown", expireAt: rotated.expireAt, clientId: rotated.clientId,
                credentialKind: rotated.kind, authorizationType: "api", tokenType: "user_access_token")
            try await manager.apiTokenVault.persistRotation(.init(deviceCredential: rotated, status: pendingStatus), pluginId: pluginId, generation: snapshot.generation)
            needsValidation = true
        }
        let stamp = validated[pluginId]
        if needsValidation || stamp?.generation != snapshot.generation || stamp?.token != credential.accessToken || now() - (stamp?.at ?? 0) >= 3_600 {
            do {
                let status = try await validate(credential, lease: lease, manager: manager)
                _ = try await manager.apiTokenVault.updateStatus(status, pluginId: pluginId, generation: snapshot.generation, manager: manager)
                validated[pluginId] = (snapshot.generation, credential.accessToken, now())
            } catch {
                if Self.isReauth(error) || (error as? APITokenError) == .invalid {
                    try await markInvalid(pluginId: pluginId, snapshot: snapshot, manager: manager)
                }
                throw error
            }
        }
        try await manager.apiTokenVault.check(pluginId: pluginId, generation: snapshot.generation)
        return try await manager.apiTokenVault.snapshot(pluginId: pluginId)
    }

    private func validate(_ credential: DeviceAPICredential, lease: LiveParsePluginRuntimeLease, manager: LiveParsePluginManager) async throws -> CredentialStatus {
        let status: CredentialStatus = try await manager.callDeviceAuth(using: lease, function: "validateCredential", payload: credential.browsePayload)
        guard status.state == "valid", status.credentialKind == credential.kind,
              status.authorizationType == "api", status.tokenType == "user_access_token",
              status.clientId == credential.clientId, let userId = status.userId, !userId.isEmpty,
              let expiry = status.expireAt, expiry.isFinite, expiry > now(),
              credential.userId == nil || credential.userId == userId else { throw APITokenError.invalid }
        let secrets = [credential.accessToken, credential.refreshToken]
        guard !secrets.contains(where: { userId.contains($0) || (status.userName ?? "").contains($0) }) else { throw APITokenError.invalid }
        return CredentialStatus(state: "valid", expireAt: expiry, userId: userId, userName: status.userName,
            clientId: credential.clientId, credentialKind: credential.kind, authorizationType: "api", tokenType: "user_access_token")
    }

    private func markInvalid(pluginId: String, snapshot: PlatformAPITokenVault.Snapshot, manager: LiveParsePluginManager) async throws {
        let status = CredentialStatus(state: "invalid", credentialKind: "oauth_device_code", authorizationType: "api")
        let retired = try await manager.apiTokenVault.updateStatus(status,
            pluginId: pluginId, generation: snapshot.generation, manager: manager)
        for runtime in retired { await runtime.retireCredentialGeneration(resetDeviceAuth: true) }
        await PlatformAPITokenService.shared.deviceCredentialCommitted(pluginId: pluginId, status: status, runtimes: [], manager: manager)
    }

    func reject(pluginId: String, generation: UUID, manager: LiveParsePluginManager) async throws {
        try await manager.apiTokenVault.check(pluginId: pluginId, generation: generation)
        let snapshot = try await manager.apiTokenVault.snapshot(pluginId: pluginId)
        guard snapshot.generation == generation else { throw APITokenError.changed }
        try await markInvalid(pluginId: pluginId, snapshot: snapshot, manager: manager)
    }

    private func pollingDelay(_ response: DeviceLoginResponse, fallback: Double) throws -> Double {
        let delay = response.retryAfter ?? response.interval ?? fallback
        guard delay.isFinite, delay >= 0, delay <= 86_400 else { throw APITokenError.invalid }
        return max(1, delay)
    }

    static func isReauth(_ error: Error) -> Bool {
        guard case let LiveParsePluginError.standardized(value) = error else { return false }
        return value.code == .authRequired && value.context["reason"] == "oauth_reauth_required"
    }

    private static func isMalformedResponse(_ error: Error) -> Bool {
        if (error as? APITokenError) == .invalid { return true }
        if case LiveParsePluginError.invalidReturnValue = error { return true }
        if case let LiveParsePluginError.standardized(value) = error { return value.code == .invalidResponse }
        return false
    }

    private func reauthError() -> Error {
        LiveParsePluginError.standardized(.init(code: .authRequired, message: "请重新登录。", context: ["reason": "oauth_reauth_required"]))
    }
}
