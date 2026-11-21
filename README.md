# Paperclip Relay

A native iOS client for a self-hosted [Paperclip](https://github.com/paperclipai/paperclip) board.

Built because the phone this client exists for runs **iOS 16.4**, and the
third-party clients do not run there: Paperclip Relay (App Store) needs
**iOS 26.5+**, `pclip` needs **iOS 17.0+**. Paperclip's own API is MIT-licensed
and reachable from any client, so the missing piece was the client, not the server.

## What it does

Five phone-first surfaces, all against the board's REST API:

- **Company** — a live operator pulse: agents, open/blocked work, spend,
  approvals, goals, org, recent activity and routine controls. It has board-wide
  search and can file a new issue without opening a laptop. A manual routine
  run requires confirmation; board-key creation/revocation remains web-only.

- **Issues** — the board's own task views as a chip row, no menu: *Needs
  attention*, *All*, *Active*, *Backlog*, *Done*, plus the board user's inbox
  (*Mine*, *Unread*, *Blocked*, *Recent*, *Everything*). Every chip shows a
  count, and the list opens on *Active*. Search on top, then open one to read
  the description and the comment thread, post a comment, or change status
  with an optional note attached to the same write.
- **Agents** — the roster with live status, plus what is running right now.
- **Approvals** — pending board approvals with approve/reject and a decision note.

Settings is available from the Company tab's gear: server URL, company id,
and credentials remain in the iOS Keychain.

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
| GET | `/api/companies/{id}/dashboard` | company health, work and cost pulse |
| GET | `/api/companies/{id}/goals` | company goals |
| GET | `/api/companies/{id}/org` | reporting hierarchy |
| GET | `/api/companies/{id}/activity` | recent company activity |
| GET | `/api/companies/{id}/routines` | routine controls |
| PATCH | `/api/routine-triggers/{id}` | pause/resume a schedule |
| POST | `/api/routines/{id}/run` | confirmed manual routine run |
| GET | `/api/companies/{id}/search` | board-wide search |
| POST | `/api/companies/{id}/issues` | file a new issue |
| GET | `/api/companies/{id}/issues?view=index` | issue list (lightweight projection) |
| GET | `/api/companies/{id}/issues?view=index&status=a,b` | one status set at a time, for the filter chips |
| GET | `/api/issues/{id}` | issue detail |
| GET | `/api/issues/{id}/comments` | comment thread |
| POST | `/api/issues/{id}/comments` | post a comment |
| PATCH | `/api/issues/{id}` | status / priority, with an optional note in the same write |
| GET | `/api/companies/{id}/live-runs` | what is running now |
| GET | `/api/companies/{id}/approvals` | pending approvals |
| GET | `/api/approvals/{id}/issues` | the issue an approval is about |
| POST | `/api/approvals/{id}/approve` | approve |
| POST | `/api/approvals/{id}/reject` | reject |
| GET | `/api/companies/{id}/projects` | project names |
| GET | `/api/board-api-keys` | key list (settings) |
| GET | `/api/companies/{id}/attention?view=mine` | the board user's needs-you feed |
| GET | `/api/companies/{id}/inbox/mine` | the board user's own inbox |
| GET | `/api/companies/{id}/issues/count?attention=blocked` | the exact blocked count |
| GET | `/api/companies/{id}/decisions?status=open` | decisions waiting on a choice |
| GET | `/api/issues/{id}/interactions` | an issue's questions, with their answers |
| POST | `/api/issues/{id}/interactions/{interactionId}/respond` | answer them |
| GET | `/api/issues/{id}/attachments` | files on an issue |
| GET | `/api/attachments/{id}/content` | the bytes behind one |
| GET | `/api/agents/{id}/configuration` | an agent's adapter and model |
| GET | `/api/companies/{id}/adapters/{type}/models` | the models an adapter offers |

Notes:

- The filter chips use the board's own vocabulary, not a new one: *Active*
  is the board's `todo + in_progress + monitoring + in_review + blocked`
  preset, *Done* is `done + cancelled`, and *Needs attention* is the
  board user's own desk — every item on `/attention?view=mine` that names
  an issue. The board names that issue in three different places depending
  on the item (subject metadata for a question or an approval, the subject
  itself for a review or a blocker, the related issue for a recovery), so
  the client reads all three.
- The inbox chips read the board's own filters, the same way the web board
  does: *Mine* is `/inbox/mine`, *Unread* is `unreadForUserId=me`,
  *Blocked* is `attention=blocked` (with the board's own exact count from
  `/issues/count`), *Recent* is `touchedByUserId=me` inside a week, and
  *Everything* is the whole list. The Issues tab reads the same endpoints
  for the same chips, so a chip means one thing in both places.
- An approval does not name its issue in its payload — the pending ones
  carry no source issue at all. The link is the board's own
  (`/api/approvals/{id}/issues`), and the payload's `risks` field is
  either a list or a paragraph depending on who wrote the request.
- A chip count is a floor, not always a total. The board has well over a
  thousand issues, so the app fetches at most 100 rows per set and marks a
  truncated count with a `+`.
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

The simulator build is signed **ad-hoc** (`CODE_SIGN_IDENTITY="-"`), unlike the
shipped `.ipa`, which is unsigned. An unsigned simulator build carries no
keychain entitlement, so the Keychain refuses the write with -34018 and the
app comes up unconfigured — the screenshots then show the first-run setup
screen and look like an app with no data. `SessionStore` also keeps the board
key in memory when a Keychain write is refused, so the app still works on a
build where the Keychain is unavailable. The `.ipa` that ships is unsigned by
design: AltStore signs it on the device, where the Keychain is available.

When a screenshot run comes back showing the setup screen, read
`relay-launch.json` from the simulator's Documents directory in the CI log
before changing anything else. It reports `hasBoardToken`,
`keychainWriteStatus`, `tokenHeldInMemory`, `bootstrapFileFound` and
`environmentHasToken`, which distinguishes "the app never got the key" from
"the app got the key and the request failed".

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
  IssuesView.swift         issue list and the filter chip row
  IssueFilters.swift       chip vocabulary, counts, the filter store
  IssueFilterService.swift the endpoints the filter reads
  IssueDetailView.swift    issue detail, comments, status change
  AgentsView.swift         roster and live runs
  ApprovalsView.swift      approvals and decisions
  SettingsView.swift       connection, credentials, key list
```

## Banner conventions

`BoardStore.banner` is a shared banner plus a `bannerIsError` flag. The flag
is not decoration: the banner is the app's only channel for both failures and
confirmations, so a message like "Status set to in review." rendered with the
same warning triangle as a server error. A confirmation wears a green
checkmark; a failure wears the orange triangle.

**When you add a banner assignment, set `bannerIsError` on the line before it.**
Confirmations (`status` changed, comment posted) set it to `false`; anything
derived from a caught error sets it to `true`. A new assignment that forgets
the flag inherits `true` and will render as an error.

## Licence

MIT, matching Paperclip upstream.
