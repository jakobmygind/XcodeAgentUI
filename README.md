# Xcode Agent UI

A native macOS control center for the [Xcode Agent Runner](https://github.com/openclaw/xcode-agent) — monitor, steer, and manage autonomous AI agents that work on your tickets in real time.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

<!--
## Screenshots

| Dashboard | Mission Control | Queue Management |
|-----------|----------------|------------------|
| ![Dashboard](screenshots/dashboard.png) | ![Mission Control](screenshots/mission-control.png) | ![Queue](screenshots/queue.png) |

| Workload Balancer | Performance Analytics | Code Review |
|-------------------|----------------------|-------------|
| ![Workload](screenshots/workload.png) | ![Performance](screenshots/performance.png) | ![Review](screenshots/diff-review.png) |
-->

## Features

### Mission Control
Interactive 4-panel session view for real-time agent oversight:
- **Diff Stream** — watch code changes appear live as the agent works
- **Acceptance Criteria** — track progress against ticket requirements
- **Agent Feed** — follow agent output, errors, and status messages
- **Steering Bar** — send commands and respond to approval requests inline

### Queue Management
Priority-based ticket queue with drag-and-drop reordering, per-model concurrency limits (Sonnet / Opus), and auto-assignment rules that route tickets by tag or pattern.

### Intelligent Workload Balancing
Distribute work across multiple agent instances using one of three strategies:
- **Least Loaded** — assign to the agent with the lowest CPU utilization
- **Round Robin** — even distribution by ticket count
- **Priority Weighted** — route critical/high-priority tickets to Opus agents

Supports agent scheduling (one-time, daily, weekdays, weekly) and automatic rebalancing.

### Performance Analytics
SQLite-backed metrics with success/failure rates, average durations, token cost tracking, and daily trend charts. Filter by time range (24h, 7d, 30d, all-time) and compare Sonnet vs. Opus performance.

### Code Review
Unified diff viewer with per-file approval status, inline commenting, and Markdown export.

### Multi-Provider Support
Integrate with **GitHub**, **GitLab**, **Jira**, and **Shortcut**. Credentials are stored in the macOS Keychain and injected as environment variables when launching agents.

### Intelligent Notifications
Native macOS notifications with actionable buttons for:
- Approval requests (approve / deny)
- Build failures (view logs / retry)
- Agent stuck detection (nudge / abort)
- Token usage thresholds (80%, 90%, 95%, 100%)
- Ticket completion (view diff)

### Dashboard
At-a-glance service health for Router and Bridge processes, live WebSocket connection status, connected clients, and scrollable process logs.

## Requirements

- **macOS 14** (Sonoma) or later
- **Swift 6.0+** / **Xcode 16+**
- [Xcode Agent Runner](https://github.com/openclaw/xcode-agent) installed at `~/.openclaw/workspace/xcode-agent` (configurable in Settings)

## Installation

### Swift Package Manager

```bash
git clone https://github.com/openclaw/xcode-agent-ui.git
cd xcode-agent-ui/XcodeAgentUI
swift build
swift run
```

### Xcode

Open `XcodeAgentUI/XcodeAgentUI.xcodeproj`, select the **XcodeAgentUI** scheme, and run (⌘R).

## Configuration

### API Tokens

Open **Settings → Tokens** and enter credentials for your providers. Tokens are stored securely in the macOS Keychain under the service `com.openclaw.xcode-agent-ui`.

| Provider | Required Credentials |
|----------|---------------------|
| GitHub   | Personal Access Token |
| GitLab   | Access Token |
| Jira     | API Token + Email |
| Shortcut | API Token |

### Providers

Go to **Settings → Providers** (or the **Providers** sidebar item) to add, edit, or remove provider integrations. Each provider needs a type and valid credentials to show as connected.

### Ports

Default service ports can be changed in **Settings → Ports**:

| Service | Default Port |
|---------|-------------|
| Router  | 3800 |
| Bridge  | 9300 |

### Notifications

Toggle per-category notifications and thresholds in **Settings → Notifications**:
- Stuck agent timeout (default: 10 minutes)
- Token usage alert threshold (default: 80%)
- Sound on/off

## Usage

### Starting Services

1. Open the **Dashboard** from the sidebar.
2. Click **Start All** to launch both the Router and Bridge, or start them individually.
3. The status cards turn green when services are running.

### Assigning a Ticket

1. Go to **Ticket Assignment** in the sidebar.
2. Select a provider, enter the ticket ID and project name.
3. Choose a model — **Sonnet** (faster, cheaper) or **Opus** (deeper reasoning).
4. Click **Assign**.

### Monitoring a Session

1. Switch to **Mission Control** once a session is active.
2. Watch diffs stream in on the left, criteria get checked off on the upper-right, and agent messages flow in the lower-right.
3. Use the steering bar at the bottom to send commands or approve/deny agent requests.

### Managing the Queue

1. Open the **Queue** view.
2. Drag tickets to reorder, right-click for priority changes.
3. Configure concurrency limits and auto-assign rules in the queue settings sheet.

## Architecture

The app is built with **SwiftUI** and follows [Point-Free](https://www.pointfree.co) patterns:

| Pattern | Usage |
|---------|-------|
| `@Observable` | All service and model classes use Observation for reactive state |
| `@MainActor` | Thread safety — all observable classes are main-actor isolated |
| `@Dependency` | Point-Free dependency injection for Keychain and haptic clients |
| `@Shared(.appStorage)` | Persistent user preferences with observation support |

### Key Dependencies

| Package | Purpose |
|---------|---------|
| [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) | Dependency injection and testing |
| [swift-sharing](https://github.com/pointfreeco/swift-sharing) | Cross-feature state sharing and persistence |
| [swift-navigation](https://github.com/pointfreeco/swift-navigation) | State-driven navigation and alerts |

### Communication

- **WebSocket** (Bridge) — real-time bidirectional messaging between the UI and agents using a typed envelope protocol (`BridgeEnvelope`)
- **Process execution** (Router/Bridge) — spawned via `Process` with piped stdout/stderr capture
- **Keychain** — credential storage via the Security framework

## Project Structure

```
XcodeAgentUI/
├── XcodeAgentUI.xcodeproj
├── Package.swift
└── XcodeAgentUI/
    ├── XcodeAgentUIApp.swift          # App entry point
    ├── ContentView.swift              # Root NavigationSplitView
    ├── Models/                        # Domain models
    │   ├── AgentSession.swift         #   Active session, diffs, criteria
    │   ├── QueueTicket.swift          #   Queue tickets, concurrency limits
    │   ├── Provider.swift             #   Provider types and credentials
    │   ├── ServiceStatus.swift        #   Router/Bridge status
    │   ├── AgentWorkload.swift        #   Workers, schedules, load
    │   ├── BridgeMessage.swift        #   WebSocket message protocol
    │   ├── CodeReview.swift           #   Diff review state
    │   ├── PerformanceMetrics.swift   #   Run records, stats, trends
    │   └── TicketConfig.swift         #   Agent model enum, assignment
    ├── Services/                      # Business logic
    │   ├── AgentService.swift         #   Central orchestrator
    │   ├── SessionManager.swift       #   Session lifecycle, commands
    │   ├── QueueManager.swift         #   Queue operations, auto-assign
    │   ├── ProcessRunner.swift        #   External process execution
    │   ├── BridgeWebSocket.swift      #   WebSocket client
    │   ├── NotificationManager.swift  #   macOS notifications
    │   ├── ProviderStore.swift        #   Provider CRUD
    │   ├── KeychainManager.swift      #   Keychain access
    │   ├── MetricsStore.swift         #   SQLite metrics persistence
    │   └── WorkloadBalancer.swift     #   Agent distribution strategies
    ├── Views/                         # SwiftUI views (28 files)
    │   ├── DashboardView.swift        #   Service health overview
    │   ├── MissionControlView.swift   #   4-panel session control
    │   ├── QueueView.swift            #   Ticket queue management
    │   ├── DiffReviewView.swift       #   Code review interface
    │   ├── WorkloadView.swift         #   Agent workload distribution
    │   ├── PerformanceView.swift      #   Analytics and charts
    │   ├── SettingsView.swift         #   Tabbed preferences
    │   └── ...                        #   Supporting views
    ├── Dependencies/                  # DI clients
    │   ├── KeychainClient.swift
    │   └── HapticClient.swift
    ├── Theme/                         # Design system
    │   ├── ColorPalette.swift         #   Colors, gradients, glass effects
    │   └── AnimationPresets.swift     #   Spring curves, shimmer, glow
    ├── Modifiers/                     # View modifiers
    ├── Transitions/                   # Custom transitions
    ├── Mocks/                         # Preview and test data
    └── Config/                        # Xcconfig credential templates
```

## Development

### Building

```bash
cd XcodeAgentUI
swift build
```

### Testing

```bash
swift test
```

### Adding a New Provider

1. Add a case to `ProviderType` in `Models/Provider.swift`.
2. Add a `TokenKey` entry in `Services/KeychainManager.swift`.
3. Map the credentials to environment variables in `ProviderStore.buildProviderEnvironment()`.
4. Update the provider picker UI in `Views/AddProviderView.swift`.

## License

MIT
