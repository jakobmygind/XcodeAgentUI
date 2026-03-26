import Foundation

/// Manages persistence of connection profiles
actor ProfileStore {
    static let shared = ProfileStore()
    
    private let fileURL: URL
    private var profiles: [ConnectionProfile] = []
    private var hasLoaded = false
    
    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let openclawDir = homeDir.appendingPathComponent(".openclaw", isDirectory: true)
        self.fileURL = openclawDir.appendingPathComponent("profiles.json")
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: openclawDir, withIntermediateDirectories: true)
    }
    
    /// Load profiles from disk, creating defaults if none exist
    func load() async throws -> [ConnectionProfile] {
        if hasLoaded {
            return profiles
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // Create default profiles
            profiles = [ConnectionProfile.local]
            try await save(profiles)
            hasLoaded = true
            return profiles
        }
        
        let data = try Data(contentsOf: fileURL)
        profiles = try JSONDecoder().decode([ConnectionProfile].self, from: data)
        hasLoaded = true
        return profiles
    }
    
    /// Save profiles to disk
    func save(_ newProfiles: [ConnectionProfile]) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(newProfiles)
        try data.write(to: fileURL, options: .atomic)
        profiles = newProfiles
    }
    
    /// Add a new profile
    func add(_ profile: ConnectionProfile) async throws {
        var current = try await load()
        
        // If this is set as default, unset others
        if profile.isDefault {
            current = current.map { var p = $0; p.isDefault = false; return p }
        }
        
        current.append(profile)
        try await save(current)
    }
    
    /// Update an existing profile
    func update(_ profile: ConnectionProfile) async throws {
        var current = try await load()
        
        // If this is set as default, unset others
        if profile.isDefault {
            current = current.map { var p = $0; p.isDefault = (p.id == profile.id); return p }
        }
        
        guard let index = current.firstIndex(where: { $0.id == profile.id }) else {
            throw ConnectionError.profileNotFound
        }
        
        current[index] = profile
        try await save(current)
    }
    
    /// Remove a profile
    func remove(id: UUID) async throws {
        var current = try await load()
        current.removeAll { $0.id == id }
        try await save(current)
    }
    
    /// Get the default profile, or the first available
    func defaultProfile() async throws -> ConnectionProfile? {
        let current = try await load()
        return current.first { $0.isDefault } ?? current.first
    }
    
    /// Set a profile as the default
    func setDefault(id: UUID) async throws {
        var current = try await load()
        current = current.map { var p = $0; p.isDefault = (p.id == id); return p }
        try await save(current)
    }
    
    /// Update last connected timestamp and latency for a profile
    func updateConnectionMetrics(id: UUID, latencyMs: Int?) async throws {
        var current = try await load()
        guard let index = current.firstIndex(where: { $0.id == id }) else {
            throw ConnectionError.profileNotFound
        }
        
        current[index].lastConnected = Date()
        current[index].lastLatencyMs = latencyMs
        try await save(current)
    }
}

// MARK: - Keychain Integration

extension ProfileStore {
    /// Save bearer token for a profile in Keychain
    nonisolated func saveToken(for profileID: UUID, token: String) throws {
        let key = KeychainManager.TokenKey.custom("openclaw-profile-\(profileID.uuidString)")
        guard KeychainManager.save(key: key, value: token) else {
            throw ConnectionError.keychainError("Failed to save token")
        }
    }
    
    /// Load bearer token for a profile from Keychain
    nonisolated func loadToken(for profileID: UUID) -> String? {
        let key = KeychainManager.TokenKey.custom("openclaw-profile-\(profileID.uuidString)")
        return KeychainManager.load(key: key)
    }
    
    /// Delete bearer token for a profile
    func deleteToken(for profileID: UUID) throws {
        let key = KeychainManager.TokenKey.custom("openclaw-profile-\(profileID.uuidString)")
        guard KeychainManager.delete(key: key) else {
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
