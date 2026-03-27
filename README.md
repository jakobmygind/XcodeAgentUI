# Xcode Agent UI

Native macOS control center for the local Xcode Agent backend.

## Package layout

Most app code lives in the local Swift package at `XcodeAgentUI/XcodeAgentUIPackage/`:

- `XcodeAgentUICore` — models, services, connection state, theming, shared modifiers/transitions
- `XcodeAgentUIFeatures` — feature views and UI flows built on top of the core module
- `XcodeAgentUIAppShell` — shell UI/glue used by the app target (`ContentView`, menu bar views, app chrome)

The macOS app target should stay thin: app entry, app delegate/configuration, assets, entitlements, and package wiring.

## Project structure

```text
XcodeAgentUI/
├── AGENTS.md
├── README.md
└── XcodeAgentUI/
    ├── XcodeAgentUI.xcodeproj
    ├── XcodeAgentUIWorkspace.xcworkspace
    ├── XcodeAgentUI/                        # App target (entry point, assets, config)
    │   ├── XcodeAgentUIApp.swift
    │   ├── Config/
    │   │   ├── Credentials.template.xcconfig
    │   │   └── Providers.xcconfig
    │   ├── Assets.xcassets/
    │   └── XcodeAgentUI.entitlements
    └── XcodeAgentUIPackage/                  # Local Swift package
        ├── Package.swift
        ├── Sources/
        │   ├── XcodeAgentUICore/
        │   ├── XcodeAgentUIFeatures/
        │   └── XcodeAgentUIAppShell/
        └── Tests/
            └── XcodeAgentUICoreTests/
```

## Manual Xcode linking

If Xcode does not automatically link the local package products into the app target:

1. Open `XcodeAgentUI/XcodeAgentUIWorkspace.xcworkspace`.
2. Select the **XcodeAgentUI** target.
3. In **General** > **Frameworks, Libraries, and Embedded Content**, add:
   - `XcodeAgentUICore`
   - `XcodeAgentUIFeatures`
   - `XcodeAgentUIAppShell`
4. In **Build Phases** > **Link Binary With Libraries**, verify the same three products are present.
5. If the package itself is not attached yet, use **File > Add Packages...** and choose the local package at `XcodeAgentUI/XcodeAgentUIPackage/`.

## What works now

The happy path is local-first and explicit:
- Backend HTTP API on `http://127.0.0.1:3800`
- Backend WebSocket bridge on `ws://127.0.0.1:9300`
- Dashboard can start the local backend
- Mission Control can start a session and trigger the backend
- Mission Control sends steering commands to the active ticket target
- The backend emits the typed envelope protocol the UI expects

## Requirements

- macOS 14+
- Xcode 16+
- Swift 6 toolchain
- Node 20+
- `claude` CLI installed for real agent execution
- Backend repo cloned locally

## Fresh-clone happy path

### 1. Clone both repos

```bash
git clone <ui-repo-url> XcodeAgentUI
git clone <backend-repo-url> xcode-agent
```

### 2. Prepare backend

```bash
cd xcode-agent
npm install
cp .env.example .env
```

Put at least this in `.env`:

```bash
PORT=3800
BRIDGE_WS_PORT=9300
GITHUB_TOKEN=ghp_...
ALLOW_LOCAL_UNAUTHENTICATED=true
```

### 3. Build and test backend

```bash
cd xcode-agent
npm test
npm run smoke:connection
```

### 4. Configure credentials (optional)

```bash
cd XcodeAgentUI/XcodeAgentUI/XcodeAgentUI/Config
cp Credentials.template.xcconfig Credentials.xcconfig
```

Fill in your tokens in `Credentials.xcconfig`. This file is gitignored.

Supported providers: GitHub, GitLab, Jira, Shortcut. Tokens can also be managed in-app via the Providers settings tab.

### 5. Build and test UI

```bash
cd XcodeAgentUI/XcodeAgentUI/XcodeAgentUIPackage
swift test
```

Or open `XcodeAgentUI/XcodeAgentUI/XcodeAgentUIWorkspace.xcworkspace` in Xcode and run the `XcodeAgentUI` scheme.

## Running the system

### Option A: start backend manually

In the backend repo:

```bash
cd xcode-agent
npm start
```

Then launch the macOS app from Xcode.

### Option B: let the app start the backend

1. Open the app.
2. In Settings or Dashboard, point `Agent Directory` at the backend repo.
3. From Dashboard, start the backend.
4. Wait for HTTP and bridge status to go green.

The default backend path expected by the app is:

```text
~/.openclaw/workspace/xcode-agent
```

Change it in-app if your clone lives elsewhere.

## Mission Control flow

1. Make sure the backend is running.
2. Open **Mission Control** (Cmd+2).
3. Click **Start Session**.
4. Choose provider, project, ticket id, model, optional acceptance criteria.
5. Click **Start**.

What the app does:
- Creates the local session state immediately
- Triggers backend `/trigger` via `npm run trigger:ui`
- Opens/uses the bridge connection as a human client
- Routes steering commands to the active ticket id instead of broadcasting blindly

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+1 | Dashboard |
| Cmd+2 | Mission Control |
| Cmd+3 | Queue |
| Cmd+0 | Toggle Sidebar |
| Cmd+Return | Approve Pending Action |
| Cmd+Shift+W | End Session |
| Cmd+Shift+K | Switch Connection |
| Cmd+Shift+R | Reconnect |

## Backend protocol expected by the UI

The UI expects bridge messages in this envelope shape:

```json
{
  "type": "agent_output",
  "from": "agent",
  "ts": "2026-03-26T15:00:00.000Z",
  "payload": "message text"
}
```

Relevant event types consumed in Mission Control:
- `agent_output`
- `agent_error`
- `agent_status`
- `file_changed`
- `agent_approval_request`
- `acceptance_criteria`
- `criterion_met`
- `token_usage`
- `build_result`
- `system`

## Known blockers / limits

- Real ticket runs still require a valid GitHub token and repo access because the backend resolves issue metadata from GitHub
- The app has rich UI for approvals/diffs/criteria, but backend production of structured diff and criteria events is still opportunistic rather than fully semantic
- The working local dev path is `npm start`; the bridge is served from the main backend process

## License

MIT
