@testable import Dependencies
import XCTest

@testable import XcodeAgentUICore

@MainActor
final class ProviderStoreTests: XCTestCase {

  var sut: ProviderStore!

  override func setUp() {
    super.setUp()
    UserDefaults.standard.removeObject(forKey: "configuredProviders")
    sut = withDependencies {
      $0.keychainClient = KeychainClient(
        save: { _, _ in true },
        load: { _ in nil },
        delete: { _ in true },
        hasValue: { _ in false }
      )
    } operation: {
      ProviderStore()
    }
  }

  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: "configuredProviders")
    sut = nil
    super.tearDown()
  }

  // MARK: - Initial State

  func testDefaultProvidersSeeded() {
    XCTAssertFalse(sut.providers.isEmpty)
    XCTAssertEqual(sut.providers.count, ProviderType.allCases.count)
  }

  func testEachProviderTypePresent() {
    for type in ProviderType.allCases {
      XCTAssertNotNil(sut.provider(for: type), "Missing provider for \(type)")
    }
  }

  // MARK: - CRUD

  func testAddProvider() {
    let customProvider = Provider(
      id: "custom-github",
      name: "Custom GitHub",
      type: .github,
      baseURL: "https://custom.github.com",
      defaultProject: "org/repo"
    )
    sut.addProvider(customProvider)
    XCTAssertTrue(sut.providers.contains(where: { $0.id == customProvider.id }))
  }

  func testAddDuplicateProviderIsNoop() {
    let existing = sut.providers.first!
    let countBefore = sut.providers.count
    sut.addProvider(existing)
    XCTAssertEqual(sut.providers.count, countBefore)
  }

  func testUpdateProvider() {
    var provider = sut.providers.first!
    let originalName = provider.name
    provider.name = "Updated Name"
    sut.updateProvider(provider)
    XCTAssertEqual(sut.providers.first(where: { $0.id == provider.id })?.name, "Updated Name")
    XCTAssertNotEqual(originalName, "Updated Name")
  }

  func testUpdateNonexistentProviderIsNoop() {
    let fake = Provider(
      id: "nonexistent",
      name: "Fake",
      type: .github,
      baseURL: "https://example.com",
      defaultProject: ""
    )
    let countBefore = sut.providers.count
    sut.updateProvider(fake)
    XCTAssertEqual(sut.providers.count, countBefore)
  }

  func testRemoveProvider() {
    let provider = sut.providers.first!
    let countBefore = sut.providers.count
    sut.removeProvider(provider)
    XCTAssertEqual(sut.providers.count, countBefore - 1)
    XCTAssertFalse(sut.providers.contains(where: { $0.id == provider.id }))
  }

  // MARK: - Persistence

  func testProvidersPersistAcrossInstances() {
    let countBefore = sut.providers.count
    let customProvider = Provider(
      id: "persisted-github",
      name: "Persisted GitHub",
      type: .github,
      baseURL: "https://persisted.github.com",
      defaultProject: "org/repo"
    )
    sut.addProvider(customProvider)

    let sut2 = withDependencies {
      $0.keychainClient = KeychainClient(
        save: { _, _ in true },
        load: { _ in nil },
        delete: { _ in true },
        hasValue: { _ in false }
      )
    } operation: {
      ProviderStore()
    }
    XCTAssertEqual(sut2.providers.count, countBefore + 1)
    XCTAssertTrue(sut2.providers.contains(where: { $0.id == customProvider.id }))
  }

  func testRemovalPersists() {
    let provider = sut.providers.first!
    let countBefore = sut.providers.count
    sut.removeProvider(provider)

    let sut2 = withDependencies {
      $0.keychainClient = KeychainClient(
        save: { _, _ in true },
        load: { _ in nil },
        delete: { _ in true },
        hasValue: { _ in false }
      )
    } operation: {
      ProviderStore()
    }
    XCTAssertEqual(sut2.providers.count, countBefore - 1)
  }

  // MARK: - Computed Properties

  func testConnectedProviders() {
    XCTAssertTrue(sut.connectedProviders.count <= sut.providers.count)
  }

  func testDisconnectedProviders() {
    XCTAssertEqual(
      sut.connectedProviders.count + sut.disconnectedProviders.count,
      sut.providers.count
    )
  }

  func testProviderForType() {
    let github = sut.provider(for: .github)
    XCTAssertNotNil(github)
    XCTAssertEqual(github?.type, .github)
  }

  // MARK: - Environment Building

  func testBuildProviderEnvironmentReturnsDict() {
    let env = sut.buildProviderEnvironment()
    XCTAssertNotNil(env)
  }

  // MARK: - Observation Trigger

  func testTriggerObservationUpdateDoesNotCrash() {
    sut.triggerObservationUpdate()
    XCTAssertFalse(sut.providers.isEmpty)
  }

  func testTriggerObservationUpdatePreservesProviders() {
    let countBefore = sut.providers.count
    let idsBefore = Set(sut.providers.map(\.id))
    sut.triggerObservationUpdate()
    XCTAssertEqual(sut.providers.count, countBefore)
    XCTAssertEqual(Set(sut.providers.map(\.id)), idsBefore)
  }
}
