# STATUS

[English](STATUS.md) · [中文](../zh-CN/STATUS.md)

As of **2026-11-11** (Asia/Shanghai).

**Stale means void: this file records only what was true when it was written.** Before taking over,
run `git log -1` and `swift test --disable-sandbox`, then repeat the relevant checks under "Last
verification". Where current output differs from this file, current output wins; update this file
before relying on it.

## Current code state

- Code HEAD: `335211b` (`chore: release v2.3.3`); `origin/main` also points at `335211b`.
  The Xcode project and both locally built configurations are version **2.3.3 (build 233)**.
- Local tags: `v2.1.0`, `v2.3.0`, `v2.3.1`, `v2.3.2`, `v2.3.3`.
- This file's worktree is on `agent/whole-project-audit` and contains the uncommitted source, test
  and documentation fixes from the whole-project audit. The main worktree separately contains
  uncommitted shared-contract fixes in `.github/workflows/ci.yml`, `AGENTS.md` and
  `scripts/{Info.plist,backup_app.sh,build_release.sh,publish_release.sh}`. Together, these two
  groups are the complete audit result.
- Settings schema: **12**. v11 added `karabinerPanelSignalEnabled` (default `true`); v12 added
  `autoAuditUnreachableShortcuts` (default `true`). Older files use those defaults when the keys
  are absent. The independent `usage.json` schema is **1**, and the menu-cache schema is **6**.
- The Info.plist in `/Applications/Kaname.app` reports **2.3.3 (232)** with
  `KanameCommit=335211b`. This round only read that metadata; it did not replace or relaunch the
  installed app.

## Current audit changes

### Source and test fixes

- Search fallback records usage only when injection returns `.sent`; failure and cancellation no
  longer inflate statistics.
- Updated system-hotkey or config-scan results now refresh an open panel and search palette. App
  launch and termination also refresh the running-app scope and the catalogs used by conflict scans.
- A second instance that never started returns early from its own `stop()` instead of clearing the
  running instance's Karabiner variable.
- Swallowed physical presses are tracked independently by key code. Once panel capture rules go
  away, repeats of the original swallowed press are still consumed until its matching key-up;
  releasing one key does not clear another key's state.
- Panel and search execution capture their target before asynchronous AX work. Injection now
  requires an explicit target, preflights the complete chord before activation or posting, resolves
  `KeyStep.alternates` in order, and rejects the whole plan when any step is unmappable.
- Surface, injection and cursor-return work have session ownership. Replacing or dismissing a
  surface invalidates older asynchronous completions, and cursor restoration survives panel/search
  transitions without allowing a stale completion to move the pointer.
- The project build number advanced from 232 to **233** while the marketing version remains 2.3.3.
  SwiftPM retains `swift-tools-version: 6.0` and Swift 6.1 CI compatibility; XCTest hosts are
  explicitly `nonisolated` instead of relying on the Swift 6.2-only default-isolation manifest setting.
- Concurrent token collection in tests uses a lock. Regression coverage now includes independent
  swallowed keys, complete injection-plan resolution and session ownership.

### Shared script and CI fixes

- Release CI enables `pipefail` for its `xcodebuild | tail` pipeline, so build failure reaches CI.
- The publisher rejects an asset when an existing tag points at a different commit from the DMG
  build. A retry with a matching tag generates notes from the preceding release tag.
- DMGs signed with `Kaname Local` do not request an Apple timestamp; Developer ID signing retains
  timestamping.
- Backup dry runs predict pruning from the post-backup count. The fallback-build plist template
  now says 2.3.3 / **233**.

### Documentation boundaries

- Current-behaviour descriptions in the README, architecture, FAQ, permissions, troubleshooting,
  release documentation and STATUS follow the code. English and Chinese pairs were updated together.
- Text explicitly marked as history, development narrative or notes for an older release keeps its
  time context. Only links, paths and errors directly established from git history are corrected.
- User-visible fixes are collected under `[Unreleased]` in the root `CHANGELOG.md`.

## Last verification

These results come from checks actually run on the current uncommitted source on 2026-11-10 and
2026-11-11.

| Check | Result |
| --- | --- |
| `git rev-parse --short HEAD` / `origin/main` | Both `335211b` |
| Installed Info.plist | `2.3.3` / `232` / `KanameCommit=335211b` |
| `swift test --disable-sandbox --enable-code-coverage` | **933 tests, 0 failures**; the pasteboard contract test emitted one `sandbox_extension_consume failed: 1 (Operation not permitted)` environment message and passed with the rest of the suite |
| `Core/Pure` line coverage, using CI's `llvm-cov report/export` commands | **88.59%**; the CI threshold is 70% |
| `xcodebuild -project Kaname.xcodeproj -scheme Kaname -configuration Debug -derivedDataPath build/audit-debug CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build` | `BUILD SUCCEEDED` |
| The same build with `-configuration Release -derivedDataPath build/audit-release`, through `set -o pipefail` and `tail` | `BUILD SUCCEEDED` |
| Source, Debug and Release Info.plists | `plutil -lint` passes; all three report 2.3.3 / 233 |
| Modified shell scripts | `bash -n` passes |
| Disposable backup dry-run fixture | Predicts no deletion within retention and the correct oldest backups at and above retention; directories remain intact |
| Disposable publisher fixtures | Commit mismatch exits 1; a matching-tag retry generates `Changes since v9.9.8`, not changes since the current tag itself |
| Relative Markdown links | Targets checked for existence; examples in fenced and inline code are not treated as links |
| `git diff --check` | Passes in both the main and audit worktrees |

Destination-selection and AppIntents metadata messages in the Debug/Release logs are not Swift
compiler warnings. Both configurations completed with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`.

## Remaining validation and design items

1. **Interactive acceptance.** VoiceOver, a real second instance, cross-Space pointer behaviour and
   real AX/injection races still require interactive validation on a running installation.
2. **Event-tap recovery.** The recovery backoff remains configured as `[0]`; changing it is a design
   decision that needs its own runtime verification.

## Environment and operating boundaries

- Tests inside the sandbox use `swift test --disable-sandbox`; without it, the run can fail
  immediately with `sandbox_apply: Operation not permitted`.
- `xcodebuild` can hit environmental failures in a nested sandbox. Use `error:` in fallback-build
  output and an outside-sandbox result to distinguish them from source failures.
- This round performed no commit, merge, push, installation, signing, notarization or publishing,
  and did not modify `/Applications`, backup directories or signing keychains.
- Large-scale decomposition and "dead-code candidates" from static reference scans are not verified
  fixes; no implementation code was deleted on that basis.
