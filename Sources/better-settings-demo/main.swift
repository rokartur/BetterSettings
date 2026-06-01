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
