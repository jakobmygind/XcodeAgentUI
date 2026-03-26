import Foundation
import Security

/// Manages persistence of connection profiles to JSON file
actor ProfileStore {
    /// Shared singleton instance
    static let shared = ProfileStore()
    
    /// URL for the profiles JSON file
    let fileURL: URL
    
    /// In-memory cache of profiles
    private var profiles: [ConnectionProfile] = []
    
    /// Whether the store has been initialized with defaults
    private var isInitialized = false
    
    /// File coordinator for atomic file operations
    private let fileCoordinator: NSFileCoordinator
    
    /// Initialize with custom file URL (for testing)
    init(fileURL: URL? = nil) {
        if let fileURL = fileURL {
            self.fileURL = fileURL
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.fileURL = home.appendingPathComponent(".openclaw/profiles.json")
        }
        self.fileCoordinator = NSFileCoordinator(filePresenter: nil)
    }
    
    // MARK: - Public API
    
    /// Load profiles from disk, creating defaults if none exist
    func load() async throws -> [ConnectionProfile] {
        // Return cached profiles if already loaded
        guard !isInitialized else {
            return profiles
        }
        
        // Ensure directory exists
        try createDirectoryIfNeeded()
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // Create default profiles on first launch
            profiles = [ConnectionProfile.local]
            try await save()
            isInitialized = true
            return profiles
        }
        
        // Read and decode with file coordination
        var coordinatorError: NSError?
        var profilesData: Data?
        var readError: Error?
        
        fileCoordinator.coordinate(readingItemAt: fileURL, options: .withoutChanges, error: &coordinatorError) { url in
            do {
                profilesData = try Data(contentsOf: url)
            } catch {
                readError = error
            }
        }
        
        if let error = coordinatorError ?? readError {
            throw ProfileStoreError.fileReadError(fileURL, error.localizedDescription)
        }
        
        guard let data = profilesData else {
            throw ProfileStoreError.fileReadError(fileURL, "No data read")
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            profiles = try decoder.decode([ConnectionProfile].self, from: data)
            isInitialized = true
            return profiles
        } catch let decodingError as DecodingError {
            throw ProfileStoreError.decodingError(decodingError.localizedDescription)
        } catch {
            throw ProfileStoreError.fileReadError(fileURL, error.localizedDescription)
        }
    }
    
    /// Save current profiles to disk atomically
    func save() async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data: Data
        do {
            data = try encoder.encode(profiles)
        } catch let encodingError as EncodingError {
            throw ProfileStoreError.encodingError(encodingError.localizedDescription)
        } catch {
            throw ProfileStoreError.encodingError(error.localizedDescription)
        }
        
        // Write atomically using file coordination
        var coordinatorError: NSError?
        var writeError: Error?
        
        fileCoordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinatorError) { url in
            do {
                // Write JSON data atomically directly to the target URL
                try data.write(to: url, options: .atomic)
            } catch {
                writeError = error
            }
        }
        
        if let error = coordinatorError ?? writeError {
            throw ProfileStoreError.fileWriteError(fileURL, error.localizedDescription)
        }
    }
    
    /// Get all profiles (loads if needed)
    func allProfiles() async throws -> [ConnectionProfile] {
        if !isInitialized {
            _ = try await load()
        }
        return profiles
    }
    
    /// Get a specific profile by ID
    func profile(id: UUID) async throws -> ConnectionProfile? {
        let all = try await allProfiles()
        return all.first { $0.id == id }
    }
    
    /// Get the default profile
    func defaultProfile() async throws -> ConnectionProfile? {
        let all = try await allProfiles()
        return all.first { $0.isDefault } ?? all.first
    }
    
    /// Add a new profile
    func add(_ profile: ConnectionProfile) async throws {
        var all = try await allProfiles()
        
        // Check for duplicate ID
        guard !all.contains(where: { $0.id == profile.id }) else {
            throw ConnectionError.duplicateProfileId(profile.id)
        }
        
        // Determine the profile to store, adjusting default status if needed
        var newProfile = profile
        
        if all.isEmpty {
            // First profile added should always become the default
            newProfile.isDefault = true
        } else if profile.isDefault {
            // Clear default from others when adding a new default profile
            all = all.map { var p = $0; p.isDefault = false; return p }
        }
        
        all.append(newProfile)
        profiles = all
        try await save()
    }
    
    /// Update an existing profile
    func update(_ profile: ConnectionProfile) async throws {
        var all = try await allProfiles()
        
        // If this is set as default, unset others
        if profile.isDefault {
            all = all.map { var p = $0; p.isDefault = (p.id == profile.id); return p }
        }
        
        guard let index = all.firstIndex(where: { $0.id == profile.id }) else {
            throw ConnectionError.profileNotFound(profile.id)
        }
        
        all[index] = profile
        profiles = all
        try await save()
    }
    
    /// Remove a profile and its associated token
    func remove(id: UUID) async throws {
        var all = try await allProfiles()
        
        // Delete associated token first
        try? deleteToken(for: id)
        
        all.removeAll { $0.id == id }
        profiles = all
        try await save()
    }
    
    /// Set a profile as the default
    func setDefault(id: UUID) async throws {
        var all = try await allProfiles()
        
        guard all.contains(where: { $0.id == id }) else {
            throw ConnectionError.profileNotFound(id)
        }
        
        all = all.map { var p = $0; p.isDefault = (p.id == id); return p }
        profiles = all
        try await save()
    }
    
    /// Update last connected timestamp and latency for a profile
    func updateConnectionMetrics(id: UUID, latencyMs: Int?) async throws {
        var all = try await allProfiles()
        guard let index = all.firstIndex(where: { $0.id == id }) else {
            throw ConnectionError.profileNotFound(id)
        }
        
        all[index].lastConnected = Date()
        all[index].lastLatencyMs = latencyMs
        profiles = all
        try await save()
    }
    
    /// Reset to default profiles (useful for testing or recovery)
    func resetToDefaults() async throws {
        // Delete all tokens first
        for profile in profiles {
            try? deleteToken(for: profile.id)
        }
        
        profiles = [ConnectionProfile.local]
        try await save()
    }
    
    // MARK: - Private Helpers
    
    private func createDirectoryIfNeeded() throws {
        let directory = fileURL.deletingLastPathComponent()
        
        guard !FileManager.default.fileExists(atPath: directory.path) else {
            return
        }
        
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700] // Restrictive permissions
            )
        } catch {
            throw ProfileStoreError.directoryCreationFailed(directory, error.localizedDescription)
        }
    }
}

// MARK: - Profile Keychain Integration

extension ProfileStore {
    /// Save bearer token for a profile in Keychain
    nonisolated func saveToken(for profileID: UUID, token: String) throws {
        let key = "openclaw-profile-\(profileID.uuidString)"
        guard saveTokenToKeychain(key: key, value: token) else {
            throw ConnectionError.keychainError("Failed to save token")
        }
    }
    
    /// Load bearer token for a profile from Keychain
    nonisolated func loadToken(for profileID: UUID) -> String? {
        let key = "openclaw-profile-\(profileID.uuidString)"
        return loadTokenFromKeychain(key: key)
    }
    
    /// Delete bearer token for a profile
    func deleteToken(for profileID: UUID) throws {
        let key = "openclaw-profile-\(profileID.uuidString)"
        guard deleteTokenFromKeychain(key: key) else {
            throw ConnectionError.keychainError("Failed to delete token")
        }
    }
    
    /// Resolve token reference to actual token
    nonisolated func resolveToken(_ tokenRef: String, for profileID: UUID) -> String? {
        if tokenRef == "keychain-ref" || tokenRef.hasPrefix("keychain-ref:") {
            return loadToken(for: profileID)
        }
        // Token is stored directly (not recommended but supported)
        return tokenRef
    }
}

// MARK: - Keychain Helpers

private let serviceName = "com.openclaw.xcode-agent-ui.profiles"

private func saveTokenToKeychain(key: String, value: String) -> Bool {
    _ = deleteTokenFromKeychain(key: key)
    
    guard let data = value.data(using: .utf8) else { return false }
    
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: serviceName,
        kSecAttrAccount as String: key,
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    
    return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
}

private func loadTokenFromKeychain(key: String) -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: serviceName,
        kSecAttrAccount as String: key,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    
    guard status == errSecSuccess, let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
}

private func deleteTokenFromKeychain(key: String) -> Bool {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: serviceName,
        kSecAttrAccount as String: key,
    ]
    return SecItemDelete(query as CFDictionary) == errSecSuccess
}
