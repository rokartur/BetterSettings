# BetterSettings

A dependency-free Swift package that builds an **ultra-efficient, macOS System
Settings–style settings window** — native AppKit, source-list sidebar, gradient
tab icon badges, rounded section cards, and (the headline feature) **fast section
search with scroll-to-and-flash navigation**.

Modeled on the BetterAudio preferences window (the reference for the search +
section-jump UX), generalized so any app drives it from a small declaration.

Requires macOS 13+. Picks up Liquid Glass automatically on macOS 26+.

## What you get

- `SettingsWindowController` — the whole window: fixed-size titled window, unified
  toolbar, sidebar + content split.
- A **source-list sidebar** with macOS-style gradient SF Symbol icon badges, a
  rounded accent selection capsule, and inactive-window dimming.
- **Search**: type in the sidebar field and the tab list is replaced by scored
  results (`Title` + `Tab · Section` subtitle). Selecting one switches tab,
  scrolls to the exact control, and flashes an accent highlight over it.
- `SettingsTabViewController` — base class for tab content. Scrolling padded
  stack, `addSection` / `addRow` / `addDivider` helpers, and **automatic**
  scroll-to-section + highlight by registering anchors/search ids (no per-tab
  navigation code).
- A `Show Details` sidebar toggle that expands/collapses every row's subtitle.

## Usage

```swift
import BetterSettings

// 1. Tab content subclasses SettingsTabViewController.
final class GeneralTab: SettingsTabViewController {
    override func setupContent() {
        let behavior = addSection(title: "Behavior", anchor: "general.behavior")
        addRow(to: behavior,
               title: "Launch at login",
               subtitle: "Start automatically when you log in.",
               accessory: NSSwitch(),
               searchItemID: "general.launchAtLogin")   // search jumps straight here
    }
}

// 2. Declare tabs + search catalog + a content factory.
let configuration = SettingsConfiguration(
    tabs: [
        SettingsTab(id: "general", title: "General", icon: "gearshape.fill",
                    iconStyle: .neutral),
        SettingsTab(id: "appearance", title: "Appearance", icon: "paintpalette.fill",
                    iconStyle: SettingsTabIconStyle(gradientStart: SettingsColor(hex: 0x42BEFF),
                                                    gradientEnd:   SettingsColor(hex: 0x0062FF))),
    ],
    searchItems: [
        SettingsSearchItem(id: "general.launchAtLogin", tabID: "general",
                           sectionAnchor: "general.behavior",
                           title: "Launch at login",
                           tabTitle: "General", sectionTitle: "Behavior",
                           keywords: ["startup", "boot"]),
    ],
    contentProvider: { tab, _ in
        switch tab.id {
        case "general":    return GeneralTab()
        case "appearance": return AppearanceTab()
        default:           return GeneralTab()
        }
    }
)

// 3. Show it.
let controller = SettingsWindowController(configuration: configuration)
controller.show(selecting: "general")
```

Strings (`title`, `tabTitle`, `sectionTitle`, `keywords`, `searchPlaceholder`,
`showDetailsLabel`, `noResultsText`) are expected pre-localized by the host app.

## Architecture

```
Domain/ (dependency-free, Sendable)
  SettingsColor          RGBA → NSColor bridge (hex helpers)
  SettingsTab            id + title + SF Symbol + gradient icon style
  SettingsSearchModels   search item / result (+ "Tab · Section" subtitle logic)
  SettingsSearchIndex    token scoring: title > keyword > tab, prefix > substring
  SettingsRouter         selected tab + one-shot navigation requests (Combine)

UI/ (AppKit, @MainActor)
  SettingsConfiguration        app-supplied tabs/catalog/content factory
  SettingsWindow(Controller)   window chrome + public entry point
  SettingsSplitViewController  sidebar + content, locked divider
  SettingsSidebarViewController source list, search field, results, Show Details
  SettingsContentViewController lazy/cached tab controllers + crossfade + nav
  SettingsTabViewController     base: scroll stack, builders, scroll/highlight nav
  SettingsSectionView           rounded card + header
  SettingsRowView               icon + title + collapsible subtitle + accessory
```

The search index is pure value logic and unit-tested
(`Tests/BetterSettingsTests`).

## Demo

```
swift run better-settings-demo
```

Opens a three-tab settings window (General / Appearance / About) wired exactly as
above. Doubles as a compile-time contract for the public API.
