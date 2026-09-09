import Foundation
import Observation

public extension Notification.Name {
    static let platformAPICredentialChanged = Notification.Name("AngelLive.platformAPICredentialChanged")
}

@MainActor @Observable
public final class PlatformAPITokenService {
    public static let shared = PlatformAPITokenService()
    public private(set) var statuses: [String: CredentialStatus] = [:]
    public private(set) var failures: [String: String] = [:]
    public private(set) var contentRevision = 0
    public private(set) var revisions: [String: Int] = [:]
    private let manager: LiveParsePluginManager
    private var attempts: [String: UUID] = [:]

    public convenience init() { self.init(manager: LiveParsePlugins.shared) }
    init(manager: LiveParsePluginManager) { self.manager = manager }

    public func statusText(pluginId: String) -> String {
        guard let status = statuses[pluginId] else { return "未配置" }
        if status.state == "valid", let expiry = status.expireAt, expiry > 0, expiry <= Date().timeIntervalSince1970 { return "已过期" }
        switch status.state {
        case "valid": return "API 已连接"
        case "invalid": return "已失效"
        case "expired": return "已过期"
        default: return "未配置"
        }
    }

    public func load(pluginId: String) async {
        let revision = revisions[pluginId, default: 0]
        do {
            let status = try await manager.apiTokenVault.record(pluginId: pluginId)?.status
            guard revisions[pluginId, default: 0] == revision else { return }
            statuses[pluginId] = status
        }
        catch { failures[pluginId] = "无法读取安全存储，请稍后重试。" }
    }

    public func validateAndSave(pluginId: String, token: String) async throws {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw APITokenError.invalid }
        try await validateAndSave(pluginId: pluginId, candidate: .init(token: token, status: .init(state: "unknown")))
    }

    public func validateAndSave(pluginId: String, clientId: String, clientSecret: String) async throws {
        let clientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientId.isEmpty, !clientSecret.isEmpty else { throw APITokenError.invalid }
        try await validateAndSave(pluginId: pluginId, candidate: .init(clientId: clientId, clientSecret: clientSecret, status: .init(state: "unknown")))
    }

    private func validateAndSave(pluginId: String, candidate: PlatformAPITokenVault.Record) async throws {
        _ = await manager.deviceAuth.cancel(pluginId: pluginId, manager: manager)
        let attempt = UUID()
        attempts[pluginId] = attempt
        let baseline = try await manager.apiTokenVault.snapshot(pluginId: pluginId)
        let lease = try manager.runtimeLease(pluginId: pluginId)
        guard lease.credentialKinds.contains(candidate.kind.rawValue) else { throw APITokenError.invalid }
        let status: CredentialStatus
        do {
            status = try await withThrowingTaskGroup(of: CredentialStatus.self) { group in
                group.addTask { [manager] in
                    try await manager.callDecodableUsingIsolatedCredential(
                        pluginId: pluginId, function: "validateCredential",
                        payload: candidate.payload, cookie: "", uid: nil, runtimeLease: lease
                    )
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(30))
                    throw LiveParsePluginError.standardized(.init(code: .timeout, message: "校验超时"))
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        } catch { throw APITokenCallPolicy.safeError(error) }
        try Task.checkCancellation()
        guard attempts[pluginId] == attempt else { throw APITokenError.changed }
        guard status.state == "valid", status.credentialKind == candidate.kind.rawValue, status.authorizationType == "api",
              status.expireAt == nil || status.expireAt == 0 || status.expireAt! > Date().timeIntervalSince1970 else { throw APITokenError.invalid }
        if let clientId = candidate.clientId, status.clientId != clientId { throw APITokenError.invalid }
        let safeStatus = sanitized(status, credential: candidate)
        let retired = try await manager.apiTokenVault.replace(
            pluginId: pluginId, record: candidate.replacingStatus(safeStatus),
            expectedGeneration: baseline.generation, manager: manager
        )
        // Keychain persistence is the commit point. Cancellation afterwards must
        // not report a failed save or restore an older credential.
        statuses[pluginId] = safeStatus
        failures[pluginId] = nil
        await invalidate(pluginId: pluginId, runtimes: retired)
    }

    public func clear(pluginId: String) async throws {
        attempts[pluginId] = UUID()
        let retired = try await manager.apiTokenVault.replace(pluginId: pluginId, record: nil, manager: manager)
        await manager.deviceAuth.forgetValidation(pluginId: pluginId, disconnected: true)
        _ = await manager.deviceAuth.cancel(pluginId: pluginId, manager: manager)
        statuses[pluginId] = nil
        failures[pluginId] = nil
        await invalidate(pluginId: pluginId, runtimes: retired)
    }

    public func refresh(pluginId: String) async {
        do {
            let snapshot = try await manager.apiTokenVault.snapshot(pluginId: pluginId)
            guard let credential = snapshot.record else { statuses[pluginId] = nil; return }
            if credential.deviceCredential != nil {
                let current = try await manager.deviceAuth.ensure(pluginId: pluginId, manager: manager, forceValidation: true)
                statuses[pluginId] = current.record?.status
                failures[pluginId] = nil
                return
            }
            let status: CredentialStatus = try await withThrowingTaskGroup(of: CredentialStatus.self) { group in
                group.addTask { [manager] in
                    try await manager.callDecodable(pluginId: pluginId, function: "getCredentialStatus", sensitive: true)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(30))
                    throw LiveParsePluginError.standardized(.init(code: .timeout, message: "校验超时"))
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
            try await manager.apiTokenVault.check(pluginId: pluginId, generation: snapshot.generation)
            guard ["valid", "invalid", "expired", "missing"].contains(status.state) else { throw APITokenError.invalid }
            if status.state == "valid" {
                guard status.credentialKind == credential.kind.rawValue, status.authorizationType == "api" else { throw APITokenError.invalid }
                if let clientId = credential.clientId, status.clientId != clientId { throw APITokenError.invalid }
            }
            let safeStatus = sanitized(status, credential: credential)
            let retired = try await manager.apiTokenVault.updateStatus(safeStatus, pluginId: pluginId, generation: snapshot.generation, manager: manager)
            statuses[pluginId] = safeStatus
            failures[pluginId] = nil
            if !retired.isEmpty { await invalidate(pluginId: pluginId, runtimes: retired) }
        } catch is CancellationError {
        } catch {
            failures[pluginId] = "校验失败，请稍后重试；已保存的凭据仍保留。"
        }
    }

    private func sanitized(_ status: CredentialStatus, credential: PlatformAPITokenVault.Record) -> CredentialStatus {
        let secrets = credential.secrets.flatMap { [$0, $0.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? $0] }.filter { !$0.isEmpty }
        func safe(_ value: String?) -> String? {
            guard let value, !secrets.contains(where: { value.contains($0) }) else { return nil }
            return String(value.prefix(256))
        }
        return CredentialStatus(state: status.state, expireAt: status.expireAt,
                                clientId: safe(status.clientId), credentialKind: credential.kind.rawValue,
                                authorizationType: "api", tokenType: safe(status.tokenType))
    }

    private func invalidate(pluginId: String, runtimes: [JSRuntime]) async {
        await manager.deviceAuth.forgetValidation(pluginId: pluginId)
        for runtime in runtimes { await runtime.retireCredentialGeneration(resetDeviceAuth: true) }
        await PluginHomeFeedCacheStore.shared.remove(pluginId: pluginId)
        contentRevision &+= 1
        revisions[pluginId, default: 0] &+= 1
        NotificationCenter.default.post(name: .platformAPICredentialChanged, object: pluginId)
    }

    func deviceCredentialCommitted(pluginId: String, status: CredentialStatus, runtimes: [JSRuntime], manager: LiveParsePluginManager) async {
        guard self.manager === manager else {
            for runtime in runtimes { await runtime.retireCredentialGeneration() }
            return
        }
        await load(pluginId: pluginId)
        failures[pluginId] = nil
        await invalidate(pluginId: pluginId, runtimes: runtimes)
    }

    func recordUnavailable(pluginId: String, generation: UUID, state: String) async {
        do {
            let previous = try await manager.apiTokenVault.record(pluginId: pluginId)
            let status = CredentialStatus(state: state, expireAt: previous?.status.expireAt, clientId: previous?.status.clientId,
                                          credentialKind: previous?.kind.rawValue ?? "token", authorizationType: "api", tokenType: previous?.status.tokenType)
            let retired = try await manager.apiTokenVault.updateStatus(status, pluginId: pluginId, generation: generation, manager: manager)
            await load(pluginId: pluginId)
            if !retired.isEmpty { await invalidate(pluginId: pluginId, runtimes: retired) }
        } catch { /* A replacement won the generation, or storage is temporarily unavailable. */ }
    }
}
