import XCTest
@testable import XcodeAgentUI

@MainActor
final class ConnectionErrorTests: XCTestCase {
    
    func testErrorDescriptions() {
        XCTAssertEqual(
            ConnectionError.healthCheckFailed.localizedDescription,
            "Backend is not responding. Check that the agent service is running."
        )
        
        XCTAssertEqual(
            ConnectionError.healthCheckTimeout.localizedDescription,
            "Connection timed out. The backend may be on a different network."
        )
        
        XCTAssertEqual(
            ConnectionError.authenticationFailed.localizedDescription,
            "Authentication failed. Check your API token in profile settings."
        )
        
        XCTAssertEqual(
            ConnectionError.allProfilesFailed.localizedDescription,
            "Could not connect to any configured backend."
        )
        
        XCTAssertEqual(
            ConnectionError.tailscaleNotRunning.localizedDescription,
            "Tailscale is not running. Start Tailscale to connect to remote backends."
        )
    }
    
    func testBackendVersionMismatchError() {
        let error = ConnectionError.backendVersionMismatch(backend: "1.0.0", minRequired: "2.0.0")
        XCTAssertEqual(
            error.localizedDescription,
            "Backend version 1.0.0 is too old. Minimum required: 2.0.0."
        )
    }
    
    func testRecoverySuggestions() {
        XCTAssertEqual(
            ConnectionError.healthCheckFailed.recoverySuggestion,
            "Ensure the backend is running and the port is correct."
        )
        
        XCTAssertEqual(
            ConnectionError.authenticationFailed.recoverySuggestion,
            "Verify your bearer token in profile settings."
        )
        
        XCTAssertEqual(
            ConnectionError.tailscaleNotRunning.recoverySuggestion,
            "Start the Tailscale app and ensure you're logged in."
        )
    }
}

@MainActor
final class ConnectionStateTests: XCTestCase {
    
    func testDisconnectedState() {
        let state = ConnectionState.disconnected
        XCTAssertFalse(state.isConnected)
        XCTAssertFalse(state.isConnecting)
        XCTAssertNil(state.activeProfile)
        XCTAssertEqual(state.displayName, "Disconnected")
    }
    
    func testConnectingState() {
        let state = ConnectionState.connecting(.tailscale)
        XCTAssertFalse(state.isConnected)
        XCTAssertTrue(state.isConnecting)
        XCTAssertNil(state.activeProfile)
        XCTAssertEqual(state.displayName, "Connecting to Tailscale...")
    }
    
    func testConnectedState() {
        let profile = ConnectionProfile(
            name: "Test",
            kind: .local,
            backendHost: "localhost",
            backendPort: 9300
        )
        let state = ConnectionState.connected(profile)
        
        XCTAssertTrue(state.isConnected)
        XCTAssertFalse(state.isConnecting)
        XCTAssertEqual(state.activeProfile?.id, profile.id)
        XCTAssertEqual(state.displayName, "Test")
    }
    
    func testReconnectingState() {
        let profile = ConnectionProfile(
            name: "Test",
            kind: .local,
            backendHost: "localhost",
            backendPort: 9300
        )
        let state = ConnectionState.reconnecting(lastProfile: profile, attempt: 3)
        
        XCTAssertFalse(state.isConnected)
        XCTAssertTrue(state.isConnecting)
        XCTAssertEqual(state.activeProfile?.id, profile.id)
        XCTAssertEqual(state.displayName, "Reconnecting to Test (attempt 3)")
    }
    
    func testFailedState() {
        let state = ConnectionState.failed(.healthCheckFailed)
        
        XCTAssertFalse(state.isConnected)
        XCTAssertFalse(state.isConnecting)
        XCTAssertNil(state.activeProfile)
        XCTAssertEqual(state.displayName, "Backend is not responding. Check that the agent service is running.")
    }
    
    func testStateEquality() {
        let profile1 = ConnectionProfile(
            name: "Test1",
            kind: .local,
            backendHost: "localhost",
            backendPort: 9300
        )
        
        // Test state comparisons by checking properties
        XCTAssertTrue(ConnectionState.disconnected.isConnected == ConnectionState.disconnected.isConnected)
        XCTAssertTrue(ConnectionState.connecting(.local).isConnecting == ConnectionState.connecting(.local).isConnecting)
        XCTAssertEqual(ConnectionState.connected(profile1).activeProfile?.id, ConnectionState.connected(profile1).activeProfile?.id)
    }
}

@MainActor
final class ProbeResultTests: XCTestCase {
    
    func testSuccessResult() {
        let profile = ConnectionProfile(
            name: "Test",
            kind: .local,
            backendHost: "localhost",
            backendPort: 9300
        )
        
        let health = HealthResponse(
            status: "ok",
            version: "1.0.0",
            protocolVersion: 1,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        
        let result = ProbeResult.success(profile: profile, latencyMs: 15, healthResponse: health)
        
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.latencyMs, 15)
        XCTAssertEqual(result.profile.id, profile.id)
        XCTAssertEqual(result.healthResponse?.version, "1.0.0")
        XCTAssertNil(result.error)
    }
    
    func testFailureResult() {
        let profile = ConnectionProfile(
            name: "Test",
            kind: .local,
            backendHost: "localhost",
            backendPort: 9300
        )
        
        let result = ProbeResult.failure(profile: profile, error: .healthCheckTimeout)
        
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.latencyMs, -1)
        if let error = result.error {
            XCTAssertEqual(error.localizedDescription, ConnectionError.healthCheckTimeout.localizedDescription)
        } else {
            XCTFail("Expected error")
        }
        XCTAssertNil(result.healthResponse)
    }
}

@MainActor
final class HealthResponseTests: XCTestCase {
    
    func testIsOK() {
        let response = HealthResponse(
            status: "ok",
            version: "1.0.0",
            protocolVersion: 1,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        
        XCTAssertTrue(response.isOK)
    }
    
    func testIsNotOK() {
        let response = HealthResponse(
            status: "error",
            version: "1.0.0",
            protocolVersion: 1,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        
        XCTAssertFalse(response.isOK)
    }
    
    func testDateParsing() {
        let formatter = ISO8601DateFormatter()
        let now = Date()
        let timestamp = formatter.string(from: now)
        
        let response = HealthResponse(
            status: "ok",
            version: "1.0.0",
            protocolVersion: 1,
            timestamp: timestamp
        )
        
        XCTAssertNotNil(response.date)
        // Allow small time difference due to formatting/parsing
        XCTAssertEqual(response.date?.timeIntervalSince1970 ?? 0, now.timeIntervalSince1970, accuracy: 1.0)
    }
    
    func testCoding() throws {
        let original = HealthResponse(
            status: "ok",
            version: "2.1.0",
            protocolVersion: 2,
            timestamp: "2026-03-26T12:00:00Z"
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(HealthResponse.self, from: data)
        
        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.version, original.version)
        XCTAssertEqual(decoded.protocolVersion, original.protocolVersion)
        XCTAssertEqual(decoded.timestamp, original.timestamp)
    }
}
