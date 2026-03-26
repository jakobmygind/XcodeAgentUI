import Foundation

/// Manages persistence of connection profiles to JSON file
actor ProfileStore {
    /// Shared singleton instance
    static let shared = ProfileStore()
    
    /// URL for the profiles JSON file
    private let fileURL: URL
    
    /// In-memory cache of profiles
    private var profiles: [ConnectionProfile] = []
    
    /// Whether the store has been initialized with defaults
    private var isInitialized = false
    
    /// Initialize with custom file URL (for testing)
    init(fileURL: URL? = nil) {
        if let fileURL = fileURL {
            self.fileURL = fileURL
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.fileURL = home.appendingPathComponent(".openclaw/profiles.json")
        }
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
            profiles = createDefaultProfiles()
            try await save()
            isInitialized = true
            return profiles
        }
        
        // Read and decode
        do {
            let data = try Data(contentsOf: fileURL)
            profiles = try JSONDecoder().decode([ConnectionProfile].self, from: data)
            isInitialized = true
            return profiles
        } catch let decodingError as DecodingError {
            throw ProfileStoreError.decodingError(decodingError.localizedDescription)
        } catch {
            throw ProfileStoreError.fileReadError(fileURL, error.localizedDescription)
        }
    }
    
    /// Save current profiles to disk
    func save() async throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(profiles)
            try data.write(to: fileURL, options: .atomic)
        } catch let encodingError as EncodingError {
            throw ProfileStoreError.encodingError(encodingError.localizedDescription)
        } catch {
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
        return all.first { $0.isDefault }
    }
    
    /// Add a new profile
    func add(_ profile: ConnectionProfile) async throws {
        var all = try await allProfiles()
        
        // If this is the first profile or marked as default, handle default status
        if profile.isDefault || all.isEmpty {
            // Clear default from others
            all = all.map { var p = $0; p.isDefault = false; return p }
        }
        
        all.append(profile)
        profiles = all
        try await save()
    }
    
    /// Update an existing profile
    func update(_ profile: ConnectionProfile) async throws {
        var all = try await allProfiles()
        
        guard let index = all.firstIndex(where: { $0.id == profile.id }) else {
            throw ConnectionError.profileNotFound(profile.id)
        }
        
        // Handle default status change
        if profile.isDefault {
            all = all.map { var p = $0; p.isDefault = false; return p }
        }
        
        all[index] = profile
        profiles = all
        try await save()
    }
    
    /// Delete a profile
    func delete(id: UUID) async throws {
        var all = try await allProfiles()
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
    
    /// Update the last connected timestamp for a profile
    func updateLastConnected(id: UUID, latencyMs: Int? = nil) async throws {
        var all = try await allProfiles()
        
        guard let index = all.firstIndex(where: { $0.id == id }) else {
            throw ConnectionError.profileNotFound(id)
        }
        
        all[index].lastConnected = Date()
        if let latency = latencyMs {
            all[index].lastLatencyMs = latency
        }
        
        profiles = all
        try await save()
    }
    
    /// Reset to default profiles (useful for testing or recovery)
    func resetToDefaults() async throws {
        profiles = createDefaultProfiles()
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
                attributes: nil
            )
        } catch {
            throw ProfileStoreError.directoryCreationFailed(directory, error.localizedDescription)
        }
    }
    
    private func createDefaultProfiles() -> [ConnectionProfile] {
        [
            ConnectionProfile.localDefault(),
            ConnectionProfile.tailscaleDefault()
        ]
    }
}

// MARK: - Profile Keychain Integration

extension ProfileStore {
    /// Service identifier for profile tokens in Keychain
    private static let keychainService = "com.openclaw.agent-profile"
    
    /// Save a bearer token for a profile
    func saveToken(for profileId: UUID, token: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: profileId.uuidString,
            kSecValueData as String: token.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete any existing token first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ConnectionError.keychainError("Failed to save token (status: \(status))")
        }
    }
    
    /// Load the bearer token for a profile
    func loadToken(for profileId: UUID) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: profileId.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw ConnectionError.keychainError("Failed to load token (status: \(status))")
        }
        
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw ConnectionError.keychainError("Invalid token data")
        }
        
        return token
    }
    
    /// Delete the bearer token for a profile
    func deleteToken(for profileId: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: profileId.uuidString
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ConnectionError.keychainError("Failed to delete token (status: \(status))")
        }
    }
    
    /// Get the token for a profile's auth method
    func resolveToken(for profile: ConnectionProfile) async throws -> String? {
        switch profile.authMethod {
        case .none:
            return nil
        case .bearerToken(let keychainRef):
            // If keychainRef is a UUID, use it directly; otherwise use profile ID
            if let uuid = UUID(uuidString: keychainRef) {
                return try loadToken(for: uuid)
            }
            return try loadToken(for: profile.id)
        }
    }
}
