import XCTest
@testable import XcodeAgentUICore

@MainActor
final class ProfileStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var store: ProfileStore!

    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let fileURL = tempDirectory.appendingPathComponent("test-profiles.json")
        store = ProfileStore(fileURL: fileURL)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - Load Tests

    func testLoadCreatesDefaultsWhenFileMissing() async throws {
        let profiles = try await store.load()

        XCTAssertEqual(profiles.count, 1)
        XCTAssertTrue(profiles.contains { $0.name == "Local" })
    }

    func testLoadReadsExistingFile() async throws {
        // First load creates defaults
        _ = try await store.load()

        // Add a custom profile
        let custom = try ConnectionProfile(
            name: "Custom",
            kind: .custom,
            backendHost: "example.com",
            backendPort: 9300
        )
        try await store.add(custom)

        // Verify profiles were saved
        let profiles = try await store.allProfiles()
        XCTAssertEqual(profiles.count, 2)
        XCTAssertTrue(profiles.contains { $0.name == "Custom" })
    }

    // MARK: - Add Tests

    func testAddProfile() async throws {
        _ = try await store.load()

        let profile = try ConnectionProfile(
            name: "New Profile",
            kind: .custom,
            backendHost: "192.168.1.1",
            backendPort: 9300
        )

        try await store.add(profile)
        let profiles = try await store.allProfiles()

        XCTAssertEqual(profiles.count, 2)
        XCTAssertTrue(profiles.contains { $0.id == profile.id })
    }

    func testAddSetsDefaultProfile() async throws {
        _ = try await store.load()

        let profile = try ConnectionProfile(
            name: "Default",
            kind: .custom,
            backendHost: "example.com",
            backendPort: 9300,
            isDefault: true
        )

        try await store.add(profile)
        let defaultProfile = try await store.defaultProfile()

        XCTAssertEqual(defaultProfile?.id, profile.id)
    }

    // MARK: - Update Tests

    func testUpdateProfile() async throws {
        _ = try await store.load()

        var profile = try ConnectionProfile(
            name: "Original",
            kind: .custom,
            backendHost: "example.com",
            backendPort: 9300
        )
        try await store.add(profile)

        // Update the profile
        profile.name = "Updated"
        try await store.update(profile)

        let updated = try await store.profile(id: profile.id)
        XCTAssertEqual(updated?.name, "Updated")
    }

    // MARK: - Remove Tests

    func testRemoveProfile() async throws {
        _ = try await store.load()

        let profile = try ConnectionProfile(
            name: "To Remove",
            kind: .custom,
            backendHost: "example.com",
            backendPort: 9300
        )
        try await store.add(profile)
        let count = try await store.allProfiles().count
        XCTAssertEqual(count, 2)

        try await store.remove(id: profile.id)
        let profiles = try await store.allProfiles()

        XCTAssertEqual(profiles.count, 1)
        XCTAssertFalse(profiles.contains { $0.id == profile.id })
    }

    // MARK: - Default Profile Tests

    func testSetDefault() async throws {
        _ = try await store.load()

        let profile = try ConnectionProfile(
            name: "New Default",
            kind: .custom,
            backendHost: "example.com",
            backendPort: 9300
        )
        try await store.add(profile)

        try await store.setDefault(id: profile.id)
        let defaultProfile = try await store.defaultProfile()

        XCTAssertEqual(defaultProfile?.id, profile.id)
    }

    // MARK: - Token Tests

    func testSaveAndLoadToken() throws {
        let profileId = UUID()
        let token = "test-token-123"

        try store.saveToken(for: profileId, token: token)
        let loaded = store.loadToken(for: profileId)

        XCTAssertEqual(loaded, token)
    }

    func testLoadNonexistentTokenReturnsNil() {
        let token = store.loadToken(for: UUID())
        XCTAssertNil(token)
    }

    func testDeleteToken() async throws {
        let profileId = UUID()

        try store.saveToken(for: profileId, token: "token")
        try await store.deleteToken(for: profileId)

        let loaded = store.loadToken(for: profileId)
        XCTAssertNil(loaded)
    }

    // MARK: - Resolve Token Tests

    func testResolveTokenForNoneAuth() {
        let profileId = UUID()
        let resolved = store.resolveToken("any", for: profileId)
        XCTAssertEqual(resolved, "any")
    }

    func testResolveTokenForBearerAuth() throws {
        let profileId = UUID()
        let token = "secret-token"

        try store.saveToken(for: profileId, token: token)
        let resolved = store.resolveToken("keychain-ref", for: profileId)

        XCTAssertEqual(resolved, token)
    }

    // MARK: - Metrics Tests

    func testUpdateConnectionMetrics() async throws {
        _ = try await store.load()
        let local = try await store.defaultProfile()

        try await store.updateConnectionMetrics(id: local!.id, latencyMs: 42)

        let updated = try await store.profile(id: local!.id)
        XCTAssertEqual(updated?.lastLatencyMs, 42)
        XCTAssertNotNil(updated?.lastConnected)
    }
}
