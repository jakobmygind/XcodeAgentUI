import XCTest
@testable import XcodeAgentUI

@MainActor
final class ConnectionProfileTests: XCTestCase {
    
    // MARK: - Validation Tests
    
    func testValidProfile() throws {
        let profile = ConnectionProfile(
            name: "Test",
            kind: .local,
            backendHost: "localhost",
            backendPort: 9300
        )
        
        XCTAssertNoThrow(try profile.validate())
    }
    
    func testEmptyHostValidation() {
        let profile = ConnectionProfile(
            name: "Test",
            kind: .local,
            backendHost: "",
            backendPort: 9300
        )
        
        XCTAssertThrowsError(try profile.validate()) { error in
            guard case ConnectionProfile.ValidationError.emptyHost = error else {
                XCTFail("Expected emptyHost error")
                return
            }
        }
    }
    
    func testInvalidPortValidation() {
        let profile = ConnectionProfile(
            name: "Test",
            kind: .local,
            backendHost: "localhost",
            backendPort: 70000
        )
        
        XCTAssertThrowsError(try profile.validate()) { error in
            guard case ConnectionProfile.ValidationError.invalidPort = error else {
                XCTFail("Expected invalidPort error")
                return
            }
        }
    }
    
    func testInvalidHostCharacters() {
        let profile = ConnectionProfile(
            name: "Test",
            kind: .local,
            backendHost: "local host!",
            backendPort: 9300
        )
        
        XCTAssertThrowsError(try profile.validate()) { error in
            guard case ConnectionProfile.ValidationError.invalidHost = error else {
                XCTFail("Expected invalidHost error")
                return
            }
        }
    }
    
    // MARK: - URL Generation Tests
    
    func testBaseURLGeneration() {
        let profile = ConnectionProfile(
            name: "Test",
            kind: .local,
            backendHost: "localhost",
            backendPort: 9300,
            useTLS: false
        )
        
        XCTAssertEqual(profile.baseURL?.absoluteString, "http://localhost:9300")
    }
    
    func testBaseURLWithTLS() {
        let profile = ConnectionProfile(
            name: "Test",
            kind: .custom,
            backendHost: "example.com",
            backendPort: 443,
            useTLS: true
        )
        
        XCTAssertEqual(profile.baseURL?.absoluteString, "https://example.com:443")
    }
    
    func testHealthURL() {
        let profile = ConnectionProfile(
            name: "Test",
            kind: .local,
            backendHost: "localhost",
            backendPort: 9300
        )
        
        XCTAssertEqual(profile.healthURL?.absoluteString, "http://localhost:9300/api/health")
    }
    
    func testWebSocketURL() {
        let profile = ConnectionProfile(
            name: "Test",
            kind: .local,
            backendHost: "localhost",
            backendPort: 9300
        )
        
        let url = profile.wsURL(role: .human, name: "test-client", token: "secret123")
        XCTAssertEqual(url?.absoluteString, "ws://localhost:9300?role=human&name=test-client&token=secret123")
    }
    
    func testWebSocketURLWithoutToken() {
        let profile = ConnectionProfile(
            name: "Test",
            kind: .local,
            backendHost: "localhost",
            backendPort: 9300
        )
        
        let url = profile.wsURL(role: .observer)
        XCTAssertEqual(url?.absoluteString, "ws://localhost:9300?role=observer&name=macos-ui")
    }
    
    // MARK: - Profile Kind Tests
    
    func testProfileKindPriority() {
        XCTAssertEqual(ProfileKind.local.priority, 0)
        XCTAssertEqual(ProfileKind.tailscale.priority, 1)
        XCTAssertEqual(ProfileKind.custom.priority, 2)
    }
    
    func testProfileKindTimeout() {
        XCTAssertEqual(ProfileKind.local.probeTimeout, 1.0)
        XCTAssertEqual(ProfileKind.tailscale.probeTimeout, 5.0)
        XCTAssertEqual(ProfileKind.custom.probeTimeout, 5.0)
    }
    
    // MARK: - Auth Method Tests
    
    func testAuthMethodNone() {
        var request = URLRequest(url: URL(string: "http://localhost")!)
        AuthMethod.none.apply(to: &request)
        
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }
    
    func testAuthMethodBearerToken() {
        var request = URLRequest(url: URL(string: "http://localhost")!)
        AuthMethod.bearerToken("my-token").apply(to: &request)
        
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer my-token")
    }
    
    func testAuthMethodWithResolver() {
        var request = URLRequest(url: URL(string: "http://localhost")!)
        AuthMethod.bearerToken("keychain-ref").apply(to: &request) { ref in
            ref == "keychain-ref" ? "resolved-token" : nil
        }
        
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer resolved-token")
    }
    
    // MARK: - Built-in Profiles
    
    func testDefaultLocalProfile() {
        let profile = ConnectionProfile.local
        
        XCTAssertEqual(profile.name, "Local")
        XCTAssertEqual(profile.kind, .local)
        XCTAssertEqual(profile.backendHost, "localhost")
        XCTAssertEqual(profile.backendPort, 9300)
        XCTAssertTrue(profile.isDefault)
        XCTAssertEqual(profile.authMethod, .none)
    }
    
    func testTailscaleProfileTemplate() {
        let profile = ConnectionProfile.tailscale(host: "mac-mini.tailnet.ts.net", port: 9400)
        
        XCTAssertEqual(profile.name, "Tailscale (mac-mini.tailnet.ts.net)")
        XCTAssertEqual(profile.kind, .tailscale)
        XCTAssertEqual(profile.backendHost, "mac-mini.tailnet.ts.net")
        XCTAssertEqual(profile.backendPort, 9400)
        XCTAssertFalse(profile.isDefault)
        
        if case .bearerToken = profile.authMethod {
            // Expected
        } else {
            XCTFail("Expected bearerToken auth method")
        }
    }
    
    // MARK: - Codable Tests
    
    func testProfileEncodingDecoding() throws {
        let original = ConnectionProfile(
            name: "Test Profile",
            kind: .tailscale,
            backendHost: "100.64.0.1",
            backendPort: 9300,
            useTLS: true,
            authMethod: .bearerToken("keychain-ref"),
            isDefault: true,
            lastConnected: Date(timeIntervalSince1970: 1000),
            lastLatencyMs: 42
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ConnectionProfile.self, from: data)
        
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.kind, original.kind)
        XCTAssertEqual(decoded.backendHost, original.backendHost)
        XCTAssertEqual(decoded.backendPort, original.backendPort)
        XCTAssertEqual(decoded.useTLS, original.useTLS)
        XCTAssertEqual(decoded.isDefault, original.isDefault)
        XCTAssertEqual(decoded.lastLatencyMs, original.lastLatencyMs)
    }
}
