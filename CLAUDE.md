## Prime directive: performance, optimization, minimal resource use — at the current animation fidelity

This package is a hand-tuned, macOS System Settings–style window. Every change is held to one bar: **maximum runtime performance, lowest CPU/GPU/memory cost, while preserving the exact motion that exists today.** The animations (subtitle expand/collapse, two-phase "Show Details" toggle, tab crossfade, search-jump highlight flash, scroll compensation) are a deliberate 1:1 port of the BetterAudio preferences window — treat their timing curves, durations, and visual result as a fixed contract. Optimize *around* them; do not flatten, simplify, or "clean up" the motion to gain speed.

Practical consequences when editing:
- Never regress the animation feel to save cycles. If an optimization changes perceived motion, it's wrong.
- Prefer reducing layout passes, allocations, and redraws over reducing animation richness. Cache measurements (see `measuredSubtitleHeight`), reuse layers, batch `layoutSubtreeIfNeeded` calls under deduplicated roots (see `prepareActiveTabLayoutForAnimation`).
- Keep the dependency-free, AppKit-only footprint. No new packages.
- Honor `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` everywhere an animation is started — reduced-motion paths must skip straight to the final state, not animate faster.
- Memory is reclaimed aggressively on window close (`SettingsPresenter.releaseOnClose` → `tearDownAndReleaseWindow` → per-controller `prepareForMemoryRelease`). Any new retained state (layers, images, observers, tasks) must be torn down on those paths.

## Commands

```bash
swift build                      # build library + demo
swift run better-settings-demo   # launch the 3-tab demo window (manual smoke test)
swift test                       # run the unit tests (search index only)

# single test:
swift test --filter BetterSettingsTests.SettingsSearchIndexTests/testKeywordMatch
```

Requires macOS 13+. Builds under Swift 6 language mode with strict concurrency on all three targets (see `Package.swift`). There is no SwiftUI, no XIB/Storyboard — everything is programmatic AppKit.

Only the `Domain/` search logic is unit-tested; all UI/animation behavior is verified by running the demo.

## Architecture

Two layers. **`Domain/`** is dependency-free, `Sendable`, and pure value/observable logic. **`UI/`** is AppKit, `@MainActor`, and builds the window.

### Data flow (single source of truth = `SettingsRouter`)
`SettingsRouter` (Combine `ObservableObject`) holds `selectedTabID` plus a one-shot `navigationRequest`. Everything else observes it; nothing reaches across controllers directly:
- `SettingsSplitViewController` observes `selectedTabID` → tells content VC to swap tabs + updates the window title.
- `SettingsSidebarViewController` observes `selectedTabID` → syncs the table selection.
- `SettingsContentViewController` observes `navigationRequest` → switches tab if needed, then dispatches the scroll-to + highlight to the active tab.

`navigationRequest` carries a `requestID` (UUID) so re-selecting the same target still fires *and* is handled exactly once (`lastHandledRequestID` guard). This is why search-jumping to a control already on screen still flashes it.

### Window lifecycle
`SettingsPresenter` is the recommended entry point: lazy create, bring-to-front activation (with an accessory-app activation retry on the next runloop tick), and `releaseOnClose` teardown that frees the whole controller tree to reclaim RAM, rebuilding on the next `show()`. `SettingsWindowController` is the lower-level alternative if the adopter wants to own create/teardown/reopen themselves.

`SettingsWindow` is fixed-size (`contentMinSize == contentMaxSize == windowSize`, locked *after* assigning the content VC so split-view constraints can't fight it) with a unified toolbar so it picks up Liquid Glass on macOS 26+. `canBecomeKey`/`canBecomeMain` are `nonisolated` overrides — AppKit's accessibility subsystem queries them off the main thread, and a `@MainActor` override would trap under Swift 6's executor check.

`SettingsContentViewController` builds each tab lazily and caches the controllers. By default (`tabUnloadPolicy == .keepAll`) every visited tab stays live until window close — smoothness-first, zero unload bookkeeping (the whole unload path sits behind one `unloadsTabs` guard). A non-`.keepAll` policy reclaims RAM by evicting inactive tabs (LRU keep-N, plus an optional drop-to-active-only when the window resigns key) and rebuilding them from `contentProvider` on revisit. This is motion-safe and search-safe: eviction is deferred one runloop turn off the crossfade frame, never tears down an on-screen view (`view.superview === containerView` guard), and the search catalog/show-details state live outside the tab controller so a rebuilt tab is identical. Cost is a rebuild (`setupContent()` + one subtitle-height re-measure) on revisit.

### Tab content (the adopter-facing base class)
Subclass `SettingsTabViewController`, override `setupContent()`, and build with `addSection(title:anchor:)` / `addRow(...searchItemID:)` / `addDivider`. Registering an `anchor` and `searchItemID` is all that's needed for search-jump navigation — the base class resolves a request to the target view, scrolls it into view, and flashes a `SearchHighlightOverlayView`. No per-tab navigation code.

### The "Show Details" toggle animation
One smooth, vsync-locked spring expands/collapses every visible row's subtitle together. The sidebar toggle (`detailsToggleChanged`) just persists state (`SettingsDetails.write`) and posts `betterSettingsShowDetailsDidChange` with `["isOn": Bool]` — there is **no coordinator and no multi-phase post**. Each `SettingsRowView` observes that notification and, when it should animate (in a window, not reduce-motion, not the initial sync), hands a track (its subtitle height constraint + label) to the singleton `SettingsDetailsSpringAnimator`.

`SettingsDetailsSpringAnimator` is the whole engine: it coalesces all rows that register on the same run-loop turn into **one `CADisplayLink`** (macOS 13 falls back to a 60 Hz `Timer`) that integrates a single semi-implicit-Euler spring (response 0.35, damping 0.8 — matched to the host app's menu-panel section motion) and, in one pass per tick, advances every track's height + opacity and lays out each affected root once. It also captures a **scroll anchor** at start and re-pins the clip origin each tick so content above the fold changing height doesn't drift the viewport. A re-toggle mid-flight rebases each track from its current value (velocity carried) instead of snapping. `cancel(_:)` drops a row's track when it takes over its own state (e.g. its subtitle text changed).

`SettingsRowView` owns the per-row half: it caches its expanded subtitle height (invalidate on text/width change), tracks the in-flight direction (`animatingTowardVisible`) so a redundant same-direction toggle is ignored, and applies the immediate (un-animated) snap for offscreen tabs and reduce-motion (skipping the layout flush when `window == nil`).

### Search
`SettingsSearchIndex` (in `Domain/`, pure + tested) pre-normalizes every catalog field once at init (case/diacritic/width folding) into a `SearchDocument`, then scores per query token with AND semantics: title > keyword > tab, word-prefix > substring, plus a whole-query phrase bonus. Catalog order is authoritative and breaks score ties (stable sort). The sidebar debounces input (`searchDebounce` 0.18s) before re-querying and swapping the table between tab rows and result rows.

### Sidebar rendering
`SidebarCellView` is a reused `NSTableCellView` that reconfigures between tab and search-result layouts by toggling pre-built constraints (no view rebuilds). Gradient icon badges use a single cached `CAGradientLayer` per cell with a precomputed `shadowPath`. Selection emphasis (active vs inactive window) is refreshed only for *visible* rows (`refreshVisibleRowStyles` over `rows(in: visibleRect)`), not the whole table.

## Conventions

- **Strict concurrency:** Swift 6 mode is on. UI types are `@MainActor`; domain types are `Sendable`. Cross-thread AppKit getters that must stay off-main are `nonisolated` and return constants only.
- **Cancellation via generation counters + `Task` handles:** in-flight animations and async layout resolution are guarded by a monotonically-bumped generation and/or a stored `Task` that's cancelled before starting the next. Match this pattern for any new async/animated work — never let a stale completion mutate current state.
- **Reduce-motion is a required branch, not an afterthought.** Every animated path has a settled-state fast path.
- **Teardown is mandatory.** Observers, `Task`s, Combine subscriptions, table delegates, and document views are all explicitly nilled in the various `tearDown()` / `prepareForMemoryRelease()` methods. New retained state goes there too.
- **Strings arrive pre-localized** from the host app via `SettingsConfiguration`; this package does no localization.
