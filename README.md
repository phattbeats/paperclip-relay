# Paperclip Relay

A native iOS client for a self-hosted [Paperclip](https://github.com/paperclipai/paperclip) board.

Built because the phone this client exists for runs **iOS 16.4**, and the
third-party clients do not run there: Paperclip Relay (App Store) needs
**iOS 26.5+**, `pclip` needs **iOS 17.0+**. Paperclip's own API is MIT-licensed
and reachable from any client, so the missing piece was the client, not the server.

## What it does

Three tabs, all against the board's REST API:

- **Issues** — list, search, filter by status; open one to read the description
  and the comment thread, post a comment, or change status with an optional
  note attached to the same write.
- **Agents** — the roster with live status, plus what is running right now.
- **Approvals** — pending board approvals with approve/reject and a decision note.

Plus settings for the server URL, the company id, and credentials.

## Requirements

- **iOS 16.0 or later.** The deployment target is enforced in CI: the build
  fails if `MinimumOSVersion` ever rises above 16.x.
- A Paperclip instance and a company id.

## Signing in

Two ways in, both board-level (a human acting on the board):

**Board API key (preferred).** Mint one from the board's API keys page. It
looks like `pcp_board_…` and can be given a multi-year expiry, so the app
keeps working without a weekly re-login. Paste it into Settings; it is stored
in the iOS Keychain. The company id is discovered from `GET /api/companies`,
so there is no UUID to type.

**Email + password.** Signs in for a 7-day session. The session cookie is
stored in the Keychain too. Board mutations through a session require a
trusted browser `Origin` header, which this client sends — it is talking to
the board as the board.

Credentials go in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`),
never in `UserDefaults` and never in the plist.

## Building

The build is **unsigned**: no Apple Developer Program account, no App Store
record, no provisioning profile.

```bash
brew install xcodegen
./ios/build-ios.sh
```

Produces `ios/build/Relay-unsigned.ipa`. CI does the same on a macOS runner
and uploads the `.ipa` as an artifact.

### Installing the unsigned .ipa

Sideload it with [AltStore](https://altstore.io) or SideStore using a free
personal Apple ID, or sign it locally with your own team in Xcode. The
install card for the Chlorophone iOS build (PHA-4553) documents the same
flow step by step.

A free personal team does **not** get the `aps-environment` entitlement, so
this client does not do push notifications. That is not a gap in scope: the
board already reaches the phone over Signal and Discord, and the need here is
reading and updating issues, not alerting.

## API surface

Every route below was verified against a live instance with a board
credential.

| Method | Route | Used for |
|---|---|---|
| GET | `/api/companies` | company discovery (finds the company id) |
| GET | `/api/companies/{id}/agents` | agent roster |
| GET | `/api/companies/{id}/issues?view=index` | issue list (lightweight projection) |
| GET | `/api/issues/{id}` | issue detail |
| GET | `/api/issues/{id}/comments` | comment thread |
| POST | `/api/issues/{id}/comments` | post a comment |
| PATCH | `/api/issues/{id}` | status / priority, with an optional note in the same write |
| GET | `/api/companies/{id}/live-runs` | what is running now |
| GET | `/api/companies/{id}/approvals` | pending approvals |
| POST | `/api/approvals/{id}/approve` | approve |
| POST | `/api/approvals/{id}/reject` | reject |
| GET | `/api/companies/{id}/projects` | project names |
| GET | `/api/board-api-keys` | key list (settings) |
| GET | `/api/companies/{id}/attention` | needs-you feed |

Notes:

- `attention` is **company-scoped**. The bare `/api/attention` path is 404.
- A status change and its note go in one `PATCH`. The server's review guard
  wants the decision comment in the same write — a separate comment `POST`
  does not satisfy it.
- Board API keys minted with `ttlDays` are clamped to 30 days. Pass an
  explicit `expiresAt` instead for a longer life.
- The board sits behind a CDN with a browser-integrity rule, so the client
  sends an iPhone Safari user agent. A custom app user agent can be answered
  with a block page before the request reaches Paperclip.

## Screenshots

CI runs the app on an iPhone simulator against the live board and captures
the three tabs. The board key comes from the repository secret
(`RELAY_BOARD_TOKEN`), never from the repository itself, and the screenshots
come out as the `paperclip-relay-ios-screenshots` artifact.

## Layout

```
ios/project.yml            XcodeGen spec (the .xcodeproj is generated, not committed)
ios/build-ios.sh           build + package the unsigned .ipa
ios/RelayApp/
  RelayApp.swift           app entry, shared BoardStore
  RootView.swift           tabs and first-run setup
  APIClient.swift          URLSession client, auth, Origin handling
  BoardService.swift       typed calls
  SessionStore.swift       settings + Keychain
  Models.swift             wire types
  IssuesView.swift         issue list
  IssueDetailView.swift    issue detail, comments, status change
  AgentsView.swift         roster and live runs
  ApprovalsView.swift      approvals and decisions
  SettingsView.swift       connection, credentials, key list
```

## Licence

MIT, matching Paperclip upstream.
