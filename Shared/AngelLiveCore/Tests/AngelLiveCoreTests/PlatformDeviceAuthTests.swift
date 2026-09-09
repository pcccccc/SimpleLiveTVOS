import Foundation
import Synchronization
import Testing
@testable import AngelLiveCore

@Suite("Device API authorization")
struct PlatformDeviceAuthTests {
    @Test func explicitDeviceKindOffersThreeHostEntries() async throws {
        let fixture = try DeviceAuthFixture()
        defer { fixture.remove() }
        let entry = try #require(await PlatformLoginRegistry(pluginManager: fixture.manager).entry(pluginId: fixture.id))
        for platform in LoginChallengeHostPlatform.allCases {
            #expect(entry.methods(for: platform) == [.deviceCode])
            #expect(entry.preferredMethod(for: platform, isLoggedIn: false) == .deviceCode)
        }
    }

    @Test func candidateUsesSameRuntimeAndCommitsOnlyAfterValidation() async throws {
        let fixture = try DeviceAuthFixture()
        defer { fixture.remove() }
        await fixture.enable()
        let id = UUID().uuidString
        let challenge = try await fixture.start(id)
        #expect(challenge.userCode == "EXAMPLE-CODE")
        #expect(try await fixture.vault.record(pluginId: fixture.id) == nil)
        if case .waiting(let delay) = try await fixture.poll(id) { #expect(delay == 5) }
        else { Issue.record("Early polling must wait") }
        fixture.clock.advance(5)
        if case .confirmed = try await fixture.poll(id) {} else { Issue.record("Expected committed login") }
        let record = try #require(try await fixture.vault.record(pluginId: fixture.id))
        #expect(record.deviceCredential?.clientId == "fixture-client")
        #expect(record.deviceCredential?.userId == "fixture-user")
        #expect(record.status.state == "valid")
        #expect(await fixture.manager.deviceAuth.cancel(pluginId: fixture.id, loginId: id, manager: fixture.manager))
    }

    @Test func cancellingOldAttemptCannotCancelNewOne() async throws {
        let fixture = try DeviceAuthFixture()
        defer { fixture.remove() }
        await fixture.enable()
        let old = UUID().uuidString
        let current = UUID().uuidString
        _ = try await fixture.start(old)
        _ = try await fixture.start(current)
        #expect(!(await fixture.manager.deviceAuth.cancel(pluginId: fixture.id, loginId: old, manager: fixture.manager)))
        fixture.clock.advance(5)
        if case .confirmed = try await fixture.poll(current) {} else { Issue.record("New attempt must survive old cancellation") }
    }

    @Test func cancelledBeforeStartNeverCreatesChallenge() async throws {
        let fixture = try DeviceAuthFixture()
        defer { fixture.remove() }
        await fixture.enable()
        let id = UUID().uuidString
        await fixture.manager.deviceAuth.cancel(pluginId: fixture.id, loginId: id, manager: fixture.manager)
        await #expect(throws: (any Error).self) { try await fixture.start(id) }
    }

    @Test func validationFailurePreservesPreviousAccount() async throws {
        let fixture = try DeviceAuthFixture(validation: "invalid")
        defer { fixture.remove() }
        await fixture.enable()
        try await fixture.store(expiry: 9000)
        let id = UUID().uuidString
        _ = try await fixture.start(id)
        fixture.clock.advance(5)
        await #expect(throws: (any Error).self) { try await fixture.poll(id) }
        #expect(try await fixture.vault.record(pluginId: fixture.id)?.deviceCredential?.accessToken == "previous-access")
        await fixture.manager.deviceAuth.cancel(pluginId: fixture.id, loginId: id, manager: fixture.manager)
    }

    @Test func concurrentRefreshRotatesOnceAndPreservesRuntime() async throws {
        let fixture = try DeviceAuthFixture()
        defer { fixture.remove() }
        await fixture.enable()
        try await fixture.store(expiry: 2010)
        let runtime = try fixture.manager.resolve(pluginId: fixture.id).runtime
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { _ = try await fixture.manager.deviceAuth.ensure(pluginId: fixture.id, manager: fixture.manager) }
            }
            try await group.waitForAll()
        }
        #expect(try await fixture.vault.record(pluginId: fixture.id)?.deviceCredential?.accessToken == "rotated-1")
        #expect(try fixture.manager.resolve(pluginId: fixture.id).runtime === runtime)
        let probe: DeviceProbe = try await fixture.manager.callDecodable(pluginId: fixture.id, function: "getRooms", payload: ["apiToken": "override", "refreshToken": "override", "page": 2])
        #expect(probe.apiToken == "rotated-1")
        #expect(probe.clientId == "fixture-client")
        #expect(probe.userId == "fixture-user")
        #expect(probe.refreshToken == nil)
        #expect(probe.page == 2)
    }

    @Test func rotationPersistsBeforeValidationNetworkFailure() async throws {
        let fixture = try DeviceAuthFixture(validation: "network")
        defer { fixture.remove() }
        await fixture.enable()
        try await fixture.store(expiry: 2010)
        for _ in 0..<2 {
            await #expect(throws: (any Error).self) { try await fixture.manager.deviceAuth.ensure(pluginId: fixture.id, manager: fixture.manager) }
        }
        #expect(try await fixture.vault.record(pluginId: fixture.id)?.deviceCredential?.refreshToken == "rotated-refresh-1")
    }

    @Test func failedRotationWriteRetainsNewPairAndRetriesOnlySave() async throws {
        let fixture = try DeviceAuthFixture(failRotationWrites: true)
        defer { fixture.remove() }
        await fixture.enable()
        try await fixture.store(expiry: 2010)
        for _ in 0..<2 {
            await #expect(throws: APITokenError.storage) { try await fixture.manager.deviceAuth.ensure(pluginId: fixture.id, manager: fixture.manager) }
        }
        #expect(try await fixture.vault.record(pluginId: fixture.id)?.deviceCredential?.accessToken == "rotated-1")
        let snapshot = try await fixture.vault.snapshot(pluginId: fixture.id)
        _ = try await fixture.vault.replace(pluginId: fixture.id, record: nil, manager: fixture.manager)
        await #expect(throws: APITokenError.changed) {
            try await fixture.vault.persistRotation(try #require(snapshot.record), pluginId: fixture.id, generation: snapshot.generation)
        }
        #expect(try await fixture.vault.record(pluginId: fixture.id) == nil)
    }

    @Test func unauthorizedRetriesOnceWithoutLosingBusinessParameters() async throws {
        let fixture = try DeviceAuthFixture(rejectBrowse: true)
        defer { fixture.remove() }
        await fixture.enable()
        try await fixture.store(expiry: 9000)
        let result: DeviceProbe = try await fixture.manager.callDecodable(pluginId: fixture.id, function: "getRooms", payload: ["page": 3])
        #expect(result.apiToken == "rotated-1")
        #expect(result.page == 3)
        #expect(result.browseCount == 2)
    }

    @Test func secondUnauthorizedRequiresLoginWithoutAnotherRefresh() async throws {
        let fixture = try DeviceAuthFixture(rejectBrowse: true, rejectAlways: true)
        defer { fixture.remove() }
        await fixture.enable()
        try await fixture.store(expiry: 9000)
        await #expect(throws: (any Error).self) {
            let _: DeviceProbe = try await fixture.manager.callDecodable(pluginId: fixture.id, function: "getRooms")
        }
        #expect(try await fixture.vault.record(pluginId: fixture.id)?.deviceCredential?.accessToken == "rotated-1")
        #expect(try await fixture.vault.record(pluginId: fixture.id)?.status.state == "invalid")
        await #expect(throws: (any Error).self) { try await fixture.manager.deviceAuth.ensure(pluginId: fixture.id, manager: fixture.manager) }
    }

    @Test func malformedResponseCannotCrashOrConnect() async throws {
        let fixture = try DeviceAuthFixture(malformed: true)
        defer { fixture.remove() }
        await fixture.enable()
        await #expect(throws: (any Error).self) { try await fixture.start(UUID().uuidString) }
        #expect(try await fixture.vault.record(pluginId: fixture.id) == nil)
    }

    @Test func malformedRotationRequiresLoginInsteadOfReusingOldRefreshToken() async throws {
        let fixture = try DeviceAuthFixture(malformedRotation: true)
        defer { fixture.remove() }
        await fixture.enable()
        try await fixture.store(expiry: 2010)
        await #expect(throws: (any Error).self) { try await fixture.manager.deviceAuth.ensure(pluginId: fixture.id, manager: fixture.manager) }
        #expect(try await fixture.vault.record(pluginId: fixture.id)?.status.state == "invalid")
        do {
            _ = try await fixture.manager.deviceAuth.ensure(pluginId: fixture.id, manager: fixture.manager)
            Issue.record("Expected reauthorization")
        } catch { #expect(PlatformDeviceAuthCoordinator.isReauth(error)) }
    }

    @Test func expiredChallengeStopsBeforeCallingPlugin() async throws {
        let fixture = try DeviceAuthFixture()
        defer { fixture.remove() }
        await fixture.enable()
        let id = UUID().uuidString
        _ = try await fixture.start(id)
        fixture.clock.advance(100)
        if case .expired = try await fixture.poll(id) {} else { Issue.record("Expired challenge must stop") }
        #expect(try await fixture.vault.record(pluginId: fixture.id) == nil)
        await fixture.manager.deviceAuth.cancel(pluginId: fixture.id, loginId: id, manager: fixture.manager)
    }

    @Test func clearedGenerationRejectsLateCandidate() async throws {
        let fixture = try DeviceAuthFixture()
        defer { fixture.remove() }
        await fixture.enable()
        try await fixture.store(expiry: 9000)
        let id = UUID().uuidString
        _ = try await fixture.start(id)
        _ = try await fixture.vault.replace(pluginId: fixture.id, record: nil, manager: fixture.manager)
        fixture.clock.advance(5)
        await #expect(throws: (any Error).self) { try await fixture.poll(id) }
        #expect(try await fixture.vault.record(pluginId: fixture.id) == nil)
        await fixture.manager.deviceAuth.cancel(pluginId: fixture.id, loginId: id, manager: fixture.manager)
    }

    @Test(arguments: ["getPlayback", "getDanmaku", "createDanmakuSession"])
    func mediaReceivesNoDeviceCredentials(function: String) async throws {
        let fixture = try DeviceAuthFixture()
        defer { fixture.remove() }
        await fixture.enable()
        try await fixture.store(expiry: 2010)
        let probe: DeviceProbe = try await fixture.manager.callDecodable(pluginId: fixture.id, function: function,
            payload: ["credentialKind": "oauth_device_code", "userId": "override", "apiToken": "override", "clientId": "override", "refreshToken": "override"])
        #expect(probe.apiToken == nil && probe.clientId == nil && probe.userId == nil && probe.refreshToken == nil)
        #expect(try await fixture.vault.record(pluginId: fixture.id)?.deviceCredential?.accessToken == "previous-access")
    }

    @Test func deviceRecordsDoNotEnableShellAuthentication() async throws {
        let fixture = try DeviceAuthFixture()
        defer { fixture.remove() }
        try await fixture.store(expiry: 2010)
        let probe: DeviceProbe = try await fixture.manager.callDecodable(pluginId: fixture.id, function: "getRooms")
        #expect(probe.apiToken == nil)
        await #expect(throws: (any Error).self) { try await fixture.start(UUID().uuidString) }
    }
}

private struct DeviceProbe: Decodable, Sendable {
    let apiToken: String?
    let clientId: String?
    let userId: String?
    let refreshToken: String?
    let page: Int?
    let browseCount: Int?
}

private final class DeviceTestClock: Sendable {
    // All test-clock mutation and reads are confined to this mutex; no await occurs while held.
    private let instant = Mutex<Double>(2000)
    func now() -> Double { instant.withLock { $0 } }
    func advance(_ seconds: Double) { instant.withLock { $0 += seconds } }
}

private final class DeviceMemoryStorage: APITokenStorage {
    private var values: [String: Data] = [:]
    let failRotationWrites: Bool
    init(failRotationWrites: Bool) { self.failRotationWrites = failRotationWrites }
    func read(pluginId: String) -> Data? { values[pluginId] }
    func write(_ data: Data, pluginId: String) throws {
        if failRotationWrites, String(decoding: data, as: UTF8.self).contains("rotated-") { throw APITokenError.storage }
        values[pluginId] = data
    }
    func delete(pluginId: String) { values[pluginId] = nil }
}

private struct DeviceAuthFixture: Sendable {
    let root: URL
    let id = "fixture-\(UUID().uuidString.lowercased()).plugin"
    let clock = DeviceTestClock()
    let vault: PlatformAPITokenVault
    let manager: LiveParsePluginManager

    init(validation: String = "valid", failRotationWrites: Bool = false, rejectBrowse: Bool = false, rejectAlways: Bool = false, malformed: Bool = false, malformedRotation: Bool = false) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = try LiveParsePluginStorage(baseDirectory: root)
        try storage.ensureDirectories()
        let clock = self.clock
        vault = PlatformAPITokenVault(storage: DeviceMemoryStorage(failRotationWrites: failRotationWrites), now: { clock.now() })
        manager = LiveParsePluginManager(storage: storage, apiTokenVault: vault)
        let directory = storage.pluginVersionDirectory(pluginId: id, version: "1.0.0")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = LiveParsePluginManifest(pluginId: id, version: "1.0.0", apiVersion: 1, displayName: "Fixture", liveTypes: ["source-a"], entry: "index.js", auth: .init(credentialKinds: ["oauth_device_code"]))
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))
        let script = """
        let active = null, refreshes = 0, browses = 0;
        function credential(token, refresh) { return {schemaVersion:1,kind:'oauth_device_code',clientId:'fixture-client',accessToken:token,refreshToken:refresh,expireAt:9000}; }
        globalThis.LiveParsePlugin = {
          apiVersion:1,
          startDeviceLogin(input) {
            if (\(malformed)) return null;
            if (input.clientId) throw new Error('Host must allow plugin default');
            active = input.loginId;
            return {state:'waiting',loginId:active,userCode:'EXAMPLE-CODE',verificationUri:'https://login.example.invalid/activate',expiresAt:2100,interval:5,retryAfter:5};
          },
          pollDeviceLogin(input) {
            if (active !== input.loginId) throw new Error('Runtime or attempt changed');
            return {state:'authorized',credential:credential('candidate-access','candidate-refresh')};
          },
          cancelDeviceLogin(input) { if(active === input.loginId) active = null; return {}; },
          resetDeviceAuth() { active = null; return {}; },
          refreshDeviceCredential(input) { refreshes++; return \(malformedRotation) ? {} : {credential:credential('rotated-'+refreshes,'rotated-refresh-'+refreshes)}; },
          validateCredential(input) {
            if ('\(validation)' === 'network') throw new Error('LP_PLUGIN_ERROR:'+JSON.stringify({code:'NETWORK',message:'private upstream response'}));
            return {state:'\(validation)',clientId:input.clientId,userId:'fixture-user',userName:'Fixture User',expireAt:9000,credentialKind:'oauth_device_code',authorizationType:'api',tokenType:'user_access_token'};
          }
        };
        function browse(input) {
          browses++;
          if (\(rejectBrowse) && (\(rejectAlways) || input.apiToken === 'previous-access')) throw new Error('LP_PLUGIN_ERROR:'+JSON.stringify({code:'AUTH_REQUIRED',message:'rejected'}));
          return Object.assign({},input,{browseCount:browses});
        }
        \(Array(APITokenCallPolicy.functions.subtracting(["validateCredential"]).union(["getPlayback", "getDanmaku", "createDanmakuSession"])).map { "LiveParsePlugin.\($0)=browse;" }.joined(separator: "\n"))
        """
        try Data(script.utf8).write(to: directory.appendingPathComponent("index.js"))
    }
    func enable() async { await vault.activate(UUID()) }
    func start(_ loginId: String) async throws -> DeviceLoginChallenge {
        try await manager.deviceAuth.start(pluginId: id, loginId: loginId, manager: manager)
    }
    func poll(_ loginId: String) async throws -> DeviceLoginProgress {
        try await manager.deviceAuth.poll(pluginId: id, loginId: loginId, manager: manager)
    }
    func store(expiry: Double) async throws {
        let credential = DeviceAPICredential(schemaVersion: 1, kind: "oauth_device_code", clientId: "fixture-client",
            accessToken: "previous-access", refreshToken: "previous-refresh", expireAt: expiry, userId: "fixture-user")
        _ = try await vault.replace(pluginId: id, record: .init(deviceCredential: credential,
            status: .init(state: "valid", credentialKind: credential.kind, authorizationType: "api")), manager: manager)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
