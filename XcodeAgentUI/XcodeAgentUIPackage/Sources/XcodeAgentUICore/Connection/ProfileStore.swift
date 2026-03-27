import Foundation

/// Manages persistence of connection profiles to JSON file
public actor ProfileStore {
    /// Shared singleton instance
    public static let shared = ProfileStore()
    
    /// URL for the profiles JSON file
    private let fileURL: URL
    
    /// In-memory cache of profiles
    private var profiles: [ConnectionProfile] = []
    
    /// Whether the store has been initialized with defaults
    private var isInitialized = false
    
    /// Initialize with custom file URL (for testing)
    public init(fileURL: URL? = nil) {
        if let fileURL = fileURL {
            self.fileURL = fileURL
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.fileURL = home.appendingPathComponent(".openclaw/profiles.json")
        }
    }
    
    // MARK: - Public API
    
    /// Load profiles from disk, creating defaults if none exist
    public func load() async throws -> [ConnectionProfile] {
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
        
        // Read and decode
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ProfileStoreError.fileReadError(fileURL, error.localizedDescription)
        }
        
        do {
            profiles = try JSONDecoder().decode([ConnectionProfile].self, from: data)
            isInitialized = true
            return profiles
        } catch let decodingError as DecodingError {
            throw ProfileStoreError.decodingError(decodingError.localizedDescription)
        } catch {
            throw ProfileStoreError.fileReadError(fileURL, error.localizedDescription)
        }
    }
    
    /// Save current profiles to disk atomically
    public func save() async throws {
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
        
        // Write atomically using .atomic option
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw ProfileStoreError.fileWriteError(fileURL, error.localizedDescription)
        }
    }
    
    /// Get all profiles (loads if needed)
    public func allProfiles() async throws -> [ConnectionProfile] {
        if !isInitialized {
            _ = try await load()
        }
        return profiles
    }
    
    /// Get a specific profile by ID
    public func profile(id: UUID) async throws -> ConnectionProfile? {
        let all = try await allProfiles()
        return all.first { $0.id == id }
    }
    
    /// Get the default profile
    public func defaultProfile() async throws -> ConnectionProfile? {
        let all = try await allProfiles()
        return all.first { $0.isDefault } ?? all.first
    }
    
    /// Add a new profile
    public func add(_ profile: ConnectionProfile) async throws {
        var all = try await allProfiles()
        
        // Check for duplicate ID
        guard !all.contains(where: { $0.id == profile.id }) else {
            throw ConnectionError.profileNotFound(profile.id)
        }
        
        // If this is set as default, unset others
        if profile.isDefault {
            all = all.map { var p = $0; p.isDefault = false; return p }
        }
        
        all.append(profile)
        profiles = all
        try await save()
    }
    
    /// Update an existing profile
    public func update(_ profile: ConnectionProfile) async throws {
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
    public func remove(id: UUID) async throws {
        var all = try await allProfiles()
        
        // Delete associated token first
        try? deleteToken(for: id)
        
        all.removeAll { $0.id == id }
        profiles = all
        try await save()
    }
    
    /// Set a profile as the default
    public func setDefault(id: UUID) async throws {
        var all = try await allProfiles()
        
        guard all.contains(where: { $0.id == id }) else {
            throw ConnectionError.profileNotFound(id)
        }
        
        all = all.map { var p = $0; p.isDefault = (p.id == id); return p }
        profiles = all
        try await save()
    }
    
    /// Update last connected timestamp and latency for a profile
    public func updateConnectionMetrics(id: UUID, latencyMs: Int?) async throws {
        var all = try await allProfiles()
        guard let index = all.firstIndex(where: { $0.id == id }) else {
            throw ConnectionError.profileNotFound(id)
        }

        all[index].lastConnected = Date()
        all[index].lastLatencyMs = latencyMs
        profiles = all  // Update the actor's profiles array
        try await save()
    }
    
    /// Reset to default profiles (useful for testing or recovery)
    public func resetToDefaults() async throws {
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
    public nonisolated func saveToken(for profileID: UUID, token: String) throws {
        let key = KeychainManager.TokenKey.custom("openclaw-profile-\(profileID.uuidString)")
        guard KeychainManager.save(key: key, value: token) else {
            throw ConnectionError.keychainError("Failed to save token")
        }
    }
    
    /// Load bearer token for a profile from Keychain
    public nonisolated func loadToken(for profileID: UUID) -> String? {
        let key = KeychainManager.TokenKey.custom("openclaw-profile-\(profileID.uuidString)")
        return KeychainManager.load(key: key)
    }
    
    /// Delete bearer token for a profile
    public func deleteToken(for profileID: UUID) throws {
        let key = KeychainManager.TokenKey.custom("openclaw-profile-\(profileID.uuidString)")
        guard KeychainManager.delete(key: key) else {
            throw ConnectionError.keychainError("Failed to delete token")
        }
    }
    
    /// Resolve token reference to actual token
    public nonisolated func resolveToken(_ tokenRef: String, for profileID: UUID) -> String? {
        if tokenRef == "keychain-ref" || tokenRef.hasPrefix("keychain-ref:") {
            return loadToken(for: profileID)
        }
        // Token is stored directly (not recommended but supported)
        return tokenRef
    }
}
