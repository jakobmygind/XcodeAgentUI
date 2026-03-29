import XCTest
@testable import XcodeAgentUICore

@MainActor
final class ConnectionProfileTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testValidProfileCreation() throws {
        let profile = try ConnectionProfile(
            name: "Test Profile",
            kind: .custom,
            backendHost: "192.168.1.100",
            backendPort: 9300
        )
        
        XCTAssertEqual(profile.name, "Test Profile")
        XCTAssertEqual(profile.kind, .custom)
        XCTAssertEqual(profile.backendHost, "192.168.1.100")
        XCTAssertEqual(profile.backendPort, 9300)
        XCTAssertFalse(profile.useTLS)
        XCTAssertEqual(profile.authMethod, .none)
        XCTAssertFalse(profile.isDefault)
    }
    
    func testProfileWithTLS() throws {
        let profile = try ConnectionProfile(
            name: "Secure Profile",
            kind: .tailscale,
            backendHost: "mac-mini.tailnet.ts.net",
            backendPort: 443,
            useTLS: true,
            authMethod: .bearerToken("test-token-ref")
        )
        
        XCTAssertTrue(profile.useTLS)
        XCTAssertEqual(profile.backendPort, 443)
    }
    
    func testEmptyNameThrows() {
        XCTAssertThrowsError(try ConnectionProfile(
            name: "",
            kind: .local,
            backendHost: "localhost",
            backendPort: 9300
        )) { error in
            guard case ConnectionProfile.ValidationError.emptyName = error else {
                XCTFail("Expected emptyName error")
                return
            }
        }
    }
    
    func testWhitespaceNameThrows() {
        XCTAssertThrowsError(try ConnectionProfile(
            name: "   ",
            kind: .local,
            backendHost: "localhost",
            backendPort: 9300
        )) { error in
            guard case ConnectionProfile.ValidationError.emptyName = error else {
                XCTFail("Expected emptyName error")
                return
            }
        }
    }
    
    func testInvalidPortThrows() {
        XCTAssertThrowsError(try ConnectionProfile(
            name: "Bad Port",
            kind: .local,
            backendHost: "localhost",
            backendPort: 0
        )) { error in
            guard case ConnectionProfile.ValidationError.invalidPort(0) = error else {
                XCTFail("Expected invalidPort error")
                return
            }
        }
        
        XCTAssertThrowsError(try ConnectionProfile(
            name: "Bad Port",
            kind: .local,
            backendHost: "localhost",
            backendPort: 70000
        )) { error in
            guard case ConnectionProfile.ValidationError.invalidPort(70000) = error else {
                XCTFail("Expected invalidPort error")
                return
            }
        }
    }
    
    func testInvalidHostThrows() {
        XCTAssertThrowsError(try ConnectionProfile(
            name: "Bad Host",
            kind: .custom,
            backendHost: "host with spaces",
            backendPort: 9300
        )) { error in
            guard case ConnectionProfile.ValidationError.invalidHost = error else {
                XCTFail("Expected invalidHost error")
                return
            }
        }
    }
    
    func testEmptyHostAllowed() throws {
        // Empty host is allowed for unconfigured profiles (like default Tailscale)
        let profile = try ConnectionProfile(
            name: "Unconfigured",
            kind: .tailscale,
            backendHost: "",
            backendPort: 9300
        )
        
        XCTAssertEqual(profile.backendHost, "")
        XCTAssertFalse(profile.isConfigured)
    }
    
    // MARK: - URL Generation Tests
    
    func testBaseURLGeneration() throws {
        let httpProfile = try ConnectionProfile(
            name: "HTTP",
            kind: .local,
            backendHost: "localhost",
            backendPort: 3800,
            useTLS: false
        )
        
        XCTAssertEqual(httpProfile.baseURL?.absoluteString, "http://localhost:3800")
        
        let httpsProfile = try ConnectionProfile(
            name: "HTTPS",
            kind: .custom,
            backendHost: "example.com",
            backendPort: 443,
            useTLS: true
        )
        
        XCTAssertEqual(httpsProfile.baseURL?.absoluteString, "https://example.com:443")
    }
    
    func testWebSocketURLGeneration() throws {
        let profile = try ConnectionProfile(
            name: "WS",
            kind: .local,
            backendHost: "localhost",
            backendPort: 9300,
            useTLS: false
        )
        
        XCTAssertEqual(profile.wsURL?.absoluteString, "ws://localhost:9300")
        
        let wssProfile = try ConnectionProfile(
            name: "WSS",
            kind: .custom,
            backendHost: "secure.example.com",
            backendPort: 443,
            useTLS: true
        )
        
        XCTAssertEqual(wssProfile.wsURL?.absoluteString, "wss://secure.example.com:443")
    }
    
    func testHealthURLGeneration() throws {
        let profile = try ConnectionProfile(
            name: "Health",
            kind: .local,
            backendHost: "localhost",
            backendPort: 3800
        )
        
        XCTAssertEqual(profile.healthURL?.absoluteString, "http://localhost:3800/health")
    }
    
    func testNilURLForInvalidHost() throws {
        let profile = try ConnectionProfile(
            name: "Invalid",
            kind: .custom,
            backendHost: "",
            backendPort: 9300
        )
        
        XCTAssertNil(profile.baseURL)
        XCTAssertNil(profile.wsURL)
        XCTAssertNil(profile.healthURL)
    }
    
    // MARK: - Configuration Status Tests
    
    func testIsConfigured() throws {
        let configured = try ConnectionProfile(
            name: "Configured",
            kind: .local,
            backendHost: "localhost",
            backendPort: 9300
        )
        XCTAssertTrue(configured.isConfigured)
        
        let unconfigured = try ConnectionProfile(
            name: "Unconfigured",
            kind: .tailscale,
            backendHost: "",
            backendPort: 9300
        )
        XCTAssertFalse(unconfigured.isConfigured)
    }
    
    // MARK: - Default Profiles Tests
    
    func testLocalDefaultProfile() {
        let local = ConnectionProfile.local
        
        XCTAssertEqual(local.name, "Local")
        XCTAssertEqual(local.kind, .local)
        XCTAssertEqual(local.backendHost, "localhost")
        XCTAssertEqual(local.backendPort, 9300)
        XCTAssertTrue(local.isDefault)
        XCTAssertTrue(local.isConfigured)
        XCTAssertEqual(local.authMethod, .none)
    }
    
    func testTailscaleDefaultProfile() {
        let tailscale = ConnectionProfile.tailscale(host: "mac.tailnet.ts.net")
        
        XCTAssertEqual(tailscale.name, "Tailscale (mac.tailnet.ts.net)")
        XCTAssertEqual(tailscale.kind, .tailscale)
        XCTAssertEqual(tailscale.backendHost, "mac.tailnet.ts.net")
        XCTAssertFalse(tailscale.isDefault)
        XCTAssertTrue(tailscale.isConfigured)
        
        if case .bearerToken(let ref) = tailscale.authMethod {
            XCTAssertEqual(ref, "keychain-ref")
        } else {
            XCTFail("Expected bearerToken auth method")
        }
    }
    
    // MARK: - Validation Tests

    func testValidationThrowsEmptyHost() throws {
        // Empty host is allowed in init but fails validation
        let invalidProfile = try ConnectionProfile(
            name: "Invalid",
            kind: .custom,
            backendHost: "",
            backendPort: 9300
        )

        XCTAssertThrowsError(try invalidProfile.validate()) { error in
            guard case ConnectionProfile.ValidationError.emptyHost = error else {
                XCTFail("Expected emptyHost error, got \(error)")
                return
            }
        }
    }
    
    // MARK: - Equality Tests
    
    func testProfileEquality() throws {
        let id = UUID()
        let profile1 = try ConnectionProfile(
            id: id,
            name: "Test",
            kind: .local,
            backendHost: "localhost",
            backendPort: 9300
        )
        
        let profile2 = try ConnectionProfile(
            id: id,
            name: "Different Name",
            kind: .custom,
            backendHost: "other.host",
            backendPort: 8080
        )
        
        // Profiles with same ID should be equal
        XCTAssertEqual(profile1, profile2)
    }
    
    // MARK: - Coding Tests
    
    func testProfileEncodingDecoding() throws {
        let original = try ConnectionProfile(
            name: "Test",
            kind: .tailscale,
            backendHost: "mac.tailnet.ts.net",
            backendPort: 9300,
            useTLS: true,
            authMethod: .bearerToken("my-token"),
            isDefault: true
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ConnectionProfile.self, from: data)
        
        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.name, decoded.name)
        XCTAssertEqual(original.kind, decoded.kind)
        XCTAssertEqual(original.backendHost, decoded.backendHost)
        XCTAssertEqual(original.backendPort, decoded.backendPort)
        XCTAssertEqual(original.useTLS, decoded.useTLS)
        XCTAssertEqual(original.isDefault, decoded.isDefault)
        XCTAssertEqual(original.authMethod, decoded.authMethod)
    }
}

// MARK: - ProfileKind Tests

extension ConnectionProfileTests {
    func testProfileKindDisplayNames() {
        XCTAssertEqual(ProfileKind.local.displayName, "Local")
        XCTAssertEqual(ProfileKind.tailscale.displayName, "Tailscale")
        XCTAssertEqual(ProfileKind.custom.displayName, "Custom")
    }
    
    func testProfileKindPriority() {
        XCTAssertEqual(ProfileKind.local.priority, 0)
        XCTAssertEqual(ProfileKind.tailscale.priority, 1)
        XCTAssertEqual(ProfileKind.custom.priority, 2)
    }
    
    func testProfileKindIcons() {
        XCTAssertEqual(ProfileKind.local.icon, "desktopcomputer")
        XCTAssertEqual(ProfileKind.tailscale.icon, "network")
        XCTAssertEqual(ProfileKind.custom.icon, "externaldrive.connected.to.line.below")
    }
}

// MARK: - AuthMethod Tests

extension ConnectionProfileTests {
    func testAuthMethodEquality() {
        let auth1 = AuthMethod.bearerToken("ref1")
        let auth2 = AuthMethod.bearerToken("ref1")
        let auth3 = AuthMethod.bearerToken("ref2")
        let auth4 = AuthMethod.none
        
        XCTAssertEqual(auth1, auth2)
        XCTAssertNotEqual(auth1, auth3)
        XCTAssertNotEqual(auth1, auth4)
        XCTAssertEqual(auth4, AuthMethod.none)
    }
    
    func testAuthMethodEncoding() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        // Test bearer token encoding
        let bearer = AuthMethod.bearerToken("test-ref")
        let bearerData = try encoder.encode(bearer)
        let decodedBearer = try decoder.decode(AuthMethod.self, from: bearerData)
        XCTAssertEqual(bearer, decodedBearer)
        
        // Test none encoding
        let none = AuthMethod.none
        let noneData = try encoder.encode(none)
        let decodedNone = try decoder.decode(AuthMethod.self, from: noneData)
        XCTAssertEqual(none, decodedNone)
    }
}
