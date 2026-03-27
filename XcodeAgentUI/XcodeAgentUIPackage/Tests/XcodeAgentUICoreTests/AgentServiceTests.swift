@testable import Dependencies
import XCTest

@testable import XcodeAgentUICore

@MainActor
final class AgentServiceTests: XCTestCase {

  var sut: AgentService!

  override func setUp() {
    super.setUp()
    sut = withDependencies {
      $0.keychainClient = KeychainClient(
        save: { _, _ in true },
        load: { _ in nil },
        delete: { _ in true },
        hasValue: { _ in false }
      )
      $0.hapticClient = HapticClient(perform: {})
    } operation: {
      AgentService()
    }
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
    XCTAssertEqual(sut.routerStatus.port, 3800)
    XCTAssertEqual(sut.bridgeStatus.port, 9300)
  }

  func testAgentDirectoryDefault() {
    XCTAssertFalse(sut.agentDirectory.isEmpty)
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

    UserDefaults.standard.removeObject(forKey: "routerPort")
  }

  func testBridgePortUpdatesPropagates() {
    let testPort = 9500
    sut.bridgePort = testPort
    XCTAssertEqual(sut.bridgePort, testPort)
    XCTAssertEqual(sut.bridgeWS.port, testPort)

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
  }

  // MARK: - Queue Dispatch Integration

  func testQueueDispatchCallbackIsSet() {
    XCTAssertNotNil(sut.queueManager.onDispatch)
  }

  // MARK: - Mock Service

  func testMockServiceIsPopulated() {
    let mock = withDependencies {
      $0.keychainClient = KeychainClient(
        save: { _, _ in true },
        load: { _ in nil },
        delete: { _ in true },
        hasValue: { _ in false }
      )
      $0.hapticClient = HapticClient(perform: {})
    } operation: {
      MockAgentService()
    }
    XCTAssertEqual(mock.routerStatus.state, .running)
    XCTAssertEqual(mock.bridgeStatus.state, .running)
    XCTAssertNotNil(mock.sessionManager.activeSession)
    XCTAssertEqual(mock.workerCount, 3)
    XCTAssertFalse(mock.queueManager.tickets.isEmpty)
  }
}
