# BetterSettings, agent guide

`README.md` carries the public API, install, layout and commands. This file carries what the code does not confess.

## Prime directive: fidelity

Every change is held to one bar: lowest CPU/GPU/memory cost at the exact motion that exists today. The animations (subtitle expand/collapse, "Show Details" toggle, tab crossfade, search-jump highlight flash, scroll compensation) are a 1:1 port of the BetterAudio preferences window; their timing curves, durations and visual result are a fixed contract. Optimize around them: fewer layout passes, allocations and redraws. An optimization that changes perceived motion is wrong.

Animation and window behavior are verified by running `swift run better-settings-demo`; unit tests cover the `Domain/` logic and row measurement only.

## Why the code is shaped this way

- `SettingsRouter` is the single source of truth: `selectedTabID` plus a one-shot `navigationRequest`. Controllers observe it; none reaches across to another. `navigationRequest.requestID` (UUID) is why re-selecting the same target still fires and `lastHandledRequestID` is why it fires once: that is what makes search-jumping to an on-screen control still flash it.
- `SettingsWindow.canBecomeKey` / `canBecomeMain` are `nonisolated` overrides: AppKit accessibility queries them off the main thread and a `@MainActor` override traps under the Swift 6 executor check. The window size is locked after the content VC is assigned so split-view constraints cannot fight it.
- `SettingsPresenter.releaseOnClose` frees the whole controller tree (`tearDownAndReleaseWindow` → per-controller `prepareForMemoryRelease`) and rebuilds on the next `show()`. The accessory-app activation retries on the next runloop tick.
- Tab eviction (`tabUnloadPolicy` other than `.keepAll`) is deferred one runloop turn off the crossfade frame and skipped for the on-screen view (`view.superview === containerView`); the search catalog and show-details state live outside the tab controller so a rebuilt tab is identical.
- "Show Details" has one coordinator-free path: the sidebar toggle persists via `SettingsDetails.write` and posts `betterSettingsShowDetailsDidChange`; each `SettingsRowView` hands its track to the singleton `SettingsDetailsSpringAnimator`, which drives every row under one `CADisplayLink` (60 Hz `Timer` below macOS 14). Each row's spring `response` scales with its travel because short rows looked floaty on a fixed duration; collapse is damped harder because its past-0 overshoot is clamped. A captured scroll anchor is re-pinned every tick so height changes above the fold do not drift the viewport. Tuning constants sit at the top of that file.
- `SettingsRowView` caches its expanded subtitle height (invalidated on text or width change) and ignores a redundant same-direction toggle via `animatingTowardVisible`.
- `SettingsSearchIndex` normalizes the catalog once at init; catalog order breaks score ties, so the stable sort stays. The sidebar debounces input by `searchDebounce` (0.18 s).
- `SidebarCellView` toggles pre-built constraints between tab and result layouts and caches one `CAGradientLayer` per cell; selection emphasis refreshes visible rows only (`refreshVisibleRowStyles`).

## Conventions

- Swift 6 strict concurrency: UI types are `@MainActor`, domain types `Sendable`. An AppKit getter that must answer off-main is `nonisolated` and returns a constant.
- Async or animated work is guarded by a bumped generation counter or a stored `Task` cancelled before the next starts, so a stale completion finds nothing to mutate.
- Every animated path honors `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` with a settled-state branch that jumps to the final state.
- Retained state (observers, `Task`s, Combine subscriptions, table delegates, document views, layers, images) is nilled in `tearDown()` / `prepareForMemoryRelease()`; new state joins that list.
- Strings arrive pre-localized from the host via `SettingsConfiguration`; the package holds no localization.
- Dependency-free, AppKit-only footprint.

## Releases & changelogs

Canonical reference for the `Better*` release process. Releases are cut manually with `gh`; the changelog is the GitHub Release body, there is no `CHANGELOG.md`.

### Versioning
SemVer `MAJOR.MINOR.PATCH`. Tag and release title are the bare version (`0.5.4`); BetterShortcuts alone uses a `v` prefix.
- `MAJOR`: source-breaking API change.
- `MINOR`: new backward-compatible API or feature.
- `PATCH`: bug fix, performance or internal change with no API change.

### Cutting a release
1. Land all changes on `main`; one tag is one coherent unit of work.
2. `git tag <version> && git push origin <version>`
3. `gh release create <version> -R rokartur/<repo> --title "<version>" --notes-file notes.md --verify-tag`, plus `--prerelease` for a `-beta.N` tag.

### Changelog format (the release body)
- First line `## <headline>`: one specific sentence on what the release delivers, optionally one line of context after it.
- Only the sections that apply: `### Added`, `### Changed`, `### Fixed`, `### Performance` (state whether perceived motion is unchanged), `### Removed`.
- Every bullet names the real symbols that changed in backticks and states the behavior, derived from the diff. A one-fix release is the headline plus one bullet.
- A release with a predecessor ends with a compare footer after a blank line: `**Full changelog:** https://github.com/rokartur/<repo>/compare/<prev>...<version>`

Regenerate a body from `git log --no-merges <prev>..<version>` and `git diff --stat <prev>..<version>`.
