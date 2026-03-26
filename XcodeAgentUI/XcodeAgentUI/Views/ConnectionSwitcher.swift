import SwiftUI

/// Toolbar view for switching between connection profiles
struct ConnectionSwitcher: View {
    @State private var connectionManager: ConnectionManager
    @State private var localDiscovery = LocalDiscovery()
    @State private var tailscaleDiscovery = TailscaleDiscovery()
    @State private var showAddProfile = false
    @State private var showDiscoverySheet = false
    @State private var isScanning = false
    
    init(connectionManager: ConnectionManager = ConnectionManager()) {
        self._connectionManager = State(initialValue: connectionManager)
    }
    
    var body: some View {
        Menu {
            connectionMenuContent
        } label: {
            HStack(spacing: 6) {
                connectionStatusDot
                Text(connectionManager.state.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(connectionStatusColor.opacity(0.3), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .task {
            await connectionManager.loadProfiles()
        }
        .sheet(isPresented: $showAddProfile) {
            AddProfileSheet { profile in
                Task {
                    try? await ProfileStore.shared.add(profile)
                    await connectionManager.loadProfiles()
                }
            }
        }
        .sheet(isPresented: $showDiscoverySheet) {
            DiscoverySheet(
                localDiscovery: localDiscovery,
                tailscaleDiscovery: tailscaleDiscovery,
                onSelect: { profile in
                    Task {
                        try? await ProfileStore.shared.add(profile)
                        await connectionManager.loadProfiles()
                        await connectionManager.connect(to: profile)
                    }
                }
            )
        }
    }
    
    @ViewBuilder
    private var connectionMenuContent: some View {
        // Current status section
        Section {
            HStack {
                Image(systemName: connectionManager.state.isConnected ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(connectionStatusColor)
                Text(connectionManager.state.displayName)
                    .font(.headline)
            }
            
            if let profile = connectionManager.activeProfile {
                if let result = connectionManager.probeResult(for: profile.id), result.success {
                    Text("Latency: \(result.latencyMs)ms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let health = connectionManager.probeResult(for: profile.id)?.healthResponse {
                    Text("Backend v\(health.version)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        
        Divider()
        
        // Profile list
        Section("Profiles") {
            ForEach(connectionManager.availableProfiles) { profile in
                profileButton(for: profile)
            }
        }
        
        Divider()
        
        // Actions
        Section {
            Button {
                Task { await connectionManager.connectToFastest() }
            } label: {
                Label("Connect to Fastest", systemImage: "bolt.fill")
            }
            .disabled(connectionManager.availableProfiles.isEmpty)
            
            Button {
                showDiscoverySheet = true
            } label: {
                Label("Scan Network...", systemImage: "magnifyingglass")
            }
            
            Button {
                showAddProfile = true
            } label: {
                Label("Add Profile...", systemImage: "plus")
            }
        }
        
        if connectionManager.state.isConnected {
            Divider()
            
            Button {
                connectionManager.disconnect()
            } label: {
                Label("Disconnect", systemImage: "xmark")
                    .foregroundStyle(.red)
            }
        }
    }
    
    private func profileButton(for profile: ConnectionProfile) -> some View {
        Button {
            Task {
                await connectionManager.connect(to: profile)
            }
        } label: {
            HStack {
                profileIndicator(for: profile)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.system(size: 13))
                    
                    Text("\(profile.backendHost):\(profile.backendPort)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isActive(profile) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
                
                if profile.isDefault {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                }
            }
        }
        .disabled(isActive(profile) && connectionManager.state.isConnected)
    }
    
    @ViewBuilder
    private func profileIndicator(for profile: ConnectionProfile) -> some View {
        let color = profileKindColor(profile.kind)
        Image(systemName: profile.kind.icon)
            .foregroundStyle(color)
            .frame(width: 20)
    }
    
    private var connectionStatusDot: some View {
        Circle()
            .fill(connectionStatusColor)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(connectionStatusColor.opacity(0.3), lineWidth: 2)
                    .frame(width: 12, height: 12)
            )
    }
    
    private var connectionStatusColor: Color {
        switch connectionManager.state {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .yellow
        case .disconnected, .failed:
            return .red
        }
    }
    
    private func profileKindColor(_ kind: ProfileKind) -> Color {
        switch kind {
        case .local:
            return .green
        case .tailscale:
            return .blue
        case .custom:
            return .orange
        }
    }
    
    private func isActive(_ profile: ConnectionProfile) -> Bool {
        connectionManager.activeProfile?.id == profile.id
    }
}

// MARK: - Add Profile Sheet

struct AddProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (ConnectionProfile) -> Void
    
    @State private var name = ""
    @State private var host = ""
    @State private var port = "9300"
    @State private var selectedKind: ProfileKind = .custom
    @State private var useTLS = false
    @State private var useAuth = false
    @State private var authToken = ""
    @State private var isDefault = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Profile Details") {
                    TextField("Name", text: $name)
                    
                    Picker("Type", selection: $selectedKind) {
                        ForEach(ProfileKind.allCases, id: \.self) { kind in
                            Label(kind.displayName, systemImage: kind.icon)
                                .tag(kind)
                        }
                    }
                    
                    Toggle("Set as Default", isOn: $isDefault)
                }
                
                Section("Connection") {
                    TextField("Host", text: $host)
                        .textContentType(.URL)
                    
                    TextField("Port", text: $port)
                        .textFieldStyle(.roundedBorder)
                    
                    Toggle("Use TLS", isOn: $useTLS)
                }
                
                Section("Authentication") {
                    Toggle("Require Bearer Token", isOn: $useAuth)
                    
                    if useAuth {
                        SecureField("Token", text: $authToken)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Connection Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProfile()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(width: 400, height: 450)
    }
    
    private var isValid: Bool {
        !name.isEmpty &&
        !host.isEmpty &&
        Int(port) != nil
    }
    
    private func saveProfile() {
        let authMethod: AuthMethod = useAuth ? .bearerToken("keychain-ref") : .none
        
        do {
            let profile = try ConnectionProfile(
                name: name,
                kind: selectedKind,
                backendHost: host,
                backendPort: Int(port) ?? 9300,
                useTLS: useTLS,
                authMethod: authMethod,
                isDefault: isDefault
            )
            
            // Save token if needed
            if useAuth && !authToken.isEmpty {
                try? ProfileStore.shared.saveToken(for: profile.id, token: authToken)
            }
            
            onSave(profile)
            dismiss()
        } catch {
            // Handle validation error - in production, show alert
            print("Failed to create profile: \(error)")
        }
    }
}

// MARK: - Discovery Sheet

struct DiscoverySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var localDiscovery: LocalDiscovery
    @State var tailscaleDiscovery: TailscaleDiscovery
    let onSelect: (ConnectionProfile) -> Void
    
    var body: some View {
        NavigationStack {
            List {
                // Local (Bonjour) section
                Section {
                    switch localDiscovery.state {
                    case .idle:
                        Button("Scan Local Network") {
                            localDiscovery.startBrowsing()
                        }
                        
                    case .browsing:
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Scanning local network...")
                                .foregroundStyle(.secondary)
                        }
                        
                    case .found(let backends):
                        ForEach(backends) { backend in
                            discoveredBackendRow(backend)
                        }
                        
                    case .error(let message):
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Local Network (Bonjour)")
                } footer: {
                    if case .found(let backends) = localDiscovery.state, backends.isEmpty {
                        Text("No OpenClaw backends found on local network")
                    }
                }
                
                // Tailscale section
                Section {
                    switch tailscaleDiscovery.state {
                    case .idle:
                        Button("Discover Tailscale Peers") {
                            Task {
                                await tailscaleDiscovery.discoverPeers()
                            }
                        }
                        
                    case .discovering:
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Discovering Tailscale peers...")
                                .foregroundStyle(.secondary)
                        }
                        
                    case .found(let peers):
                        if peers.isEmpty {
                            Text("No online Tailscale peers found")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(peers) { peer in
                                tailscalePeerRow(peer)
                            }
                        }
                        
                    case .error(let message):
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Tailscale Network")
                }
            }
            .navigationTitle("Discover Backends")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        localDiscovery.stopBrowsing()
                        tailscaleDiscovery.stopDiscovery()
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 450, height: 400)
    }
    
    private func discoveredBackendRow(_ backend: DiscoveredBackend) -> some View {
        Button {
            Task {
                if let resolved = try? await localDiscovery.resolve(backend) {
                    let profile = resolved.toProfile(kind: .local)
                    onSelect(profile)
                    dismiss()
                }
            }
        } label: {
            HStack {
                Image(systemName: backend.icon)
                    .foregroundStyle(.blue)
                Text(backend.displayName)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func tailscalePeerRow(_ peer: TailscalePeer) -> some View {
        Button {
            let profile = peer.toProfile()
            onSelect(profile)
            dismiss()
        } label: {
            HStack {
                Image(systemName: "network")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text(peer.displayName)
                    Text(peer.tailscaleIP)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(peer.tailscaleIP.isEmpty)
    }
}

// MARK: - Preview

#Preview {
    HStack {
        ConnectionSwitcher()
        Spacer()
    }
    .padding()
    .frame(width: 400)
}
