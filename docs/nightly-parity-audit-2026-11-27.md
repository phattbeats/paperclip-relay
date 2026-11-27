# Paperclip Relay nightly parity audit — 2026-11-27

## Evidence and bounds

- **Upstream nightly source:** `paperclipai/paperclip` `635ed5a36480dc1886e6d18ee7eeb96f7486a81b` (2026-11-27).
- **Latest tagged release reviewed:** `v2026.1117.0` (2026-11-17).
- **Deployed-board contract:** `GET /api/openapi.json`, fetched 2026-11-27; 941 paths. Only routes documented there and marked `BoardApiKeyAuth` are candidates for Relay.
- **Relay baseline:** `303f5e5` (latest published iOS build). The unfinished local run-inspector/attachment work is intentionally *not* counted as shipped parity.
- **Deliberate boundary:** board-key mint/revoke, secrets, connections, environments, member invite, and company import/export remain web-only. They are company-administrative or credential operations, not casual phone actions.

## Current product direction in nightly

Nightly's default is now the **Coordinator workspace**: one conversation per agent, a task queue, compact decision/task cards, and direct agent steering. It also makes run evidence first-class: plans, tool calls, diffs, subagents, verification, usage limits, retry state, and full task-chat transcript all appear around the task. This is the useful north star for Relay—not a pixel-for-pixel desktop clone.

## Parity table

| Nightly capability | Documented board-key route / source | Relay at `303f5e5` | Effort / disposition |
|---|---|---:|---|
| Company dashboard, live work and health | `GET /companies/{cid}/dashboard`, `/live-runs`, `/timeline`, costs and observability routes | **Yes** | Shipped as Pulse / Spend / People / Log / Health. |
| Issue queue, filters, Inbox and decisions | issue, attention, decisions, interaction routes | **Yes** | Shipped; active filter, decision cards and response routing are present. |
| Issue detail, markdown, comments and attachments | issue, comments and attachment reads | **Yes** | Shipped; issue attachment **upload** is a read-safe next gap. |
| Approvals with source issue and attachments | approvals + `GET /approvals/{id}/issues` | **Yes** | Shipped. |
| Agent roster, detail, pause/resume/model/wake | agents plus pause/resume/wakeup/configuration | **Yes** | Shipped; model changes only where the board advertises a model catalog. |
| Company operation: spend, roles, routines, labels, project assignment | costs, members, routines, labels, projects | **Yes, mostly** | Shipped console and guarded budget/role writes. Inline label/project creation is a small gap. |
| **Run transcript / evidence inspector** | `GET /heartbeat-runs/{id}`, `/events`, `/log`, `/issues`; `/issues/{id}/runs` | **No** | **Read-safe, first build gap.** Nightly makes plans, tools, verification and output first-class; Relay currently only shows run rows. |
| Agent chat / mid-turn steering | `POST /board/chat/stream`, issue chat bootstrap | **Unavailable on this board** | API is board-key authenticated, but live probe returns `FEATURE_DISABLED` / responsibilities disabled. Do not ship a dead composer; enable server feature first. |
| Projects detail / workspace / budget | projects, workspaces and project-scoped routes | **Partial** | Relay can assign a project and show project costs; detail/workspaces are read-safe later work. |
| Goals | `GET/POST /companies/{cid}/goals` | **Read only** | Goal creation is safe but lower value than run evidence. |
| Routines detail and responsible-user flow | company routines and routine detail routes | **Partial** | Toggle/manual-run are shipped; detailed history and ownership are later work. |
| Artifacts / work products | artifacts and issue work-product routes | **Partial** | Relay reads attachments; structured work-product linking is a small next gap. |
| Cases | `GET/POST /companies/{cid}/cases` and case routes | **No** | Read-safe later work; separate information architecture needed. |
| Global search | `GET /companies/{cid}/search` | **Yes** | Shipped. |
| Skills / skill browser | company skills routes | **No** | Read-safe later work, but a large mobile surface. |
| Workspaces / file viewer | workspace routes | **No** | Read-safe but desktop-shaped; lower priority on a phone. |
| Secrets, API keys, connections, environments, company import/export | documented admin routes | **Deliberately no** | Keep web-only: credential and company-administration boundary. |
| Offline queue / resilient drafts | nightly UI behavior, not a safe board-key endpoint | **No** | Later platform work; do not imply offline mutation reliability before an explicit design. |

## Read-safe build order

1. **Run inspector**: run status, current tool, last agent output, cost/tokens, errors, event stream, bounded log tail, touched issues. This is the mobile answer to “what is my fleet actually doing?”
2. **Issue evidence capture**: select a photo/file and upload it directly to an issue. The phone is uniquely good at this; `POST /companies/{cid}/issues/{issueId}/attachments` was verified against the live board with a board key, then cleaned up.
3. Project detail, goals and routine history, only after the run inspector proves clean on both simulator lanes.

## iOS 26 delivery decision

- Keep `IPHONEOS_DEPLOYMENT_TARGET = 16.0` for Brandon’s iOS 16.4 phone.
- Existing CI is `macos-15` / Xcode 16.4 / iOS 18.5 SDK, so it cannot compile iOS 26 symbols.
- GitHub’s public `macos-26` image ships Xcode 26.6 and iOS 26.5 SDK/simulators. The cheapest $0 fix is a modern-design CI lane on `macos-26` (pin `DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer`), while `macos-15-intel` continues to capture the `#available(iOS 26, *)` fallback on an iOS 18 simulator—proving the iOS 16-compatible code path without raising the deployment floor.
- Liquid Glass and iOS 26-only navigation/material APIs must be guarded with `#available(iOS 26, *)`; the iOS 16 fallback remains current material, spacing and navigation rather than a broken imitation.

## Day-one design test

Open a 300 KB run record and a log with megabytes of output on a slow connection. The inspector must load only on tap, request a bounded event count, request a bounded log tail, and keep each endpoint’s failure local to its section. If the rest of the run stays inspectable when the log storage is unavailable, the design holds.
