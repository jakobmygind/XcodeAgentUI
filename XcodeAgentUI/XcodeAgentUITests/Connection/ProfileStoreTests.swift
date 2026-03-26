import XCTest
@testable import XcodeAgentUI

actor ProfileStoreTests {
    private var tempDirectory: URL!
    private var store: ProfileStore!
    
    func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        let fileURL = tempDirectory.appendingPathComponent("test-profiles.json")
        store = ProfileStore(fileURL: fileURL)
    }
    
    func tearDown() async throws {
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
        
        // Create new store pointing to same file
        let newStore = ProfileStore(fileURL: store.fileURL)
        let profiles = try await newStore.load()
        
        XCTAssertEqual(profiles.count, 2)
        XCTAssertTrue(profiles.contains { $0.name == "Custom" })
    }
    
    func testLoadCachesResults() async throws {
        let profiles1 = try await store.load()
        let profiles2 = try await store.load()
        
        // Should be same array instance due to caching
        XCTAssertTrue(profiles1 === profiles2)
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
    
    func testAddDuplicateIDThrows() async throws {
        _ = try await store.load()
        
        let profile = try ConnectionProfile(
            name: "Original",
            kind: .custom,
            backendHost: "host1",
            backendPort: 9300
        )
        try await store.add(profile)
        
        let duplicate = try ConnectionProfile(
            id: profile.id,
            name: "Duplicate",
            kind: .custom,
            backendHost: "host2",
            backendPort: 9300
        )
        
        do {
            try await store.add(duplicate)
            XCTFail("Should have thrown error")
        } catch {
            // Expected
        }
    }
    
    func testAddFirstProfileBecomesDefault() async throws {
        // Create empty store
        let emptyFile = tempDirectory.appendingPathComponent("empty.json")
        FileManager.default.createFile(atPath: emptyFile.path, contents: "[]".data(using: .utf8))
        let emptyStore = ProfileStore(fileURL: emptyFile)
        _ = try await emptyStore.load()
        
        let profile = try ConnectionProfile(
            name: "First",
            kind: .custom,
            backendHost: "host",
            backendPort: 9300,
            isDefault: false
        )
        
        try await emptyStore.add(profile)
        let profiles = try await emptyStore.allProfiles()
        
        XCTAssertTrue(profiles.first?.isDefault ?? false)
    }
    
    // MARK: - Update Tests
    
    func testUpdateProfile() async throws {
        _ = try await store.load()
        
        var local = try await store.defaultProfile()
        XCTAssertNotNil(local)
        
        let originalName = local!.name
        var updated = local!
        updated.name = "Updated Local"
        
        try await store.update(updated)
        
        let profiles = try await store.allProfiles()
        let found = profiles.first { $0.id == local!.id }
        XCTAssertEqual(found?.name, "Updated Local")
    }
    
    func testUpdateNonexistentProfileThrows() async throws {
        _ = try await store.load()
        
        let fakeProfile = try ConnectionProfile(
            id: UUID(),
            name: "Fake",
            kind: .custom,
            backendHost: "host",
            backendPort: 9300
        )
        
        do {
            try await store.update(fakeProfile)
            XCTFail("Should have thrown error")
        } catch {
            // Expected
        }
    }
    
    // MARK: - Delete Tests
    
    func testDeleteProfile() async throws {
        _ = try await store.load()
        
        let local = try await store.defaultProfile()
        XCTAssertNotNil(local)
        
        try await store.delete(id: local!.id)
        
        let profiles = try await store.allProfiles()
        XCTAssertFalse(profiles.contains { $0.id == local!.id })
    }
    
    func testDeleteAlsoRemovesToken() async throws {
        _ = try await store.load()
        
        let profile = try ConnectionProfile(
            name: "With Token",
            kind: .custom,
            backendHost: "host",
            backendPort: 9300,
            authMethod: .bearerToken(keychainRef: "test-ref")
        )
        try await store.add(profile)
        
        // Save a token
        try store.saveToken(for: profile.id, token: "secret-token")
        
        // Verify token exists
        let tokenBefore = try store.loadToken(for: profile.id)
        XCTAssertEqual(tokenBefore, "secret-token")
        
        // Delete profile
        try await store.delete(id: profile.id)
        
        // Token should be deleted
        let tokenAfter = try store.loadToken(for: profile.id)
        XCTAssertNil(tokenAfter)
    }
    
    // MARK: - Default Profile Tests
    
    func testSetDefault() async throws {
        _ = try await store.load()
        
        // Add a tailscale profile first
        let tailscale = ConnectionProfile.tailscale(host: "test.tailnet.ts.net")
        try await store.add(tailscale)
        
        try await store.setDefault(id: tailscale.id)
        
        let profiles = try await store.allProfiles()
        let updatedTailscale = profiles.first { $0.id == tailscale.id }
        let updatedLocal = profiles.first { $0.name == "Local" }
        
        XCTAssertTrue(updatedTailscale?.isDefault ?? false)
        XCTAssertFalse(updatedLocal?.isDefault ?? true)
    }
    
    func testSetDefaultNonexistentThrows() async throws {
        _ = try await store.load()
        
        do {
            try await store.setDefault(id: UUID())
            XCTFail("Should have thrown error")
        } catch {
            // Expected
        }
    }
    
    // MARK: - Token Management Tests
    
    func testSaveAndLoadToken() throws {
        let profileId = UUID()
        let token = "bearer-token-12345"
        
        try store.saveToken(for: profileId, token: token)
        let loaded = try store.loadToken(for: profileId)
        
        XCTAssertEqual(loaded, token)
    }
    
    func testLoadNonexistentTokenReturnsNil() throws {
        let token = try store.loadToken(for: UUID())
        XCTAssertNil(token)
    }
    
    func testUpdateToken() throws {
        let profileId = UUID()
        
        try store.saveToken(for: profileId, token: "first")
        try store.saveToken(for: profileId, token: "second")
        
        let loaded = try store.loadToken(for: profileId)
        XCTAssertEqual(loaded, "second")
    }
    
    func testDeleteToken() throws {
        let profileId = UUID()
        
        try store.saveToken(for: profileId, token: "token")
        try store.deleteToken(for: profileId)
        
        let loaded = try store.loadToken(for: profileId)
        XCTAssertNil(loaded)
    }
    
    func testResolveTokenForNoneAuth() async throws {
        let profile = try ConnectionProfile(
            name: "No Auth",
            kind: .local,
            backendHost: "localhost",
            backendPort: 9300,
            authMethod: .none
        )
        
        let token = store.resolveToken("none", for: profile.id)
        XCTAssertNil(token)
    }
    
    func testResolveTokenForBearerAuth() async throws {
        let profileId = UUID()
        let profile = try ConnectionProfile(
            id: profileId,
            name: "With Auth",
            kind: .custom,
            backendHost: "host",
            backendPort: 9300,
            authMethod: .bearerToken("keychain-ref")
        )
        
        try store.saveToken(for: profileId, token: "my-secret-token")
        
        let token = store.resolveToken("keychain-ref", for: profileId)
        XCTAssertEqual(token, "my-secret-token")
    }
    
    // MARK: - Last Connected Tests
    
    func testUpdateLastConnected() async throws {
        _ = try await store.load()
        
        let local = try await store.defaultProfile()
        XCTAssertNotNil(local)
        XCTAssertNil(local?.lastConnected)
        
        let beforeUpdate = Date()
        try await store.updateLastConnected(id: local!.id, latencyMs: 42)
        
        let updated = try await store.profile(id: local!.id)
        XCTAssertNotNil(updated?.lastConnected)
        XCTAssertEqual(updated?.lastLatencyMs, 42)
        
        // Date should be recent
        if let lastConnected = updated?.lastConnected {
            XCTAssertGreaterThanOrEqual(lastConnected.timeIntervalSince(beforeUpdate), -1)
        }
    }
    
    // MARK: - Reset Tests
    
    func testResetToDefaults() async throws {
        _ = try await store.load()
        
        // Add custom profile
        let custom = try ConnectionProfile(
            name: "Custom",
            kind: .custom,
            backendHost: "host",
            backendPort: 9300
        )
        try await store.add(custom)
        
        // Reset
        try await store.resetToDefaults()
        
        let profiles = try await store.allProfiles()
        XCTAssertEqual(profiles.count, 1)
        XCTAssertTrue(profiles.contains { $0.name == "Local" })
        XCTAssertFalse(profiles.contains { $0.name == "Custom" })
    }
}

// MARK: - Run Tests

extension ProfileStoreTests {
    func runAllTests() async {
        do {
            try await setUp()
            
            // Load tests
            await runTest("testLoadCreatesDefaultsWhenFileMissing", testLoadCreatesDefaultsWhenFileMissing)
            await runTest("testLoadReadsExistingFile", testLoadReadsExistingFile)
            await runTest("testLoadCachesResults", testLoadCachesResults)
            
            // Add tests
            await runTest("testAddProfile", testAddProfile)
            await runTest("testAddDuplicateIDThrows", testAddDuplicateIDThrows)
            await runTest("testAddFirstProfileBecomesDefault", testAddFirstProfileBecomesDefault)
            
            // Update tests
            await runTest("testUpdateProfile", testUpdateProfile)
            await runTest("testUpdateNonexistentProfileThrows", testUpdateNonexistentProfileThrows)
            
            // Delete tests
            await runTest("testDeleteProfile", testDeleteProfile)
            await runTest("testDeleteAlsoRemovesToken", testDeleteAlsoRemovesToken)
            
            // Default tests
            await runTest("testSetDefault", testSetDefault)
            await runTest("testSetDefaultNonexistentThrows", testSetDefaultNonexistentThrows)
            
            // Token tests
            await runTest("testSaveAndLoadToken", testSaveAndLoadToken)
            await runTest("testLoadNonexistentTokenReturnsNil", testLoadNonexistentTokenReturnsNil)
            await runTest("testUpdateToken", testUpdateToken)
            await runTest("testDeleteToken", testDeleteToken)
            await runTest("testResolveTokenForNoneAuth", testResolveTokenForNoneAuth)
            await runTest("testResolveTokenForBearerAuth", testResolveTokenForBearerAuth)
            
            // Last connected tests
            await runTest("testUpdateLastConnected", testUpdateLastConnected)
            
            // Reset tests
            await runTest("testResetToDefaults", testResetToDefaults)
            
            try await tearDown()
            
            print("✅ All ProfileStore tests passed")
        } catch {
            print("❌ Test failed with error: \(error)")
        }
    }
    
    private func runTest(_ name: String, _ test: () async throws -> Void) async {
        do {
            try await test()
            print("  ✅ \(name)")
        } catch {
            print("  ❌ \(name): \(error)")
        }
    }
}
