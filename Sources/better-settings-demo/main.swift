//
//  main.swift
//  better-settings-demo
//
//  Minimal runnable wiring of BetterSettings: three tabs, a search catalog, and
//  content controllers that register sections + search targets so sidebar search
//  jumps straight to the matching control. Also serves as a compile-time check
//  of the public API.
//
//  Run: swift run better-settings-demo
//

import AppKit
import BetterSettings

// MARK: - Tab content controllers

final class GeneralTab: SettingsTabViewController {
    override func setupContent() {
        let behavior = addSection(title: "Behavior", anchor: "general.behavior")
        addRow(to: behavior, title: "Launch at login",
               subtitle: "Start automatically when you log in.",
               accessory: NSSwitch(), searchItemID: "general.launchAtLogin")
        addDivider(to: behavior)
        addRow(to: behavior, title: "Show in menu bar",
               subtitle: "Display the status item in the menu bar.",
               accessory: NSSwitch(), searchItemID: "general.menuBar")

        let updates = addSection(title: "Updates", anchor: "general.updates")
        addRow(to: updates, title: "Check for updates automatically",
               subtitle: "Download and install updates in the background.",
               accessory: NSSwitch(), searchItemID: "general.autoUpdate")
    }
}

final class AppearanceTab: SettingsTabViewController {
    override func setupContent() {
        let theme = addSection(title: "Theme", anchor: "appearance.theme")
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: ["System", "Light", "Dark"])
        addRow(to: theme, title: "Appearance",
               subtitle: "Match the system, or force light/dark.",
               accessory: popup, searchItemID: "appearance.mode")
        addDivider(to: theme)
        addRow(to: theme, title: "Accent color",
               accessory: NSColorWell(frame: NSRect(x: 0, y: 0, width: 44, height: 23)),
               searchItemID: "appearance.accent")
    }
}

final class AboutTab: SettingsTabViewController {
    override func setupContent() {
        let about = addSection(title: "About", anchor: "about.info")
        addRow(to: about, title: "BetterSettings Demo", subtitle: "Version 1.0.0")
    }
}

// MARK: - Show Details test tabs (varying subtitle line counts)

// Explicit "\n" so each tab hits an exact line count regardless of column width.
private let oneLineSub = "Single line of detail text."
private let twoLineSub = "First line of detail text.\nSecond line of detail text."
private let threeLineSub = "First line of detail text.\nSecond line of detail text.\nThird line of detail text."
private let fourLineSub = "First line of detail text.\nSecond line of detail text.\nThird line of detail text.\nFourth line of detail text."
private let paragraphSub = "A deliberately long, multi-sentence paragraph used to stress the reveal/hide motion. It wraps across many lines so the height delta is large; when you toggle Show Details this row travels far and uses the full, slower spring while the one-line rows snap quickly. Add sentences here for an even taller subtitle."

/// A tab full of identical-length subtitles so one line-count can be judged in isolation.
final class LinesTab: SettingsTabViewController {
    private let sectionTitle: String
    private let subtitle: String
    private let count: Int

    init(sectionTitle: String, subtitle: String, count: Int) {
        self.sectionTitle = sectionTitle
        self.subtitle = subtitle
        self.count = count
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func setupContent() {
        let section = addSection(title: sectionTitle, anchor: "lines.main")
        for i in 1...count {
            addRow(to: section, title: "Item \(i)", subtitle: subtitle, accessory: NSSwitch())
            if i < count { addDivider(to: section) }
        }
    }
}

/// Interleaves short and tall subtitles so short and long rows animate together —
/// the case where short rows used to look cheap next to the tall ones.
final class MixedTab: SettingsTabViewController {
    override func setupContent() {
        let subs = [oneLineSub, paragraphSub, oneLineSub, twoLineSub, fourLineSub, oneLineSub, threeLineSub, paragraphSub]
        let section = addSection(title: "Mixed lengths", anchor: "mixed.main")
        for (i, sub) in subs.enumerated() {
            addRow(to: section, title: "Row \(i + 1)", subtitle: sub, accessory: NSSwitch())
            if i < subs.count - 1 { addDivider(to: section) }
        }
    }
}

// MARK: - Configuration

let configuration = SettingsConfiguration(
    tabs: [
        SettingsTab(id: "general", title: "General", icon: "gearshape.fill",
                    iconStyle: .neutral),
        SettingsTab(id: "appearance", title: "Appearance", icon: "paintpalette.fill",
                    iconStyle: SettingsTabIconStyle(gradientStart: SettingsColor(hex: 0x42BEFF),
                                                    gradientEnd: SettingsColor(hex: 0x0062FF))),
        SettingsTab(id: "about", title: "About", icon: "info.circle.fill",
                    iconStyle: .solid(SettingsColor(hex: 0xFF6F00))),
        SettingsTab(id: "oneline", title: "1 Line", icon: "text.alignleft",
                    iconStyle: .solid(SettingsColor(hex: 0x34C759))),
        SettingsTab(id: "twoline", title: "2 Lines", icon: "text.justify",
                    iconStyle: .solid(SettingsColor(hex: 0x30B0C7))),
        SettingsTab(id: "threeline", title: "3 Lines", icon: "text.justifyleft",
                    iconStyle: .solid(SettingsColor(hex: 0x5856D6))),
        SettingsTab(id: "paragraph", title: "Paragraph", icon: "doc.plaintext.fill",
                    iconStyle: .solid(SettingsColor(hex: 0xAF52DE))),
        SettingsTab(id: "mixed", title: "Mixed", icon: "rectangle.grid.1x2.fill",
                    iconStyle: .solid(SettingsColor(hex: 0xFF2D55))),
    ],
    searchItems: [
        SettingsSearchItem(id: "general.launchAtLogin", tabID: "general", sectionAnchor: "general.behavior",
                           title: "Launch at login", tabTitle: "General", sectionTitle: "Behavior",
                           keywords: ["startup", "boot", "open at login"]),
        SettingsSearchItem(id: "general.menuBar", tabID: "general", sectionAnchor: "general.behavior",
                           title: "Show in menu bar", tabTitle: "General", sectionTitle: "Behavior",
                           keywords: ["status item", "tray"]),
        SettingsSearchItem(id: "general.autoUpdate", tabID: "general", sectionAnchor: "general.updates",
                           title: "Check for updates automatically", tabTitle: "General", sectionTitle: "Updates",
                           keywords: ["update", "upgrade", "auto"]),
        SettingsSearchItem(id: "appearance.mode", tabID: "appearance", sectionAnchor: "appearance.theme",
                           title: "Appearance", tabTitle: "Appearance", sectionTitle: "Theme",
                           keywords: ["dark mode", "light mode", "theme"]),
        SettingsSearchItem(id: "appearance.accent", tabID: "appearance", sectionAnchor: "appearance.theme",
                           title: "Accent color", tabTitle: "Appearance", sectionTitle: "Theme",
                           keywords: ["color", "tint", "highlight"]),
    ],
    contentProvider: { tab, _ in
        // Logs every (re)build so the unload policy below is observable: an evicted
        // tab prints again when you return to it; a kept one does not.
        print("contentProvider: building tab \(tab.id)")
        switch tab.id {
        case "general": return GeneralTab()
        case "appearance": return AppearanceTab()
        case "oneline": return LinesTab(sectionTitle: "One-line details", subtitle: oneLineSub, count: 7)
        case "twoline": return LinesTab(sectionTitle: "Two-line details", subtitle: twoLineSub, count: 6)
        case "threeline": return LinesTab(sectionTitle: "Three-line details", subtitle: threeLineSub, count: 6)
        case "paragraph": return LinesTab(sectionTitle: "Paragraph details", subtitle: paragraphSub, count: 5)
        case "mixed": return MixedTab()
        default: return AboutTab()
        }
    },
    // Demo runs the recommended low-RAM policy so the behavior is exercised:
    // keep active + 1 previous live; drop to active-only when the window loses key.
    tabUnloadPolicy: .balanced
)

// MARK: - App bootstrap

final class DemoAppDelegate: NSObject, NSApplicationDelegate {
    var controller: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = SettingsWindowController(configuration: configuration)
        self.controller = controller
        controller.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = DemoAppDelegate()
app.delegate = delegate
app.run()
