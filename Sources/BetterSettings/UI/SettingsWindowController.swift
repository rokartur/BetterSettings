//
//  SettingsWindowController.swift
//  BetterSettings
//
//  Public entry point. Owns the window, the split view (sidebar + content), and
//  the router. Create one, call `show()`, and release it on close.
//

import AppKit
import Combine

@MainActor
public final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    public let router: SettingsRouter
    private let configuration: SettingsConfiguration
    private let splitVC: SettingsSplitViewController

    /// Builds the controller. The first tab is selected unless `initialTabID`
    /// names another tab.
    public init(configuration: SettingsConfiguration, initialTabID: String? = nil) {
        precondition(!configuration.tabs.isEmpty, "SettingsConfiguration requires at least one tab")

        // Point the shared "Show Details" store at the app's configured defaults.
        SettingsDetails.defaults = configuration.defaults
        SettingsDetails.defaultsKey = configuration.showDetailsDefaultsKey

        let startTab = initialTabID.flatMap(configuration.tab(for:))?.id ?? configuration.tabs[0].id
        let router = SettingsRouter(selectedTabID: startTab)
        self.router = router
        self.configuration = configuration
        self.splitVC = SettingsSplitViewController(configuration: configuration, router: router)

        let window = SettingsWindow(contentSize: configuration.windowSize)
        super.init(window: window)

        window.delegate = self
        window.contentViewController = splitVC

        // Lock the size after assigning the content controller so split-view
        // constraints can't override it.
        window.setContentSize(configuration.windowSize)
        window.contentMinSize = configuration.windowSize
        window.contentMaxSize = configuration.windowSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows the window, optionally selecting a tab, and brings the app forward.
    public func show(selecting tabID: String? = nil) {
        if let tabID, configuration.tab(for: tabID) != nil {
            splitVC.selectTab(tabID)
        }
        guard let window else { return }

        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Tears down child controllers and releases the window for memory.
    public func tearDownAndReleaseWindow() {
        splitVC.tearDown()
        guard let window else { return }
        window.makeFirstResponder(nil)
        window.orderOut(nil)
        window.delegate = nil
        window.toolbar = nil
        window.contentViewController = nil
        self.window = nil
    }

    // MARK: - NSWindowDelegate

    public func windowDidBecomeKey(_ notification: Notification) {
        splitVC.selectTab(router.selectedTabID)
    }
}
