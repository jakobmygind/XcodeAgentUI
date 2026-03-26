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
            profiles = createDefaultProfiles()
            try await save()
            isInitialized = true
            return profiles
        }
        
        // Read and decode with file coordination
        var readError: Error?
        var profilesData: Data?
        
        fileCoordinator.coordinate(readingItemAt: fileURL, options: .withoutChanges, error: &readError) { url in
            do {
                profilesData = try Data(contentsOf: url)
            } catch {
                readError = error
            }
        }
        
        if let error = readError {
            throw ProfileStoreError.fileReadError(fileURL, error.localizedDescription)
        }
        
        guard let data = profilesData else {
            throw ProfileStoreError.fileReadError(fileURL, "No data read")
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
        var writeError: Error?
        
        fileCoordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &writeError) { url in
            do {
                // Write to temporary file first, then move atomically
                let tempURL = url.appendingPathExtension("tmp")
                try data.write(to: tempURL, options: .atomic)
                try FileManager.default.moveItem(at: tempURL, to: url)
            } catch {
                writeError = error
            }
        }
        
        if let error = writeError {
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
        
        // Check for duplicate ID
        guard !all.contains(where: { $0.id == profile.id }) else {
            throw ConnectionError.profileNotFound(profile.id)
        }
        
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
    
    /// Delete a profile and its associated token
    func delete(id: UUID) async throws {
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
        // Delete all tokens first
        for profile in profiles {
            try? deleteToken(for: profile.id)
        }
        
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
                attributes: [.posixPermissions: 0o700] // Restrictive permissions
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
        guard let data = token.data(using: .utf8) else {
            throw ConnectionError.keychainError("Failed to encode token")
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: profileId.uuidString,
            kSecValueData as String: data,
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
            // The keychainRef should be the profile ID for the token
            if let uuid = UUID(uuidString: keychainRef) {
                return try loadToken(for: uuid)
            }
            // Fallback to profile's own ID
            return try loadToken(for: profile.id)
        }
    }
}
