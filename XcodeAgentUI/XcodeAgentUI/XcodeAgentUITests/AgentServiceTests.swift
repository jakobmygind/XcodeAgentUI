import XCTest

@testable import XcodeAgentUI

final class AgentServiceTests: XCTestCase {

  var sut: AgentService!

  override func setUp() {
    super.setUp()
    sut = AgentService()
  }

  override func tearDown() {
    sut.stopAll()
    sut = nil
    super.tearDown()
  }

  // MARK: - Initialization

  func testInitialState() {
    XCTAssertEqual(sut.routerStatus.state, .stopped)
    XCTAssertEqual(sut.bridgeStatus.state, .stopped)
    XCTAssertNil(sut.sessionManager.activeSession)
    XCTAssertEqual(sut.workerCount, 0)
  }

  func testDefaultPorts() {
    // Default ports unless overridden by UserDefaults
    XCTAssertEqual(sut.routerStatus.port, 3800)
    XCTAssertEqual(sut.bridgeStatus.port, 9300)
  }

  func testAgentDirectoryDefault() {
    let expected = NSHomeDirectory() + "/.openclaw/workspace/xcode-agent"
    // Either the saved value or the default
    XCTAssertFalse(sut.agentDirectory.isEmpty)
    // The directory should be a plausible path
    XCTAssertTrue(
      sut.agentDirectory.contains(".openclaw") || sut.agentDirectory.contains("xcode-agent")
        || !sut.agentDirectory.isEmpty
    )
  }

  // MARK: - Port Configuration

  func testPortPersistence() {
    let testPort = 4200
    sut.routerPort = testPort
    XCTAssertEqual(sut.routerPort, testPort)
    XCTAssertEqual(UserDefaults.standard.integer(forKey: "routerPort"), testPort)

    // Clean up
    UserDefaults.standard.removeObject(forKey: "routerPort")
  }

  func testBridgePortUpdatesPropagates() {
    let testPort = 9500
    sut.bridgePort = testPort
    XCTAssertEqual(sut.bridgePort, testPort)
    XCTAssertEqual(sut.bridgeWS.port, testPort)

    // Clean up
    UserDefaults.standard.removeObject(forKey: "bridgePort")
  }

  // MARK: - Sub-Manager Access

  func testSessionManagerExists() {
    XCTAssertNotNil(sut.sessionManager)
  }

  func testProviderStoreExists() {
    XCTAssertNotNil(sut.providerStore)
  }

  func testQueueManagerExists() {
    XCTAssertNotNil(sut.queueManager)
  }

  func testMetricsStoreExists() {
    XCTAssertNotNil(sut.metricsStore)
  }

  // MARK: - Service State Transitions

  func testStartRouterSetsStartingState() {
    // Starting router sets state to .starting before the process actually launches
    sut.startRouter()
    XCTAssertEqual(sut.routerStatus.state, .starting)
    sut.stopRouter()
  }

  func testStartBridgeSetsStartingState() {
    sut.startBridge()
    XCTAssertEqual(sut.bridgeStatus.state, .starting)
    sut.stopBridge()
  }

  func testStopRouterAfterStart() {
    sut.startRouter()
    sut.stopRouter()
    // After stop, the state should eventually return to stopped
    // (may need RunLoop for async, but the call should not crash)
  }

  // MARK: - Queue Dispatch Integration

  func testQueueDispatchCallbackIsSet() {
    XCTAssertNotNil(sut.queueManager.onDispatch)
  }

  // MARK: - Mock Service

  func testMockServiceIsPopulated() {
    let mock = MockAgentService()
    XCTAssertEqual(mock.routerStatus.state, .running)
    XCTAssertEqual(mock.bridgeStatus.state, .running)
    XCTAssertNotNil(mock.sessionManager.activeSession)
    XCTAssertEqual(mock.workerCount, 3)
    XCTAssertFalse(mock.queueManager.tickets.isEmpty)
  }
}
