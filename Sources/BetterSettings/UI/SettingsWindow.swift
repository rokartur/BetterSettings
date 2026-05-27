//
//  SettingsWindow.swift
//  BetterSettings
//
//  Fixed-size, titled window with a unified toolbar so it picks up Liquid Glass
//  on macOS 26+ and standard vibrancy below. Mirrors the macOS System Settings
//  window chrome.
//

import AppKit

public final class SettingsWindow: NSWindow {

    // `nonisolated`: AppKit's accessibility subsystem queries these getters from
    // background threads. Under Swift 6 a MainActor-isolated override would run a
    // runtime executor check there and trap (`_dispatch_assert_queue_fail`).
    // They only return a constant, so off-main access is safe.
    override public nonisolated var canBecomeKey: Bool { true }
    override public nonisolated var canBecomeMain: Bool { true }

    /// Handle ⌘W locally. Accessory (menu-bar) apps have no File ▸ Close menu
    /// item to route the shortcut, so close the window directly.
    override public func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    init(contentSize: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        titleVisibility = .visible
        titlebarAppearsTransparent = false
        titlebarSeparatorStyle = .automatic

        isMovableByWindowBackground = true
        isReleasedWhenClosed = true
        isOpaque = false
        isRestorable = false
        tabbingMode = .disallowed

        level = .normal
        hidesOnDeactivate = false
        collectionBehavior.insert(.moveToActiveSpace)
        collectionBehavior.insert(.fullScreenAuxiliary)
        animationBehavior = .default

        let toolbar = NSToolbar(identifier: "BetterSettingsToolbar")
        toolbar.displayMode = .iconOnly
        self.toolbar = toolbar
        toolbarStyle = .unified

        center()
    }

    override public func orderFront(_ sender: Any?) {
        super.orderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}
