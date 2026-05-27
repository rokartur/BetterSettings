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

    /// Shows the window, optionally selecting a tab, and brings the app forward
    /// as the active app with the window key — immediately, even for accessory
    /// (menu-bar) apps where the activation-policy transition can otherwise leave
    /// the window non-key on the first runloop pass.
    public func show(selecting tabID: String? = nil) {
        if let tabID, configuration.tab(for: tabID) != nil {
            splitVC.selectTab(tabID)
        }
        guard let window else { return }

        if !window.isVisible { window.center() }

        // Activate the app first, then key the window. `orderFrontRegardless`
        // surfaces it even while another app is frontmost.
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)

        // Retry next tick: an accessory app may still be mid activation-policy
        // transition and not yet hold key status.
        DispatchQueue.main.async { [weak window] in
            guard let window, window.isVisible else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
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
